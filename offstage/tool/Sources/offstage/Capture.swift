import Foundation
import AppKit
import ScreenCaptureKit

/// Photographs one app on the virtual display through ScreenCaptureKit.
/// Display-level capture filtered to the app means popovers, menus, sheets
/// and secondary windows all land in the same frame; other sessions sharing
/// the display are excluded.
struct Capture {
    struct Result {
        let image: CGImage
        let frame: CGRect      // global points that the image covers
        let scale: Int
        let windows: [JSON]
    }

    static func content() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    }

    /// Windows of `pid` currently composited on `display`.
    static func windows(of pid: pid_t, on display: CGRect, content: SCShareableContent) -> [SCWindow] {
        content.windows.filter {
            $0.owningApplication?.processID == pid && $0.isOnScreen
                && $0.frame.width >= 2 && $0.frame.height >= 2
                && $0.frame.intersects(display)
        }
    }

    static func windowJSON(_ w: SCWindow) -> JSON {
        ["id": Int(w.windowID), "title": w.title ?? "", "frame": rectJSON(w.frame),
         "layer": w.windowLayer, "onScreen": w.isOnScreen]
    }

    /// Capture `pid` on the virtual display, cropped to `region` (global
    /// points) or to the union of its windows when nil.
    static func shoot(pid: pid_t, displayID: CGDirectDisplayID, displayBounds: CGRect,
                      region: CGRect?, scale: Int, windowID: CGWindowID? = nil) async throws -> Result {
        let content = try await content()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw fail("virtual display \(displayID) is not in the shareable content")
        }
        guard let app = content.applications.first(where: { $0.processID == pid }) else {
            throw fail("pid \(pid) has no shareable windows yet")
        }
        let wins = windows(of: pid, on: displayBounds, content: content)
        let filter: SCContentFilter
        var crop: CGRect
        if let windowID, let w = wins.first(where: { $0.windowID == windowID }) {
            filter = SCContentFilter(desktopIndependentWindow: w)
            crop = w.frame
        } else {
            filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
            if let region {
                crop = region
            } else {
                let real = wins.filter { $0.windowLayer == 0 }
                let union = (real.isEmpty ? wins : real).reduce(CGRect.null) { $0.union($1.frame) }
                guard !union.isNull else { throw fail("no on-screen windows for pid \(pid)") }
                crop = union.insetBy(dx: -6, dy: -6)
            }
            crop = crop.intersection(displayBounds)
            guard !crop.isEmpty else { throw fail("capture region is outside the virtual display") }
        }
        crop = crop.integral

        let conf = SCStreamConfiguration()
        conf.showsCursor = false
        conf.captureResolution = .best
        conf.scalesToFit = false
        conf.ignoreShadowsDisplay = true
        conf.ignoreShadowsSingleWindow = true
        conf.ignoreGlobalClipDisplay = true
        conf.ignoreGlobalClipSingleWindow = true
        conf.width = Int(crop.width) * scale
        conf.height = Int(crop.height) * scale
        if windowID == nil {
            // sourceRect is display-relative.
            conf.sourceRect = CGRect(x: crop.minX - displayBounds.minX, y: crop.minY - displayBounds.minY,
                                     width: crop.width, height: crop.height)
        }
        let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: conf)
        return Result(image: img, frame: crop, scale: scale, windows: wins.map(windowJSON))
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw fail("PNG encode failed") }
        try data.write(to: url)
    }

    static func downscale(_ image: CGImage, by factor: Int) -> CGImage? {
        guard factor > 1 else { return image }
        let w = image.width / factor, h = image.height / factor
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}
