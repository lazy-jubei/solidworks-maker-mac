// Usage: SwConfigOps.exe <saved baseline cut part> <new output .SLDPRT>
// Checks independent configuration dimensions, suppression and save/reopen.
using System;using System.IO;using System.Reflection;using System.Runtime.InteropServices;
using SolidWorks.Interop.swconst;
class SwConfigOps {
 static void Log(string s){Console.WriteLine(DateTime.UtcNow.ToString("o")+" "+s);Console.Out.Flush();}
 static void Need(bool b,string s){if(!b)throw new Exception(s);}
 static object Call(object o,string n,params object[] a){Log("begin "+n);object v=o.GetType().InvokeMember(n,BindingFlags.InvokeMethod,null,o,a);Log("end "+n);return v;}
 static object Get(object o,string n){return o.GetType().InvokeMember(n,BindingFlags.GetProperty,null,o,null);}
 static void Active(object sw,string path){object d=Get(sw,"ActiveDoc");Need(d!=null&&string.Equals((string)Call(d,"GetPathName"),path,StringComparison.OrdinalIgnoreCase),"Test part no longer active");}
 static void Check(object d,string config,double depth,bool cut){
  Need((string)Get(Get(Get(d,"ConfigurationManager"),"ActiveConfiguration"),"Name")==config,"Wrong active configuration");
  double actual=Convert.ToDouble(Get(Call(d,"Parameter","D1@Boss-Extrude1"),"SystemValue"));Need(Math.Abs(actual-depth)<1e-10,"Configuration depth mismatch");
  Array bodies=Call(d,"GetBodies2",0,false) as Array;Need(bodies!=null&&bodies.Length==1,"Expected one solid");
  double[] m=(double[])Call(bodies.GetValue(0),"GetMassProperties",1.0);double expected=(.05*.03-(cut?Math.PI*.005*.005:0))*depth;
  Need(Math.Abs(m[3]-expected)<1e-12,"Configuration volume mismatch "+m[3]+" expected "+expected);
  Log("Configuration="+config+" depth="+depth.ToString("R")+" cut="+cut+" volume="+m[3].ToString("R"));
 }
 static void Switch(object sw,object d,string path,string config){Active(sw,path);string current=(string)Get(Get(Get(d,"ConfigurationManager"),"ActiveConfiguration"),"Name");if(current!=config)Need(Convert.ToBoolean(Call(d,"ShowConfiguration2",config)),"Configuration switch failed");Need((string)Get(Get(Get(d,"ConfigurationManager"),"ActiveConfiguration"),"Name")==config,"Requested configuration not active");Need(Convert.ToBoolean(Call(d,"EditRebuild3")),"Incremental rebuild failed");}
 static void Save(object d,string path){
  object ext=Get(d,"Extension");object[] a={path,0,1,new DispatchWrapper(null),0,0};var p=new ParameterModifier(a.Length);p[4]=p[5]=true;
  Log("begin SaveAs");bool ok=Convert.ToBoolean(ext.GetType().InvokeMember("SaveAs",BindingFlags.InvokeMethod,null,ext,a,new[]{p},null,null));Log("end SaveAs errors="+a[4]+" warnings="+a[5]);
  Need(ok&&Convert.ToInt32(a[4])==0&&File.Exists(path)&&new FileInfo(path).Length>0&&!Convert.ToBoolean(Call(d,"GetSaveFlag")),"Save failed");
 }
 [STAThread]static int Main(string[] a){try{
  Need(a.Length==2&&File.Exists(a[0])&&!File.Exists(a[1])&&a[1].EndsWith(".SLDPRT",StringComparison.OrdinalIgnoreCase),"Expected source part and new SLDPRT output");
  object sw=Marshal.GetActiveObject("SldWorks.Application");
  for(object d=Call(sw,"GetFirstDocument");d!=null;d=Call(d,"GetNext")){Need(!Convert.ToBoolean(Call(d,"GetSaveFlag"))&&Call(d,"GetActiveSketch2")==null,"Save documents and close sketches first");}
  object doc=Call(sw,"OpenDoc",a[0],1);Need(doc!=null,"Open source failed");
  object[] activation={(string)Call(doc,"GetTitle"),false,(int)swRebuildOnActivation_e.swDontRebuildActiveDoc,0};var pm=new ParameterModifier(4);pm[3]=true;
  object activated=sw.GetType().InvokeMember("ActivateDoc3",BindingFlags.InvokeMethod,null,sw,activation,new[]{pm},null,null);Need(activated!=null&&Convert.ToInt32(activation[3])==0,"Activation failed");Active(sw,a[0]);
  Array names=Call(doc,"GetConfigurationNames") as Array;Need(names!=null&&names.Length==1,"Expected single-configuration source");string original=(string)names.GetValue(0);Need(original!="CodexTall","Test configuration already exists");
  Check(doc,original,.025,true);Need(Call(doc,"FeatureByName","Cut-Extrude1")!=null,"Expected baseline cut feature");Save(doc,a[1]);Active(sw,a[1]);
  object config=Call(Get(doc,"ConfigurationManager"),"AddConfiguration2","CodexTall","Configuration regression","",0,"","40 mm test",true);Need(config!=null,"Add configuration failed");
  Switch(sw,doc,a[1],"CodexTall");object dimension=Call(doc,"Parameter","D1@Boss-Extrude1");
  int status=Convert.ToInt32(Call(dimension,"SetSystemValue3",.04,(int)swSetValueInConfiguration_e.swSetValue_InSpecificConfigurations,new string[]{"CodexTall"}));Need(status==0,"Specific configuration dimension edit failed");
  Active(sw,a[1]);Need(Convert.ToBoolean(Call(doc,"EditRebuild3")),"Dimension rebuild failed");Check(doc,"CodexTall",.04,true);
  Switch(sw,doc,a[1],original);Check(doc,original,.025,true);Switch(sw,doc,a[1],"CodexTall");Check(doc,"CodexTall",.04,true);
  object cut=Call(doc,"FeatureByName","Cut-Extrude1");Need(Convert.ToBoolean(Call(cut,"SetSuppression2",0,1,null)),"Configuration cut suppression failed");Check(doc,"CodexTall",.04,false);
  Switch(sw,doc,a[1],original);Check(doc,original,.025,true);Switch(sw,doc,a[1],"CodexTall");Check(doc,"CodexTall",.04,false);
  Need(Convert.ToBoolean(Call(cut,"SetSuppression2",1,1,null)),"Configuration cut restore failed");Active(sw,a[1]);Need(Convert.ToBoolean(Call(doc,"EditRebuild3")),"Cut restore rebuild failed");Check(doc,"CodexTall",.04,true);
  Call(doc,"ClearSelection2",true);Call(doc,"ShowNamedView2","*Isometric",7);Call(doc,"ViewZoomtofit2");Save(doc,a[1]);
  Call(sw,"CloseDoc",Call(doc,"GetTitle"));doc=Call(sw,"OpenDoc",a[1],1);Need(doc!=null,"Reopen failed");Active(sw,a[1]);Check(doc,"CodexTall",.04,true);
  Switch(sw,doc,a[1],original);Check(doc,original,.025,true);Switch(sw,doc,a[1],"CodexTall");Check(doc,"CodexTall",.04,true);Save(doc,a[1]);
  Log("Configuration dimensions/suppression/switch/rebuild/save/reopen passed");return 0;
 }catch(Exception e){while(e.InnerException!=null)e=e.InnerException;Log("Failed: "+e.GetType().Name+" "+e.Message);return 1;}}
}
