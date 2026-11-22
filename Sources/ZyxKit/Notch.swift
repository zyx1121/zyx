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

extension Notch {
    /// The notch grown by `grow`, still centered on the camera and flush
    /// with the top of the screen.
    public static func grown(_ notch: CGRect, by grow: CGSize) -> CGRect {
        CGRect(x: notch.minX - grow.width / 2, y: notch.minY - grow.height,
               width: notch.width + grow.width, height: notch.height + grow.height)
    }

    /// Whether the cursor is on the island. It enters on the notch and leaves
    /// only past the grown shape, so the edge does not flicker in and out.
    public static func hovers(_ point: CGPoint, notch: CGRect, grown: CGRect, hovering: Bool) -> Bool {
        let area = hovering ? grown : notch
        // The cursor stops on the top edge of the screen: count that row.
        return point.x >= area.minX && point.x <= area.maxX && point.y >= area.minY && point.y <= area.maxY
    }
}
