// Focused stale-body diagnostic. No ForceRebuild call or fallback.
// Usage: source.SLDPRT new-output.SLDPRT sta|mta legacy|current
using System;using System.IO;using System.Reflection;using System.Runtime.InteropServices;using System.Threading;
class SwDimensionCycles {
 static void Log(string s){Console.WriteLine(DateTime.UtcNow.ToString("o")+" "+s);Console.Out.Flush();}
 static void Need(bool b,string s){if(!b)throw new Exception(s);}
 static object Call(object o,string n,params object[] a){return o.GetType().InvokeMember(n,BindingFlags.InvokeMethod,null,o,a);}
 static object Get(object o,string n){return o.GetType().InvokeMember(n,BindingFlags.GetProperty,null,o,null);}
 static void Save(object d,string path){object[] a={path,0,1,new DispatchWrapper(null),0,0};var p=new ParameterModifier(6);p[4]=p[5]=true;bool ok=Convert.ToBoolean(Get(d,"Extension").GetType().InvokeMember("SaveAs",BindingFlags.InvokeMethod,null,Get(d,"Extension"),a,new[]{p},null,null));Need(ok&&Convert.ToInt32(a[4])==0&&File.Exists(path)&&!Convert.ToBoolean(Call(d,"GetSaveFlag")),"Save failed");Log("Saved errors="+a[4]+" warnings="+a[5]);}
 static void Active(object sw,string path){object d=Get(sw,"ActiveDoc");Need(d!=null&&string.Equals((string)Call(d,"GetPathName"),path,StringComparison.OrdinalIgnoreCase)&&Call(d,"GetActiveSketch2")==null,"Expected active saved part with no sketch");}
 static void Check(object d,double value,string stage){
  double parameter=Convert.ToDouble(Get(Call(d,"Parameter","D1@Boss-Extrude1"),"SystemValue"));
  Array bodies=Call(d,"GetBodies2",0,false) as Array;Need(bodies!=null&&bodies.Length==1,"Expected one solid");
  double body=((double[])Call(bodies.GetValue(0),"GetMassProperties",1.0))[3];double mass=Convert.ToDouble(Get(Call(Get(d,"Extension"),"CreateMassProperty"),"Volume"));
  double expected=(.05*.03-Math.PI*.005*.005)*value;
  Log(stage+" depth="+parameter.ToString("R")+" bodyVolume="+body.ToString("R")+" massVolume="+mass.ToString("R")+" expected="+expected.ToString("R")+" needs="+Get(Get(d,"Extension"),"NeedsRebuild2"));
  Need(Math.Abs(parameter-value)<1e-10&&Math.Abs(body-expected)<1e-12&&Math.Abs(mass-expected)<1e-12,"Stale or incorrect dimension/body");
 }
 static int Run(string[] a){try{
  Need(a.Length==4&&File.Exists(a[0])&&!File.Exists(a[1])&&a[1].EndsWith(".SLDPRT",StringComparison.OrdinalIgnoreCase)&&(a[3]=="legacy"||a[3]=="current"),"Expected source/new output/apartment/setter");
  object sw=Marshal.GetActiveObject("SldWorks.Application");
  for(object d=Call(sw,"GetFirstDocument");d!=null;d=Call(d,"GetNext"))Need(!Convert.ToBoolean(Call(d,"GetSaveFlag"))&&Call(d,"GetActiveSketch2")==null,"Save and exit sketch editors first");
  object doc=Call(sw,"OpenDoc",a[0],1);Need(doc!=null,"Open failed");
  object[] aa={Call(doc,"GetTitle"),false,0,0};var p=new ParameterModifier(4);p[3]=true;
  Need(sw.GetType().InvokeMember("ActivateDoc3",BindingFlags.InvokeMethod,null,sw,aa,new[]{p},null,null)!=null&&Convert.ToInt32(aa[3])==0,"Activate failed");Active(sw,a[0]);
  Need(((Array)Call(doc,"GetConfigurationNames")).Length==1,"Expected one configuration");Check(doc,.025,"baseline");Save(doc,a[1]);Active(sw,a[1]);
  Log("Apartment="+Thread.CurrentThread.GetApartmentState()+" setter="+a[3]);
  double[] values={.03,.021,.042,.027,.05,.024,.039,.026,.045,.025};
  for(int i=0;i<values.Length;i++){
   Active(sw,a[1]);object dim=Call(doc,"Parameter","D1@Boss-Extrude1");
   if(a[3]=="legacy")dim.GetType().InvokeMember("SystemValue",BindingFlags.SetProperty,null,dim,new object[]{values[i]});
   else Need(Convert.ToInt32(Call(dim,"SetSystemValue3",values[i],1,null))==0,"Setter failed");
   Log("Cycle="+i+" needsBefore="+Get(Get(doc,"Extension"),"NeedsRebuild2"));Need(Convert.ToBoolean(Call(doc,"EditRebuild3")),"Incremental rebuild failed");Check(doc,values[i],"cycle="+i);
  }
  Save(doc,a[1]);Call(sw,"CloseDoc",Call(doc,"GetTitle"));doc=Call(sw,"OpenDoc",a[1],1);Need(doc!=null,"Reopen failed");Active(sw,a[1]);Check(doc,.025,"reopened");
  Log("Ten dimension cycles passed without full rebuild");return 0;
 }catch(Exception e){while(e.InnerException!=null)e=e.InnerException;Log("Failed: "+e.GetType().Name+" "+e.Message);return 1;}}
 static int Main(string[] a){if(a.Length!=4||(a[2]!="sta"&&a[2]!="mta")){Console.WriteLine("Expected source output sta|mta legacy|current");return 2;}int result=1;var t=new Thread(()=>{result=Run(a);});t.SetApartmentState(a[2]=="sta"?ApartmentState.STA:ApartmentState.MTA);t.Start();t.Join();return result;}
}
