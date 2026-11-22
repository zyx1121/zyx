import AppKit
for s in NSScreen.screens {
  print(s.localizedName, "frame", s.frame, "visible", s.visibleFrame, "scale", s.backingScaleFactor)
  print("  safeAreaInsets", s.safeAreaInsets)
  print("  auxL", s.auxiliaryTopLeftArea as Any, "auxR", s.auxiliaryTopRightArea as Any)
  if let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
    print("  notch x", l.maxX, "...", r.minX, "w", r.minX - l.maxX, "h", s.safeAreaInsets.top)
  }
}
