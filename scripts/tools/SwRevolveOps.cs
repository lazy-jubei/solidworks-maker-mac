// Operate only on the observed newly created blank part, then save a new file.
// Usage: SwRevolveOps.exe <active blank part title> <new output .SLDPRT>
// Compile against the installed SolidWorks.Interop.swconst.dll.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using SolidWorks.Interop.swconst;
class SwRevolveOps {
 static void Log(string s){Console.WriteLine(DateTime.UtcNow.ToString("o")+" "+s);Console.Out.Flush();}
 static void Require(bool b,string s){if(!b)throw new Exception(s);}
 static object Call(object o,string n,params object[] a){Log("begin "+n);var t=Stopwatch.StartNew();try{return o.GetType().InvokeMember(n,BindingFlags.InvokeMethod,null,o,a);}finally{t.Stop();Log("end "+n+" ms="+t.ElapsedMilliseconds);}}
 static object Get(object o,string n){return o.GetType().InvokeMember(n,BindingFlags.GetProperty,null,o,null);}
 static void Set(object o,string n,object v){o.GetType().InvokeMember(n,BindingFlags.SetProperty,null,o,new[]{v});}
 static void Active(object sw,string path){object active=Get(sw,"ActiveDoc");Require(active!=null&&string.Equals((string)Call(active,"GetPathName"),path,StringComparison.OrdinalIgnoreCase),"Test part is no longer active; refusing session-wide undo/rebuild");}
 static void Check(object doc,int count,string stage){
  double expected=Math.PI*(0.02*0.02-0.01*0.01)*0.03;
  Array bodies=Call(doc,"GetBodies2",0,false) as Array;Require(bodies!=null&&bodies.Length==count,stage+" body count mismatch");
  var centres=new List<double>();double sum=0;
  foreach(object body in bodies){double[] m=(double[])Call(body,"GetMassProperties",1.0);Require(Math.Abs(m[3]-expected)<1e-12,stage+" body volume mismatch");Require(Math.Abs(m[1]-0.015)<1e-8&&Math.Abs(m[2])<1e-8,stage+" centre mismatch");sum+=m[3];centres.Add(m[0]);}
  centres.Sort();Require(Math.Abs(centres[0])<1e-8||Math.Abs(centres[centres.Count-1])<1e-8,stage+" seed moved");
  for(int i=1;i<centres.Count;i++)Require(Math.Abs(centres[i]-centres[i-1]-0.06)<1e-8,stage+" spacing mismatch");
  Log(stage+" bodies="+count+" volume="+sum.ToString("R")+" centresX="+string.Join(",",centres));
 }
 static void Save(object doc,string path){
  object ext=Get(doc,"Extension");object[] a={path,0,1,new DispatchWrapper(null),0,0};var p=new ParameterModifier(a.Length);p[4]=p[5]=true;
  Log("begin SaveAs");bool ok=Convert.ToBoolean(ext.GetType().InvokeMember("SaveAs",BindingFlags.InvokeMethod,null,ext,a,new[]{p},null,null));Log("end SaveAs errors="+a[4]+" warnings="+a[5]);
  Require(ok&&Convert.ToInt32(a[4])==0&&File.Exists(path)&&new FileInfo(path).Length>0,"Save failed");Require(!Convert.ToBoolean(Call(doc,"GetSaveFlag")),"Saved part dirty");
 }
 [STAThread] static int Main(string[] a){try{
  Require(a.Length==2&&!File.Exists(a[1])&&a[1].EndsWith(".SLDPRT",StringComparison.OrdinalIgnoreCase),"Expected blank title and new SLDPRT output");
  object sw=Marshal.GetActiveObject("SldWorks.Application"),doc=Get(sw,"ActiveDoc");
  Require(doc!=null&&(string)Call(doc,"GetTitle")==a[0]&&(string)Call(doc,"GetPathName")==""&&Convert.ToInt32(Call(doc,"GetType"))==1,"Expected active untitled part");
  Require(!Convert.ToBoolean(Call(doc,"GetSaveFlag"))&&Call(doc,"GetActiveSketch2")==null&&Call(doc,"FeatureByName","Sketch1")==null,"Part is not blank/clean");
  Array existing=Call(doc,"GetBodies2",0,false) as Array;Require(existing==null||existing.Length==0,"Part already contains a solid");
  object ext=Get(doc,"Extension"),sketch=Get(doc,"SketchManager"),fm=Get(doc,"FeatureManager");
  Require(Convert.ToBoolean(Call(ext,"SelectByID2","Front Plane","PLANE",0.0,0.0,0.0,false,0,new DispatchWrapper(null),0)),"Front plane selection failed");
  Call(sketch,"InsertSketch",true);Call(sketch,"CreateCornerRectangle",0.01,0.0,0.0,0.02,0.03,0.0);
  object axis=Call(sketch,"CreateCenterLine",0.0,0.0,0.0,0.0,0.03,0.0);Require(axis!=null,"Centreline creation failed");
  Call(doc,"ClearSelection2",true);Call(sketch,"InsertSketch",true);
  object profile=Call(doc,"FeatureByName","Sketch1");Require(profile!=null&&Convert.ToBoolean(Call(profile,"Select2",false,0)),"Profile selection failed");
  object sd=Call(Get(doc,"SelectionManager"),"CreateSelectData");Set(sd,"Mark",4);Require(Convert.ToBoolean(Call(axis,"Select4",true,sd)),"Revolve axis selection failed");
  object revolve=Call(fm,"FeatureRevolve2",true,true,false,false,false,false,0,0,2*Math.PI,0.0,false,false,0.0,0.0,0,0.0,0.0,true,true,true);Require(revolve!=null,"Revolve creation failed");
  Call(doc,"ClearSelection2",true);Check(doc,1,"360 degree revolve");Save(doc,a[1]);
  // Use documented marked selections; standalone object-property assignment
  // did not create a feature through this late-bound client.
  Call(doc,"ClearSelection2",true);
  Require(Convert.ToBoolean(Call(Call(doc,"FeatureByName","Right Plane"),"Select2",false,1)),"Pattern direction selection failed");
  Array seed=(Array)Call(doc,"GetBodies2",0,false);object bodySelect=Call(Get(doc,"SelectionManager"),"CreateSelectData");Set(bodySelect,"Mark",256);
  Require(Convert.ToBoolean(Call(seed.GetValue(0),"Select2",true,bodySelect)),"Pattern body selection failed");
  object data=Call(fm,"CreateDefinition",(int)swFeatureNameID_e.swFmLPattern);Require(data!=null,"Pattern definition missing");
  Set(data,"BodyPattern",true);
  Set(data,"D1EndCondition",(int)swPatternEndCondition_e.swPatternEndCondition_SpacingAndInstances);
  Set(data,"D1Spacing",0.06);Set(data,"D1TotalInstances",3);Set(data,"D1ReverseDirection",false);Set(data,"D2TotalInstances",1);
  object pattern=Call(fm,"CreateFeature",data);Require(pattern!=null,"Body pattern creation failed");string name=(string)Get(pattern,"Name");
  Check(doc,3,"three body pattern");
  Active(sw,a[1]);Call(doc,"EditUndo2",1);Check(doc,1,"pattern undo");Active(sw,a[1]);Call(doc,"EditRedo2",1);Check(doc,3,"pattern redo");
  pattern=Call(doc,"FeatureByName",name);Require(pattern!=null,"Pattern missing after redo");
  Require(Convert.ToBoolean(Call(pattern,"SetSuppression2",0,1,null)),"Pattern suppression failed");Check(doc,1,"pattern suppressed");
  Require(Convert.ToBoolean(Call(pattern,"SetSuppression2",1,1,null)),"Pattern restore failed");Active(sw,a[1]);Require(Convert.ToBoolean(Call(doc,"EditRebuild3")),"Incremental rebuild failed");Check(doc,3,"pattern restored");
  Call(doc,"ClearSelection2",true);Call(doc,"ShowNamedView2","*Isometric",7);Call(doc,"ViewZoomtofit2");Save(doc,a[1]);
  Call(sw,"CloseDoc",Call(doc,"GetTitle"));doc=Call(sw,"OpenDoc",a[1],1);Require(doc!=null,"Part reopen failed");
  Require(string.Equals((string)Call(doc,"GetPathName"),a[1],StringComparison.OrdinalIgnoreCase),"Wrong part reopened");Check(doc,3,"reopened pattern");
  Log("Revolve/body pattern/undo/redo/suppression/save/reopen passed");return 0;
 }catch(Exception e){while(e.InnerException!=null)e=e.InnerException;Log("Failed: "+e.GetType().Name+" "+e.Message);return 1;}}
}
