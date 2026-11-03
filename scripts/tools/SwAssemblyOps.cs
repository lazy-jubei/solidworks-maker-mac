// Copy a saved two-instance assembly; move, mate, suppress/restore, save/reopen.
// Compile with the installed SolidWorks.Interop.swconst.dll reference.
// Usage: SwAssemblyOps.exe <saved source .SLDASM> <new output .SLDASM>
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using SolidWorks.Interop.swconst;
class SwAssemblyOps {
 static void Log(string s){Console.WriteLine(DateTime.UtcNow.ToString("o")+" "+s);Console.Out.Flush();}
 static void Require(bool b,string s){if(!b)throw new Exception(s);}
 static object Call(object o,string n,params object[] a){Log("begin "+n);var t=Stopwatch.StartNew();try{return o.GetType().InvokeMember(n,BindingFlags.InvokeMethod,null,o,a);}finally{t.Stop();Log("end "+n+" ms="+t.ElapsedMilliseconds);}}
 static object Get(object o,string n){return o.GetType().InvokeMember(n,BindingFlags.GetProperty,null,o,null);}
 static object RefCall(object o,string n,object[] a,params int[] refs){var p=new ParameterModifier(a.Length);foreach(int i in refs)p[i]=true;return o.GetType().InvokeMember(n,BindingFlags.InvokeMethod,null,o,a,new[]{p},null,null);}
 static double Volume(object d){return Convert.ToDouble(Get(Call(Get(d,"Extension"),"CreateMassProperty"),"Volume"));}
 static void CheckVolume(object d,double expected,string stage){double v=Volume(d);Log(stage+" volume="+v.ToString("R"));Require(Math.Abs(v-expected)<1e-12,stage+" volume mismatch");}
 static double[] Transform(object c){return (double[])Get(Get(c,"Transform2"),"ArrayData");}
 static void CheckPosition(object c,double[] expected){double[] p=Transform(c);for(int i=0;i<13;i++)Require(Math.Abs(p[i]-expected[i])<1e-8,"Component transform mismatch at "+i);}
 static object[] Components(object d){Array a=(Array)Call(d,"GetComponents",false);Require(a!=null&&a.Length==2,"Expected two components");object x=a.GetValue(0),y=a.GetValue(1);return Transform(x)[9]<Transform(y)[9]?new[]{x,y}:new[]{y,x};}
 static void SelectComponent(object d,object c){Call(d,"ClearSelection2",true);Require(Convert.ToBoolean(Call(c,"Select4",false,new DispatchWrapper(null),false)),"Component selection failed");}
 static void Save(object d,string path){object[] a={path,0,1,new DispatchWrapper(null),0,0};Log("begin SaveAs");bool ok=Convert.ToBoolean(RefCall(Get(d,"Extension"),"SaveAs",a,4,5));Log("end SaveAs errors="+a[4]+" warnings="+a[5]);Require(ok&&Convert.ToInt32(a[4])==0,"Save failed");Require(File.Exists(path)&&new FileInfo(path).Length>0,"Saved file missing");Require(!Convert.ToBoolean(Call(d,"GetSaveFlag")),"Saved assembly dirty");}
 [STAThread] static int Main(string[] a){try{
  Require(a.Length==2,"Expected source and new output");Require(File.Exists(a[0])&&!File.Exists(a[1]),"Source missing or output exists");Require(a[1].EndsWith(".SLDASM",StringComparison.OrdinalIgnoreCase),"Output must be SLDASM");
  object sw=Marshal.GetActiveObject("SldWorks.Application");
  for(object d=Call(sw,"GetFirstDocument");d!=null;d=Call(d,"GetNext"))Require(!Convert.ToBoolean(Call(d,"GetSaveFlag")),"Save open documents first");
  object doc=Call(sw,"OpenDoc",a[0],2);Require(doc!=null,"Assembly open failed");
  object[] activate={Call(doc,"GetTitle"),false,(int)swRebuildOnActivation_e.swDontRebuildActiveDoc,0};
  Require(RefCall(sw,"ActivateDoc3",activate,3)!=null&&Convert.ToInt32(activate[3])==0,"Assembly activation failed");
  Require(string.Equals((string)Call(Get(sw,"ActiveDoc"),"GetPathName"),a[0],StringComparison.OrdinalIgnoreCase),"Source not active");
  double baseline=Volume(doc);Require(baseline>0,"Empty assembly");
  object[] c=Components(doc);Require(string.Equals((string)Call(c[0],"GetPathName"),(string)Call(c[1],"GetPathName"),StringComparison.OrdinalIgnoreCase),"Expected two instances of one part");
  Save(doc,a[1]);Require(string.Equals((string)Call(doc,"GetPathName"),a[1],StringComparison.OrdinalIgnoreCase),"Copy not active; refusing edits");
  c=Components(doc);object anchor=c[0],moving=c[1];
  SelectComponent(doc,anchor);Call(doc,"FixComponent");Require(Convert.ToBoolean(Call(anchor,"IsFixed")),"Anchor not fixed");
  SelectComponent(doc,moving);Call(doc,"UnfixComponent");Require(!Convert.ToBoolean(Call(moving,"IsFixed")),"Moving component fixed");
  double[] anchorPos=Transform(anchor),target=Transform(moving);target[9]+=0.02;
  object transform=Call(Call(sw,"GetMathUtility"),"CreateTransform",(object)target);
  Require(Convert.ToBoolean(Call(moving,"SetTransformAndSolve3",transform,true)),"Component movement failed");
  Call(doc,"UpdateBox");Require(Convert.ToBoolean(Call(doc,"EditRebuild3")),"Rebuild after movement failed");CheckPosition(moving,target);CheckPosition(anchor,anchorPos);CheckVolume(doc,baseline,"moved");
  Call(doc,"ClearSelection2",true);string assemblyName=Path.GetFileNameWithoutExtension((string)Call(doc,"GetTitle"));
  object ext=Get(doc,"Extension");
  for(int i=0;i<2;i++){
   string plane="Front Plane@"+Get(c[i],"Name2")+"@"+assemblyName;
   Require(Convert.ToBoolean(Call(ext,"SelectByID2",plane,"PLANE",0.0,0.0,0.0,i!=0,1,new DispatchWrapper(null),0)),"Mate plane selection failed: "+plane);
  }
  object[] mateArgs={(int)swMateType_e.swMateDISTANCE,(int)swMateAlign_e.swMateAlignALIGNED,false,0.04,0.04,0.04,1.0,1.0,0.0,0.0,0.0,false,false,0,0};
  object mate=RefCall(doc,"AddMate5",mateArgs,14);Log("Distance mate status="+mateArgs[14]);Require(mate!=null&&Convert.ToInt32(mateArgs[14])==(int)swAddMateError_e.swAddMateError_NoError,"Distance mate creation failed");
  Call(doc,"ClearSelection2",true);
  Require(Convert.ToBoolean(Call(doc,"EditRebuild3")),"Mate rebuild failed");CheckPosition(anchor,anchorPos);
  double[] mated=Transform(moving);Require(Math.Abs(Math.Abs(mated[11]-anchorPos[11])-0.04)<1e-8,"Distance mate did not move planes 40 mm apart");CheckVolume(doc,baseline,"mated");
  Require(Convert.ToInt32(Call(moving,"SetSuppression2",(int)swComponentSuppressionState_e.swComponentSuppressed))==(int)swSuppressionError_e.swSuppressionChangeOk,"Component suppression failed");
  CheckVolume(doc,baseline/2,"one component suppressed");
  Require(Convert.ToInt32(Call(moving,"SetSuppression2",(int)swComponentSuppressionState_e.swComponentFullyResolved))==(int)swSuppressionError_e.swSuppressionChangeOk,"Component restore failed");
  Require(Convert.ToBoolean(Call(doc,"EditRebuild3")),"Restore rebuild failed");CheckVolume(doc,baseline,"restored");CheckPosition(moving,mated);
  Call(doc,"ClearSelection2",true);Call(doc,"ShowNamedView2","*Isometric",7);Call(doc,"ViewZoomtofit2");Save(doc,a[1]);
  Call(sw,"CloseDoc",Call(doc,"GetTitle"));doc=Call(sw,"OpenDoc",a[1],2);Require(doc!=null,"Assembly reopen failed");
  c=Components(doc);CheckPosition(c[0],anchorPos);CheckPosition(c[1],mated);CheckVolume(doc,baseline,"reopened");
  Array mates=Call(c[1],"GetMates") as Array;Require(mates!=null&&mates.Length>0,"Mate missing after reopen");
  Log("Assembly movement/mate/suppression/save/reopen passed");return 0;
 }catch(Exception e){while(e.InnerException!=null)e=e.InnerException;Log("Failed: "+e.GetType().Name+" "+e.Message);return 1;}}
}
