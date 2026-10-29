import CoreGraphics
import Foundation

/// The one private call this app relies on. `CGSConfigureDisplayEnabled` is the
/// SkyLight routine behind the "disable display" option that tools like
/// displayplacer use. It is looked up at runtime so the app still builds and
/// runs (with mirroring only) if Apple ever removes it.
enum PrivateAPI {
    typealias ConfigureDisplayEnabled = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

    static let configureDisplayEnabled: ConfigureDisplayEnabled? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let symbol = dlsym(handle, "CGSConfigureDisplayEnabled") else { return nil }
        return unsafeBitCast(symbol, to: ConfigureDisplayEnabled.self)
    }()

    static var canDisableDisplays: Bool { configureDisplayEnabled != nil }
}
