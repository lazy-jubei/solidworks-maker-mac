// Inspect the active regression part without creating or discarding documents.
using System;
using System.Reflection;
using System.Runtime.InteropServices;
class SwRebuildProbe {
 static object Call(object o,string n,params object[] a){return o.GetType().InvokeMember(n,BindingFlags.InvokeMethod,null,o,a);}
 static object Get(object o,string n){return o.GetType().InvokeMember(n,BindingFlags.GetProperty,null,o,null);}
 [STAThread] static int Main(){try{
  object sw=Marshal.GetActiveObject("SldWorks.Application"), doc=Get(sw,"ActiveDoc");
  if(Call(doc,"GetActiveSketch2")!=null)throw new Exception("Exit the active sketch or extrusion editor before running a rebuild probe");
  object dimension=Call(doc,"Parameter","D1@Boss-Extrude1");
  Console.WriteLine("Depth before="+Get(dimension,"SystemValue"));
  Console.WriteLine("NeedsRebuild="+Get(Get(doc,"Extension"),"NeedsRebuild2"));
  Console.WriteLine("EditRebuild3="+Call(doc,"EditRebuild3"));
  Console.WriteLine("Volume after edit rebuild="+Get(Call(Get(doc,"Extension"),"CreateMassProperty"),"Volume"));
  Console.WriteLine("ForceRebuild3="+Call(doc,"ForceRebuild3",false));
  Console.WriteLine("Depth after="+Get(dimension,"SystemValue"));
  Console.WriteLine("Volume after force rebuild="+Get(Call(Get(doc,"Extension"),"CreateMassProperty"),"Volume"));return 0;
 }catch(Exception e){while(e.InnerException!=null)e=e.InnerException;Console.WriteLine(e);return 1;}}
}
