// Target native events only at a live SOLIDWORKS Wine window observed by CGWindowList.
// Usage: swift cad-native-input.swift <unix pid> click <screen x> <screen y>
//        swift cad-native-input.swift <unix pid> escape
import AppKit
import CoreGraphics
import ApplicationServices
let args = CommandLine.arguments
func fail(_ text: String) -> Never { fputs(text + "\n", stderr); exit(1) }
guard args.count >= 3, let pid = Int32(args[1]) else { fail("Expected CAD PID and action") }
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String:Any]] ?? []
guard let window = windows.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowName as String] as? String ?? "").hasPrefix("SOLIDWORKS Design Professional for Makers") }),
      let bounds = window[kCGWindowBounds as String] as? [String:Double],
      let x = bounds["X"], let y = bounds["Y"], let width = bounds["Width"], let height = bounds["Height"] else { fail("No visible SOLIDWORKS window for that PID") }
let rect = CGRect(x:x,y:y,width:width,height:height)
guard let app = NSRunningApplication(processIdentifier: pid) else { fail("No native CAD process") }
_ = app.activate(options: [.activateAllWindows])
// Wine's unbundled process ignores ordinary activation, but its native AX app
// supports the standard frontmost attribute. Keep the foreground/occlusion checks.
_ = AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
RunLoop.current.run(until: Date().addingTimeInterval(0.5))
guard let source = CGEventSource(stateID: .hidSystemState) else { fail("No native event source") }
Thread.sleep(forTimeInterval: 0.3)
if args[2] == "click" {
    guard args.count == 5, let x = Double(args[3]), let y = Double(args[4]) else { fail("Expected x and y") }
    let point = CGPoint(x:x,y:y)
    guard rect.contains(point) else { fail("Point is outside the observed CAD window") }
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { fail("Cannot create mouse event") }
        event.setIntegerValueField(.mouseEventClickState,value:1)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { fail("CAD is not the foreground app; mouse event cancelled") }
        let underPoint = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String:Any]] ?? []).first { candidate in
            guard (candidate[kCGWindowLayer as String] as? Int) == 0,
                  let b = candidate[kCGWindowBounds as String] as? [String:Double],
                  let x=b["X"],let y=b["Y"],let w=b["Width"],let h=b["Height"] else { return false }
            return CGRect(x:x,y:y,width:w,height:h).contains(point)
        }
        guard (underPoint?[kCGWindowOwnerPID as String] as? Int32) == pid else { fail("Another app covers the click point; mouse event cancelled") }
        event.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.15)
    }
} else if args[2] == "type-number" {
    guard args.count==4, !args[3].isEmpty, args[3].allSatisfy({"0123456789.".contains($0)}) else { fail("Only numeric CAD input is supported") }
    let keys:[Character:CGKeyCode] = ["1":18,"2":19,"3":20,"4":21,"5":23,"6":22,"7":26,"8":28,"9":25,"0":29,".":47]
    // Wine maps native key codes; its Cocoa input path ignores injected Unicode text.
    for char in args[3] { for down in [true,false] {
        guard let event=CGEvent(keyboardEventSource:source,virtualKey:keys[char]!,keyDown:down) else { fail("Cannot create numeric key event") }
        event.flags=[]
        event.postToPid(pid)
        Thread.sleep(forTimeInterval:0.12)
    } }
} else if args[2] == "select-all" {
    for down in [true,false] {
        guard let event=CGEvent(keyboardEventSource:source,virtualKey:0,keyDown:down) else { fail("Cannot create selection key event") }
        event.flags=[.maskControl]
        event.postToPid(pid)
        Thread.sleep(forTimeInterval:0.15)
    }
} else if ["escape","tab","enter"].contains(args[2]) {
    let key:CGKeyCode=args[2]=="escape" ? 53 : (args[2]=="tab" ? 48 : 36)
    for down in [true,false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { fail("Cannot create keyboard event") }
        event.postToPid(pid)
        Thread.sleep(forTimeInterval: 0.15)
    }
} else { fail("Unknown action") }
print("Native event sent to observed CAD PID",pid)
