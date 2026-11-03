// Export/import a dedicated saved regression part as STEP and check solid geometry.
// Usage: SwExportOps.exe <saved source part> <new output stem>
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
class SwExportOps {
 static void Log(string s){Console.WriteLine(DateTime.UtcNow.ToString("o")+" "+s);Console.Out.Flush();}
 static object Call(object o,string n,params object[] a){Log("begin "+n);var t=Stopwatch.StartNew();try{return o.GetType().InvokeMember(n,BindingFlags.InvokeMethod,null,o,a);}finally{t.Stop();Log("end "+n+" ms="+t.ElapsedMilliseconds);}}
 static object CallRef(object o,string name,object[] args,params int[] refs){
  var modifier=new ParameterModifier(args.Length);foreach(int i in refs)modifier[i]=true;
  Log("begin "+name);var t=Stopwatch.StartNew();
  try{return o.GetType().InvokeMember(name,BindingFlags.InvokeMethod,null,o,args,new[]{modifier},null,null);}
  finally{t.Stop();Log("end "+name+" ms="+t.ElapsedMilliseconds);}
 }
 static object Get(object o,string n){return o.GetType().InvokeMember(n,BindingFlags.GetProperty,null,o,null);}
 static double Volume(object doc){return Convert.ToDouble(Get(Call(Get(doc,"Extension"),"CreateMassProperty"),"Volume"));}
 static void Require(bool b,string s){if(!b)throw new Exception(s);}
 [STAThread] static int Main(string[] args){try{
  Require(args.Length==2,"Expected source part and new output stem");
  string step=args[1]+".step",part=args[1]+"-imported.SLDPRT";
  Require(!File.Exists(step)&&!File.Exists(part),"Output exists; choose a new stem");
  object sw=Marshal.GetActiveObject("SldWorks.Application"),doc=Get(sw,"ActiveDoc");
  Require(doc!=null && string.Equals((string)Call(doc,"GetPathName"),args[0],StringComparison.OrdinalIgnoreCase),"Activate the specified saved regression part first");
  Require(!Convert.ToBoolean(Call(doc,"GetSaveFlag")),"Save the source part first");
  Require(Call(doc,"GetActiveSketch2")==null,"Close the active sketch/editor first");
  double original=Volume(doc);Require(original>0,"Source has no solid volume");Log("Source volume="+original.ToString("R"));
  Call(doc,"ClearSelection2",true);
  object[] save={step,0,1,new DispatchWrapper(null),0,0};
  Require(Convert.ToBoolean(CallRef(Get(doc,"Extension"),"SaveAs",save,4,5)),"STEP export failed");
  Log("STEP save errors="+save[4]+" warnings="+save[5]);Require(Convert.ToInt32(save[4])==0,"STEP save errors");
  string text=File.ReadAllText(step);Require(text.StartsWith("ISO-10303-21;"),"STEP header invalid");
  Require(text.Contains("MANIFOLD_SOLID_BREP") && text.Contains("CYLINDRICAL_SURFACE"),"STEP lacks expected solid/cylinder entities");
  Log("STEP bytes="+new FileInfo(step).Length);
  object import=Call(sw,"GetImportFileData",step);Require(import!=null,"STEP import settings missing");
  object[] load={step,"r",import,0};
  object imported=CallRef(sw,"LoadFile4",load,3);Log("STEP load errors="+load[3]);Require(imported!=null,"STEP import failed");Require(Convert.ToInt32(load[3])==0,"STEP load errors");
  double actual=Volume(imported);Log("Imported volume="+actual.ToString("R"));Require(Math.Abs(actual-original)<1e-12,"STEP round-trip volume mismatch");
  Array bodies=Call(imported,"GetBodies2",0,false) as Array;Require(bodies!=null && bodies.Length==1,"Expected one imported solid body");
  Call(imported,"ShowNamedView2","*Isometric",7);Call(imported,"ViewZoomtofit2");
  Call(imported,"ClearSelection2",true);
  object[] nativeSave={part,0,1,new DispatchWrapper(null),0,0};
  bool saved=Convert.ToBoolean(CallRef(Get(imported,"Extension"),"SaveAs",nativeSave,4,5));
  Log("Native save errors="+nativeSave[4]+" warnings="+nativeSave[5]);
  Require(saved && Convert.ToInt32(nativeSave[4])==0,"Imported part save failed");
  Require(File.Exists(part) && new FileInfo(part).Length>0,"Native part file missing/empty");
  Require(!Convert.ToBoolean(Call(imported,"GetSaveFlag")),"Imported part remains dirty");
  Call(sw,"CloseDoc",Call(imported,"GetTitle"));imported=Call(sw,"OpenDoc",part,1);Require(imported!=null,"Imported part reopen failed");
  Require(string.Equals((string)Call(imported,"GetPathName"),part,StringComparison.OrdinalIgnoreCase),"Wrong part reopened");
  actual=Volume(imported);Require(Math.Abs(actual-original)<1e-12,"Reopened import volume mismatch");
  Log("STEP export/import/save/reopen passed; volume="+actual.ToString("R"));return 0;
 }catch(Exception e){while(e.InnerException!=null)e=e.InnerException;Log("Failed: "+e.GetType().Name+" "+e.Message);return 1;}}
}
