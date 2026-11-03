// Local document regression: two-component assembly, drawing views and PDF export.
// Usage: SwDocumentOps.exe <saved test part> <output stem, without extension>
using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
class SwDocumentOps {
    static string stage="connect";
    static object Call(object o,string n,params object[] a){return o.GetType().InvokeMember(n,BindingFlags.InvokeMethod,null,o,a);}
    static object Get(object o,string n){return o.GetType().InvokeMember(n,BindingFlags.GetProperty,null,o,null);}
    static void Set(object o,string n,object v){o.GetType().InvokeMember(n,BindingFlags.SetProperty,null,o,new[]{v});}
    static void Require(bool v,string message){if(!v)throw new Exception(message);}
    static void Log(string text){Console.WriteLine(text);Console.Out.Flush();}
    static double Volume(object doc){return Convert.ToDouble(Get(Call(Get(doc,"Extension"),"CreateMassProperty"),"Volume"));}
    static void CheckVolume(object doc,double expected){double actual=Volume(doc);Log(stage+" volume="+actual.ToString("R",System.Globalization.CultureInfo.InvariantCulture));Require(Math.Abs(actual-expected)<1e-12,"Volume mismatch");}
    static int CountViews(object drawing){int count=0;for(object view=Call(drawing,"GetFirstView");view!=null;view=Call(view,"GetNextView")){count++;if(count>100)throw new Exception("View traversal did not terminate");}return count;}
    static object New(object sw,int pref){string path=(string)Call(sw,"GetUserPreferenceStringValue",pref);Require(File.Exists(path),"Default template missing: "+path);object doc=Call(sw,"NewDocument",path,0,0.0,0.0);Require(doc!=null,"NewDocument returned null");return doc;}
    static void Save(object doc,string path){Require(Convert.ToBoolean(Call(doc,"SaveAs",path)),"Save failed: "+path);Require(File.Exists(path),"Saved file missing");Log("Saved "+path);}
    static object Reopen(object sw,object doc,string path,int type){Call(sw,"CloseDoc",Call(doc,"GetTitle"));object result=Call(sw,"OpenDoc",path,type);Require(result!=null,"Reopen failed");return result;}
    static void CheckViewBounds(object drawing,double width,double height){
        object sheet=Call(drawing,"GetFirstView");
        for(object view=Call(sheet,"GetNextView");view!=null;view=Call(view,"GetNextView")){
            Array bounds=(Array)Call(view,"GetOutline");
            double left=Convert.ToDouble(bounds.GetValue(0)),bottom=Convert.ToDouble(bounds.GetValue(1)),right=Convert.ToDouble(bounds.GetValue(2)),top=Convert.ToDouble(bounds.GetValue(3));
            Log("View bounds m="+left+","+bottom+" to "+right+","+top);
            Require(left>=0.005 && bottom>=0.005 && right<=width-0.005 && top<=height-0.005,"Drawing view clipped by sheet edge");
            Require(right>left && top>bottom,"Drawing view empty");
        }
    }
    static int Main(string[] a){try{return Run(a);}catch(Exception e){while(e.InnerException!=null)e=e.InnerException;Log("Failed at "+stage+": "+e.GetType().Name+" "+e.Message);return 1;}}
    static int Run(string[] a){
        Require(a.Length==2,"Expected part and output stem");
        Require(File.Exists(a[0]),"Saved source part missing");
        foreach(string extension in new[]{".SLDASM",".SLDDRW",".pdf"})
            Require(!File.Exists(a[1]+extension),"Output exists; choose a new stem: "+a[1]+extension);
        object sw=Marshal.GetActiveObject("SldWorks.Application");
        stage="load source part";object part=Call(sw,"OpenDoc",a[0],1);Require(part!=null,"Source part open failed");double partVolume=Volume(part);Require(partVolume>0,"Source part has no volume");
        stage="new assembly";object assembly=New(sw,9);Log("Created assembly");
        stage="insert first component";object first=Call(assembly,"AddComponent5",a[0],0,"",false,"",0.0,0.0,0.0);Require(first!=null,"First component missing");Log("First component inserted");
        stage="insert second component";object second=Call(assembly,"AddComponent5",a[0],0,"",false,"",0.08,0.0,0.0);Require(second!=null,"Second component missing");Log("Second component inserted");
        int components=Convert.ToInt32(Call(assembly,"GetComponentCount",false));Log("Component count="+components);Require(components==2,"Expected two components");
        Call(assembly,"EditRebuild3");CheckVolume(assembly,2*partVolume);Call(assembly,"ShowNamedView2","*Isometric",7);Call(assembly,"ViewZoomtofit2");Save(assembly,a[1]+".SLDASM");
        stage="reopen assembly";assembly=Reopen(sw,assembly,a[1]+".SLDASM",2);Require(Convert.ToInt32(Call(assembly,"GetComponentCount",false))==2,"Components lost after reopen");CheckVolume(assembly,2*partVolume);
        stage="new drawing";object drawing=New(sw,10);Log("Created drawing");
        Array properties=(Array)Call(Call(drawing,"GetCurrentSheet"),"GetProperties2");
        double width=Convert.ToDouble(properties.GetValue(5)),height=Convert.ToDouble(properties.GetValue(6));
        Log("Drawing sheet size m="+width+" x "+height);
        stage="front drawing view";object front=Call(drawing,"CreateDrawViewFromModelView3",a[0],"*Front",0.27*width,0.55*height,0.0);Require(front!=null,"Front view missing");Set(front,"UseSheetScale",0);Set(front,"ScaleDecimal",1.0);
        stage="isometric drawing view";object iso=Call(drawing,"CreateDrawViewFromModelView3",a[0],"*Isometric",0.72*width,0.55*height,0.0);Require(iso!=null,"Isometric view missing");Set(iso,"UseSheetScale",0);Set(iso,"ScaleDecimal",1.0);
        Call(drawing,"EditRebuild3");CheckViewBounds(drawing,width,height);
        int views=CountViews(drawing);Log("Drawing view count including sheet="+views);Require(views==3,"Expected sheet plus two model views");Call(drawing,"ViewZoomtofit2");Save(drawing,a[1]+".SLDDRW");
        stage="PDF export";Save(drawing,a[1]+".pdf");byte[] header=new byte[5];using(var f=File.OpenRead(a[1]+".pdf")){Require(f.Length>1000,"PDF too small");f.Read(header,0,5);}Require(System.Text.Encoding.ASCII.GetString(header)=="%PDF-","Invalid PDF header");
        stage="reopen drawing";drawing=Reopen(sw,drawing,a[1]+".SLDDRW",3);Require(CountViews(drawing)==3,"Drawing views lost after reopen");CheckViewBounds(drawing,width,height);
        Log("Assembly, drawing and PDF checks passed");return 0;
    }
}
