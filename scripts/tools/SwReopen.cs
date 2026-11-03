// Verify that a saved test part survives close/reopen with the expected volume.
// Usage: SwReopen.exe <test part path> <expected volume in cubic metres>
using System;
using System.Globalization;
using System.Reflection;
using System.Runtime.InteropServices;
class SwReopen
{
    static object Call(object o,string n,params object[] a){return o.GetType().InvokeMember(n,BindingFlags.InvokeMethod,null,o,a);}
    static object Get(object o,string n){return o.GetType().InvokeMember(n,BindingFlags.GetProperty,null,o,null);}
    static int Main(string[] a){
        object sw=Marshal.GetActiveObject("SldWorks.Application");
        string name=System.IO.Path.GetFileName(a[0]);
        Call(sw,"CloseDoc",name);
        object doc=Call(sw,"OpenDoc",a[0],1);
        if(doc==null){Console.WriteLine("Reopen failed");return 1;}
        object ext=Get(doc,"Extension");
        double volume=Convert.ToDouble(Get(Call(ext,"CreateMassProperty"),"Volume"));
        double expected=double.Parse(a[1],CultureInfo.InvariantCulture);
        Call(doc,"ShowNamedView2","*Isometric",7);Call(doc,"ViewZoomtofit2");
        Console.WriteLine("Reopened: "+Call(doc,"GetTitle"));
        Console.WriteLine("Volume m3: "+volume.ToString("R",CultureInfo.InvariantCulture));
        Console.WriteLine("Volume matches: "+(Math.Abs(volume-expected)<1e-12));
        return Math.Abs(volume-expected)<1e-12 ? 0:2;
    }
}
