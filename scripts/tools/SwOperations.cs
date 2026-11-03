// Local modeling regression: sketch, extrusion, dimension edit, circular cut, suppression and reopen.
// Usage, with SOLIDWORKS already open: SwOperations.exe <output .SLDPRT path> [part template]
// Checks analytical volumes after each operation. Uses late binding because GetTypeInfo fails under Wine.
using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

class SwOperations
{
    static object Call(object target, string name, params object[] args)
    {
        return target.GetType().InvokeMember(name, BindingFlags.InvokeMethod, null, target, args);
    }

    static object Get(object target, string name)
    {
        return target.GetType().InvokeMember(name, BindingFlags.GetProperty, null, target, null);
    }

    [STAThread] static int Main(string[] args) {
        try { return Run(args); }
        catch (Exception e) {
            while (e.InnerException != null) e = e.InnerException;
            Console.WriteLine("Modeling check failed: " + e.GetType().Name + " " + e.Message);
            return 1;
        }
    }
    static int Run(string[] args)
    {
        if(args.Length<1 || args.Length>2){Console.WriteLine("Usage: SwOperations.exe <new output .SLDPRT> [part template]");return 2;}
        if(!args[0].EndsWith(".SLDPRT",StringComparison.OrdinalIgnoreCase) || File.Exists(args[0])){
            Console.WriteLine("Choose a new output .SLDPRT path; existing files will not be overwritten");return 2;
        }
        object sw = null;
        DateTime deadline = DateTime.UtcNow.AddMinutes(5);
        while (sw == null)
        {
            try { sw = Marshal.GetActiveObject("SldWorks.Application"); }
            catch (COMException e)
            {
                if (e.ErrorCode != unchecked((int)0x800401e3)) throw;
                if (DateTime.UtcNow >= deadline) { Console.WriteLine("SolidWorks API did not become ready within five minutes"); return 2; }
                System.Threading.Thread.Sleep(1000);
            }
        }
        Console.WriteLine("revision: " + Call(sw, "RevisionNumber"));
        string template = args.Length > 1 ? args[1] : (string)Call(sw, "GetUserPreferenceStringValue", 8); // swDefaultTemplatePart
        Console.WriteLine("template: " + template);
        object doc = Call(sw, "NewDocument", template, 0, 0.0, 0.0);
        if (doc == null) { Console.WriteLine("NewDocument failed"); return 1; }
        if ((string)Call(doc,"GetTitle") != (string)Call(Get(sw,"ActiveDoc"),"GetTitle"))
            throw new Exception("New part is not the active document required by EditRebuild3");
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
        // Use the current dimension API and require an ordinary incremental rebuild.
        int setStatus=Convert.ToInt32(Call(depth,"SetSystemValue3",0.025,1,null));
        Console.WriteLine("SetSystemValue3 status: "+setStatus);
        if(setStatus!=0)throw new Exception("Extrusion dimension edit failed");
        Console.WriteLine("Edited depth m: " + Get(depth, "SystemValue"));
        if(!Convert.ToBoolean(Call(doc,"EditRebuild3")))throw new Exception("Incremental rebuild failed");
        CheckVolume(ext, 0.05 * 0.03 * 0.025, "edited extrusion");
        Call(doc, "ClearSelection2", true);
        if (!Convert.ToBoolean(Call(ext, "SelectByID2", "Front Plane", "PLANE", 0.0, 0.0, 0.0, false, 0, new DispatchWrapper(null), 0)))
            throw new Exception("Cut sketch plane selection failed");
        Call(sketch, "InsertSketch", true);
        Call(sketch, "CreateCircleByRadius", 0.025, 0.015, 0.0, 0.005);
        Call(doc, "ClearSelection2", true);
        Call(sketch, "InsertSketch", true);
        object cut = Call(Get(doc, "FeatureManager"), "FeatureCut3", true, false, true, 1, 0, 0.025, 0.0,
            false, false, false, false, 0.0, 0.0, false, false, false, false, false, true, true, false, false, false, 0, 0.0, false);
        if (cut == null) throw new Exception("Circular cut creation failed");
        Console.WriteLine("cut: " + Get(cut, "Name"));
        double expected = (0.05 * 0.03 - Math.PI * 0.005 * 0.005) * 0.025;
        CheckVolume(ext, expected, "through cut");
        if (!Convert.ToBoolean(Call(cut, "SetSuppression2", 0, 1, null))) throw new Exception("Suppress failed");
        CheckVolume(ext, 0.05 * 0.03 * 0.025, "suppressed cut");
        if (!Convert.ToBoolean(Call(cut, "SetSuppression2", 1, 1, null))) throw new Exception("Unsuppress failed");
        CheckVolume(ext, expected, "restored cut");
        Call(doc, "ClearSelection2", true);
        Call(doc, "ShowNamedView2", "*Isometric", 7);
        Call(doc, "ViewZoomtofit2");
        if (!Convert.ToBoolean(Call(doc, "SaveAs", args[0]))) throw new Exception("Save failed");
        string title = (string)Call(doc, "GetTitle");
        Call(sw, "CloseDoc", title);
        doc = Call(sw, "OpenDoc", args[0], 1);
        if (doc == null) throw new Exception("Reopen failed");
        CheckVolume(Get(doc, "Extension"), expected, "reopened model");
        Console.WriteLine("All local modeling checks passed");
        return 0;
    }
    static void CheckVolume(object ext, double expected, string stage) {
        double actual = Convert.ToDouble(Get(Call(ext, "CreateMassProperty"), "Volume"));
        Console.WriteLine(stage + " volume m3: " + actual.ToString("R", System.Globalization.CultureInfo.InvariantCulture));
        if (Math.Abs(actual - expected) > 1e-12) throw new Exception(stage + " volume mismatch");
    }
}
