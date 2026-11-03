// Measures how fast SOLIDWORKS redraws the active document's view. Turns the view, but not the model.
// Usage, with a part open: SwFps.exe [seconds]
using System;
using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;

class SwFps
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
        double seconds = args.Length > 0 ? double.Parse(args[0]) : 5;
        object sw = Marshal.GetActiveObject("SldWorks.Application");
        object doc = Get(sw, "ActiveDoc");
        if (doc == null) { Console.WriteLine("no active document"); return 1; }
        object view = Get(doc, "ActiveView");
        Stopwatch trivial = Stopwatch.StartNew();
        for (int n = 0; n < 10; n++) Call(sw, "RevisionNumber");
        Console.WriteLine("ms per trivial API call: " + (trivial.Elapsed.TotalMilliseconds / 10).ToString("F0"));
        int frames = 0;
        double rotate = 0, redraw = 0;
        Stopwatch clock = Stopwatch.StartNew();
        while (clock.Elapsed.TotalSeconds < seconds)
        {
            double t0 = clock.Elapsed.TotalSeconds;
            Call(view, "RotateAboutCenter", 0.03, 0.0);
            double t1 = clock.Elapsed.TotalSeconds;
            Call(view, "GraphicsRedraw", new DispatchWrapper(null));
            rotate += t1 - t0;
            redraw += clock.Elapsed.TotalSeconds - t1;
            frames++;
        }
        Console.WriteLine("ms per frame: rotate " + (1000 * rotate / frames).ToString("F0") + ", redraw " + (1000 * redraw / frames).ToString("F0"));
        Console.WriteLine("frames: " + frames + " fps: " + (frames / clock.Elapsed.TotalSeconds).ToString("F1"));
        return 0;
    }
}
