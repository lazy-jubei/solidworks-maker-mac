// Native Smart Dimension check for a 30 mm deep box with a 5 mm radius through hole.
// inspect/reopen require D1@Sketch1 = requested width and D2@Sketch1 = 30 mm.
// Never sets dimensions; native sketch edits are delivered separately.
using System;using System.Reflection;using System.Runtime.InteropServices;
class SwSketchDimensionUi {
 static object Call(object o,string n,params object[] a){return o.GetType().InvokeMember(n,BindingFlags.InvokeMethod,null,o,a);}
 static object Get(object o,string n){return o.GetType().InvokeMember(n,BindingFlags.GetProperty,null,o,null);}
 static void Need(bool b,string s){if(!b)throw new Exception(s);}
 static void Log(string s){Console.WriteLine(s);Console.Out.Flush();}
 [STAThread]static int Main(string[] a){try{
  Need(a.Length==3,"Expected edit|inspect|reopen, exact saved path, width in metres");
  double width=double.Parse(a[2],System.Globalization.CultureInfo.InvariantCulture);Need(width>.04&&width<.1,"Width out of range");
  object sw=Marshal.GetActiveObject("SldWorks.Application"),d=Get(sw,"ActiveDoc");
  Need(d!=null&&string.Equals((string)Call(d,"GetPathName"),a[1],StringComparison.OrdinalIgnoreCase)&&Convert.ToInt32(Call(d,"GetType"))==1,"Wrong active saved part");
  Need(Call(d,"GetActiveSketch2")==null,"Exit sketch before invoking this checker");
  if(a[0]=="reopen"){
   Need(!Convert.ToBoolean(Call(d,"GetSaveFlag")),"Save first");Call(sw,"CloseDoc",Call(d,"GetTitle"));d=Call(sw,"OpenDoc",a[1],1);
   Need(d!=null&&string.Equals((string)Call(d,"GetPathName"),a[1],StringComparison.OrdinalIgnoreCase),"Wrong reopened part");
  }
  Array bodies=Call(d,"GetBodies2",0,false) as Array;Need(bodies!=null&&bodies.Length==1,"Expected one solid");
  double body=((double[])Call(bodies.GetValue(0),"GetMassProperties",1.0))[3];
  double mass=Convert.ToDouble(Get(Call(Get(d,"Extension"),"CreateMassProperty"),"Volume"));
  double expected=(width*.03-Math.PI*.005*.005)*.03;
  Log("Part="+Call(d,"GetTitle")+" bodyVolume="+body.ToString("R")+" massVolume="+mass.ToString("R")+" expected="+expected.ToString("R")+" dirty="+Call(d,"GetSaveFlag")+" needs="+Get(Get(d,"Extension"),"NeedsRebuild2"));
  Need(Math.Abs(body-expected)<1e-12&&Math.Abs(mass-expected)<1e-12,"Solid volume mismatch");
  if(a[0]=="edit"){
   Need(!Convert.ToBoolean(Call(d,"GetSaveFlag")),"Save before sketch edit");
   object feature=Call(d,"FeatureByName","Sketch1");Need(feature!=null&&Convert.ToBoolean(Call(feature,"Select2",false,0)),"Sketch selection failed");
   Call(d,"EditSketch");Need(Call(d,"GetActiveSketch2")!=null,"Sketch editor did not open");
   Call(d,"ShowNamedView2","*Front",1);Call(d,"ViewZoomtofit2");Log("Native sketch editor opened");
  }else{
   Need(a[0]=="inspect"||a[0]=="reopen","Unknown action");
   object dimension=Call(d,"Parameter","D1@Sketch1");Need(dimension!=null,"Sketch dimension missing");
   double value=Convert.ToDouble(Get(dimension,"SystemValue"));Log("Sketch dimension="+value.ToString("R"));Need(Math.Abs(value-width)<1e-10,"Sketch width mismatch");
   object heightDimension=Call(d,"Parameter","D2@Sketch1");Need(heightDimension!=null,"Sketch height dimension missing");
   double height=Convert.ToDouble(Get(heightDimension,"SystemValue"));Log("Sketch height="+height.ToString("R"));Need(Math.Abs(height-.03)<1e-10,"Sketch height mismatch");
  }
  return 0;
 }catch(Exception e){while(e.InnerException!=null)e=e.InnerException;Log(e.GetType().Name+" "+e.Message);return 1;}}
}
