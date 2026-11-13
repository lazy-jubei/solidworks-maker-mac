// Scoped show/hide of a PID's own on-screen windows. No input, no clicks, no credential handling.
//   WinHide.exe --list --pid <pid>
//   WinHide.exe --hide --pid <pid> --state <file>   records what it hid
//   WinHide.exe --show --state <file>               restores only the recorded windows
// --show deliberately takes no --pid: restoring "every window of the PID" would SW_SHOW the
// prefix's internal hidden windows (hotWnd, Properties, VBA, IME), which is blanket input.
using System;using System.Collections.Generic;using System.IO;using System.Runtime.InteropServices;using System.Text;
class WinHide {
 const int SW_HIDE=0;
 const int SW_SHOW=5;
 delegate bool EnumProc(IntPtr window,IntPtr parameter);
 [DllImport("user32.dll")]static extern bool EnumWindows(EnumProc callback,IntPtr parameter);
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
 [DllImport("user32.dll")]static extern bool IsWindow(IntPtr window);
 [DllImport("user32.dll")]static extern bool IsWindowVisible(IntPtr window);
 [DllImport("user32.dll")]static extern bool ShowWindow(IntPtr window,int command);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int GetWindowTextW(IntPtr window,StringBuilder text,int count);
 [DllImport("user32.dll")]static extern int GetWindowTextLength(IntPtr window);
 static string Describe(IntPtr window,uint pid){
  var title=new StringBuilder(Math.Max(GetWindowTextLength(window)+1,1));
  if(title.Capacity>1)GetWindowTextW(window,title,title.Capacity);
  string text=title.ToString().Replace("\r"," ").Replace("\n"," ");
  if(text.Length>120)text=text.Substring(0,120);
  return "hwnd=0x"+((long)window).ToString("x")+" pid="+pid+" visible="+IsWindowVisible(window)+" title="+text;
 }
 static int Main(string[] args){try{
  string mode="",state="";uint want=0;
  for(int i=0;i<args.Length;i++){
   if(args[i]=="--hide")mode="hide";
   else if(args[i]=="--list")mode="list";
   else if(args[i]=="--show")mode="show";
   else if(args[i]=="--state"&&i+1<args.Length)state=args[++i];
   else if(args[i]=="--pid"&&i+1<args.Length){
    string value=args[++i];
    // Accept the decimal pid that CadPid.exe prints and the 0x form the other helpers use.
    want=value.StartsWith("0x")?Convert.ToUInt32(value.Substring(2),16):uint.Parse(value);
   }
   else return 2;
  }
  if(mode=="show"){
   if(state==""||!File.Exists(state))return 2;
   int restored=0;
   foreach(string line in File.ReadAllLines(state)){
    if(line.Trim()=="")continue;
    IntPtr window=new IntPtr(Convert.ToInt64(line.Trim().Substring(2),16));
    if(!IsWindow(window)){Console.WriteLine("stale "+line.Trim());continue;}
    ShowWindow(window,SW_SHOW);
    Console.WriteLine("show "+Describe(window,0));restored++;
   }
   File.Delete(state);
   Console.Out.Flush();
   return restored>0?0:3;
  }
  if(want==0)return 2;
  var targets=new List<IntPtr>();
  EnumWindows((window,parameter)=>{
   uint pid;GetWindowThreadProcessId(window,out pid);
   // Only on-screen windows of this PID are ever touched.
   if(pid==want&&IsWindowVisible(window))targets.Add(window);
   return true;
  },IntPtr.Zero);
  var hid=new List<string>();
  foreach(IntPtr window in targets){
   if(mode=="hide"){ShowWindow(window,SW_HIDE);hid.Add("0x"+((long)window).ToString("x"));}
   Console.WriteLine((mode=="hide"?"hid ":"visible ")+Describe(window,want));
  }
  if(mode=="hide"&&state!="")File.WriteAllLines(state,hid);
  Console.Out.Flush();
  return 0;
 }catch(Exception e){Console.Error.WriteLine(e.Message);return 1;}}
}
