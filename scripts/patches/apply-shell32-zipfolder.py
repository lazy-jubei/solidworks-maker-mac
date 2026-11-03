#!/usr/bin/env python3
"""Add zip folder support and FolderImpl_CopyHere to Wine 11.16's dlls/shell32.

Usage: apply-shell32-zipfolder.py <wine source dir>
Refuses to run if the code it replaces isn't there exactly once.
"""
import pathlib
import shutil
import sys

src = pathlib.Path(sys.argv[1]) / "dlls" / "shell32"
here = pathlib.Path(__file__).resolve().parent


def replace(text, old, new):
    if text.count(old) != 1:
        sys.exit(f"expected exactly one match for: {old[:60]!r}")
    return text.replace(old, new)


shutil.copy(here / "shell32-zipfolder.c", src / "zipfolder.c")

make = (src / "Makefile.in").read_text()
make = replace(make, "IMPORTS   = uuid shlwapi user32 gdi32 advapi32\n",
               "IMPORTS   = $(ZLIB_PE_LIBS) uuid shlwapi user32 gdi32 advapi32\n"
               "EXTRAINCL = $(ZLIB_PE_CFLAGS)\n")
make = replace(make, "\tshelldispatch.c \\\n", "\tshelldispatch.c \\\n\tzipfolder.c \\\n")
(src / "Makefile.in").write_text(make)

code = (src / "shelldispatch.c").read_text()
code = replace(code, """        case VT_BSTR:
            if (FAILED(hr = SHParseDisplayName(V_BSTR(&dir), NULL, &pidl, 0, NULL)))
                return S_FALSE;
""", """        case VT_BSTR:
        {
            WCHAR zipdir[MAX_PATH];

            hr = zipfolder_open(V_BSTR(&dir), zipdir, ARRAY_SIZE(zipdir));
            if (FAILED(hr))
                return S_FALSE;
            if (FAILED(hr = SHParseDisplayName(hr == S_OK ? zipdir : V_BSTR(&dir), NULL, &pidl, 0, NULL)))
                return S_FALSE;
""")
code = replace(code, """                return S_FALSE;

            break;
        default:
            WARN("Ignoring directory value %s\\n", debugstr_variant(&dir));
""", """                return S_FALSE;

            break;
        }
        default:
            WARN("Ignoring directory value %s\\n", debugstr_variant(&dir));
""")
code = replace(code, """    FIXME("(%p,%s,%s)\\n", iface, debugstr_variant(&item), debugstr_variant(&options));

    return E_NOTIMPL;
}

static HRESULT WINAPI FolderImpl_GetDetailsOf""", """    FolderImpl *This = impl_from_Folder(iface);
    WCHAR *from = NULL, *to = NULL;
    FolderItems *items = NULL;
    FolderItem *one = NULL;
    SHFILEOPSTRUCTW op = {0};
    SIZE_T used = 0, cap = 1;
    HRESULT hr = S_OK;
    VARIANT *arg = &item;

    TRACE("(%p,%s,%s)\\n", iface, debugstr_variant(&item), debugstr_variant(&options));

    if (V_VT(arg) == (VT_VARIANT | VT_BYREF))
        arg = V_VARIANTREF(arg);
    if (!(from = calloc(cap, sizeof(WCHAR))))
        return E_OUTOFMEMORY;

    if (V_VT(arg) == VT_BSTR)
    {
        hr = zip_append_path(&from, &used, &cap, V_BSTR(arg));
    }
    else if (V_VT(arg) == VT_DISPATCH || V_VT(arg) == VT_UNKNOWN)
    {
        IUnknown *unk = V_UNKNOWN(arg);

        if (!unk)
            hr = E_INVALIDARG;
        else if (SUCCEEDED(IUnknown_QueryInterface(unk, &IID_FolderItems, (void **)&items)))
        {
            LONG count = 0, i;

            hr = FolderItems_get_Count(items, &count);
            for (i = 0; SUCCEEDED(hr) && i < count; i++)
            {
                VARIANT index;
                BSTR path = NULL;

                V_VT(&index) = VT_I4;
                V_I4(&index) = i;
                if (FAILED(hr = FolderItems_Item(items, index, &one)) || !one)
                    break;
                if (SUCCEEDED(hr = FolderItem_get_Path(one, &path)))
                    hr = zip_append_path(&from, &used, &cap, path);
                SysFreeString(path);
                FolderItem_Release(one);
            }
            FolderItems_Release(items);
        }
        else if (SUCCEEDED(IUnknown_QueryInterface(unk, &IID_FolderItem, (void **)&one)))
        {
            BSTR path = NULL;

            if (SUCCEEDED(hr = FolderItem_get_Path(one, &path)))
                hr = zip_append_path(&from, &used, &cap, path);
            SysFreeString(path);
            FolderItem_Release(one);
        }
        else
            hr = E_INVALIDARG;
    }
    else
        hr = E_INVALIDARG;

    if (SUCCEEDED(hr) && used)
    {
        SIZE_T len = lstrlenW(This->path);

        if (!(to = calloc(len + 2, sizeof(WCHAR))))
            hr = E_OUTOFMEMORY;
        else
        {
            memcpy(to, This->path, len * sizeof(WCHAR));
            op.wFunc = FO_COPY;
            op.pFrom = from;
            op.pTo = to;
            op.fFlags = FOF_SILENT | FOF_NOCONFIRMATION | FOF_NOCONFIRMMKDIR | FOF_NOERRORUI;
            if (SHFileOperationW(&op))
                hr = E_FAIL;
        }
    }
    free(from);
    free(to);
    return hr;
}

static HRESULT WINAPI FolderImpl_GetDetailsOf""")
code = replace(code, """static HRESULT WINAPI FolderImpl_CopyHere(Folder3 *iface""",
               """/* Appends a path to a double-null-terminated SHFileOperation list. */
static HRESULT zip_append_path(WCHAR **list, SIZE_T *used, SIZE_T *cap, const WCHAR *path)
{
    SIZE_T len = lstrlenW(path) + 1;

    if (*used + len + 1 > *cap)
    {
        SIZE_T newcap = (*used + len + 1) * 2;
        WCHAR *grown = realloc(*list, newcap * sizeof(WCHAR));

        if (!grown)
            return E_OUTOFMEMORY;
        *list = grown;
        *cap = newcap;
    }
    memcpy(*list + *used, path, len * sizeof(WCHAR));
    *used += len;
    (*list)[*used] = 0;
    return S_OK;
}

static HRESULT WINAPI FolderImpl_CopyHere(Folder3 *iface""")
code = replace(code, """#include "wine/debug.h"
""", """#include "wine/debug.h"

extern HRESULT zipfolder_open(const WCHAR *zip_path, WCHAR *dir, DWORD dir_len);
""")
(src / "shelldispatch.c").write_text(code)
print("patched", src)
