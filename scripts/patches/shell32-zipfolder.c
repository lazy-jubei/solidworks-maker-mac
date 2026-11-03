/*
 * Minimal zip folder support for Shell.Application.
 *
 * Windows' NameSpace("x.zip") returns a virtual folder. Here the archive is extracted to a
 * new temporary directory and that directory is used as the folder, so Items() and
 * CopyHere() work unchanged.
 *
 * This library is free software; you can redistribute it and/or modify it under the terms
 * of the GNU Lesser General Public License as published by the Free Software Foundation;
 * either version 2.1 of the License, or (at your option) any later version.
 */

#include <stdarg.h>
#include <zlib.h>

#include "windef.h"
#include "winbase.h"
#include "winnls.h"
#include "shlwapi.h"
#include "wine/debug.h"

WINE_DEFAULT_DEBUG_CHANNEL(shell);

#define SIG_EOCD      0x06054b50
#define SIG_EOCD64LOC 0x07064b50
#define SIG_EOCD64    0x06064b50
#define SIG_CENTRAL   0x02014b50
#define SIG_LOCAL     0x04034b50
#define OUT_CHUNK     (1024 * 1024)
#define IN_CHUNK      (1024 * 1024 * 1024)

static inline UINT16 rd16(const BYTE *p) { return p[0] | p[1] << 8; }
static inline UINT32 rd32(const BYTE *p) { return p[0] | p[1] << 8 | p[2] << 16 | (UINT32)p[3] << 24; }
static inline UINT64 rd64(const BYTE *p) { return rd32(p) | (UINT64)rd32(p + 4) << 32; }

/* Reject anything that could land outside the extraction directory. */
static BOOL safe_name(const WCHAR *name)
{
    const WCHAR *p = name, *end;

    if (!*name || *name == '\\' || wcschr(name, ':')) return FALSE;
    while (*p)
    {
        end = wcschr(p, '\\');
        if (!end) end = p + lstrlenW(p);
        if (end - p == 2 && p[0] == '.' && p[1] == '.') return FALSE;
        p = *end ? end + 1 : end;
    }
    return TRUE;
}

/* Creates the directories of path below base; base itself already exists. */
static BOOL make_parents(WCHAR *path, SIZE_T base_len)
{
    WCHAR *p = path + base_len + 1;

    while ((p = wcschr(p, '\\')))
    {
        *p = 0;
        if (!CreateDirectoryW(path, NULL) && GetLastError() != ERROR_ALREADY_EXISTS)
        {
            *p = '\\';
            return FALSE;
        }
        *p++ = '\\';
    }
    return TRUE;
}

static BOOL write_stored(HANDLE file, const BYTE *data, UINT64 size, uLong *crc)
{
    DWORD chunk, written;

    while (size)
    {
        chunk = size > IN_CHUNK ? IN_CHUNK : size;
        if (!WriteFile(file, data, chunk, &written, NULL) || written != chunk) return FALSE;
        *crc = crc32(*crc, data, chunk);
        data += chunk;
        size -= chunk;
    }
    return TRUE;
}

/* Wine's zlib is built with Z_SOLO, which has no default allocator. */
static void *zip_alloc(void *opaque, unsigned int items, unsigned int size)
{
    return HeapAlloc(GetProcessHeap(), 0, (SIZE_T)items * size);
}

static void zip_free(void *opaque, void *ptr)
{
    HeapFree(GetProcessHeap(), 0, ptr);
}

static BOOL write_deflated(HANDLE file, const BYTE *data, UINT64 csize, uLong *crc)
{
    z_stream zs = {0};
    BYTE *out;
    DWORD have, written;
    BOOL ok = FALSE;
    int ret = Z_OK;

    if (!(out = HeapAlloc(GetProcessHeap(), 0, OUT_CHUNK))) return FALSE;
    zs.zalloc = zip_alloc;
    zs.zfree = zip_free;
    if (inflateInit2(&zs, -MAX_WBITS) != Z_OK) goto done;
    zs.next_in = (BYTE *)data;
    while (ret != Z_STREAM_END)
    {
        if (!zs.avail_in)
        {
            zs.avail_in = csize > IN_CHUNK ? IN_CHUNK : csize;
            csize -= zs.avail_in;
        }
        zs.next_out = out;
        zs.avail_out = OUT_CHUNK;
        ret = inflate(&zs, Z_NO_FLUSH);
        if (ret != Z_OK && ret != Z_STREAM_END) break;
        have = OUT_CHUNK - zs.avail_out;
        if (!have && !zs.avail_in && !csize) break;
        if (!WriteFile(file, out, have, &written, NULL) || written != have) break;
        *crc = crc32(*crc, out, have);
    }
    ok = ret == Z_STREAM_END;
    inflateEnd(&zs);
done:
    HeapFree(GetProcessHeap(), 0, out);
    return ok;
}

static BOOL extract_all(const BYTE *zip, UINT64 size, const WCHAR *dir)
{
    const BYTE *eocd = NULL, *p;
    UINT64 count, offset, cdsize, i, pos;
    UINT64 min = size > 65557 ? size - 65557 : 0, at;
    static WCHAR path[32768], wname[32768];

    if (size < 22) return FALSE;
    for (at = size - 22; at + 1 > min; at--)
    {
        if (rd32(zip + at) == SIG_EOCD) { eocd = zip + at; break; }
        if (!at) break;
    }
    if (!eocd) return FALSE;

    count = rd16(eocd + 10);
    cdsize = rd32(eocd + 12);
    offset = rd32(eocd + 16);
    if (eocd - zip >= 20 && rd32(eocd - 20) == SIG_EOCD64LOC)
    {
        UINT64 e64 = rd64(eocd - 20 + 8);
        if (e64 + 56 > size || rd32(zip + e64) != SIG_EOCD64) return FALSE;
        count = rd64(zip + e64 + 32);
        cdsize = rd64(zip + e64 + 40);
        offset = rd64(zip + e64 + 48);
    }
    if (offset > size || cdsize > size - offset) return FALSE;

    pos = offset;
    for (i = 0; i < count; i++)
    {
        UINT64 csize, usize, lhoff, end;
        UINT16 method, flags, nlen, xlen, clen, llen, lxlen;
        UINT32 crc_want;
        uLong crc = 0;
        const BYTE *x;
        HANDLE file;
        int wlen;
        BOOL ok;

        if (pos + 46 > offset + cdsize) return FALSE;
        p = zip + pos;
        if (rd32(p) != SIG_CENTRAL) return FALSE;
        flags = rd16(p + 8);
        method = rd16(p + 10);
        crc_want = rd32(p + 16);
        csize = rd32(p + 20);
        usize = rd32(p + 24);
        nlen = rd16(p + 28);
        xlen = rd16(p + 30);
        clen = rd16(p + 32);
        lhoff = rd32(p + 42);
        if (pos + 46 + nlen + xlen + clen > offset + cdsize) return FALSE;
        if (flags & 1) { ERR("encrypted entries are not supported\n"); return FALSE; }

        for (x = p + 46 + nlen; x + 4 <= p + 46 + nlen + xlen; x += 4 + rd16(x + 2))
        {
            const BYTE *v = x + 4, *vend = v + rd16(x + 2);

            if (rd16(x) != 1) continue;
            if (usize == 0xffffffff && v + 8 <= vend) { usize = rd64(v); v += 8; }
            if (csize == 0xffffffff && v + 8 <= vend) { csize = rd64(v); v += 8; }
            if (lhoff == 0xffffffff && v + 8 <= vend) { lhoff = rd64(v); }
        }

        wlen = MultiByteToWideChar(flags & 0x800 ? CP_UTF8 : CP_ACP, 0, (const char *)p + 46, nlen,
                                   wname, ARRAY_SIZE(wname) - 1);
        if (!wlen) return FALSE;
        wname[wlen] = 0;
        for (WCHAR *c = wname; *c; c++) if (*c == '/') *c = '\\';
        if (!safe_name(wname)) { ERR("unsafe name %s\n", debugstr_w(wname)); return FALSE; }

        if (lstrlenW(dir) + 1 + wlen + 1 > ARRAY_SIZE(path)) return FALSE;
        lstrcpyW(path, dir);
        lstrcatW(path, L"\\");
        lstrcatW(path, wname);
        if (!make_parents(path, lstrlenW(dir))) return FALSE;

        pos += 46 + nlen + xlen + clen;
        if (wname[wlen - 1] == '\\') continue;

        if (lhoff + 30 > size || rd32(zip + lhoff) != SIG_LOCAL) return FALSE;
        llen = rd16(zip + lhoff + 26);
        lxlen = rd16(zip + lhoff + 28);
        end = lhoff + 30 + llen + lxlen;
        if (end > size || csize > size - end) return FALSE;

        file = CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
        if (file == INVALID_HANDLE_VALUE) return FALSE;
        if (method == 0) ok = write_stored(file, zip + end, csize, &crc);
        else if (method == 8) ok = write_deflated(file, zip + end, csize, &crc);
        else { ERR("unsupported method %u\n", method); ok = FALSE; }
        CloseHandle(file);
        if (!ok || crc != crc_want)
        {
            ERR("failed to extract %s\n", debugstr_w(wname));
            return FALSE;
        }
    }
    return TRUE;
}

/* S_OK: dir holds the extracted archive. S_FALSE: path isn't a zip file. E_FAIL: bad archive. */
HRESULT zipfolder_open(const WCHAR *zip_path, WCHAR *dir, DWORD dir_len)
{
    WCHAR temp[MAX_PATH];
    LARGE_INTEGER size;
    HANDLE file, map;
    const BYTE *view;
    HRESULT hr = E_FAIL;
    DWORD attrs = GetFileAttributesW(zip_path);
    const WCHAR *ext = wcsrchr(zip_path, '.');

    if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_DIRECTORY)) return S_FALSE;
    if (!ext || lstrcmpiW(ext, L".zip")) return S_FALSE;

    if (!GetTempPathW(ARRAY_SIZE(temp), temp)) return E_FAIL;
    if (!GetTempFileNameW(temp, L"zip", 0, dir)) return E_FAIL;
    DeleteFileW(dir);
    if (!CreateDirectoryW(dir, NULL)) return E_FAIL;

    file = CreateFileW(zip_path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (file == INVALID_HANDLE_VALUE) return E_FAIL;
    if (GetFileSizeEx(file, &size) && (map = CreateFileMappingW(file, NULL, PAGE_READONLY, 0, 0, NULL)))
    {
        if ((view = MapViewOfFile(map, FILE_MAP_READ, 0, 0, 0)))
        {
            if (extract_all(view, size.QuadPart, dir)) hr = S_OK;
            UnmapViewOfFile(view);
        }
        CloseHandle(map);
    }
    CloseHandle(file);
    TRACE("%s -> %s: %#lx\n", debugstr_w(zip_path), debugstr_w(dir), hr);
    return hr;
}
