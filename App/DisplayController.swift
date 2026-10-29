import AppKit
import Combine
import CoreGraphics

struct DisplayInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let isMain: Bool
    let isActive: Bool
    let mirrorOf: CGDirectDisplayID
    let bounds: CGRect

    var isMirrored: Bool { mirrorOf != kCGNullDirectDisplay }
    var pixelSize: String { "\(CGDisplayPixelsWide(id))×\(CGDisplayPixelsHigh(id))" }
}

enum ScreenMode {
    case extended      // two or more active displays
    case mirrored      // secondary displays mirror the main one
    case secondaryOff  // secondary displays were disabled by this app
    case single        // only one display is online and nothing is hidden

    var isOneScreen: Bool { self == .mirrored || self == .secondaryOff }
}

enum OneScreenMethod: String, CaseIterable, Identifiable {
    case mirror
    case turnOff

    var id: String { rawValue }
    var title: String {
        switch self {
        case .mirror: return "Mirror onto the main display"
        case .turnOff: return "Turn the second display off"
        }
    }
}

/// Reads the display layout through Core Graphics and switches between an
/// extended desktop and a single screen. All work happens on the main actor.
@MainActor
final class DisplayController: ObservableObject {
    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var mode: ScreenMode = .single
    @Published private(set) var lastError: String?
    @Published var method: OneScreenMethod {
        didSet {
            guard method != oldValue else { return }
            defaults.set(method.rawValue, forKey: Keys.method)
            // Changing the method while already on one screen re-applies it,
            // so the picker always reflects what is actually happening.
            if mode.isOneScreen {
                useTwoScreens()
                useOneScreen()
            }
        }
    }

    private enum Keys {
        static let method = "oneScreenMethod"
        static let disabledIDs = "disabledDisplayIDs"
        static let names = "displayNames"
    }

    private let defaults = UserDefaults.standard
    private var cachedNames: [String: String]

    /// Displays this app turned off. A disabled display drops out of every
    /// Core Graphics list, so the ID is the only handle left to turn it back on.
    private var disabledIDs: [CGDirectDisplayID] {
        get { (defaults.array(forKey: Keys.disabledIDs) as? [Int] ?? []).map { CGDirectDisplayID($0) } }
        set { defaults.set(newValue.map { Int($0) }, forKey: Keys.disabledIDs) }
    }

    init() {
        method = OneScreenMethod(rawValue: defaults.string(forKey: Keys.method) ?? "") ?? .mirror
        cachedNames = defaults.dictionary(forKey: Keys.names) as? [String: String] ?? [:]
        refresh()
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(DisplayController.reconfigured, userInfo)
        NotificationCenter.default.addObserver(forName: AppDelegate.commandNotification, object: nil, queue: .main) { [weak self] note in
            guard let command = note.userInfo?["command"] as? String else { return }
            Task { @MainActor in self?.handle(command: command) }
        }
    }

    /// Commands arriving from the `onescreen://` URL scheme.
    func handle(command: String) {
        switch command {
        case "one": useOneScreen()
        case "two": useTwoScreens()
        case "toggle": toggle()
        default: lastError = "Unknown command \"\(command)\". Use one, two or toggle."
        }
    }

    private static let reconfigured: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
        guard let userInfo, !flags.contains(.beginConfigurationFlag) else { return }
        let controller = Unmanaged<DisplayController>.fromOpaque(userInfo).takeUnretainedValue()
        Task { @MainActor in
            // Give the window server a moment to settle before reading the new layout.
            try? await Task.sleep(nanoseconds: 300_000_000)
            controller.refresh()
        }
    }

    // MARK: State

    var statusText: String {
        switch mode {
        case .extended: return "Two screens: extended desktop"
        case .mirrored: return "One screen: second display mirrors main"
        case .secondaryOff: return "One screen: second display is off"
        case .single: return "One display connected"
        }
    }

    var canToggle: Bool {
        mode != .single
    }

    func positionLabel(for display: DisplayInfo) -> String {
        if display.isMain { return "Main" }
        if display.isMirrored { return "Mirroring main" }
        guard let main = displays.first(where: { $0.isMain }) else { return "" }
        let dx = display.bounds.midX - main.bounds.midX
        let dy = display.bounds.midY - main.bounds.midY
        if abs(dx) >= abs(dy) { return dx < 0 ? "Left of main" : "Right of main" }
        return dy < 0 ? "Above main" : "Below main"
    }

    func refresh() {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        CGGetOnlineDisplayList(16, &ids, &count)
        let online = Array(ids.prefix(Int(count)))

        let screensByID = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, NSScreen)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.uint32Value, screen)
        })

        displays = online.map { id in
            if let name = screensByID[id]?.localizedName {
                cachedNames[String(id)] = name
            }
            return DisplayInfo(id: id,
                               name: cachedNames[String(id)] ?? "Display \(id)",
                               isMain: CGDisplayIsMain(id) != 0,
                               isActive: CGDisplayIsActive(id) != 0,
                               mirrorOf: CGDisplayMirrorsDisplay(id),
                               bounds: CGDisplayBounds(id))
        }
        .sorted { a, b in a.isMain != b.isMain ? a.isMain : a.bounds.minX < b.bounds.minX }
        defaults.set(cachedNames, forKey: Keys.names)

        // A display that came back on its own (replug, reboot) is no longer "ours".
        let stillHidden = disabledIDs.filter { id in !online.contains(id) }
        if stillHidden != disabledIDs { disabledIDs = stillHidden }

        let activeCount = displays.filter(\.isActive).count
        if displays.contains(where: \.isMirrored) {
            mode = .mirrored
        } else if !stillHidden.isEmpty {
            mode = .secondaryOff
        } else if activeCount >= 2 {
            mode = .extended
        } else {
            mode = .single
        }
    }

    // MARK: Actions

    func toggle() {
        if mode.isOneScreen { useTwoScreens() } else { useOneScreen() }
    }

    func useOneScreen() {
        lastError = nil
        refresh()
        let main = CGMainDisplayID()
        let others = displays.filter { $0.id != main }
        guard !others.isEmpty else {
            lastError = "Only one display is connected."
            return
        }

        switch method {
        case .mirror:
            configure { config in
                for display in others where !display.isMirrored {
                    let error = CGConfigureDisplayMirrorOfDisplay(config, display.id, main)
                    if error != .success { return error }
                }
                return .success
            }

        case .turnOff:
            guard let disable = PrivateAPI.configureDisplayEnabled else {
                lastError = "Turning displays off is not available on this macOS. Use Mirror instead."
                return
            }
            // Leave any mirror set first; disabling a mirrored display is unreliable.
            if displays.contains(where: \.isMirrored) { unmirrorAll() }
            let targets = others.map(\.id)
            if configure({ config in
                for id in targets {
                    let error = disable(config, id, false)
                    if error != .success { return error }
                }
                return .success
            }) {
                disabledIDs = Array(Set(disabledIDs + targets)).sorted()
            }
        }
        refresh()
    }

    func useTwoScreens() {
        lastError = nil
        refresh()
        if displays.contains(where: \.isMirrored) { unmirrorAll() }

        let hidden = disabledIDs
        if !hidden.isEmpty {
            guard let enable = PrivateAPI.configureDisplayEnabled else {
                lastError = "Cannot re-enable the display on this macOS. Use System Settings > Displays."
                return
            }
            // One transaction per display so a stale ID cannot block a valid one.
            for id in hidden { _ = configure { enable($0, id, true) } }
            disabledIDs = []
        }
        refresh()
    }

    /// Recovery for a display this app turned off but whose ID was lost (for
    /// example after a reboot). Tries to enable every plausible ID that is not
    /// online; IDs that do not exist simply fail and are ignored.
    func lookForHiddenDisplays() {
        lastError = nil
        guard let enable = PrivateAPI.configureDisplayEnabled else { return }
        let online = Set(displays.map(\.id))
        for id in CGDirectDisplayID(1)...CGDirectDisplayID(8) where !online.contains(id) {
            var config: CGDisplayConfigRef?
            guard CGBeginDisplayConfiguration(&config) == .success, let config else { continue }
            if enable(config, id, true) == .success {
                CGCompleteDisplayConfiguration(config, .permanently)
            } else {
                CGCancelDisplayConfiguration(config)
            }
        }
        disabledIDs = []
        refresh()
        if mode == .single { lastError = "No hidden displays found." }
    }

    // MARK: Helpers

    private func unmirrorAll() {
        configure { config in
            for display in displays where display.isMirrored {
                let error = CGConfigureDisplayMirrorOfDisplay(config, display.id, kCGNullDirectDisplay)
                if error != .success { return error }
            }
            return .success
        }
    }

    @discardableResult
    private func configure(_ body: (CGDisplayConfigRef) -> CGError) -> Bool {
        var config: CGDisplayConfigRef?
        var error = CGBeginDisplayConfiguration(&config)
        guard error == .success, let config else {
            report("Could not start a display change", error)
            return false
        }
        error = body(config)
        guard error == .success else {
            CGCancelDisplayConfiguration(config)
            report("Display change was rejected", error)
            return false
        }
        error = CGCompleteDisplayConfiguration(config, .permanently)
        guard error == .success else {
            report("Display change failed", error)
            return false
        }
        return true
    }

    private func report(_ message: String, _ error: CGError) {
        lastError = "\(message) (error \(error.rawValue))."
    }
}
