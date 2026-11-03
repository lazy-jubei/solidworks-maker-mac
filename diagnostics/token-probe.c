#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc,char **argv)
{
    HANDLE process=argc>1?OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,strtoul(argv[1],NULL,0)):GetCurrentProcess();
    HANDLE token;DWORD size;TOKEN_ELEVATION elevation;TOKEN_ELEVATION_TYPE type;
    BYTE buffer[512];TOKEN_MANDATORY_LABEL *label=(TOKEN_MANDATORY_LABEL *)buffer;
    if(!process || !OpenProcessToken(process,TOKEN_QUERY,&token)){printf("Open token error %lu\n",GetLastError());return 1;}
    if(GetTokenInformation(token,TokenElevation,&elevation,sizeof(elevation),&size))printf("elevated=%lu\n",elevation.TokenIsElevated);
    if(GetTokenInformation(token,TokenElevationType,&type,sizeof(type),&size))printf("elevation_type=%u\n",type);
    if(GetTokenInformation(token,TokenIntegrityLevel,buffer,sizeof(buffer),&size)) {
        PSID sid=label->Label.Sid;
        printf("integrity_rid=%lu\n",*GetSidSubAuthority(sid,*GetSidSubAuthorityCount(sid)-1));
    }
    CloseHandle(token);if(argc>1)CloseHandle(process);return 0;
}
