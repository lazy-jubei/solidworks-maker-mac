// Explicitly targeted input. Text is read from stdin, never a command-line argument.
// Usage: WinInput.exe <exact title> [click x y | key virtual-key | text | info]
using System;
using System.Text;
using System.Threading;
using System.Runtime.InteropServices;
class WinInput
{
    delegate bool EnumProc(IntPtr h, IntPtr p);
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int x,y; }
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int l,t,r,b; }
    [StructLayout(LayoutKind.Explicit,Size=40)] struct INPUT {
        [FieldOffset(0)] public uint type;
        [FieldOffset(8)] public int dx;
        [FieldOffset(12)] public int dy;
        [FieldOffset(20)] public uint mouseFlags;
        [FieldOffset(8)] public ushort vk;
        [FieldOffset(10)] public ushort scan;
        [FieldOffset(12)] public uint keyFlags;
    }
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h,EnumProc f,IntPtr p);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassNameW(IntPtr h,StringBuilder b,int n);
    [DllImport("user32.dll")] static extern bool PostMessageW(IntPtr h,uint msg,IntPtr w,IntPtr l);
    [DllImport("user32.dll")] static extern IntPtr SendMessageW(IntPtr h,uint msg,IntPtr w,IntPtr l);
    [DllImport("user32.dll")] static extern bool ScreenToClient(IntPtr h,ref POINT p);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowTextW(IntPtr h,StringBuilder b,int n);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr h);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
    [StructLayout(LayoutKind.Sequential)] struct GUITHREADINFO {public int size,flags;public IntPtr active,focus,capture,menuOwner,moveSize,caret;public RECT caretRect;}
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread,ref GUITHREADINFO info);
    [DllImport("user32.dll")] static extern int GetDlgCtrlID(IntPtr h);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h,out RECT r);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h,out RECT r);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h,ref POINT p);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x,int y);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll")] static extern uint SendInput(uint n,INPUT[] i,int size);
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr h,out uint mode);
    [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr h,uint mode);
    static string ReadText() {
        IntPtr h=GetStdHandle(-10);uint mode;bool console=GetConsoleMode(h,out mode);
        if(console)SetConsoleMode(h,mode & ~4u);
        string text=Console.ReadLine();if(console)SetConsoleMode(h,mode);
        return text;
    }
    static void Send(INPUT i) { if(SendInput(1,new[]{i},40)!=1) throw new Exception("SendInput failed"); }
    static int Main(string[] a) {
        SetProcessDPIAware();
        if(a[0]=="--children") {
            IntPtr root=(IntPtr)Convert.ToInt64(a[1],16);
            EnumChildWindows(root,(h,p)=>{var b=new StringBuilder(512);GetWindowTextW(h,b,512);var c=new StringBuilder(256);GetClassNameW(h,c,256);RECT rr,pos;GetClientRect(h,out rr);GetWindowRect(h,out pos);Console.WriteLine(h.ToString("x")+" "+c+" "+(rr.r-rr.l)+"x"+(rr.b-rr.t)+" at="+pos.l+","+pos.t+" visible="+IsWindowVisible(h)+" "+b+(c.ToString()=="SysTreeView32" ? " items="+SendMessageW(h,0x1105,IntPtr.Zero,IntPtr.Zero):""));return true;},IntPtr.Zero);
            return 0;
        }
        if(a[0]=="--list") {
            EnumWindows((h,p)=>{if(IsWindowVisible(h)){var b=new StringBuilder(512);GetWindowTextW(h,b,512);var c=new StringBuilder(256);GetClassNameW(h,c,256);RECT rr;GetClientRect(h,out rr);Console.WriteLine(h.ToString("x")+" "+c+" "+(rr.r-rr.l)+"x"+(rr.b-rr.t)+" "+b);}return true;},IntPtr.Zero);
            return 0;
        }
        IntPtr target=IntPtr.Zero;
        if(a[0].StartsWith("hwnd:")){target=(IntPtr)Convert.ToInt64(a[0].Substring(5),16);if(!IsWindow(target)||!IsWindowVisible(target))target=IntPtr.Zero;}
        else EnumWindows((h,p)=>{var b=new StringBuilder(512);GetWindowTextW(h,b,512);if(IsWindowVisible(h)&&b.ToString()==a[0]){target=h;return false;}return true;},IntPtr.Zero);
        if(target==IntPtr.Zero){Console.WriteLine("No matching visible window");return 1;}
        RECT r;GetClientRect(target,out r); Console.WriteLine("client "+(r.r-r.l)+"x"+(r.b-r.t));
        if(a[1]=="hit"){
            POINT point=new POINT{x=int.Parse(a[2]),y=int.Parse(a[3])};ClientToScreen(target,ref point);
            Console.WriteLine("Screen point: "+point.x+","+point.y+" foreground="+GetForegroundWindow().ToString("x")+" left-state="+GetAsyncKeyState(1));
            POINT cursor;GetCursorPos(out cursor);Console.WriteLine("Actual cursor: "+cursor.x+","+cursor.y+" hit="+WindowFromPoint(cursor).ToString("x"));
            IntPtr hit=WindowFromPoint(point);Console.WriteLine("Hit: "+hit.ToString("x"));
            uint pid;uint thread=GetWindowThreadProcessId(target,out pid);var info=new GUITHREADINFO();info.size=Marshal.SizeOf(info);
            if(GetGUIThreadInfo(thread,ref info))Console.WriteLine("CAD active="+info.active.ToString("x")+" focus="+info.focus.ToString("x")+" capture="+info.capture.ToString("x"));
            for(int i=0;hit!=IntPtr.Zero && i<16;i++,hit=GetParent(hit)){
                var cls=new StringBuilder(256);var text=new StringBuilder(256);GetClassNameW(hit,cls,256);GetWindowTextW(hit,text,256);
                Console.WriteLine(hit.ToString("x")+" "+cls+" ctrl="+GetDlgCtrlID(hit)+" enabled="+IsWindowEnabled(hit)+" "+text);
            }
            return 0;
        }
        if(a[1]=="info"){RECT pos;GetWindowRect(target,out pos);Console.WriteLine("window "+pos.l+" "+pos.t+" "+(pos.r-pos.l)+" "+(pos.b-pos.t));return 0;}
        if(a[1]=="press"){SendMessageW(target,0xF5,IntPtr.Zero,IntPtr.Zero);return 0;}
        if(a[1]=="combo-list"){
            int count=SendMessageW(target,0x146,IntPtr.Zero,IntPtr.Zero).ToInt32();
            Console.WriteLine("Selected: "+SendMessageW(target,0x147,IntPtr.Zero,IntPtr.Zero));
            if(count<0 || count>100)return 6;
            for(int i=0;i<count;i++){
                int length=SendMessageW(target,0x149,(IntPtr)i,IntPtr.Zero).ToInt32();
                if(length<0 || length>4096)return 6;
                IntPtr text=Marshal.AllocHGlobal((length+1)*2);
                try{SendMessageW(target,0x148,(IntPtr)i,text);Console.WriteLine(i+": "+Marshal.PtrToStringUni(text));}
                finally{Marshal.FreeHGlobal(text);}
            }
            return 0;
        }
        if(a[1]=="combo-select"){
            int index=int.Parse(a[2]);
            if(SendMessageW(target,0x14E,(IntPtr)index,IntPtr.Zero).ToInt32()<0)return 6;
            PostMessageW(GetParent(target),0x111,(IntPtr)((1<<16)|(GetDlgCtrlID(target)&65535)),target);
            return 0;
        }
        if(a[1]=="close"){PostMessageW(target,0x10,IntPtr.Zero,IntPtr.Zero);return 0;}
        if(a[1]=="move"){Console.WriteLine("Moved: "+SetWindowPos(target,IntPtr.Zero,int.Parse(a[2]),int.Parse(a[3]),int.Parse(a[4]),int.Parse(a[5]),0x14));return 0;}
        if(a[1].StartsWith("post")) {
            IntPtr render=IntPtr.Zero;int count=0;
            EnumChildWindows(target,(h,p)=>{var b=new StringBuilder(256);GetClassNameW(h,b,256);if(IsWindowVisible(h)&&b.ToString()=="Chrome_RenderWidgetHostHWND"){render=h;count++;}return true;},IntPtr.Zero);
            if(count!=1){if(a[1]=="postkey" && count==0)render=target;else {Console.WriteLine("Expected exactly one browser input window");return 4;}}
            if(a[1]=="postclick"){
                POINT p=new POINT{x=int.Parse(a[2]),y=int.Parse(a[3])};ClientToScreen(target,ref p);ScreenToClient(render,ref p);
                IntPtr pos=(IntPtr)((p.y<<16)|(p.x&65535));
                PostMessageW(render,0x200,IntPtr.Zero,pos);PostMessageW(render,0x201,(IntPtr)1,pos);PostMessageW(render,0x202,IntPtr.Zero,pos);
            }else if(a[1]=="posttext" || a[1]=="postenv"){
                string text=a[1]=="postenv" ? Environment.GetEnvironmentVariable("SW_INPUT_TEXT") : ReadText();
                Environment.SetEnvironmentVariable("SW_INPUT_TEXT",null);
                if(text==null){Console.WriteLine("No input received");return 5;}
                foreach(char c in text)PostMessageW(render,0x102,(IntPtr)c,IntPtr.Zero);
                Console.WriteLine("Text entered");
            }else if(a[1]=="postkey"){
                IntPtr k=(IntPtr)int.Parse(a[2]);PostMessageW(render,0x100,k,IntPtr.Zero);PostMessageW(render,0x101,k,(IntPtr)0xc0000001L);
            }else return 3;
            return 0;
        }
        if(!SetForegroundWindow(target)){Console.WriteLine("Could not foreground target");return 2;}Thread.Sleep(150);
        if(a[1]=="click"){
            POINT p=new POINT{x=int.Parse(a[2]),y=int.Parse(a[3])};ClientToScreen(target,ref p);SetCursorPos(p.x,p.y);Thread.Sleep(100);
            Send(new INPUT{mouseFlags=2});Send(new INPUT{mouseFlags=4});
        } else if(a[1]=="key") {
            ushort k=ushort.Parse(a[2]);Send(new INPUT{type=1,vk=k});Send(new INPUT{type=1,vk=k,keyFlags=2});
        } else if(a[1]=="text") {
            string text=ReadText();if(text==null){Console.WriteLine("No input received");return 5;}foreach(char c in text){Send(new INPUT{type=1,scan=c,keyFlags=4});Send(new INPUT{type=1,scan=c,keyFlags=6});}
            Console.WriteLine("Text entered");
        } else return 3;
        return 0;
    }
}
