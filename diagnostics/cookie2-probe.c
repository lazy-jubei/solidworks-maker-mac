/* Synthetic cookie API regression: never uses account/session cookies. */
#include <windows.h>
#include <wininet.h>
#include <stdio.h>
#include <wchar.h>
typedef struct { WCHAR *name,*value,*domain,*path; DWORD flags; FILETIME expiry; BOOL expires; } COOKIE2;
typedef DWORD (WINAPI *SET)(const WCHAR *,const COOKIE2 *,const WCHAR *,DWORD,DWORD *);
typedef DWORD (WINAPI *GET)(const WCHAR *,const WCHAR *,DWORD,COOKIE2 **,DWORD *);
typedef void (WINAPI *FREE)(COOKIE2 *,DWORD);
int main(void) {
 HMODULE lib=LoadLibraryW(L"wininet.dll");
 SET set=(SET)GetProcAddress(lib,"InternetSetCookieEx2");
 GET get=(GET)GetProcAddress(lib,"InternetGetCookieEx2");
 FREE release=(FREE)GetProcAddress(lib,"InternetFreeCookies");
 COOKIE2 c={L"SW_COOKIE_PROBE",L"synthetic-value",NULL,L"/",INTERNET_COOKIE_HTTPONLY|INTERNET_COOKIE_IS_SECURE,{0},FALSE},*out=NULL;
 DWORD state=0,count=0,status; WCHAR buf[512];DWORD size=512;BOOL legacy;
 if(!set||!get||!release)return 2;
 status=set(L"https://sw-cookie-probe.invalid/",&c,NULL,0,&state);
 printf("set status=%lu state=%lu\n",status,state);if(status)return 3;
 legacy=InternetGetCookieExW(L"https://sw-cookie-probe.invalid/",NULL,buf,&size,INTERNET_COOKIE_HTTPONLY,NULL);
 printf("legacy matching=%d\n",legacy && wcsstr(buf,L"SW_COOKIE_PROBE=synthetic-value")!=NULL);
 if(!legacy || !wcsstr(buf,L"SW_COOKIE_PROBE=synthetic-value"))return 4;
 status=get(L"https://sw-cookie-probe.invalid/",c.name,INTERNET_COOKIE_NON_SCRIPT,&out,&count);
 printf("get status=%lu count=%lu\n",status,count);
 if(status||count!=1)return 5;
 if(wcscmp(out[0].name,c.name)||wcscmp(out[0].value,c.value))return 6;
 release(out,count);out=NULL;count=0;
 status=get(L"https://sw-cookie-probe.invalid/",c.name,0,&out,&count);
 printf("script query status=%lu count=%lu\n",status,count);release(out,count);
 return status||count?7:0;
}
