#!/usr/bin/env python3
"""Add InternetSetCookieEx2 and friends to Wine 11.16's dlls/wininet.

SWXDesktopLauncher.exe looks up InternetSetCookieEx2 and calls the result without checking it,
so with no export it crashes at address 0. It uses this to hand its login cookie to the session.

Usage: wininet-cookie2.py <wine source dir>
"""
import pathlib
import sys

src = pathlib.Path(sys.argv[1]) / "dlls" / "wininet"

spec = (src / "wininet.spec").read_text()
if "InternetSetCookieEx2" in spec:
    # Replace our prior implementation so an existing build receives fixes too.
    cookie_file = src / "cookie.c"
    existing = cookie_file.read_text()
    marker = "\ntypedef struct\n{\n    WCHAR *pwszName;"
    if marker not in existing:
        sys.exit("unrecognized existing Cookie2 implementation")
    cookie_file.write_text(existing[:existing.index(marker)])
    spec = "\n".join(line for line in spec.splitlines() if not any(
        name in line for name in ("InternetSetCookieEx2", "InternetGetCookieEx2", "InternetFreeCookies"))) + "\n"
spec += """@ stdcall InternetFreeCookies(ptr long)
@ stdcall InternetGetCookieEx2(wstr wstr long ptr ptr)
@ stdcall InternetSetCookieEx2(wstr ptr wstr long ptr)
"""
(src / "wininet.spec").write_text(spec)

code = (src / "cookie.c").read_text()
code += r"""
typedef struct
{
    WCHAR *pwszName;
    WCHAR *pwszValue;
    WCHAR *pwszDomain;
    WCHAR *pwszPath;
    DWORD dwFlags;
    FILETIME ftExpires;
    BOOL fExpiresSet;
} INTERNET_COOKIE2;

#define COOKIE2_FLAG_SECURE   0x00000001
#define COOKIE2_FLAG_HTTPONLY 0x00002000

/***********************************************************************
 *           InternetSetCookieEx2 (WININET.@)
 */
DWORD WINAPI InternetSetCookieEx2(const WCHAR *url, const INTERNET_COOKIE2 *cookie, const WCHAR *policy,
        DWORD flags, DWORD *state)
{
    WCHAR expires[INTERNET_RFC1123_BUFSIZE] = {0}, *data, *built_url = NULL;
    const WCHAR *name, *value, *domain, *path;
    SYSTEMTIME st;
    SIZE_T len;
    DWORD res, err = ERROR_SUCCESS;

    TRACE("(%s, %s, %p, %lx, %p)\n", debugstr_w(url), debugstr_w(policy), cookie, flags, state);

    if (!cookie) return ERROR_INVALID_PARAMETER;

    name = cookie->pwszName;
    value = cookie->pwszValue ? cookie->pwszValue : L"";
    domain = cookie->pwszDomain;
    path = cookie->pwszPath;

    if (!url)
    {
        const WCHAR *host = domain;

        if (!host) return ERROR_INVALID_PARAMETER;
        if (*host == '.') host++;
        len = lstrlenW(L"https://") + lstrlenW(host) + (path ? lstrlenW(path) : 1) + 1;
        if (!(built_url = malloc(len * sizeof(WCHAR)))) return ERROR_OUTOFMEMORY;
        swprintf(built_url, len, L"https://%s%s", host, path ? path : L"/");
        url = built_url;
    }

    if (cookie->fExpiresSet && FileTimeToSystemTime(&cookie->ftExpires, &st))
        InternetTimeFromSystemTimeW(&st, INTERNET_RFC1123_FORMAT, expires, sizeof(expires));

    len = lstrlenW(value) + (domain ? lstrlenW(domain) + 9 : 0) + (path ? lstrlenW(path) + 7 : 0)
            + (expires[0] ? lstrlenW(expires) + 10 : 0) + 18 + 1;
    if (!(data = malloc(len * sizeof(WCHAR))))
    {
        free(built_url);
        return ERROR_OUTOFMEMORY;
    }
    lstrcpyW(data, value);
    if (domain) { lstrcatW(data, L"; domain="); lstrcatW(data, domain); }
    if (path) { lstrcatW(data, L"; path="); lstrcatW(data, path); }
    if (expires[0]) { lstrcatW(data, L"; expires="); lstrcatW(data, expires); }
    if (cookie->dwFlags & COOKIE2_FLAG_SECURE) lstrcatW(data, L"; secure");

    if (cookie->dwFlags & COOKIE2_FLAG_HTTPONLY) lstrcatW(data, L"; httponly");

    res = InternetSetCookieExW(url, name, data,
            (cookie->dwFlags & COOKIE2_FLAG_HTTPONLY) ? INTERNET_COOKIE_HTTPONLY : 0, 0);
    if (res == COOKIE_STATE_UNKNOWN) err = GetLastError() ? GetLastError() : ERROR_INVALID_OPERATION;
    if (state) *state = res;

    free(data);
    free(built_url);
    return err;
}

/***********************************************************************
 *           InternetGetCookieEx2 (WININET.@)
 */
DWORD WINAPI InternetGetCookieEx2(const WCHAR *url, const WCHAR *name, DWORD flags,
        INTERNET_COOKIE2 **cookies, DWORD *count)
{
    cookie_set_t set = {0};
    substr_t host, path;
    INTERNET_COOKIE2 *result;
    DWORD res, n = 0, i;

    if (!cookies || !count || !url) return ERROR_INVALID_PARAMETER;
    *cookies = NULL;
    *count = 0;
    if (!cookie_parse_url(url, &host, &path)) return ERROR_INVALID_PARAMETER;
    EnterCriticalSection(&cookie_cs);
    res = get_cookie(host, path, (flags & INTERNET_COOKIE_NON_SCRIPT) ? INTERNET_COOKIE_HTTPONLY : 0, &set);
    if (res == ERROR_NO_MORE_ITEMS) res = ERROR_SUCCESS;
    if (res) goto done;
    result = calloc(set.cnt ? set.cnt : 1, sizeof(*result));
    if (!result) { res = ERROR_OUTOFMEMORY; goto done; }
    for (i = 0; i < set.cnt; i++)
    {
        cookie_t *c = set.cookies[i];
        INTERNET_COOKIE2 *out;
        if (name && wcscmp(name, c->name)) continue;
        out = &result[n++];
        out->pwszName = wcsdup(c->name);
        out->pwszValue = wcsdup(c->data);
        out->pwszDomain = wcsdup(c->container->domain->domain);
        out->pwszPath = strndupW(c->container->path.str, c->container->path.len);
        out->dwFlags = c->flags;
        out->ftExpires = c->expiry;
        out->fExpiresSet = c->expiry.dwLowDateTime || c->expiry.dwHighDateTime;
        if (!out->pwszName || !out->pwszValue || !out->pwszDomain || !out->pwszPath)
        {
            DWORD j;
            for (j = 0; j < n; j++)
            {
                free(result[j].pwszName); free(result[j].pwszValue);
                free(result[j].pwszDomain); free(result[j].pwszPath);
            }
            free(result); res = ERROR_OUTOFMEMORY; goto done;
        }
    }
    *cookies = result;
    *count = n;
done:
    free(set.cookies);
    LeaveCriticalSection(&cookie_cs);
    return res;
}

/***********************************************************************
 *           InternetFreeCookies (WININET.@)
 */
void WINAPI InternetFreeCookies(INTERNET_COOKIE2 *cookies, DWORD count)
{
    DWORD i;
    if (!cookies) return;
    for (i = 0; i < count; i++)
    {
        free(cookies[i].pwszName); free(cookies[i].pwszValue);
        free(cookies[i].pwszDomain); free(cookies[i].pwszPath);
    }
    free(cookies);
}
"""
(src / "cookie.c").write_text(code)
print("patched", src)
