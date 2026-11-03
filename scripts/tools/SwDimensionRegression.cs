// Compare incremental rebuild after the obsolete setter and the current dimension API.
// Creates a dedicated new test part and never edits existing documents.
using System;
using System.Reflection;
using System.Runtime.InteropServices;
class SwDimensionRegression {
    static object Call(object target, string name, params object[] args)
    {
        return target.GetType().InvokeMember(name, BindingFlags.InvokeMethod, null, target, args);
    }

    static object Get(object target, string name)
    {
        return target.GetType().InvokeMember(name, BindingFlags.GetProperty, null, target, null);
    }

    static void Log(string text){Console.WriteLine(text);Console.Out.Flush();}
    static double Volume(object doc){return Convert.ToDouble(Get(Call(Get(doc,"Extension"),"CreateMassProperty"),"Volume"));}
    [STAThread] static int Main(string[] args){try{
        object sw=Marshal.GetActiveObject("SldWorks.Application");
        Console.WriteLine("revision: " + Call(sw, "RevisionNumber"));
        string template = args.Length > 1 ? args[1] : (string)Call(sw, "GetUserPreferenceStringValue", 8); // swDefaultTemplatePart
        Console.WriteLine("template: " + template);
        object doc = Call(sw, "NewDocument", template, 0, 0.0, 0.0);
        if (doc == null) { Console.WriteLine("NewDocument failed"); return 1; }
        object ext = Get(doc, "Extension");
        Console.WriteLine("plane selected: " + Call(ext, "SelectByID2", "Front Plane", "PLANE", 0.0, 0.0, 0.0, false, 0,
            new DispatchWrapper(null), 0));
        object sketch = Get(doc, "SketchManager");
        Console.WriteLine("Starting sketch");
        Call(sketch, "InsertSketch", true);
        Console.WriteLine("Creating rectangle");
        Call(sketch, "CreateCornerRectangle", 0.0, 0.0, 0.0, 0.05, 0.03, 0.0);
        Console.WriteLine("Closing sketch");
        Call(doc, "ClearSelection2", true);
        Call(sketch, "InsertSketch", true);
        object feature = Call(Get(doc, "FeatureManager"), "FeatureExtrusion2", true, false, false, 0, 0, 0.02, 0.0, false,
            false, false, false, 0.0, 0.0, false, false, false, false, true, true, true, 0, 0.0, false);
        Console.WriteLine("feature: " + (feature == null ? "none" : Get(feature, "Name")));
        Call(doc, "ClearSelection2", true);
        Call(doc, "ShowNamedView2", "*Isometric", 7);
        Call(doc, "ViewZoomtofit2");
        double volume = Convert.ToDouble(Get(Call(ext, "CreateMassProperty"), "Volume"));
        Console.WriteLine("volume m3: " + volume);
        object depth = Call(doc, "Parameter", "D1@" + Get(feature, "Name"));
        if (depth == null) throw new Exception("Extrusion depth parameter missing");

        string title=(string)Call(doc,"GetTitle");
        Log("Returned document="+title+" Active document="+Call(Get(sw,"ActiveDoc"),"GetTitle"));
        if(title!=(string)Call(Get(sw,"ActiveDoc"),"GetTitle"))throw new Exception("New part is not active");
        depth.GetType().InvokeMember("SystemValue",BindingFlags.SetProperty,null,depth,new object[]{0.025});
        Log("Obsolete setter depth="+Get(depth,"SystemValue")+" NeedsRebuild="+Get(ext,"NeedsRebuild2"));
        Log("Obsolete setter EditRebuild3="+Call(doc,"EditRebuild3")+" volume="+Volume(doc)+" needs="+Get(ext,"NeedsRebuild2"));
        Log("Full rebuild="+Call(doc,"ForceRebuild3",false)+" volume="+Volume(doc));
        int status=Convert.ToInt32(Call(depth,"SetSystemValue3",0.030,1,null));
        Log("SetSystemValue3 status="+status+" depth="+Get(depth,"SystemValue")+" needs="+Get(ext,"NeedsRebuild2"));
        if(status!=0)throw new Exception("Current dimension setter failed");
        Log("Current setter EditRebuild3="+Call(doc,"EditRebuild3")+" volume="+Volume(doc)+" needs="+Get(ext,"NeedsRebuild2"));
        if(Math.Abs(Volume(doc)-0.05*0.03*0.030)>1e-12)throw new Exception("Current setter incremental rebuild retained stale geometry");
        Log("Both API paths inspected; current setter incremental rebuild passed");
        return 0;
    }catch(Exception e){while(e.InnerException!=null)e=e.InnerException;Log("Failed: "+e.GetType().Name+" "+e.Message);return 1;}}
}
