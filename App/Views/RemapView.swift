import SwiftUI
import OpenMountKit

enum ActionKind: String, CaseIterable, Identifiable {
    case key = "Key", media = "Media", mouse = "Mouse", lighting = "Lighting", macro = "Macro", special = "Special", disabled = "Disabled"
    var id: String { rawValue }
}

struct RemapView: View {
    @EnvironmentObject var device: DeviceController
    @State private var layer: BindingLayer = .base
    @State private var selection: Set<KeyID> = []

    var selected: KeyID? { selection.count == 1 ? selection.first : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("Layer", selection: $layer) {
                    ForEach(BindingLayer.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 260).labelsHidden()
                Spacer()
                Toggle("Mac modifier layout", isOn: Binding(get: { device.macModifiersEnabled }, set: { device.setMacModifiers($0) }))
                    .toggleStyle(.switch)
                    .help("Swaps Win and Alt so the keys next to the space bar are ⌘ Command, then ⌥ Option, like on a Mac keyboard.")
                Button("Reset all keys…") { confirmReset = true }
            }
            HStack(spacing: 10) {
                Image(systemName: "globe").foregroundStyle(.secondary)
                Text("Language switch key")
                Picker("Language switch key", selection: Binding(get: { device.languageKey }, set: { device.setLanguageKey($0) })) {
                    ForEach(DeviceController.LanguageKey.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 380)
                Spacer()
            }
            .help("Sends ⌃Space, which macOS uses to switch between input sources such as English and Korean.")
            if device.languageKey == .fn {
                Text("Fn now switches language (⌃Space). The Fn layer (Fn + arrows for lighting, Fn + Pause for game mode) has moved to Right Ctrl.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if device.languageKey != .off {
                Text("Sends ⌃Space. If it doesn't switch, check System Settings › Keyboard › Keyboard Shortcuts › Input Sources.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !device.macModifiersEnabled && !dismissedMacTip {
                HStack {
                    Image(systemName: "command").font(.title3)
                    VStack(alignment: .leading) {
                        Text("Using this keyboard with a Mac?").font(.callout.weight(.semibold))
                        Text("Turn on the Mac modifier layout so the key next to the space bar is ⌘ Command and Win becomes ⌥ Option.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Turn on") { device.setMacModifiers(true) }.buttonStyle(.borderedProminent)
                    Button("Not now") { dismissedMacTip = true }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12)))
            }
            KeyboardCanvas(layout: device.layout, selection: $selection,
                           fill: { k in device.isCustomised(k, layer: layer) ? Color.orange.opacity(0.35) : Color(nsColor: .controlBackgroundColor) },
                           badge: { k in device.isCustomised(k, layer: layer) ? short(device.bindings[layer]?[k]) : nil })
            if let k = selected {
                BindingEditor(key: k, layer: layer).id("\(k.rawValue)-\(layer.rawValue)")
                Spacer()
            } else {
                Text(layer == .fn ? "Pick a key to change what it does while Fn is held." : "Pick a key to change what it does. Orange keys have been remapped.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(20)
        .onChange(of: selection) { if selection.count > 1, let last = selection.first { selection = [last] } }
        .confirmationDialog("Restore every key on both layers to the factory default?", isPresented: $confirmReset) {
            Button("Reset all keys", role: .destructive) { device.resetAllBindings() }
        }
    }

    @State private var confirmReset = false
    @AppStorage("dismissedMacTip") private var dismissedMacTip = false

    func short(_ b: KeyBinding?) -> String? {
        guard let b else { return nil }
        switch b {
        case .key(let m, let u) where m == .leftCtrl && u == 0x2C: return "🌐"
        case .key(let m, let u): return m.symbols + (u == 0 ? "" : HIDUsage.name(u))
        case .media: return "♫"
        case .mouse: return "🖱"
        case .lighting: return "☀︎"
        case .macro(let id): return "M\(id)"
        case .disabled: return "✕"
        case .fnLayer: return "Fn"
        case .raw: return "…"
        }
    }
}

struct BindingEditor: View {
    @EnvironmentObject var device: DeviceController
    let key: KeyID
    let layer: BindingLayer

    @State private var kind: ActionKind = .key
    @State private var usage: UInt8 = 0x04
    @State private var mods: Modifiers = []
    @State private var media: MediaAction = .playPause
    @State private var mouse: MouseButton = .left
    @State private var lightingAction: LightingAction = .nextEffect
    @State private var macroID: UInt16 = 1
    @State private var special: SpecialAction = .language
    enum SpecialAction { case language, fnLayer }
    @State private var capturing = false
    @State private var monitor: Any?

    var current: KeyBinding? { device.bindings[layer]?[key] }

    var body: some View {
        Card(title: "\(key.rawValue)\(layer == .fn ? " (with Fn)" : "")") {
            HStack {
                Text("Now:").foregroundStyle(.secondary)
                Text(device.describe(current)).font(.body.weight(.semibold))
                if let d = device.defaultBindings[layer]?[key], d != current {
                    Text("· default: \(device.describe(d))").foregroundStyle(.secondary)
                }
            }
            Picker("Action", selection: $kind) { ForEach(ActionKind.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented)
            switch kind {
            case .key:
                HStack {
                    Picker("Key", selection: $usage) {
                        Text("Modifiers only").tag(UInt8(0))
                        ForEach(Dictionary(grouping: HIDUsage.all, by: \.group).sorted { $0.key < $1.key }, id: \.key) { g in
                            Section(g.key) { ForEach(g.value) { Text($0.name).tag($0.usage) } }
                        }
                    }
                    .frame(width: 260)
                    Button(capturing ? "Press a key…" : "Capture key") { startCapture() }
                }
                HStack(spacing: 14) {
                    Toggle("⌃ Control", isOn: modBinding(.leftCtrl))
                    Toggle("⌥ Option", isOn: modBinding(.leftAlt))
                    Toggle("⇧ Shift", isOn: modBinding(.leftShift))
                    Toggle("⌘ Command", isOn: modBinding(.leftGui))
                }
                .toggleStyle(.checkbox)
            case .media:
                Picker("Media action", selection: $media) { ForEach(MediaAction.allCases) { Text($0.displayName).tag($0) } }.frame(width: 300)
            case .mouse:
                Picker("Mouse button", selection: $mouse) { ForEach(MouseButton.allCases) { Text($0.displayName).tag($0) } }.frame(width: 300)
            case .lighting:
                Picker("Lighting action", selection: $lightingAction) { ForEach(LightingAction.allCases) { Text($0.displayName).tag($0) } }.frame(width: 300)
            case .macro:
                if device.macros.isEmpty {
                    Text("No macros yet. Create one on the Macros page.").foregroundStyle(.secondary)
                } else {
                    Picker("Macro", selection: $macroID) { ForEach(device.macros) { Text($0.name).tag($0.id) } }.frame(width: 300)
                }
            case .special:
                Picker("Special action", selection: $special) {
                    Text("Switch language (⌃Space)").tag(SpecialAction.language)
                    Text("Fn layer").tag(SpecialAction.fnLayer)
                }
                .frame(width: 300)
            case .disabled:
                Text("The key will do nothing.").foregroundStyle(.secondary)
            }
            HStack {
                Button("Apply") { device.setBinding(binding, for: key, layer: layer) }
                    .buttonStyle(.borderedProminent)
                    .disabled(kind == .macro && device.macros.isEmpty)
                Button("Reset to default") { device.resetBinding(key, layer: layer) }
                if key == .fn && layer == .fn { Text("Fn has no Fn-layer binding.").foregroundStyle(.secondary) }
            }
            .disabled(key == .fn && layer == .fn)
        }
        .onAppear(perform: loadFromCurrent)
        .onChange(of: current) { loadFromCurrent() }
        .onDisappear(perform: stopCapture)
    }

    var binding: KeyBinding {
        switch kind {
        case .key:
            if let bit = HIDUsage.modifierBit(usage) { return .key(modifiers: mods.union(bit), usage: 0) }
            return .key(modifiers: mods, usage: usage)
        case .media: return .media(media)
        case .mouse: return .mouse(mouse)
        case .lighting: return .lighting(lightingAction)
        case .macro: return .macro(macroID)
        case .special: return special == .language ? .languageSwitch : .fnLayer
        case .disabled: return .disabled
        }
    }

    func modBinding(_ m: Modifiers) -> Binding<Bool> {
        Binding(get: { mods.contains(m) }, set: { if $0 { mods.insert(m) } else { mods.remove(m) } })
    }

    func loadFromCurrent() {
        macroID = device.macros.first?.id ?? 1
        switch current {
        case .fnLayer?: kind = .special; special = .fnLayer
        case let b? where b == .languageSwitch: kind = .special; special = .language
        case .key(let m, let u)?: kind = .key; mods = m; usage = u
        case .media(let a)?: kind = .media; media = a
        case .mouse(let b)?: kind = .mouse; mouse = b
        case .lighting(let a)?: kind = .lighting; lightingAction = a
        case .macro(let id)?: kind = .macro; macroID = id
        case .disabled?: kind = .disabled
        default: kind = .key
        }
    }

    func startCapture() {
        stopCapture()
        capturing = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { e in
            if let u = HIDUsage.fromMacKeyCode(e.keyCode) {
                if e.type == .flagsChanged { usage = u } else {
                    usage = u
                    var m: Modifiers = []
                    if e.modifierFlags.contains(.control) { m.insert(.leftCtrl) }
                    if e.modifierFlags.contains(.option) { m.insert(.leftAlt) }
                    if e.modifierFlags.contains(.shift) { m.insert(.leftShift) }
                    if e.modifierFlags.contains(.command) { m.insert(.leftGui) }
                    mods = m
                }
                stopCapture()
            }
            return nil
        }
    }

    func stopCapture() {
        capturing = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
