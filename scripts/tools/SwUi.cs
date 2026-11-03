// Inspect FeatureManager width, or invoke its normal visibility command.
using System;
using System.Reflection;
using System.Runtime.InteropServices;
class SwUi {
    static object Call(object o,string n,params object[] a){return o.GetType().InvokeMember(n,BindingFlags.InvokeMethod,null,o,a);}
    static object Get(object o,string n){return o.GetType().InvokeMember(n,BindingFlags.GetProperty,null,o,null);}
    static void Main(string[] args){
        object sw=Marshal.GetActiveObject("SldWorks.Application");
        if(args.Length==1 && args[0]=="new") {Console.WriteLine("New dialog: "+Call(sw,"RunCommand",1,""));return;}
        if(args.Length==1 && args[0]=="templates") {
            foreach(int pref in new[]{6,8,9,10}) Console.WriteLine("Template preference "+pref+": "+Call(sw,"GetUserPreferenceStringValue",pref));
            return;
        }
        object doc=Get(sw,"ActiveDoc");
        if(doc==null){Console.WriteLine("No active document");return;}
        Console.WriteLine("Tree width before: "+Call(doc,"GetFeatureManagerWidth"));
        if(args.Length==1 && args[0]=="toggle-tree")Console.WriteLine("Toggle tree: "+Call(sw,"RunCommand",2556,""));
    }
}
