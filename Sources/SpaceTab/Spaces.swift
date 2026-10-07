import CoreGraphics
import Foundation

/// Private SkyLight call that brings one window of an app to the front, and
/// with it the desktop the window is on. Loaded at runtime, so a macOS
/// without it only loses this step.
private typealias SetFrontProcessWithOptions = @convention(c) (
    UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32
) -> CGError
private typealias GetProcessForPIDFunction = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

private let setFrontProcessWithOptions: SetFrontProcessWithOptions? = {
    guard
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
        let symbol = dlsym(handle, "_SLPSSetFrontProcessWithOptions")
    else { return nil }
    return unsafeBitCast(symbol, to: SetFrontProcessWithOptions.self)
}()

private let getProcessForPID: GetProcessForPIDFunction? = {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "GetProcessForPID") else { return nil }
    return unsafeBitCast(symbol, to: GetProcessForPIDFunction.self)
}()

// Private SkyLight functions, exported through CoreGraphics. macOS has no
// public API for desktops (Spaces); every window manager uses these.
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(_ connection: Int32, _ mask: Int32, _ windowIDs: CFArray) -> Unmanaged<CFArray>?

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ connection: Int32) -> Unmanaged<CFArray>?

/// Which desktop (Space) windows are on.
enum Spaces {
    /// Current, other and user spaces.
    private static let allSpacesMask: Int32 = 0x7

    /// The desktop each display is showing now. Nil if macOS didn't answer.
    static func currentSpaceIDs() -> Set<UInt64>? {
        guard
            let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue() as? [[String: Any]]
        else { return nil }
        var ids = Set<UInt64>()
        for display in displays {
            guard let current = display["Current Space"] as? [String: Any] else { continue }
            if let id = (current["id64"] as? NSNumber ?? current["ManagedSpaceID"] as? NSNumber)?.uint64Value {
                ids.insert(id)
            }
        }
        return ids.isEmpty ? nil : ids
    }

    /// Brings the window to the front of its app and switches to the desktop
    /// it is on, the way a click in Mission Control does. Returns false when
    /// the call isn't available.
    @discardableResult
    static func bringToFront(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let setFrontProcessWithOptions, let getProcessForPID else { return false }
        var psn = ProcessSerialNumber()
        guard getProcessForPID(pid, &psn) == noErr else { return false }
        let userGenerated: UInt32 = 0x200
        return setFrontProcessWithOptions(&psn, windowID, userGenerated) == .success
    }

    /// The desktops a window is on. Minimized and hidden windows keep the
    /// desktop they were on.
    static func spaceIDs(of windowID: CGWindowID) -> Set<UInt64> {
        let ids = [NSNumber(value: windowID)] as CFArray
        guard
            let spaces = CGSCopySpacesForWindows(CGSMainConnectionID(), allSpacesMask, ids)?.takeRetainedValue() as? [NSNumber]
        else { return [] }
        return Set(spaces.map(\.uint64Value))
    }
}
