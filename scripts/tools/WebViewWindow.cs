// Diagnose embedded WebView2 windows. Optional detach makes a cross-process
// child a standalone window, avoiding Wine Mac driver's foreign-parent GDI path.
// The detached page is owned by the login window and kept over its client area,
// so it moves with that window's title bar instead of sitting at the screen corner.
// Usage: WebViewWindow.exe [detach | follow]
//   detach: detach the page (if still embedded), line it up, and start one background follower.
//   follow: detach, then keep it lined up until the login window closes.
using System;
using System.Text;
using System.Threading;
using System.Collections.Generic;
using System.Runtime.InteropServices;
class WebViewWindow
{
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    delegate bool EnumProc(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h, EnumProc f, IntPtr p);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowTextW(IntPtr h, StringBuilder b, int n);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassNameW(IntPtr h, StringBuilder b, int n);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
    [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr SetParent(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] static extern int GetWindowLongW(IntPtr h, int n);
    [DllImport("user32.dll")] static extern int SetWindowLongW(IntPtr h, int n, int v);
    [DllImport("user32.dll")] static extern IntPtr SetWindowLongPtrW(IntPtr h, int n, IntPtr v);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);

    const int GWL_STYLE = -16, GWLP_HWNDPARENT = -8;
    const int WS_CHILD = 0x40000000, WS_POPUP = unchecked((int)0x80000000), WS_CAPTION_FRAME = 0x00cf0000;
    const uint GW_OWNER = 4;
    const uint SWP_NOACTIVATE = 0x10, SWP_FRAMECHANGED = 0x20, SWP_SHOWWINDOW = 0x40, SWP_NOZORDER = 0x4, SWP_NOOWNERZORDER = 0x200;

    const string FollowerName = "SolidWorksSigninPageFollower";
    static string Text(IntPtr h, bool cls) { var b=new StringBuilder(512); if(cls) GetClassNameW(h,b,512); else GetWindowTextW(h,b,512); return b.ToString(); }
    static uint Pid(IntPtr h) { uint p; GetWindowThreadProcessId(h,out p); return p; }

    // The Launcher's login window: titled "...3DEXPERIENCE ID..." and not itself a WebView2 page.
    static List<IntPtr> Hosts()
    {
        var hosts=new List<IntPtr>();
        EnumWindows((h,p)=> {
            // Visible only: a login frame the Launcher keeps hidden after sign-in shouldn't hold a follower.
            if (IsWindowVisible(h) && Text(h,false).Contains("3DEXPERIENCE ID") && !Text(h,true).StartsWith("Chrome_WidgetWin_")) hosts.Add(h);
            return true;
        },IntPtr.Zero);
        return hosts;
    }

    // Pages already detached from this host: top-level WebView2 windows from another process,
    // owned by the host, or left unowned by an older version of this tool.
    static List<IntPtr> Detached(IntPtr host)
    {
        var pages=new List<IntPtr>(); uint hostPid=Pid(host);
        EnumWindows((h,p)=> {
            if (Pid(h)==hostPid || !Text(h,true).StartsWith("Chrome_WidgetWin_") || !IsWindowVisible(h)) return true;
            IntPtr owner=GetWindow(h,GW_OWNER);
            string title=Text(h,false);
            if (owner==host || (owner==IntPtr.Zero && (title.Contains("3DEXPERIENCE ID") || title.Contains("SolidWorks sign-in")))) pages.Add(h);
            return true;
        },IntPtr.Zero);
        return pages;
    }

    static void Detach(IntPtr host, bool log)
    {
        uint hostPid=Pid(host);
        if (log) Console.WriteLine("host " + host.ToString("x") + " pid=" + hostPid + " " + Text(host,false));
        var embedded=new List<IntPtr>();
        EnumChildWindows(host,(h,q)=> {
            uint pid=Pid(h); string cls=Text(h,true);
            if (log) Console.WriteLine("child " + h.ToString("x") + " pid=" + pid + " parent=" + GetParent(h).ToString("x") + " visible=" + IsWindowVisible(h) + " class=" + cls);
            if (pid!=hostPid && Pid(GetParent(h))==hostPid && cls.StartsWith("Chrome_WidgetWin_")) embedded.Add(h);
            return true;
        },IntPtr.Zero);
        foreach (var h in embedded) {
            SetParent(h,IntPtr.Zero);
            // A borderless popup: Chrome draws over its whole window, so Wine would show no frame anyway.
            int style=GetWindowLongW(h,GWL_STYLE);
            SetWindowLongW(h,GWL_STYLE,(style & ~WS_CHILD & ~WS_CAPTION_FRAME) | WS_POPUP);
            Console.WriteLine("detached " + h.ToString("x"));
            Align(host,h,true);
        }
        if (log) foreach (var h in Detached(host)) Align(host,h,true);
    }

    static RECT Target(IntPtr host)
    {
        RECT c; GetClientRect(host,out c);
        var o=new POINT(); ClientToScreen(host,ref o);
        return new RECT { Left=o.X, Top=o.Y, Right=o.X+c.Right, Bottom=o.Y+c.Bottom };
    }

    // Owned by the host so it stays above it and minimises/closes with it; placed over its client area.
    static void Align(IntPtr host, IntPtr page, bool force)
    {
        if (GetWindow(page,GW_OWNER)!=host) { SetWindowLongPtrW(page,GWLP_HWNDPARENT,host); force=true; }
        if (IsIconic(host)) return;
        RECT t=Target(host), now; GetWindowRect(page,out now);
        if (!force && now.Left==t.Left && now.Top==t.Top && now.Right==t.Right && now.Bottom==t.Bottom) return;
        SetWindowPos(page,host,t.Left,t.Top,t.Right-t.Left,t.Bottom-t.Top,
                     SWP_NOACTIVATE|SWP_NOOWNERZORDER|SWP_SHOWWINDOW|(force?SWP_FRAMECHANGED:0));
        // Inserting after the host puts the page below it; bring it back in front of its owner.
        SetWindowPos(page,IntPtr.Zero,0,0,0,0,0x1|0x2|SWP_NOACTIVATE|SWP_NOOWNERZORDER);
    }

    static void Main(string[] args)
    {
        string mode=args.Length==1 ? args[0] : "";
        if (mode!="detach" && mode!="follow") {
            foreach (var host in Hosts()) {
                Console.WriteLine("host " + host.ToString("x") + " pid=" + Pid(host) + " " + Text(host,false));
                EnumChildWindows(host,(h,q)=> { Console.WriteLine("child " + h.ToString("x") + " pid=" + Pid(h) + " class=" + Text(h,true)); return true; },IntPtr.Zero);
                foreach (var h in Detached(host)) Console.WriteLine("detached " + h.ToString("x") + " owner=" + GetWindow(h,GW_OWNER).ToString("x"));
            }
            return;
        }
        var hosts0=Hosts();
        foreach (var host in hosts0) Detach(host,true);
        if (mode!="follow") {
            // The sign-in monitor calls detach every couple of seconds; only the first starts a follower.
            Mutex existing;
            if (hosts0.Count>0 && !Mutex.TryOpenExisting(FollowerName,out existing)) {
                var start=new System.Diagnostics.ProcessStartInfo(System.Reflection.Assembly.GetExecutingAssembly().Location,"follow");
                // Shell launch: no inherited handles, so the caller's output pipe isn't held open.
                start.UseShellExecute=true; start.WindowStyle=System.Diagnostics.ProcessWindowStyle.Hidden;
                System.Diagnostics.Process.Start(start);
            }
            return;
        }
        bool owned;
        var follower=new Mutex(true,FollowerName,out owned);
        if (!owned) return;
        // Follow the host until it closes. Cheap: one rect comparison per page every 30 ms.
        while (true) {
            var hosts=Hosts();
            if (hosts.Count==0) { GC.KeepAlive(follower); return; }
            foreach (var host in hosts) {
                Detach(host,false);
                foreach (var h in Detached(host)) Align(host,h,false);
            }
            Thread.Sleep(30);
        }
    }
}
