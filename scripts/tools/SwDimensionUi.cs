// Guarded native depth-edit check for a 50x30 mm box with a 5 mm radius through hole.
// Edits are performed separately through the UI; this checker never sets dimensions.
// Usage: SwDimensionUi.exe inspect|edit|reopen <exact saved part> <depth in metres>
using System;using System.IO;using System.Reflection;using System.Runtime.InteropServices;
class SwDimensionUi {
 static object Call(object o,string n,params object[] a){return o.GetType().InvokeMember(n,BindingFlags.InvokeMethod,null,o,a);}
 static object Get(object o,string n){return o.GetType().InvokeMember(n,BindingFlags.GetProperty,null,o,null);}
 static void Need(bool b,string s){if(!b)throw new Exception(s);}
 static void Log(string s){Console.WriteLine(s);Console.Out.Flush();}
 [STAThread]static int Main(string[] a){try{
  Need(a.Length==3,"Expected inspect|edit|reopen, exact part path and expected depth in metres");
  double depth=double.Parse(a[2],System.Globalization.CultureInfo.InvariantCulture);Need(depth>0&&depth<0.1,"Depth out of range");
  object sw=Marshal.GetActiveObject("SldWorks.Application"),d=Get(sw,"ActiveDoc");
  Need(d!=null&&string.Equals((string)Call(d,"GetPathName"),a[1],StringComparison.OrdinalIgnoreCase)&&Convert.ToInt32(Call(d,"GetType"))==1,"Wrong active part");
  Need(Call(d,"GetActiveSketch2")==null,"Exit sketch before checking");
  if(a[0]=="reopen"){
   Need(!Convert.ToBoolean(Call(d,"GetSaveFlag")),"Save before reopen");Call(sw,"CloseDoc",Call(d,"GetTitle"));d=Call(sw,"OpenDoc",a[1],1);
   Need(d!=null&&string.Equals((string)Call(d,"GetPathName"),a[1],StringComparison.OrdinalIgnoreCase),"Wrong reopened part");
  }
  double parameter=Convert.ToDouble(Get(Call(d,"Parameter","D1@Boss-Extrude1"),"SystemValue"));
  Array bodies=Call(d,"GetBodies2",0,false) as Array;Need(bodies!=null&&bodies.Length==1,"Expected one solid");
  double actual=((double[])Call(bodies.GetValue(0),"GetMassProperties",1.0))[3];
  double mass=Convert.ToDouble(Get(Call(Get(d,"Extension"),"CreateMassProperty"),"Volume"));
  double expected=(0.05*0.03-Math.PI*0.005*0.005)*depth;
  Log("Part="+Call(d,"GetTitle")+" depth="+parameter.ToString("R")+" bodyVolume="+actual.ToString("R")+" massVolume="+mass.ToString("R")+" expected="+expected.ToString("R")+" needs="+Get(Get(d,"Extension"),"NeedsRebuild2")+" dirty="+Call(d,"GetSaveFlag"));
  Need(Math.Abs(parameter-depth)<1e-10&&Math.Abs(actual-expected)<1e-12&&Math.Abs(mass-expected)<1e-12,"Dimension or rebuilt geometry mismatch");
  if(a[0]=="edit"){
   object feature=Call(d,"FeatureByName","Boss-Extrude1");Need(feature!=null&&Convert.ToBoolean(Call(feature,"Select2",false,0)),"Select extrusion failed");
   Need(Convert.ToBoolean(Call(sw,"RunCommand",623,"")),"Edit Feature command failed");Log("Native extrusion editor opened");
  }else Need(a[0]=="inspect"||a[0]=="reopen","Unknown action");
  return 0;
 }catch(Exception e){while(e.InnerException!=null)e=e.InnerException;Log(e.GetType().Name+" "+e.Message);return 1;}}
}
