import CoreGraphics

/// The camera housing at the top of a notched screen, in screen points.
public enum Notch {
    /// The gap between the two menu bar areas beside the camera, as AppKit
    /// reports them (`NSScreen.auxiliaryTopLeftArea` and
    /// `auxiliaryTopRightArea`), with the height of the top safe area inset.
    /// Nil when the screen has no notch.
    public static func rect(frame: CGRect, left: CGRect?, right: CGRect?, top: CGFloat) -> CGRect? {
        guard let left, let right, top > 0, right.minX > left.maxX else { return nil }
        return CGRect(x: left.maxX, y: frame.maxY - top, width: right.minX - left.maxX, height: top)
    }
}
