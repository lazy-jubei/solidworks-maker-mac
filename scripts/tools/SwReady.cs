// Wait for startup add-ins as well as ROT registration before driving CAD.
using System;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
class SwReady {
    static object Get(object o,string n){return o.GetType().InvokeMember(n,BindingFlags.GetProperty,null,o,null);}
    [STAThread] static int Main(){
        DateTime deadline=DateTime.UtcNow.AddMinutes(5);object sw=null;
        while(DateTime.UtcNow<deadline){
            try {
                if(sw==null)sw=Marshal.GetActiveObject("SldWorks.Application");
                if(Convert.ToBoolean(Get(sw,"StartupProcessCompleted"))){Console.WriteLine("StartupProcessCompleted=True");Console.WriteLine("UserControl="+Get(sw,"UserControl"));return 0;}
            } catch(Exception e){
                while(e.InnerException!=null)e=e.InnerException;
                var com=e as COMException;
                if(com==null || (com.ErrorCode!=unchecked((int)0x800401e3) && com.ErrorCode!=unchecked((int)0x80010001) && com.ErrorCode!=unchecked((int)0x8001010a))){
                    Console.WriteLine("Startup check failed: "+e.GetType().Name+" "+e.Message);return 2;
                }
            }
            Thread.Sleep(1000);
        }
        Console.WriteLine("CAD startup did not complete within five minutes");return 1;
    }
}
