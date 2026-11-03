// Diagnose embedded WebView2 windows. Optional detach makes a cross-process
// child a standalone window, avoiding Wine Mac driver's foreign-parent GDI path.
// Usage: WebViewWindow.exe [detach]
using System;
using System.Text;
using System.Runtime.InteropServices;
class WebViewWindow
{
    delegate bool EnumProc(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h, EnumProc f, IntPtr p);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowTextW(IntPtr h, StringBuilder b, int n);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassNameW(IntPtr h, StringBuilder b, int n);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
    [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr SetParent(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] static extern int GetWindowLongW(IntPtr h, int n);
    [DllImport("user32.dll")] static extern int SetWindowLongW(IntPtr h, int n, int v);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool SetWindowTextW(IntPtr h, string s);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    static string Text(IntPtr h, bool cls) { var b=new StringBuilder(512); if(cls) GetClassNameW(h,b,512); else GetWindowTextW(h,b,512); return b.ToString(); }
    static void Main(string[] args)
    {
        bool detach=args.Length==1 && args[0]=="detach";
        EnumWindows((root,p)=> {
            string title=Text(root,false);
            if (!title.Contains("3DEXPERIENCE ID")) return true;
            uint rootPid; GetWindowThreadProcessId(root,out rootPid);
            Console.WriteLine("host " + root.ToString("x") + " pid=" + rootPid + " " + title);
            EnumChildWindows(root,(h,q)=> {
                uint pid; GetWindowThreadProcessId(h,out pid);
                string cls=Text(h,true);
                Console.WriteLine("child " + h.ToString("x") + " pid=" + pid + " parent=" + GetParent(h).ToString("x") + " visible=" + IsWindowVisible(h) + " class=" + cls);
                uint parentPid; GetWindowThreadProcessId(GetParent(h),out parentPid);
                if(detach && pid!=rootPid && parentPid==rootPid && cls.StartsWith("Chrome_WidgetWin_")) {
                    SetParent(h,IntPtr.Zero);
                    int style=GetWindowLongW(h,-16);
                    SetWindowLongW(h,-16,(style & ~0x40000000) | 0x00cf0000);
                    SetWindowTextW(h,"SolidWorks sign-in (Wine workaround)");
                    SetWindowPos(h,IntPtr.Zero,120,80,1200,1000,0x0060);
                    ShowWindow(h,5);
                    Console.WriteLine("detached " + h.ToString("x"));
                }
                return true;
            },IntPtr.Zero);
            return true;
        },IntPtr.Zero);
    }
}
