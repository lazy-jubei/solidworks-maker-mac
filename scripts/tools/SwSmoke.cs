// Smoke test through SOLIDWORKS' COM API: extrudes a 50 x 30 x 20 mm box and saves it.
// Usage, with SOLIDWORKS already open: SwSmoke.exe <output .SLDPRT path> [part template]
// Expected volume: 3e-05 m^3. Uses plain late binding because IDispatch::GetTypeInfo fails under Wine.
using System;
using System.Reflection;
using System.Runtime.InteropServices;

class SwSmoke
{
    static object Call(object target, string name, params object[] args)
    {
        return target.GetType().InvokeMember(name, BindingFlags.InvokeMethod, null, target, args);
    }

    static object Get(object target, string name)
    {
        return target.GetType().InvokeMember(name, BindingFlags.GetProperty, null, target, null);
    }

    static int Main(string[] args)
    {
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
        object saved = Call(doc, "SaveAs", args[0]);
        Console.WriteLine("saved: " + saved);
        return feature != null && Convert.ToBoolean(saved) && Math.Abs(volume - 3e-5) < 1e-12 ? 0 : 1;
    }
}
