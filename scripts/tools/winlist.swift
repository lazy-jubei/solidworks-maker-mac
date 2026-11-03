// Lists on-screen Wine windows as: id pid x y w h title
import CoreGraphics
let l = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String:Any]]
for w in l where (w["kCGWindowOwnerName"] as? String ?? "") == "wine" {
  let b = w["kCGWindowBounds"] as! [String:Any]
  print(w["kCGWindowNumber"]!, w["kCGWindowOwnerPID"]!, b["X"]!, b["Y"]!, b["Width"]!, b["Height"]!, w["kCGWindowName"] ?? "-")
}
