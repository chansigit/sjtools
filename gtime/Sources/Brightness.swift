import AppKit
import CoreGraphics
import Foundation
import IOKit

// MARK: - Private framework bindings (resolved at runtime via dlsym)

private typealias DSGetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
private typealias DSSetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
private typealias AVServiceCreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
private typealias AVWriteI2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32

private struct PrivateAPI {
    let dsGet: DSGetBrightnessFn?
    let dsSet: DSSetBrightnessFn?
    let avCreate: AVServiceCreateFn?
    let avWrite: AVWriteI2CFn?

    init() {
        let ds = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        dsGet = PrivateAPI.sym(ds, "DisplayServicesGetBrightness")
        dsSet = PrivateAPI.sym(ds, "DisplayServicesSetBrightness")
        let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        avCreate = PrivateAPI.sym(iokit, "IOAVServiceCreateWithService")
        avWrite = PrivateAPI.sym(iokit, "IOAVServiceWriteI2C")
    }

    static func sym<T>(_ handle: UnsafeMutableRawPointer?, _ name: String) -> T? {
        guard let handle = handle, let s = dlsym(handle, name) else { return nil }
        return unsafeBitCast(s, to: T.self)
    }
}

// MARK: - Brightness targets

enum DisplayKind { case builtin, external }

final class BrightnessTarget {
    let id: CGDirectDisplayID
    let name: String
    let kind: DisplayKind
    let avService: CFTypeRef?
    let supported: Bool

    init(id: CGDirectDisplayID, name: String, kind: DisplayKind, avService: CFTypeRef?) {
        self.id = id
        self.name = name
        self.kind = kind
        self.avService = avService
        self.supported = (kind == .builtin) || (avService != nil)
    }
}

// MARK: - Controller

final class BrightnessController {
    private let api = PrivateAPI()
    private let defaults = UserDefaults.standard
    private(set) var targets: [BrightnessTarget] = []

    /// Re-enumerate displays and pair external ones with their DDC AV services (in order).
    func refresh() {
        let displays = listDockDisplays()   // reuse: id, name, bounds, isMain
        let externalServices = collectExternalAVServices()
        var extIndex = 0
        targets = displays.map { d in
            if CGDisplayIsBuiltin(d.id) != 0 {
                return BrightnessTarget(id: d.id, name: d.name, kind: .builtin, avService: nil)
            }
            let svc = extIndex < externalServices.count ? externalServices[extIndex] : nil
            extIndex += 1
            return BrightnessTarget(id: d.id, name: d.name, kind: .external, avService: svc)
        }
    }

    /// Best-effort current brightness (0...100). Built-in reads live; external uses the
    /// remembered value (DDC reads are slow/unreliable), defaulting to 50.
    func currentPercent(_ t: BrightnessTarget) -> Int {
        if t.kind == .builtin, let get = api.dsGet {
            var value: Float = 0
            if get(t.id, &value) == 0 { return clampBrightnessPercent(Int((value * 100).rounded())) }
        }
        if let saved = defaults.object(forKey: prefKey(t)) as? Int {
            return clampBrightnessPercent(saved)
        }
        return 50
    }

    /// Apply a brightness percentage to the display and remember it.
    @discardableResult
    func setPercent(_ t: BrightnessTarget, _ percent: Int) -> Bool {
        let p = clampBrightnessPercent(percent)
        defaults.set(p, forKey: prefKey(t))
        switch t.kind {
        case .builtin:
            guard let set = api.dsSet else { return false }
            return set(t.id, Float(p) / 100.0) == 0
        case .external:
            guard let svc = t.avService, let write = api.avWrite else { return false }
            var payload = ddcSetVCPPayload(vcp: 0x10, value: UInt16(p))
            let rc = payload.withUnsafeMutableBytes { buf -> Int32 in
                write(svc, 0x37, 0x51, buf.baseAddress!, UInt32(buf.count))
            }
            return rc == 0
        }
    }

    private func prefKey(_ t: BrightnessTarget) -> String {
        return "brightness.\(t.name)"
    }

    /// External DCPAVServiceProxy nodes (Location == External), in IORegistry order.
    private func collectExternalAVServices() -> [CFTypeRef] {
        guard let create = api.avCreate else { return [] }
        var result: [CFTypeRef] = []
        var iterator = io_iterator_t()
        let match = IOServiceMatching("DCPAVServiceProxy")
        guard IOServiceGetMatchingServices(kIOMasterPortDefault, match, &iterator) == KERN_SUCCESS else {
            return []
        }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let loc = IORegistryEntryCreateCFProperty(service, "Location" as CFString,
                                                      kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            if loc == "External", let av = create(kCFAllocatorDefault, service)?.takeRetainedValue() {
                result.append(av)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
        return result
    }
}
