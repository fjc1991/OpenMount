import Foundation
import SwiftUI
import OpenMountKit

/// Owns the keyboard connection. All device I/O runs on a private serial queue; state is published on the main actor.
@MainActor
final class DeviceController: ObservableObject {
    enum State: Equatable { case searching, connected, failed(String) }

    @Published private(set) var state: State = .searching
    @Published private(set) var deviceName = "Light Mount"
    @Published private(set) var firmware = ""
    @Published private(set) var serial = ""
    @Published private(set) var pollingRate: UInt16 = 0
    @Published private(set) var busy = false
    @Published var lastError: String?
    @Published var toast: String?

    // Lighting (the keyboard can't report its effect back, so the last applied state is remembered locally)
    @Published var lighting: GlobalLighting { didSet { save(lighting, "lighting") } }
    @Published var perKeyColors: [Int: RGB] { didSet { save(perKeyColors, "perKey") } }
    @Published var perKeyActive: Bool { didSet { UserDefaults.standard.set(perKeyActive, forKey: "perKeyActive") } }
    @Published var physicalLayout: PhysicalLayout { didSet { UserDefaults.standard.set(physicalLayout.rawValue, forKey: "layout") } }

    // Read from the keyboard
    @Published private(set) var bindings: [BindingLayer: [KeyID: KeyBinding]] = [:]
    @Published private(set) var defaultBindings: [BindingLayer: [KeyID: KeyBinding]] = [:]
    @Published var macros: [Macro] = []

    /// Called after a change was successfully written to the keyboard (used by the tip jar).
    var onSuccess: (() -> Void)?

    private let queue = DispatchQueue(label: "OpenMount.device")
    private nonisolated(unsafe) var device: LightMountDevice?
    private var timer: Timer?

    init() {
        lighting = Self.load("lighting") ?? GlobalLighting()
        perKeyColors = Self.load("perKey") ?? [:]
        perKeyActive = UserDefaults.standard.bool(forKey: "perKeyActive")
        physicalLayout = PhysicalLayout(rawValue: UserDefaults.standard.string(forKey: "layout") ?? "") ?? .ansi
        defaultBindings = Self.load("defaultBindings") ?? [:]
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }

    var isConnected: Bool { state == .connected }
    var layout: KeyboardLayout { .lightMount(physicalLayout) }

    // MARK: Connection

    private func tick() {
        if device == nil {
            connect()
        } else {
            queue.async { [weak self] in
                guard let self, let dev = self.device else { return }
                do { try dev.keepAlive() } catch {
                    dev.close(); self.device = nil
                    Task { @MainActor in self.state = .searching }
                }
            }
        }
    }

    private var connecting = false
    private func connect() {
        guard !connecting else { return }
        connecting = true
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let dev = try LightMountDevice.connect()
                self.device = dev
                let rate = (try? dev.pollingRate()) ?? 0
                let b = (try? dev.allBindings(layer: .base)) ?? [:]
                let fn = (try? dev.allBindings(layer: .fn)) ?? [:]
                let m = (try? dev.macros()) ?? []
                let customKeys = Set(((try? dev.customBindings()) ?? []).map { $0.0 })
                Task { @MainActor in
                    self.connecting = false
                    self.deviceName = dev.match.name
                    self.firmware = dev.info.map { String(format: "0x%04X", $0.firmware) } ?? "?"
                    self.serial = dev.serial
                    self.pollingRate = rate
                    self.bindings = [.base: b, .fn: fn]
                    self.macros = m
                    self.rememberDefaults(customKeys: customKeys)
                    self.state = .connected
                    if self.perKeyActive { self.applyPerKey() }
                }
            } catch {
                Task { @MainActor in
                    self.connecting = false
                    if case TransportError.deviceNotFound = error { self.state = .searching }
                    else { self.state = .failed("\(error)") }
                }
            }
        }
    }

    /// Records factory bindings for keys that aren't customised, so the UI can show what "reset" restores.
    private func rememberDefaults(customKeys: Set<UInt16>) {
        for layer in BindingLayer.allCases {
            var d = defaultBindings[layer] ?? [:]
            for (k, b) in bindings[layer] ?? [:] where !customKeys.contains(UInt16(k.bindingIndex) + layer.keyOffset) {
                d[k] = b
            }
            defaultBindings[layer] = d
        }
        save(defaultBindings, "defaultBindings")
    }

    func isCustomised(_ k: KeyID, layer: BindingLayer) -> Bool {
        guard let cur = bindings[layer]?[k], let def = defaultBindings[layer]?[k] else { return false }
        return cur != def
    }

    /// Runs `work` on the device queue and reports errors.
    private func perform(_ label: String, _ work: @escaping (LightMountDevice) throws -> Void, done: (@MainActor () -> Void)? = nil) {
        guard device != nil else { lastError = "The keyboard isn't connected."; return }
        busy = true
        queue.async { [weak self] in
            guard let self, let dev = self.device else { return }
            do {
                try work(dev)
                Task { @MainActor in
                    self.busy = false
                    done?()
                    if label != "Reading keyboard" { self.onSuccess?() }
                }
            } catch {
                Task { @MainActor in self.busy = false; self.lastError = "\(label) failed: \(error)" }
            }
        }
    }

    // MARK: Lighting

    private var pendingLighting: DispatchWorkItem?

    /// Applies the on-board effect (debounced so sliders feel live).
    func applyLighting() {
        perKeyActive = false
        pendingLighting?.cancel()
        let cfg = lighting
        let item = DispatchWorkItem { [weak self] in
            guard let dev = self?.device else { return }
            do { try dev.apply(cfg) } catch { Task { @MainActor in self?.lastError = "Lighting failed: \(error)" } }
        }
        pendingLighting = item
        queue.asyncAfter(deadline: .now() + 0.12, execute: item)
    }

    func applyPerKey() {
        perKeyActive = true
        var colors = [RGB](repeating: .off, count: LightMountLEDs.count)
        for (i, c) in perKeyColors where i < colors.count { colors[i] = c }
        perform("Per-key lighting", { try $0.paint(colors) })
    }

    func lightsOff() {
        perKeyActive = false
        perform("Lights off", { try $0.setLightingMode(.disabled) }) { self.toast = "Lights off" }
    }

    // MARK: Bindings

    func setBinding(_ b: KeyBinding, for key: KeyID, layer: BindingLayer) {
        perform("Remap", { try $0.setBinding(b, for: key, layer: layer) }) {
            self.bindings[layer, default: [:]][key] = b
            self.toast = "\(key.label.isEmpty ? key.rawValue : key.label) → \(self.describe(b))"
        }
    }

    func resetBinding(_ key: KeyID, layer: BindingLayer) {
        var fresh: KeyBinding?
        perform("Reset", { dev in
            try dev.resetBinding(key, layer: layer)
            fresh = try dev.binding(key, layer: layer)
        }) {
            if let f = fresh { self.bindings[layer, default: [:]][key] = f }
            self.toast = "Reset \(key.rawValue)"
        }
    }

    /// Win/Alt swap so the bottom row reads Ctrl, ⌥, ⌘ like a Mac keyboard (both sides, main layer).
    static let macModifierMap: [(KeyID, KeyBinding)] = [
        (.leftGui, .key(modifiers: .leftAlt, usage: 0)),
        (.leftAlt, .key(modifiers: .leftGui, usage: 0)),
        (.rightAlt, .key(modifiers: .rightGui, usage: 0)),
        (.rightGui, .key(modifiers: .rightAlt, usage: 0)),
    ]

    var macModifiersEnabled: Bool {
        Self.macModifierMap.allSatisfy { bindings[.base]?[$0.0] == $0.1 }
    }

    func setMacModifiers(_ on: Bool) {
        let map = Self.macModifierMap
        var fresh: [KeyID: KeyBinding] = [:]
        perform("Mac modifier layout", { dev in
            for (key, b) in map {
                if on { try dev.setBinding(b, for: key, layer: .base) } else { try dev.resetBinding(key, layer: .base) }
                fresh[key] = try dev.binding(key, layer: .base)
            }
        }) {
            for (k, b) in fresh { self.bindings[.base, default: [:]][k] = b }
            self.toast = on ? "Mac layout on: Win is ⌥ Option, Alt is ⌘ Command" : "Windows layout restored"
        }
    }

    func macroName(_ id: UInt16) -> String { macros.first { $0.id == id }?.name ?? "Macro \(id)" }

    func describe(_ b: KeyBinding?) -> String {
        guard let b else { return "–" }
        if case .macro(let id) = b { return "Macro: " + macroName(id) }
        return b.displayName
    }

    func resetAllBindings() {
        var all: [BindingLayer: [KeyID: KeyBinding]] = [:]
        perform("Reset all", { dev in
            for (raw, _) in try dev.customBindings() {
                var w = ByteWriter(); w.u16(raw)
                try dev.client.request(0x11, 0x03, w.bytes)
            }
            all = [.base: try dev.allBindings(layer: .base), .fn: try dev.allBindings(layer: .fn)]
        }) {
            self.bindings = all
            self.toast = "All keys restored to factory defaults"
        }
    }

    // MARK: Macros

    func saveMacros(_ list: [Macro]) {
        perform("Saving macros", { try $0.saveMacros(list) }) {
            self.macros = list
            self.toast = "Macros saved to the keyboard"
        }
    }

    // MARK: Backup

    struct Backup: Codable {
        var created = Date()
        var lighting: GlobalLighting
        var perKey: [Int: RGB]
        var bindings: [String: [String: KeyBinding]]
        var macros: [Macro]
    }

    func makeBackup() -> Backup {
        Backup(lighting: lighting, perKey: perKeyColors,
               bindings: Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, Dictionary(uniqueKeysWithValues: $0.value.map { ($0.key.rawValue, $0.value) })) }),
               macros: macros)
    }

    func restore(_ b: Backup) {
        lighting = b.lighting
        perKeyColors = b.perKey
        let targets = b.bindings
        perform("Restore", { dev in
            try dev.apply(b.lighting)
            try dev.saveMacros(b.macros)
            for (layerName, keys) in targets {
                guard let layer = BindingLayer(rawValue: layerName) else { continue }
                for (keyName, binding) in keys {
                    guard let key = KeyID(rawValue: keyName) else { continue }
                    if (try? dev.binding(key, layer: layer)) != binding { try dev.setBinding(binding, for: key, layer: layer) }
                }
            }
        }) {
            self.macros = b.macros
            self.toast = "Backup restored"
            self.device.map { _ in self.reload() }
        }
    }

    func reload() {
        var b: [BindingLayer: [KeyID: KeyBinding]] = [:]
        var m: [Macro] = []
        perform("Reading keyboard", { dev in
            b = [.base: try dev.allBindings(layer: .base), .fn: try dev.allBindings(layer: .fn)]
            m = try dev.macros()
        }) { self.bindings = b; self.macros = m }
    }

    // MARK: Persistence

    private func save<T: Encodable>(_ v: T, _ key: String) {
        if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) }
    }
    private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
