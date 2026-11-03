/* Bounded, thread-scoped mouse/confirmation diagnostic. No keyboard/text capture.
 * Build twice with llvm-mingw: -DSW_TRACE_DLL -shared for the hook DLL, without
 * that define for the host. Host usage: input-trace.exe <CAD root HWND hex> <DLL>.
 * Records messages in shared memory to avoid file I/O inside CAD's event loop. */
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <stdio.h>
#include <wchar.h>
#define COUNT 256
struct entry { DWORD tick,kind,msg; ULONG_PTR hwnd,wparam,lparam,capture; SHORT left; };
struct shared { volatile LONG count; struct entry entries[COUNT]; };
static void name_for(WCHAR *name,DWORD thread) { swprintf(name,80,L"Local\\SwMouseTrace2_%lu",thread); }
#ifdef SW_TRACE_DLL
static struct shared *data;
static HANDLE mapping;
static void record(DWORD kind,HWND hwnd,UINT msg,WPARAM wp,LPARAM lp) {
    LONG i;
    if (msg!=WM_LBUTTONDOWN && msg!=WM_LBUTTONUP && msg!=WM_CAPTURECHANGED &&
        msg!=WM_CANCELMODE && msg!=WM_SETFOCUS && msg!=WM_KILLFOCUS && msg!=WM_ACTIVATE && msg!=WM_ACTIVATEAPP &&
        !(msg==WM_COMMAND && (LOWORD(wp)==4900 || LOWORD(wp)==4903))) return;
    if (!data) {
        WCHAR name[80];name_for(name,GetCurrentThreadId());
        mapping=OpenFileMappingW(FILE_MAP_ALL_ACCESS,FALSE,name);
        if (!mapping) return;
        data=MapViewOfFile(mapping,FILE_MAP_ALL_ACCESS,0,0,sizeof(*data));
        if (!data) return;
    }
    i=InterlockedIncrement(&data->count)-1;
    if (i>=COUNT) return;
    data->entries[i]=(struct entry){GetTickCount(),kind,msg,(ULONG_PTR)hwnd,(ULONG_PTR)wp,(ULONG_PTR)lp,(ULONG_PTR)GetCapture(),GetAsyncKeyState(VK_LBUTTON)};
}
__declspec(dllexport) LRESULT CALLBACK trace_getmsg(int code,WPARAM wp,LPARAM lp) {
    if (code==HC_ACTION && wp==PM_REMOVE) { const MSG *m=(const MSG*)lp;record(1,m->hwnd,m->message,m->wParam,m->lParam); }
    return CallNextHookEx(NULL,code,wp,lp);
}
__declspec(dllexport) LRESULT CALLBACK trace_sent(int code,WPARAM wp,LPARAM lp) {
    if (code==HC_ACTION) { const CWPSTRUCT *m=(const CWPSTRUCT*)lp;record(2,m->hwnd,m->message,m->wParam,m->lParam); }
    return CallNextHookEx(NULL,code,wp,lp);
}
BOOL WINAPI DllMain(HINSTANCE module,DWORD reason,void *reserved) {
    if (reason==DLL_PROCESS_DETACH) { if(data)UnmapViewOfFile(data);if(mapping)CloseHandle(mapping); }
    return TRUE;
}
#else
int wmain(int argc,WCHAR **argv) {
    HWND root;DWORD pid,thread;WCHAR title[512],name[80];HANDLE map;struct shared *shared;
    HMODULE dll;HHOOK queued,sent;
    if(argc!=3)return 2;
    root=(HWND)(ULONG_PTR)wcstoull(argv[1],NULL,16);
    if(!IsWindowVisible(root) || !GetWindowTextW(root,title,512) ||
        wcsncmp(title,L"SOLIDWORKS Design Professional for Makers",40)) {
        puts("Refusing: expected visible Makers CAD root window");return 2;
    }
    thread=GetWindowThreadProcessId(root,&pid);name_for(name,thread);
    map=CreateFileMappingW(INVALID_HANDLE_VALUE,NULL,PAGE_READWRITE,0,sizeof(*shared),name);
    if(!map || GetLastError()==ERROR_ALREADY_EXISTS){puts("Cannot create unique trace mapping");return 3;}
    shared=MapViewOfFile(map,FILE_MAP_ALL_ACCESS,0,0,sizeof(*shared));
    if(!shared)return 3;
    dll=LoadLibraryW(argv[2]);if(!dll){printf("DLL load failed %lu\n",GetLastError());return 3;}
    queued=SetWindowsHookExW(WH_GETMESSAGE,(HOOKPROC)GetProcAddress(dll,"trace_getmsg"),dll,thread);
    sent=SetWindowsHookExW(WH_CALLWNDPROC,(HOOKPROC)GetProcAddress(dll,"trace_sent"),dll,thread);
    if(!queued || !sent){printf("Hook installation failed %lu\n",GetLastError());if(queued)UnhookWindowsHookEx(queued);if(sent)UnhookWindowsHookEx(sent);return 3;}
    printf("Mouse-only trace active on CAD thread %lu for 35 seconds\n",thread);fflush(stdout);
    Sleep(35000);UnhookWindowsHookEx(queued);UnhookWindowsHookEx(sent);
    for(LONG i=0;i<shared->count && i<COUNT;i++){
        struct entry e=shared->entries[i];
        printf("tick=%lu kind=%lu hwnd=%llx msg=%04lx wp=%llx lp=%llx capture=%llx left=%04x\n",e.tick,e.kind,
            (unsigned long long)e.hwnd,e.msg,(unsigned long long)e.wparam,(unsigned long long)e.lparam,(unsigned long long)e.capture,(USHORT)e.left);
    }
    printf("Trace stopped; records=%ld\n",shared->count);
    UnmapViewOfFile(shared);CloseHandle(map);FreeLibrary(dll);return 0;
}
#endif
