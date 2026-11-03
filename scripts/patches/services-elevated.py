#!/usr/bin/env python3
"""Make Wine 11.16's services.exe start services with an elevated token.

On Windows, services run with full rights. Wine starts them with its default limited
token, so the 3DEXPERIENCE Launcher's admin pipe server (StartTUI --pipeserver) decides it
isn't elevated and exits, and the installer GUI fails with "Failed to send Execute to
named pipe server: File not found".

Usage: services-elevated.py <wine source dir>
"""
import pathlib
import sys

path = pathlib.Path(sys.argv[1]) / "programs" / "services" / "services.c"
code = path.read_text()


def replace(text, old, new):
    if text.count(old) != 1:
        sys.exit(f"expected exactly one match for: {old[:60]!r}")
    return text.replace(old, new)


code = replace(code, """static DWORD service_start_process(struct service_entry *service_entry, struct process_entry **new_process,""",
"""/* Returns the elevated token linked to the current limited one, or NULL. */
static HANDLE get_elevated_token(void)
{
    TOKEN_ELEVATION_TYPE type;
    TOKEN_LINKED_TOKEN linked;
    DWORD size;

    if (!GetTokenInformation(GetCurrentProcessToken(), TokenElevationType, &type, sizeof(type), &size)
            || type != TokenElevationTypeLimited)
        return NULL;
    if (!GetTokenInformation(GetCurrentProcessToken(), TokenLinkedToken, &linked, sizeof(linked), &size))
        return NULL;
    return linked.LinkedToken;
}

static DWORD service_start_process(struct service_entry *service_entry, struct process_entry **new_process,""")
code = replace(code, """    r = CreateProcessW(NULL, path, NULL, NULL, FALSE, CREATE_UNICODE_ENVIRONMENT | DETACHED_PROCESS,""",
"""    token = get_elevated_token();
    r = CreateProcessAsUserW(token, NULL, path, NULL, NULL, FALSE, CREATE_UNICODE_ENVIRONMENT | DETACHED_PROCESS,""")
code = replace(code, """    free(path);
    if (!r)
    {
        err = GetLastError();
        process_terminate(process);""", """    err = GetLastError();
    if (token)
        CloseHandle(token);
    free(path);
    if (!r)
    {
        process_terminate(process);""")
path.write_text(code)
print("patched", path)
