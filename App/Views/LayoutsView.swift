import SwiftUI
import AppKit
import Carbon
import OpenMountKit

/// Shared state for the Layouts page and the floating reference window.
@MainActor
final class LayoutReference: ObservableObject {
    static let shared = LayoutReference()

    @Published private(set) var layouts: [LanguageLayout] = []
    @Published private(set) var loadProblems: [String] = []
    @Published var selectedID: String? { didSet { UserDefaults.standard.set(selectedID, forKey: "layouts.selected") } }
    @Published var followInputSource: Bool { didSet { UserDefaults.standard.set(followInputSource, forKey: "layouts.follow"); if followInputSource { syncToInputSource() } } }
    @Published var highlightEverywhere: Bool { didSet { UserDefaults.standard.set(highlightEverywhere, forKey: "layouts.global"); updateMonitors() } }
    @Published private(set) var currentInputSourceName = ""
    @Published private(set) var pressed: Set<KeyID> = []
    @Published private(set) var shiftDown = false

    private var panel: NSPanel?

    var selected: LanguageLayout? { layouts.first { $0.id == selectedID } }

    private init() {
        selectedID = UserDefaults.standard.string(forKey: "layouts.selected")
        followInputSource = UserDefaults.standard.object(forKey: "layouts.follow") as? Bool ?? true
        highlightEverywhere = UserDefaults.standard.bool(forKey: "layouts.global")
        reload()
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.syncToInputSource() }
        }
        syncToInputSource()
        updateMonitors()
    }

    /// Bundled layouts live in Contents/Resources/Layouts; during development they're read from the repo.
    func reload() {
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent("Layouts"),
                          URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Layouts").standardized]
        for case let dir? in candidates where FileManager.default.fileExists(atPath: dir.path) {
            let (l, p) = LayoutLibrary.load(from: dir)
            layouts = l
            loadProblems = p.map(\.description)
            return
        }
    }

    func syncToInputSource() {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
        func prop(_ key: CFString) -> String? {
            guard let p = TISGetInputSourceProperty(src, key) else { return nil }
            return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
        }
        currentInputSourceName = prop(kTISPropertyLocalizedName) ?? ""
        guard followInputSource else { return }
        let ids = [prop(kTISPropertyInputModeID), prop(kTISPropertyInputSourceID)].compactMap { $0 }
        selectedID = layouts.first { l in l.macInputSources.contains { ids.contains($0) } }?.id
    }

    // MARK: Key highlighting

    /// Physical key for each HID usage the keyboard sends, accounting for remaps (e.g. with the Mac
    /// layout the physical Alt key sends ⌘, so a ⌘ press must light the Alt key).
    private var physicalForUsage: [UInt8: KeyID] = [:]

    func updatePhysicalMap(_ base: [KeyID: KeyBinding]) {
        var m: [UInt8: KeyID] = [:]
        for (key, b) in base {
            guard case .key(let mods, let usage) = b else { continue }
            if usage != 0 && mods.isEmpty { m[usage] = key }
            else if usage == 0, mods.rawValue.nonzeroBitCount == 1 {
                m[0xE0 + UInt8(mods.rawValue.trailingZeroBitCount)] = key
            }
        }
        physicalForUsage = m
    }

    private func physicalKey(_ usage: UInt8) -> KeyID? { physicalForUsage[usage] ?? KeyID.fromHIDUsage(usage) }

    /// Device-dependent modifier bits in CGEventFlags, by macOS key code.
    private static let modifierBits: [UInt16: UInt64] = [
        59: 0x01, 62: 0x2000,   // left / right control
        56: 0x02, 60: 0x04,     // left / right shift
        58: 0x20, 61: 0x40,     // left / right option
        55: 0x08, 54: 0x10,     // left / right command
    ]

    fileprivate func handle(type: CGEventType, keyCode: UInt16, flags: UInt64) {
        shiftDown = flags & CGEventFlags.maskShift.rawValue != 0
        // Re-derive every modifier from the flags so nothing can get stuck.
        for (code, bit) in Self.modifierBits {
            guard let u = HIDUsage.fromMacKeyCode(code), let k = physicalKey(u) else { continue }
            if flags & bit != 0 { pressed.insert(k) } else { pressed.remove(k) }
        }
        guard let usage = HIDUsage.fromMacKeyCode(keyCode), let key = physicalKey(usage) else { return }
        switch type {
        case .keyDown: pressed.insert(key)
        case .keyUp: pressed.remove(key)
        case .flagsChanged where keyCode == 57:   // Caps Lock only reports a toggle: flash it
            pressed.insert(key)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { self.pressed.remove(key) }
        default: break
        }
    }

    /// Input Monitoring lets OpenMount see key presses in other apps (listen-only; nothing is recorded).
    var listenAllowed: Bool { CGPreflightListenEventAccess() }

    func requestListenAccess() {
        if !CGRequestListenEventAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
        }
        updateMonitors()
        objectWillChange.send()
    }

    private var localMonitor: Any?
    fileprivate static var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?

    /// Highlighting is wanted when the user opted in, or whenever the floating window is open.
    private var wantsGlobal: Bool { highlightEverywhere || floatingVisible }

    func updateMonitors() {
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] e in
                // Only needed when the tap isn't running (no permission yet).
                if Self.tap == nil {
                    let t: CGEventType = e.type == .keyDown ? .keyDown : e.type == .keyUp ? .keyUp : .flagsChanged
                    self?.handle(type: t, keyCode: e.keyCode, flags: UInt64(e.modifierFlags.rawValue))
                }
                return e
            }
        }
        if wantsGlobal && listenAllowed { startTap() } else if !wantsGlobal { stopTap() }
    }

    private func startTap() {
        guard Self.tap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = LayoutReference.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags.rawValue
            DispatchQueue.main.async { LayoutReference.shared.handle(type: type, keyCode: code, flags: flags) }
            return Unmanaged.passUnretained(event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                        eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: nil) else { return }
        let src = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        Self.tap = t
        tapSource = src
    }

    private func stopTap() {
        if let t = Self.tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        Self.tap = nil; tapSource = nil
        pressed.removeAll()
    }

    // MARK: Floating window

    func toggleFloatingWindow(layout: PhysicalLayout) {
        if let p = panel, p.isVisible { p.close(); updateMonitors(); objectWillChange.send(); return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 860, height: 300),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.title = "OpenMount – Layout reference"
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: FloatingLayoutView(physical: layout).environmentObject(self))
        let kb = KeyboardLayout.lightMount(layout)
        // Keep the keyboard's proportions when the window edge is dragged (header ≈ 52 pt, padding 40 pt).
        p.contentAspectRatio = NSSize(width: kb.width * 40 + 40, height: kb.height * 40 + 52 + 40)
        p.contentMinSize = NSSize(width: 420, height: 170)
        p.setFrameAutosaveName("OpenMount.LayoutReference")
        if !p.setFrameUsingName("OpenMount.LayoutReference") { p.center() }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: p, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateMonitors(); self?.objectWillChange.send() }
        }
        p.orderFrontRegardless()
        panel = p
        updateMonitors()
    }

    /// Grows or shrinks the floating window in steps, keeping its top-left corner in place.
    func resizePanel(by factor: CGFloat) {
        guard let p = panel else { return }
        let content = p.contentRect(forFrameRect: p.frame)
        let ratio = content.height / content.width
        let w = min(max(content.width * factor, 420), (p.screen?.visibleFrame.width ?? 3000) - 40)
        let newContent = NSRect(x: content.minX, y: content.maxY - w * ratio, width: w, height: w * ratio)
        p.setFrame(p.frameRect(forContentRect: newContent), display: true, animate: true)
    }

    var floatingVisible: Bool { panel?.isVisible ?? false }
}

/// Keyboard drawing with the selected language's legends.
struct LayoutKeyboard: View {
    @EnvironmentObject var ref: LayoutReference
    let physical: PhysicalLayout

    var body: some View {
        let layout = KeyboardLayout.lightMount(ref.selected?.physicalLayout ?? physical)
        KeyboardCanvas(layout: layout, selection: .constant([]),
                       fill: { k in ref.pressed.contains(k) ? Color.orange : Color(white: 0.16) },
                       legend: { k in ref.selected?.legend(for: k) },
                       showShift: ref.shiftDown)
            .allowsHitTesting(false)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.9)))
    }
}

struct LayoutsView: View {
    @EnvironmentObject var device: DeviceController
    @ObservedObject var ref = LayoutReference.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Picker("Language", selection: $ref.selectedID) {
                        Text("English (printed legends)").tag(String?.none)
                        ForEach(ref.layouts) { Text($0.name).tag(String?.some($0.id)) }
                    }
                    .frame(width: 320)
                    .disabled(ref.followInputSource)
                    Toggle("Follow macOS input source", isOn: $ref.followInputSource)
                    Spacer()
                    Button {
                        ref.toggleFloatingWindow(layout: device.physicalLayout)
                    } label: { Label("Floating window", systemImage: "macwindow.on.rectangle") }
                    .help("Opens a small always-on-top window you can keep beside whatever you're typing in.")
                }
                if ref.followInputSource {
                    Text("Current input source: \(ref.currentInputSourceName.trimmingCharacters(in: CharacterSet(charactersIn: ".")))." + " Switch languages (for example with your language switch key) and the keyboard below follows.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                LayoutKeyboard(physical: device.physicalLayout).environmentObject(ref)

                HStack(alignment: .top, spacing: 16) {
                    Card(title: "Highlight keys as I type") {
                        Text("Keys light up as you press them. To see this while you type in other apps (for example with the floating window open), macOS needs to let OpenMount notice key presses. It only uses this to light up keys on screen, and never records or stores what you type.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Toggle("Highlight while typing in other apps", isOn: $ref.highlightEverywhere)
                        ListenPermissionRow()
                    }
                    Card(title: "Add your language") {
                        Text("Layouts are community-made. Each one is a small JSON file you can submit with a pull request on GitHub.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Link(destination: URL(string: "https://github.com/fjc1991/OpenMount/blob/main/Layouts/README.md")!) {
                            Label("How to add a layout", systemImage: "plus.bubble")
                        }
                        if let s = ref.selected {
                            Text("\(s.name) by \(s.authors.joined(separator: ", "))").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if !ref.loadProblems.isEmpty {
                    Text("Some layout files couldn't be loaded:\n" + ref.loadProblems.joined(separator: "\n"))
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
            .padding(20)
        }
    }
}

struct FloatingLayoutView: View {
    @EnvironmentObject var ref: LayoutReference
    let physical: PhysicalLayout
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                Text(ref.selected?.name ?? "English").font(.callout.weight(.medium))
                if ref.shiftDown { Text("⇧ Shift").font(.caption).foregroundStyle(.orange) }
                Spacer()
                ControlGroup {
                    Button { ref.resizePanel(by: 1 / 1.2) } label: { Image(systemName: "minus.magnifyingglass") }
                        .help("Smaller")
                    Button { ref.resizePanel(by: 1.2) } label: { Image(systemName: "plus.magnifyingglass") }
                        .help("Larger")
                }
                .controlSize(.small)
                .fixedSize()
            }
            .padding(.horizontal, 6)
            if !ref.listenAllowed { ListenPermissionRow(compact: true).padding(.horizontal, 6) }
            LayoutKeyboard(physical: physical)
        }
        .padding(10)
        .frame(minWidth: 400, minHeight: 150)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Explains and requests the Input Monitoring permission used to light up keys typed in other apps.
struct ListenPermissionRow: View {
    @ObservedObject var ref = LayoutReference.shared
    var compact = false
    @State private var tick = 0
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if ref.listenAllowed {
                if !compact {
                    Label("Allowed in Input Monitoring", systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(.green)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "keyboard.badge.eye").foregroundStyle(.orange)
                    Text(compact ? "Allow OpenMount to light up keys as you type in other apps."
                                 : "Not allowed yet. Click Allow, then turn on OpenMount under Privacy & Security › Input Monitoring.")
                        .font(.footnote).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Allow…") { ref.requestListenAccess() }.controlSize(.small)
                }
            }
        }
        .id(tick)
        .onReceive(timer) { _ in
            // Permission changes in System Settings don't notify apps; re-check while visible.
            if !ref.listenAllowed { tick += 1 } else if tick >= 0 { tick = -1; ref.updateMonitors() }
        }
    }
}
