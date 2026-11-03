#!/usr/bin/env python3
"""Opt-in consistency correction for Wine 11.16's hardcoded High integrity SID.

Only a token explicitly reported as TokenElevationTypeLimited is adjusted.
Elevated tokens remain untouched. No token privileges or access rights change.
"""
import pathlib
import sys

path = pathlib.Path(sys.argv[1]) / 'dlls/kernelbase/security.c'
code = path.read_text()
old = '    return set_ntstatus( NtQueryInformationToken( token, class, info, len, retlen ));\n'
new = r'''    NTSTATUS status = NtQueryInformationToken( token, class, info, len, retlen );

    /* ntdll currently hardcodes High IL even for a limited token. Keep that
     * result consistent with the limited token for opt-in WebView hosts. */
    if (!status && class == TokenIntegrityLevel)
    {
        DWORD saved_error = GetLastError();
        WCHAR image[MAX_PATH], *filename;
        DWORD length = GetEnvironmentVariableW( L"SW_REPORT_STANDARD_INTEGRITY", NULL, 0 )
                ? GetModuleFileNameW( NULL, image, ARRAY_SIZE(image) ) : 0;
        BOOL webview_host = FALSE;
        if (length && length < ARRAY_SIZE(image))
        {
            filename = wcsrchr( image, L'\\' );
            filename = filename ? filename + 1 : image;
            webview_host = !wcsicmp( filename, L"SWXDesktopLauncher.exe" )
                    || !wcsicmp( filename, L"msedgewebview2.exe" )
                    || !wcsicmp( filename, L"token-probe.exe" ); /* diagnostic only */
        }
        if (webview_host)
        {
            TOKEN_ELEVATION_TYPE type;
            ULONG size;
            TOKEN_MANDATORY_LABEL *label = info;
            if (!NtQueryInformationToken( token, TokenElevationType, &type, sizeof(type), &size )
                    && type == TokenElevationTypeLimited && RtlValidSid( label->Label.Sid )
                    && *RtlSubAuthorityCountSid( label->Label.Sid ))
            {
                ULONG *rid = RtlSubAuthoritySid( label->Label.Sid,
                        *RtlSubAuthorityCountSid( label->Label.Sid ) - 1 );
                if (*rid == SECURITY_MANDATORY_HIGH_RID) *rid = SECURITY_MANDATORY_MEDIUM_RID;
            }
        }
        SetLastError( saved_error );
    }
    return set_ntstatus( status );
'''
if 'SW_REPORT_STANDARD_INTEGRITY' in code:
    start = code.index('    NTSTATUS status = NtQueryInformationToken( token, class, info, len, retlen );')
    tail = '    return set_ntstatus( status );\n'
    end = code.index(tail, start) + len(tail)
    path.write_text(code[:start] + new + code[end:])
    print('updated', path)
elif code.count(old) != 1:
    sys.exit('expected GetTokenInformation body not found')
else:
    path.write_text(code.replace(old, new))
    print('patched', path)
