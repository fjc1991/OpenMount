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

    private var localMonitor: Any?
    private var globalMonitor: Any?
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

    private func handle(_ e: NSEvent) {
        shiftDown = e.modifierFlags.contains(.shift)
        guard let usage = HIDUsage.fromMacKeyCode(e.keyCode), let key = KeyID.fromHIDUsage(usage) else { return }
        switch e.type {
        case .keyDown: pressed.insert(key)
        case .keyUp: pressed.remove(key)
        case .flagsChanged:
            if HIDUsage.modifierBit(usage) != nil {
                if pressed.contains(key) { pressed.remove(key) } else { pressed.insert(key) }
            }
        default: break
        }
    }

    var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    func updateMonitors() {
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] e in
                self?.handle(e); return e
            }
        }
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        guard highlightEverywhere else { return }
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] e in
            Task { @MainActor in self?.handle(e) }
        }
    }

    // MARK: Floating window

    func toggleFloatingWindow(layout: PhysicalLayout) {
        if let p = panel, p.isVisible { p.close(); return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 860, height: 300),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.title = "OpenMount – Layout reference"
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: FloatingLayoutView(physical: layout).environmentObject(self))
        p.setFrameAutosaveName("OpenMount.LayoutReference")
        if !p.setFrameUsingName("OpenMount.LayoutReference") { p.center() }
        p.orderFrontRegardless()
        panel = p
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
                       fill: { k in ref.pressed.contains(k) ? Color.accentColor : Color(white: 0.16) },
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
                        Text("Keys light up while you type in this window. To see them while you type in other apps too, OpenMount needs Accessibility permission. It only uses this to light up the keys on screen and never records or stores what you type.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Toggle("Also highlight while typing in other apps", isOn: $ref.highlightEverywhere)
                        if ref.highlightEverywhere && !ref.accessibilityTrusted {
                            Text("Allow OpenMount in System Settings › Privacy & Security › Accessibility, then turn this off and on again.")
                                .font(.footnote).foregroundStyle(.orange)
                        }
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
            HStack {
                Image(systemName: "globe")
                Text(ref.selected?.name ?? "English").font(.callout.weight(.medium))
                Spacer()
                if ref.shiftDown { Text("⇧ Shift").font(.caption).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 6)
            LayoutKeyboard(physical: physical)
        }
        .padding(10)
        .frame(minWidth: 520, minHeight: 200)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
