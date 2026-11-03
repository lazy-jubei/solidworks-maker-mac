/*
 * Helper DLL for functions Wine's ntdll doesn't export. ntdll.dll forwards to it (see
 * pe-add-forward-exports.py) so that the Staging ntdll's own code stays untouched.
 *
 * SOLIDWORKS' JS0CORBADicExe looks up RtlIsNameInExpression and exits if it's missing.
 *
 * This library is free software; you can redistribute it and/or modify it under the terms
 * of the GNU Lesser General Public License as published by the Free Software Foundation;
 * either version 2.1 of the License, or (at your option) any later version.
 */

typedef unsigned short WCHAR;
typedef unsigned char BOOLEAN;

typedef struct
{
    unsigned short Length;
    unsigned short MaximumLength;
    WCHAR *Buffer;
} UNICODE_STRING;

__declspec(dllimport) WCHAR __stdcall RtlUpcaseUnicodeChar(WCHAR ch);

#define DOS_STAR 0x3c /* '<' */
#define DOS_QM   0x3e /* '>' */
#define DOS_DOT  0x22 /* '"' */

static int same(WCHAR a, WCHAR b, BOOLEAN ignore_case)
{
    if (a == b) return 1;
    return ignore_case && RtlUpcaseUnicodeChar(a) == RtlUpcaseUnicodeChar(b);
}

static int match(const WCHAR *e, int elen, const WCHAR *n, int nlen, BOOLEAN ignore_case)
{
    int i;

    while (elen)
    {
        WCHAR c = *e;

        if (c == '*' || c == DOS_STAR)
        {
            int limit = nlen;

            /* DOS_STAR doesn't go past the final dot. */
            if (c == DOS_STAR)
                for (i = nlen - 1; i >= 0; i--)
                    if (n[i] == '.') { limit = i; break; }
            for (i = 0; i <= limit; i++)
                if (match(e + 1, elen - 1, n + i, nlen - i, ignore_case)) return 1;
            return 0;
        }
        if (c == DOS_QM)
        {
            /* One character, or nothing at the end of the name or before a dot. */
            if (nlen && *n != '.') { n++; nlen--; }
        }
        else if (c == DOS_DOT)
        {
            /* A dot, or nothing at the end of the name. */
            if (nlen)
            {
                if (*n != '.') return 0;
                n++;
                nlen--;
            }
        }
        else
        {
            if (!nlen) return 0;
            if (c != '?' && !same(c, *n, ignore_case)) return 0;
            n++;
            nlen--;
        }
        e++;
        elen--;
    }
    return !nlen;
}

__declspec(dllexport) BOOLEAN __stdcall RtlIsNameInExpression(const UNICODE_STRING *expression,
        const UNICODE_STRING *name, BOOLEAN ignore_case, const WCHAR *upcase_table)
{
    (void)upcase_table;
    return match(expression->Buffer, expression->Length / sizeof(WCHAR),
                 name->Buffer, name->Length / sizeof(WCHAR), ignore_case);
}

int __stdcall DllMainCRTStartup(void *module, unsigned long reason, void *reserved)
{
    return 1;
}
