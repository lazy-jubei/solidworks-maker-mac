// Usage: SwStlOps.exe <exact active saved cut-box part> <new output .stl>
// Exports a millimetre binary STL and restores the previous export preferences.
using System;using System.IO;using System.Reflection;using System.Runtime.InteropServices;
using SolidWorks.Interop.swconst;
class SwStlOps {
 static void Log(string s){Console.WriteLine(DateTime.UtcNow.ToString("o")+" "+s);Console.Out.Flush();}
 static void Need(bool b,string s){if(!b)throw new Exception(s);}
 static object Call(object o,string n,params object[] a){return o.GetType().InvokeMember(n,BindingFlags.InvokeMethod,null,o,a);}
 static object Get(object o,string n){return o.GetType().InvokeMember(n,BindingFlags.GetProperty,null,o,null);}
 [STAThread]static int Main(string[] a){try{
  Need(a.Length==2&&File.Exists(a[0])&&!File.Exists(a[1])&&a[1].EndsWith(".stl",StringComparison.OrdinalIgnoreCase),"Expected saved source and new STL output");
  object sw=Marshal.GetActiveObject("SldWorks.Application"),doc=Get(sw,"ActiveDoc");
  Need(doc!=null&&Convert.ToInt32(Call(doc,"GetType"))==1&&string.Equals((string)Call(doc,"GetPathName"),a[0],StringComparison.OrdinalIgnoreCase),"Expected exact active part");
  Need(!Convert.ToBoolean(Call(doc,"GetSaveFlag"))&&Call(doc,"GetActiveSketch2")==null,"Save part and exit sketch first");
  Array bodies=Call(doc,"GetBodies2",0,false) as Array;Need(bodies!=null&&bodies.Length==1,"Expected one solid");
  double volume=((double[])Call(bodies.GetValue(0),"GetMassProperties",1.0))[3];double expected=(.05*.03-Math.PI*.005*.005)*.025;
  Need(Math.Abs(volume-expected)<1e-12,"Expected baseline cut-box volume");Log("Source volume m3="+volume.ToString("R"));
  int binary=(int)swUserPreferenceToggle_e.swSTLBinaryFormat,preview=(int)swUserPreferenceToggle_e.swSTLPreview,units=(int)swUserPreferenceIntegerValue_e.swExportStlUnits;
  bool oldBinary=Convert.ToBoolean(Call(sw,"GetUserPreferenceToggle",binary)),oldPreview=Convert.ToBoolean(Call(sw,"GetUserPreferenceToggle",preview));int oldUnits=Convert.ToInt32(Call(sw,"GetUserPreferenceIntegerValue",units));
  Log("Previous binary="+oldBinary+" preview="+oldPreview+" units="+oldUnits);
  try{
   if(!oldBinary)Log("Set binary result="+Call(sw,"SetUserPreferenceToggle",binary,true));
   if(oldPreview)Log("Disable preview result="+Call(sw,"SetUserPreferenceToggle",preview,false));
   if(oldUnits!=(int)swLengthUnit_e.swMM)Log("Set units result="+Call(sw,"SetUserPreferenceIntegerValue",units,(int)swLengthUnit_e.swMM));
   Need(Convert.ToBoolean(Call(sw,"GetUserPreferenceToggle",binary))&&!Convert.ToBoolean(Call(sw,"GetUserPreferenceToggle",preview))&&Convert.ToInt32(Call(sw,"GetUserPreferenceIntegerValue",units))==(int)swLengthUnit_e.swMM,"Export preferences mismatch");
   Call(doc,"ClearSelection2",true);object ext=Get(doc,"Extension");object[] save={a[1],0,1,new DispatchWrapper(null),0,0};var p=new ParameterModifier(6);p[4]=p[5]=true;
   Log("begin STL SaveAs");bool ok=Convert.ToBoolean(ext.GetType().InvokeMember("SaveAs",BindingFlags.InvokeMethod,null,ext,save,new[]{p},null,null));Log("end STL SaveAs errors="+save[4]+" warnings="+save[5]);
   Need(ok&&Convert.ToInt32(save[4])==0&&File.Exists(a[1])&&new FileInfo(a[1]).Length>84,"STL export failed");
  }finally{
   Call(sw,"SetUserPreferenceToggle",binary,oldBinary);Call(sw,"SetUserPreferenceToggle",preview,oldPreview);Call(sw,"SetUserPreferenceIntegerValue",units,oldUnits);
   Need(Convert.ToBoolean(Call(sw,"GetUserPreferenceToggle",binary))==oldBinary&&Convert.ToBoolean(Call(sw,"GetUserPreferenceToggle",preview))==oldPreview&&Convert.ToInt32(Call(sw,"GetUserPreferenceIntegerValue",units))==oldUnits,"Export preferences not restored");Log("Previous export preferences restored");
  }
  Need(string.Equals((string)Call(doc,"GetPathName"),a[0],StringComparison.OrdinalIgnoreCase)&&!Convert.ToBoolean(Call(doc,"GetSaveFlag")),"Source path/clean state changed");
  Log("STL export passed; validate mesh independently");return 0;
 }catch(Exception e){while(e.InnerException!=null)e=e.InnerException;Log("Failed: "+e.GetType().Name+" "+e.Message);return 1;}}
}
