// Dedicated cut-box regression: fillet, chamfer, suppression and save/reopen.
// Compile with a reference to the installed api/redist/SolidWorks.Interop.swconst.dll.
// Usage: SwEdgeOps.exe <saved cut regression part> <new output .SLDPRT>
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using SolidWorks.Interop.swconst;
class SwEdgeOps {
 static void Log(string s){Console.WriteLine(DateTime.UtcNow.ToString("o")+" "+s);Console.Out.Flush();}
 static void Require(bool b,string s){if(!b)throw new Exception(s);}
 static object Call(object o,string n,params object[] a){Log("begin "+n);var t=Stopwatch.StartNew();try{return o.GetType().InvokeMember(n,BindingFlags.InvokeMethod,null,o,a);}finally{t.Stop();Log("end "+n+" ms="+t.ElapsedMilliseconds);}}
 static object Get(object o,string n){return o.GetType().InvokeMember(n,BindingFlags.GetProperty,null,o,null);}
 static void Set(object o,string n,object v){o.GetType().InvokeMember(n,BindingFlags.SetProperty,null,o,new[]{v});}
 static double Volume(object d){return Convert.ToDouble(Get(Call(Get(d,"Extension"),"CreateMassProperty"),"Volume"));}
 static void Check(object d,double expected,string stage){double v=Volume(d);Log(stage+" volume="+v.ToString("R"));Require(Math.Abs(v-expected)<1e-12,stage+" volume mismatch");}
 static bool Near(double a,double b){return Math.Abs(a-b)<1e-8;}
 static void SelectEdge(object doc,double y,double z,int mark){
  Call(doc,"ClearSelection2",true);
  Array bodies=Call(doc,"GetBodies2",0,false) as Array;Require(bodies!=null && bodies.Length==1,"Expected one solid");
  object found=null;
  foreach(object edge in (Array)Call(bodies.GetValue(0),"GetEdges")){
   object v1=Call(edge,"GetStartVertex"),v2=Call(edge,"GetEndVertex");if(v1==null || v2==null)continue;
   double[] a=(double[])Call(v1,"GetPoint"),b=(double[])Call(v2,"GetPoint");
   if(Near(a[1],y)&&Near(b[1],y)&&Near(a[2],z)&&Near(b[2],z)&&Near(Math.Min(a[0],b[0]),0)&&Near(Math.Max(a[0],b[0]),0.05)){
    Require(found==null,"Edge match ambiguous");found=edge;
   }
  }
  Require(found!=null,"Expected 50 mm edge missing");
  object sd=Call(Get(doc,"SelectionManager"),"CreateSelectData");Set(sd,"Mark",mark);
  Require(Convert.ToBoolean(Call(found,"Select4",false,sd)),"Edge selection failed");
 }
 static void Save(object d,string path){
  object[] a={path,0,1,new DispatchWrapper(null),0,0};var modifier=new ParameterModifier(a.Length);modifier[4]=true;modifier[5]=true;
  object ext=Get(d,"Extension");Log("begin SaveAs "+path);var t=Stopwatch.StartNew();
  bool ok=Convert.ToBoolean(ext.GetType().InvokeMember("SaveAs",BindingFlags.InvokeMethod,null,ext,a,new[]{modifier},null,null));t.Stop();
  Log("end SaveAs ms="+t.ElapsedMilliseconds+" errors="+a[4]+" warnings="+a[5]);
  Require(ok&&Convert.ToInt32(a[4])==0,"Native save failed");Require(File.Exists(path)&&new FileInfo(path).Length>0,"Saved part absent/empty");
  Require(!Convert.ToBoolean(Call(d,"GetSaveFlag")),"Saved part dirty");
 }
 [STAThread] static int Main(string[] a){try{
  Require(a.Length==2,"Expected source and new output path");Require(File.Exists(a[0])&&!File.Exists(a[1]),"Source missing or output already exists");
  Require(a[1].EndsWith(".SLDPRT",StringComparison.OrdinalIgnoreCase),"Output must be SLDPRT");
  object sw=Marshal.GetActiveObject("SldWorks.Application");
  // Refuse all dirty/editor documents before opening a different active model.
  for(object d=Call(sw,"GetFirstDocument");d!=null;d=Call(d,"GetNext")){
   Require(!Convert.ToBoolean(Call(d,"GetSaveFlag")),"Save open documents first");Require(Call(d,"GetActiveSketch2")==null,"Close active sketch first");
  }
  object doc=Call(sw,"OpenDoc",a[0],1);Require(doc!=null,"Source open failed");
  object[] activate={(string)Call(doc,"GetTitle"),false,(int)swRebuildOnActivation_e.swDontRebuildActiveDoc,0};
  var activateModifier=new ParameterModifier(activate.Length);activateModifier[3]=true;
  object active=sw.GetType().InvokeMember("ActivateDoc3",BindingFlags.InvokeMethod,null,sw,activate,new[]{activateModifier},null,null);
  Require(active!=null && Convert.ToInt32(activate[3])==0,"Source activation failed");
  Require(string.Equals((string)Call(Get(sw,"ActiveDoc"),"GetPathName"),a[0],StringComparison.OrdinalIgnoreCase),"Source not active");
  double baseline=(0.05*0.03-Math.PI*0.005*0.005)*0.025;Check(doc,baseline,"baseline");
  Save(doc,a[1]);Require(string.Equals((string)Call(doc,"GetPathName"),a[1],StringComparison.OrdinalIgnoreCase),"Copy not active; refusing edits");
  object fm=Get(doc,"FeatureManager");
  object data=Call(fm,"CreateDefinition",(int)swFeatureNameID_e.swFmFillet);Require(data!=null,"Fillet definition missing");
  Require(Convert.ToBoolean(Call(data,"Initialize",(int)swSimpleFilletType_e.swConstRadiusFillet)),"Fillet initialize failed");
  Set(data,"ConicTypeForCrossSectionProfile",(int)swFeatureFilletProfileType_e.swFeatureFilletCircular);
  Set(data,"DefaultRadius",0.002);Set(data,"OverflowType",(int)swFilletOverFlowType_e.swFilletOverFlowType_Default);
  Set(data,"PropagateToTangentFaces",false);
  SelectEdge(doc,0.03,0.025,1);
  object fillet=Call(fm,"CreateFeature",data);Require(fillet!=null,"Fillet creation failed");
  double afterFillet=baseline-0.05*0.002*0.002*(1-Math.PI/4);Check(doc,afterFillet,"2 mm fillet");
  SelectEdge(doc,0,0,0);
  object chamfer=Call(fm,"InsertFeatureChamfer",0,(int)swChamferType_e.swChamferAngleDistance,0.002,Math.PI/4,0.0,0.0,0.0,0.0);
  Require(chamfer!=null,"Chamfer creation failed");double expected=afterFillet-0.05*0.002*0.002/2;Check(doc,expected,"2 mm chamfer");
  Require(Convert.ToBoolean(Call(chamfer,"SetSuppression2",0,1,null)),"Chamfer suppression failed");Check(doc,afterFillet,"chamfer suppressed");
  Require(Convert.ToBoolean(Call(chamfer,"SetSuppression2",1,1,null)),"Chamfer restore failed");
  Require(Convert.ToBoolean(Call(doc,"EditRebuild3")),"Incremental rebuild failed");Check(doc,expected,"restored chamfer");
  Call(doc,"ClearSelection2",true);Call(doc,"ShowNamedView2","*Isometric",7);Call(doc,"ViewZoomtofit2");Save(doc,a[1]);
  string title=(string)Call(doc,"GetTitle");Call(sw,"CloseDoc",title);doc=Call(sw,"OpenDoc",a[1],1);Require(doc!=null,"Reopen failed");Check(doc,expected,"reopened edge features");
  Require(string.Equals((string)Call(doc,"GetPathName"),a[1],StringComparison.OrdinalIgnoreCase),"Wrong part reopened");
  Log("Fillet/chamfer/suppress/restore/save/reopen passed");return 0;
 }catch(Exception e){while(e.InnerException!=null)e=e.InnerException;Log("Failed: "+e.GetType().Name+" "+e.Message);return 1;}}
}
