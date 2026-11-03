// Usage: SwShellOps.exe <observed active blank part title> <new output .SLDPRT>
// Makes a 50 x 30 x 25 mm open box, checks 2/3 mm walls and save/reopen.
using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
class SwShellOps {
 static void Log(string s){Console.WriteLine(DateTime.UtcNow.ToString("o")+" "+s);Console.Out.Flush();}
 static void Require(bool b,string s){if(!b)throw new Exception(s);}
 static object Call(object o,string n,params object[] a){Log("begin "+n);object v=o.GetType().InvokeMember(n,BindingFlags.InvokeMethod,null,o,a);Log("end "+n);return v;}
 static object Get(object o,string n){return o.GetType().InvokeMember(n,BindingFlags.GetProperty,null,o,null);}
 static void Set(object o,string n,object v){o.GetType().InvokeMember(n,BindingFlags.SetProperty,null,o,new[]{v});}
 static void Active(object sw,string path){object d=Get(sw,"ActiveDoc");Require(d!=null&&string.Equals((string)Call(d,"GetPathName"),path,StringComparison.OrdinalIgnoreCase),"Test part no longer active");}
 static void Check(object d,double thickness,string stage){
  Array bodies=Call(d,"GetBodies2",0,false) as Array;Require(bodies!=null&&bodies.Length==1,"Expected one solid");
  double[] m=(double[])Call(bodies.GetValue(0),"GetMassProperties",1.0);
  double expected=thickness==0 ? .05*.03*.025 : .05*.03*.025-(.05-2*thickness)*(.03-2*thickness)*(.025-thickness);
  Require(Math.Abs(m[3]-expected)<1e-12,stage+" volume mismatch "+m[3]+" expected "+expected);
  Require(Math.Abs(m[0]-.025)<1e-8&&Math.Abs(m[1]-.015)<1e-8,stage+" centre mismatch");
  Log(stage+" volume="+m[3].ToString("R"));
 }
 static void Save(object d,string path){
  object ext=Get(d,"Extension");object[] a={path,0,1,new DispatchWrapper(null),0,0};var p=new ParameterModifier(a.Length);p[4]=p[5]=true;
  Log("begin SaveAs");bool ok=Convert.ToBoolean(ext.GetType().InvokeMember("SaveAs",BindingFlags.InvokeMethod,null,ext,a,new[]{p},null,null));Log("end SaveAs errors="+a[4]+" warnings="+a[5]);
  Require(ok&&Convert.ToInt32(a[4])==0&&File.Exists(path)&&new FileInfo(path).Length>0,"Save failed");Require(!Convert.ToBoolean(Call(d,"GetSaveFlag")),"Saved part dirty");
 }
 [STAThread] static int Main(string[] a){try{
  Require(a.Length==2&&!File.Exists(a[1])&&a[1].EndsWith(".SLDPRT",StringComparison.OrdinalIgnoreCase),"Expected blank title and new SLDPRT path");
  object sw=Marshal.GetActiveObject("SldWorks.Application"),doc=Get(sw,"ActiveDoc");
  Require(doc!=null&&(string)Call(doc,"GetTitle")==a[0]&&(string)Call(doc,"GetPathName")==""&&Convert.ToInt32(Call(doc,"GetType"))==1,"Expected observed active untitled part");
  Require(!Convert.ToBoolean(Call(doc,"GetSaveFlag"))&&Call(doc,"GetActiveSketch2")==null&&Call(doc,"FeatureByName","Sketch1")==null,"Part not blank/clean");
  Array existing=Call(doc,"GetBodies2",0,false) as Array;Require(existing==null||existing.Length==0,"Part already has solid");
  object ext=Get(doc,"Extension"),sm=Get(doc,"SketchManager");
  Require(Convert.ToBoolean(Call(ext,"SelectByID2","Front Plane","PLANE",0.0,0.0,0.0,false,0,new DispatchWrapper(null),0)),"Plane selection failed");
  Call(sm,"InsertSketch",true);Call(sm,"CreateCornerRectangle",0.0,0.0,0.0,.05,.03,0.0);Call(doc,"ClearSelection2",true);Call(sm,"InsertSketch",true);
  object boss=Call(Get(doc,"FeatureManager"),"FeatureExtrusion2",true,false,false,0,0,.025,0.0,false,false,false,false,0.0,0.0,false,false,false,false,true,true,true,0,0.0,false);Require(boss!=null,"Box extrusion failed");
  Check(doc,0,"solid box");Save(doc,a[1]);Active(sw,a[1]);Call(doc,"ClearSelection2",true);
  Require(Convert.ToBoolean(Call(ext,"SelectByID2","","FACE",.025,.015,.025,false,1,new DispatchWrapper(null),0)),"Top face selection failed");
  Call(doc,"InsertFeatureShell",.002,false);object shell=Call(doc,"FeatureByName","Shell1");Require(shell!=null,"Shell feature missing");Check(doc,.002,"2 mm shell");
  object data=Call(shell,"GetDefinition");Require(data!=null&&Math.Abs(Convert.ToDouble(Get(data,"Thickness"))-.002)<1e-10,"Shell thickness mismatch");
  Require(Convert.ToBoolean(Call(data,"AccessSelections",doc,new DispatchWrapper(null))),"Shell selection access failed");
  Set(data,"Thickness",.003);Require(Convert.ToBoolean(Call(shell,"ModifyDefinition",data,doc,new DispatchWrapper(null))),"Shell thickness edit failed");
  Active(sw,a[1]);Require(Convert.ToBoolean(Call(doc,"EditRebuild3")),"Incremental rebuild failed");Check(doc,.003,"3 mm shell");
  Require(Convert.ToBoolean(Call(shell,"SetSuppression2",0,1,null)),"Shell suppression failed");Check(doc,0,"suppressed shell");
  Require(Convert.ToBoolean(Call(shell,"SetSuppression2",1,1,null)),"Shell restore failed");Active(sw,a[1]);Require(Convert.ToBoolean(Call(doc,"EditRebuild3")),"Restore rebuild failed");Check(doc,.003,"restored shell");
  Call(doc,"ClearSelection2",true);Call(doc,"ShowNamedView2","*Isometric",7);Call(doc,"ViewZoomtofit2");Save(doc,a[1]);
  Call(sw,"CloseDoc",Call(doc,"GetTitle"));doc=Call(sw,"OpenDoc",a[1],1);Require(doc!=null&&string.Equals((string)Call(doc,"GetPathName"),a[1],StringComparison.OrdinalIgnoreCase),"Wrong part reopened");Check(doc,.003,"reopened shell");
  shell=Call(doc,"FeatureByName","Shell1");Require(shell!=null&&Math.Abs(Convert.ToDouble(Get(Call(shell,"GetDefinition"),"Thickness"))-.003)<1e-10,"Reopened thickness mismatch");
  Log("Shell/thickness edit/suppression/rebuild/save/reopen passed");return 0;
 }catch(Exception e){while(e.InnerException!=null)e=e.InnerException;Log("Failed: "+e.GetType().Name+" "+e.Message);return 1;}}
}
