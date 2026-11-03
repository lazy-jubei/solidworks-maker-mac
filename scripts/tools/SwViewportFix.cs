// EXPERIMENTAL view-only workaround; can crash sketch editing. Autorun is disabled.
// Keep SOLIDWORKS' OpenGL child beside the FeatureManager instead of covering it.
// Wine's Mac driver displays the GL child above GDI siblings. No vendor files change.
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
class SwViewportFix
{
    delegate bool EnumProc(IntPtr h,IntPtr p);
    [StructLayout(LayoutKind.Sequential)] struct RECT {public int l,t,r,b;}
    [StructLayout(LayoutKind.Sequential)] struct POINT {public int x,y;}
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f,IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h,EnumProc f,IntPtr p);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowTextW(IntPtr h,StringBuilder b,int n);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassNameW(IntPtr h,StringBuilder b,int n);
    [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsChild(IntPtr parent,IntPtr child);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h,out RECT r);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h,out RECT r);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h,ref POINT p);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    static string Name(IntPtr h,bool cls){var b=new StringBuilder(512);if(cls)GetClassNameW(h,b,512);else GetWindowTextW(h,b,512);return b.ToString();}
    static IntPtr Document(IntPtr h){
        for(IntPtr p=GetParent(h);p!=IntPtr.Zero;h=p,p=GetParent(h))
            if(Name(p,true)=="swMdiClient")return h;
        return IntPtr.Zero;
    }
    class Stable { public string Geometry; public DateTime Changed; }
    static readonly Dictionary<IntPtr,Stable> stable = new Dictionary<IntPtr,Stable>();
    static void Fix(IntPtr root,bool debug=false){
        var trees=new List<IntPtr>();var views=new List<IntPtr>();
        EnumChildWindows(root,(h,p)=>{
            string cls=Name(h,true);
            if(cls=="AfxFrameOrView140u" && Name(h,false)=="Tree Container Wnd" && IsWindowVisible(h))trees.Add(h);
            if(IsWindowVisible(h) && cls.StartsWith("Afx:") && cls.Contains(":2b:")){
                // This own-DC class plus document/geometry checks identifies the
                // viewport. Avoid cross-process DC acquisition. Even geometry-only
                // adjustment caused editing crashes, so this is diagnostic only.
                if(debug)Console.WriteLine("candidate "+h.ToString("x")+" "+cls);
                views.Add(h);
            }
            return true;
        },IntPtr.Zero);
        foreach(IntPtr view in views){
            IntPtr doc=Document(view),parent=GetParent(view);
            if(debug){Console.WriteLine("view="+view.ToString("x")+" doc="+doc.ToString("x")+" parent="+parent.ToString("x"));for(IntPtr p=view;p!=IntPtr.Zero;p=GetParent(p))Console.WriteLine("ancestor "+p.ToString("x")+" "+Name(p,true));}
            if(doc==IntPtr.Zero || parent==IntPtr.Zero)continue;
            RECT bounds,current;GetClientRect(parent,out bounds);GetWindowRect(view,out current);
            int width=bounds.r-bounds.l,height=bounds.b-bounds.t;
            if(width<800 || height<400 || Math.Abs(current.b-current.t-height)>8)continue;
            POINT origin=new POINT();ClientToScreen(parent,ref origin);
            int left=0;
            foreach(IntPtr tree in trees){
                if(!IsChild(doc,tree))continue;
                RECT r;GetWindowRect(tree,out r);
                if(Math.Abs(r.l-origin.x)<=8 && r.r-r.l>50 && r.r-r.l<width/2 && r.b-r.t>height/2)
                    left=Math.Max(left,r.r-origin.x);
            }
            // Wait for CAD's geometry to settle; mode changes (including entering
            // sketches) resize this window. Never fight that transition.
            string geometry=doc+":"+current.l+":"+current.t+":"+current.r+":"+current.b+":"+left+":"+width+":"+height;
            Stable state;
            if(!stable.TryGetValue(view,out state) || state.Geometry!=geometry){
                state=new Stable{Geometry=geometry,Changed=DateTime.UtcNow};stable[view]=state;
            }
            if(!debug && (DateTime.UtcNow-state.Changed).TotalSeconds<3)continue;
            if(current.l!=origin.x+left || current.r-current.l!=width-left)
                // ASYNCWINDOWPOS posts the resize to the owning UI thread.
                SetWindowPos(view,IntPtr.Zero,left,0,width-left,height,0x4014);
        }
    }
    [STAThread] static void Main(string[] args){
        SetProcessDPIAware();bool created;
        if(args.Length==1 && args[0]=="--once"){
            EnumWindows((h,p)=>{if(IsWindowVisible(h)&&Name(h,false).StartsWith("SOLIDWORKS Design Professional for Makers"))Fix(h,true);return true;},IntPtr.Zero);return;
        }
        using(var mutex=new Mutex(true,"Local\\SolidWorksWineViewportFix",out created)){
            if(!created)return;
            DateTime last=DateTime.UtcNow;
            while(true){
                bool found=false;
                EnumWindows((h,p)=>{
                    if(IsWindowVisible(h) && Name(h,false).StartsWith("SOLIDWORKS Design Professional for Makers")){
                        found=true;Fix(h);
                    }
                    return true;
                },IntPtr.Zero);
                if(found)last=DateTime.UtcNow;
                else if((DateTime.UtcNow-last).TotalSeconds>300)return;
                Thread.Sleep(1000);
            }
        }
    }
}
