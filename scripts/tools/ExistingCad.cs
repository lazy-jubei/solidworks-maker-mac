// Detect CAD/startup only in this Wine prefix; optionally foreground its own window.
using System;using System.Collections.Generic;using System.IO;using System.Runtime.InteropServices;using System.Text;
class ExistingCad {
 delegate bool EnumProc(IntPtr window,IntPtr parameter);
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]struct ProcessEntry {
  public uint size,usage,pid;public UIntPtr heap;public uint module,threads,parent;public int priority;public uint flags;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)]public string executable;
 }
 [DllImport("kernel32.dll",SetLastError=true)]static extern IntPtr CreateToolhelp32Snapshot(uint flags,uint pid);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool Process32FirstW(IntPtr snapshot,ref ProcessEntry entry);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool Process32NextW(IntPtr snapshot,ref ProcessEntry entry);
 [DllImport("kernel32.dll")]static extern bool CloseHandle(IntPtr handle);
 [DllImport("user32.dll")]static extern bool EnumWindows(EnumProc callback,IntPtr parameter);
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
 [DllImport("user32.dll")]static extern bool IsWindowVisible(IntPtr window);
 [DllImport("user32.dll")]static extern bool IsIconic(IntPtr window);
 [DllImport("user32.dll")]static extern bool ShowWindow(IntPtr window,int command);
 [DllImport("user32.dll")]static extern bool SetForegroundWindow(IntPtr window);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int GetWindowTextW(IntPtr window,StringBuilder text,int count);
 static int Main(string[] args){try{
  if(args.Length!=1||(args[0]!="--status"&&args[0]!="--activate"))return 1;
  var cad=new HashSet<uint>();var startup=new HashSet<uint>();
  IntPtr snapshot=CreateToolhelp32Snapshot(2,0);
  if(snapshot==new IntPtr(-1))throw new Exception("Cannot inspect this prefix's running applications");
  try{
   var entry=new ProcessEntry();entry.size=(uint)Marshal.SizeOf(entry);
   if(!Process32FirstW(snapshot,ref entry))throw new Exception("Cannot enumerate this prefix's processes");
   do{
    string name=Path.GetFileName(entry.executable);
    if(string.Equals(name,"sldworks.exe",StringComparison.OrdinalIgnoreCase))cad.Add(entry.pid);
    if(string.Equals(name,"SWXDesktopLauncher.exe",StringComparison.OrdinalIgnoreCase))startup.Add(entry.pid);
   }while(Process32NextW(snapshot,ref entry));
   if(Marshal.GetLastWin32Error()!=18)throw new Exception("Incomplete process enumeration");
  }finally{CloseHandle(snapshot);}
  if(cad.Count==0&&startup.Count==0)return 2;
  IntPtr target=IntPtr.Zero,fallback=IntPtr.Zero;
  EnumWindows((window,parameter)=>{
   uint pid;GetWindowThreadProcessId(window,out pid);
   if(!IsWindowVisible(window)||(!cad.Contains(pid)&&!startup.Contains(pid)))return true;
   if(fallback==IntPtr.Zero)fallback=window;
   var title=new StringBuilder(512);GetWindowTextW(window,title,title.Capacity);
   if(cad.Contains(pid)&&title.ToString().StartsWith("SOLIDWORKS Design Professional for Makers",StringComparison.OrdinalIgnoreCase)){
    target=window;return false;
   }
   return true;
  },IntPtr.Zero);
  if(target==IntPtr.Zero)target=fallback;
  if(args[0]=="--activate"&&target!=IntPtr.Zero){
   if(IsIconic(target))ShowWindow(target,9);
   SetForegroundWindow(target);
  }
  Console.WriteLine("Existing SOLIDWORKS session: CAD="+cad.Count+" startup="+startup.Count+" visible="+(target!=IntPtr.Zero));
  return 0;
 }catch(Exception e){Console.Error.WriteLine(e.Message);return 1;}}
}
