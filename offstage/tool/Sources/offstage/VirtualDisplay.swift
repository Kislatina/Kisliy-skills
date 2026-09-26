import Foundation
import AppKit

/// A headless display created through CoreGraphics' private CGVirtualDisplay
/// API, reached dynamically through the ObjC runtime so the binary still links
/// (and fails with a readable error) if Apple renames something.
///
/// The display exists for as long as this object is alive, so only the daemon
/// holds one. Windows placed on it are composited by the window server (so
/// ScreenCaptureKit can photograph them) but no physical screen shows them.
final class VirtualDisplay {
    let id: CGDirectDisplayID
    let pointSize: CGSize
    let scale: Int
    private let display: NSObject

    // A stable identity matters: macOS remembers the arrangement per
    // (vendor, product, serial). The very first time a given identity shows
    // up it is mirrored onto the main screen for ~100 ms until we configure
    // it; every time after that it comes up already extended, in its corner.
    private static let vendorID: UInt32 = 0x4F53   // "OS"
    private static let productID: UInt32 = 0x0001
    private static let serial: UInt32 = 0x1234

    var bounds: CGRect { CGDisplayBounds(id) }

    init(width: Int, height: Int, scale: Int) throws {
        guard let descC = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
              let settC = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
              let modeC = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type,
              let dispC = NSClassFromString("CGVirtualDisplay") as? NSObject.Type else {
            throw fail("CGVirtualDisplay private API is not available on this macOS")
        }
        let desc = descC.init()
        desc.setValue("Offstage", forKey: "name")
        desc.setValue(Self.vendorID, forKey: "vendorID")
        desc.setValue(Self.productID, forKey: "productID")
        desc.setValue(Self.serial, forKey: "serialNum")
        desc.setValue(UInt32(width * scale), forKey: "maxPixelsWide")
        desc.setValue(UInt32(height * scale), forKey: "maxPixelsHigh")
        desc.setValue(NSValue(size: NSSize(width: 340, height: 210)), forKey: "sizeInMillimeters")
        desc.setValue(NSValue(point: NSPoint(x: 0.64, y: 0.33)), forKey: "redPrimary")
        desc.setValue(NSValue(point: NSPoint(x: 0.30, y: 0.60)), forKey: "greenPrimary")
        desc.setValue(NSValue(point: NSPoint(x: 0.15, y: 0.06)), forKey: "bluePrimary")
        desc.setValue(NSValue(point: NSPoint(x: 0.3127, y: 0.3290)), forKey: "whitePoint")
        desc.setValue(DispatchQueue.main, forKey: "queue")

        let allocSel = NSSelectorFromString("alloc")
        guard let raw = (dispC as AnyObject).perform(allocSel)?.takeUnretainedValue() as? NSObject else {
            throw fail("CGVirtualDisplay alloc failed")
        }
        let initSel = NSSelectorFromString("initWithDescriptor:")
        typealias InitFn = @convention(c) (AnyObject, Selector, AnyObject) -> Unmanaged<AnyObject>?
        guard let initImp = raw.method(for: initSel),
              let d = unsafeBitCast(initImp, to: InitFn.self)(raw, initSel, desc)?.takeUnretainedValue() as? NSObject else {
            throw fail("CGVirtualDisplay initWithDescriptor: failed")
        }
        display = d

        let modeSel = NSSelectorFromString("initWithWidth:height:refreshRate:")
        guard let modeRaw = (modeC as AnyObject).perform(allocSel)?.takeUnretainedValue() as? NSObject,
              let modeImp = modeRaw.method(for: modeSel) else {
            throw fail("CGVirtualDisplayMode alloc failed")
        }
        typealias ModeFn = @convention(c) (AnyObject, Selector, UInt, UInt, Double) -> Unmanaged<AnyObject>?
        guard let mode = unsafeBitCast(modeImp, to: ModeFn.self)(modeRaw, modeSel, UInt(width), UInt(height), 60)?.takeUnretainedValue() else {
            throw fail("CGVirtualDisplayMode init failed")
        }
        let settings = settC.init()
        settings.setValue(UInt32(scale >= 2 ? 1 : 0), forKey: "hiDPI")
        settings.setValue([mode], forKey: "modes")
        let applySel = NSSelectorFromString("applySettings:")
        typealias ApplyFn = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
        guard let applyImp = display.method(for: applySel),
              unsafeBitCast(applyImp, to: ApplyFn.self)(display, applySel, settings) else {
            throw fail("CGVirtualDisplay applySettings: failed")
        }
        guard let did = display.value(forKey: "displayID") as? UInt32, did != 0 else {
            throw fail("virtual display got no displayID")
        }
        id = CGDirectDisplayID(did)
        pointSize = CGSize(width: width, height: height)
        self.scale = scale
        try arrange()
    }

    /// Un-mirror and park the display diagonally off the main screen's
    /// bottom-right corner. Corner-only contact means the cursor has almost no
    /// way to wander into it. `.forSession` still gets remembered by macOS
    /// for the next creation of the same identity.
    private func arrange() throws {
        let main = CGMainDisplayID()
        guard main != id else { throw fail("virtual display became main; refusing") }
        let mb = CGDisplayBounds(main)
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success, let cfg else {
            throw fail("CGBeginDisplayConfiguration failed")
        }
        CGConfigureDisplayMirrorOfDisplay(cfg, id, kCGNullDirectDisplay)
        CGConfigureDisplayOrigin(cfg, id, Int32(mb.maxX), Int32(mb.maxY))
        let r = CGCompleteDisplayConfiguration(cfg, .forSession)
        guard r == .success else { throw fail("display configuration failed: \(r.rawValue)") }
        // Sanity: the user's main display must be untouched.
        if CGMainDisplayID() != main || CGDisplayMirrorsDisplay(main) != kCGNullDirectDisplay {
            throw fail("main display changed during arrangement; aborting")
        }
    }

    var json: JSON {
        ["id": Int(id), "bounds": rectJSON(bounds), "scale": scale,
         "pixels": ["w": CGDisplayCopyDisplayMode(id)?.pixelWidth ?? 0, "h": CGDisplayCopyDisplayMode(id)?.pixelHeight ?? 0]]
    }
}
