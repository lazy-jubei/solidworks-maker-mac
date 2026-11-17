#!/usr/bin/env python3
"""Decline the 3DEXPERIENCE sign-in server's password prompt without showing Wine's dialog.

During a fresh sign-in, SWXDesktopLauncher.exe asks InternetErrorDlg about a 401 from
*.iam.3dexperience.3ds.com (realm "CAS Server"). Wine answers with its generic password box,
which the sign-in monitor then cancels; the real sign-in happens in the embedded browser.
Return that same ERROR_CANCELLED at once for this host only, so no box flashes up.
Other hosts keep Wine's normal dialog. Idempotent.

Usage: wininet-cas-auth-cancel.py <wine source dir>
"""
import pathlib
import sys

path = pathlib.Path(sys.argv[1]) / "dlls" / "wininet" / "dialogs.c"
code = path.read_text()
if "is_3dexperience_signin_server" in code:
    sys.exit(0)

helper = r'''
/* The 3DEXPERIENCE Launcher's sign-in happens in its browser; its 401 needs no password box. */
static BOOL is_3dexperience_signin_server( http_request_t *req )
{
    static const WCHAR suffix[] = L".iam.3dexperience.3ds.com";
    size_t len, suffix_len = ARRAY_SIZE(suffix) - 1;

    if (!req->server || !req->server->name) return FALSE;
    len = wcslen( req->server->name );
    return len > suffix_len && !wcsicmp( req->server->name + len - suffix_len, suffix );
}

/***********************************************************************
 *         InternetErrorDlg
 */'''
anchor = '''
/***********************************************************************
 *         InternetErrorDlg
 */'''
old_case = '''        case HTTP_STATUS_DENIED:
            res = DialogBoxParamW( WININET_hModule, MAKEINTRESOURCEW( IDD_AUTHDLG ),'''
new_case = '''        case HTTP_STATUS_DENIED:
            if (is_3dexperience_signin_server( req ))
            {
                res = ERROR_CANCELLED;
                break;
            }
            res = DialogBoxParamW( WININET_hModule, MAKEINTRESOURCEW( IDD_AUTHDLG ),'''
if code.count(anchor) != 1 or code.count(old_case) != 1:
    sys.exit("unrecognized wininet dialogs.c")
code = code.replace(anchor, helper).replace(old_case, new_case)
path.write_text(code)
