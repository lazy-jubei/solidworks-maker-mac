// Exercise standard UI commands; geometry is entered with real input, not Create* API calls.
using System;
using System.Reflection;
using System.Runtime.InteropServices;
class SwInteractive {
    static object Call(object o,string n,params object[] a){return o.GetType().InvokeMember(n,BindingFlags.InvokeMethod,null,o,a);}
    static object Get(object o,string n){return o.GetType().InvokeMember(n,BindingFlags.GetProperty,null,o,null);}
    static int Main(string[] a){try{return Run(a);}catch(Exception e){while(e.InnerException!=null)e=e.InnerException;Console.WriteLine(e.GetType().Name+": "+e.Message);return 1;}}
    static int Run(string[] a){
        if(a[0]=="commands"){
            Type t=Assembly.LoadFrom(a[1]).GetType("SolidWorks.Interop.swcommands.swCommands_e");
            foreach(string name in Enum.GetNames(t))if(System.Text.RegularExpressions.Regex.IsMatch(name,@"^swCommands_(Sketch$|Rectangle$|Circle$|Extrude.*|InsertSketch.*|SmartDimension.*|EditFeature.*|EditDefinition.*|Rebuild.*)"))Console.WriteLine(name+"="+Convert.ToInt32(Enum.Parse(t,name)));
            return 0;
        }
        object sw=Marshal.GetActiveObject("SldWorks.Application");
        if(a[0]=="command"){Console.WriteLine("Command accepted: "+Call(sw,"RunCommand",int.Parse(a[1]),""));return 0;}
        object doc;
        if(a[0]=="prepare"){
            string template=(string)Call(sw,"GetUserPreferenceStringValue",8);
            doc=Call(sw,"NewDocument",template,0,0.0,0.0);if(doc==null)throw new Exception("New part failed");
            object ext=Get(doc,"Extension");
            Console.WriteLine("Front Plane selected: "+Call(ext,"SelectByID2","Front Plane","PLANE",0.0,0.0,0.0,false,0,new DispatchWrapper(null),0));
            Call(doc,"ShowNamedView2","*Front",1);Call(doc,"ViewZoomtofit2");
            Console.WriteLine("Prepared "+Call(doc,"GetTitle"));return 0;
        }
        doc=Get(sw,"ActiveDoc");if(doc==null)throw new Exception("No active document");
        if(a[0]=="save"){
            if(Call(doc,"FeatureByName","Boss-Extrude1")==null)throw new Exception("Extrusion has not been committed");
            double volume=Convert.ToDouble(Get(Call(Get(doc,"Extension"),"CreateMassProperty"),"Volume"));
            Console.WriteLine("Solid volume m3: "+volume.ToString("R",System.Globalization.CultureInfo.InvariantCulture));
            if(volume<=0)throw new Exception("No positive solid volume");
            if(a.Length>2){
                object depth=Call(doc,"Parameter","D1@Boss-Extrude1");
                if(depth==null)throw new Exception("Extrusion depth parameter missing");
                double actual=Convert.ToDouble(Get(depth,"SystemValue")),expected=double.Parse(a[2],System.Globalization.CultureInfo.InvariantCulture);
                Console.WriteLine("Extrusion depth m: "+actual);
                if(Math.Abs(actual-expected)>1e-12)throw new Exception("Typed extrusion depth mismatch");
            }
            bool saved=Convert.ToBoolean(Call(doc,"SaveAs",a[1]));
            Console.WriteLine("Saved: "+saved);
            if(!saved || !System.IO.File.Exists(a[1]))throw new Exception("Save failed");return 0;
        }
        if(a[0]=="select-extrusion"){
            object feature=Call(doc,"FeatureByName","Boss-Extrude1");
            if(feature==null)throw new Exception("Extrusion missing");
            Console.WriteLine("Extrusion selected: "+Call(feature,"Select2",false,0));return 0;
        }
        if(a[0]=="select-sketch"){
            Console.WriteLine("Sketch selected: "+Call(Get(doc,"Extension"),"SelectByID2","Sketch1","SKETCH",0.0,0.0,0.0,false,0,new DispatchWrapper(null),0));return 0;
        }
        if(a[0]=="status"){
            Console.WriteLine("Active document: "+Call(doc,"GetTitle"));
            object sketch=Call(doc,"GetActiveSketch2");
            if(sketch!=null){Array segments=Call(sketch,"GetSketchSegments") as Array;Console.WriteLine("Active sketch segments: "+(segments==null?0:segments.Length));}
            int n=0;for(object f=Call(doc,"FirstFeature");f!=null;f=Call(f,"GetNextFeature")){
                Console.WriteLine(Get(f,"Name")+" ["+Call(f,"GetTypeName2")+"]");if(++n>100)break;
            }
            return 0;
        }
        return 2;
    }
}
