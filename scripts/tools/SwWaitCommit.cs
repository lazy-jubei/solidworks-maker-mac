// Read-only observation of a sketch-based extrusion edit; never rebuilds, saves or sends input.
using System;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
class SwWaitCommit {
 static object Call(object o,string n,params object[] a){return o.GetType().InvokeMember(n,BindingFlags.InvokeMethod,null,o,a);}
 static object Get(object o,string n){return o.GetType().InvokeMember(n,BindingFlags.GetProperty,null,o,null);}
 [STAThread] static int Main(string[] args){try{
  object sw=Marshal.GetActiveObject("SldWorks.Application"),doc=Get(sw,"ActiveDoc");
  string title=(string)Call(doc,"GetTitle");DateTime deadline=DateTime.UtcNow.AddSeconds(60);
  Console.WriteLine("Observing "+title);Console.Out.Flush();
  while(DateTime.UtcNow<deadline){
   if(Call(doc,"GetActiveSketch2")==null){
    double depth=Convert.ToDouble(Get(Call(doc,"Parameter","D1@Boss-Extrude1"),"SystemValue"));
    double volume=Convert.ToDouble(Get(Call(Get(doc,"Extension"),"CreateMassProperty"),"Volume"));
    Console.WriteLine("Edit closed; depth="+depth+" volume="+volume);
    var culture=System.Globalization.CultureInfo.InvariantCulture;
    if(Math.Abs(depth-double.Parse(args[0],culture))>1e-12 || Math.Abs(volume-double.Parse(args[1],culture))>1e-12)return 2;
    Console.WriteLine("UI edit closed with expected geometry");return 0;
   }
   Thread.Sleep(1000);
  }
  Console.WriteLine("Feature editor still active after 60 seconds");return 1;
 }catch(Exception e){while(e.InnerException!=null)e=e.InnerException;Console.WriteLine(e.GetType().Name+" "+e.Message);return 3;}}
}
