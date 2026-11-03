// Clicks one button of a dialog, only if the dialog's text contains an expected string.
// Lets a dialog be answered remotely, without weakening what it checks.
// Usage: ConfirmDialog.exe <window title> <required text> <button caption>
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

class ConfirmDialog
{
    delegate bool EnumProc(IntPtr hwnd, IntPtr param);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc proc, IntPtr param);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc proc, IntPtr param);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowTextW(IntPtr hwnd, StringBuilder text, int max);
    [DllImport("user32.dll")] static extern IntPtr SendMessageW(IntPtr hwnd, uint msg, IntPtr w, IntPtr l);
    const uint BM_CLICK = 0x00F5;

    static int Main(string[] args)
    {
        if (args.Length != 3) { Console.WriteLine("usage: <title> <required text> <button>"); return 2; }
        // Several windows can share a title (the Launcher's hidden tray window does).
        var dialogs = new List<IntPtr>();
        EnumWindows((h, p) => {
            var sb = new StringBuilder(512);
            GetWindowTextW(h, sb, sb.Capacity);
            if (sb.ToString() == args[0]) dialogs.Add(h);
            return true;
        }, IntPtr.Zero);
        if (dialogs.Count == 0) { Console.WriteLine("no window titled: " + args[0]); return 3; }

        foreach (var dlg in dialogs)
        {
            var children = new List<KeyValuePair<IntPtr, string>>();
            EnumChildWindows(dlg, (h, p) => {
                var sb = new StringBuilder(2048);
                GetWindowTextW(h, sb, sb.Capacity);
                children.Add(new KeyValuePair<IntPtr, string>(h, sb.ToString()));
                return true;
            }, IntPtr.Zero);

            bool found = false;
            IntPtr button = IntPtr.Zero;
            foreach (var c in children)
            {
                Console.WriteLine("child: " + c.Value.Replace("\r", " ").Replace("\n", " "));
                if (c.Value.Contains(args[1])) found = true;
                if (c.Value.Replace("&", "") == args[2]) button = c.Key;
            }
            if (!found || button == IntPtr.Zero) continue;
            SendMessageW(button, BM_CLICK, IntPtr.Zero, IntPtr.Zero);
            Console.WriteLine("clicked: " + args[2]);
            return 0;
        }
        Console.WriteLine("REFUSED: no matching dialog with that text and button");
        return 4;
    }
}
