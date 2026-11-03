import SwiftUI
import UniformTypeIdentifiers
import OpenMountKit

struct MacrosView: View {
    @EnvironmentObject var device: DeviceController
    @State private var draft: [Macro] = []
    @State private var selectedID: UInt16?
    @State private var loaded = false

    var dirty: Bool { draft != device.macros }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                List(selection: $selectedID) {
                    ForEach(draft) { m in
                        VStack(alignment: .leading) {
                            Text(m.name)
                            Text("\(m.events.count) events · \(m.playback.displayName)").font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(m.id)
                    }
                }
                HStack {
                    Button { add() } label: { Image(systemName: "plus") }
                        .disabled(draft.count >= LightMountDevice.maxMacros)
                        .help("New macro")
                    Button { remove() } label: { Image(systemName: "minus") }
                        .disabled(selectedID == nil)
                        .help("Delete macro")
                    Spacer()
                    Text("\(draft.count)/\(LightMountDevice.maxMacros)").font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(minWidth: 220, maxWidth: 300)

            VStack(alignment: .leading, spacing: 12) {
                if let i = draft.firstIndex(where: { $0.id == selectedID }) {
                    MacroEditor(macro: $draft[i])
                } else {
                    ContentUnavailableView("No macro selected", systemImage: "record.circle",
                                           description: Text("Macros are stored on the keyboard (up to 10, 56 steps each). Assign one to a key on the Key remapping page."))
                }
                Spacer()
                HStack {
                    if dirty { Text("Unsaved changes").foregroundStyle(.orange) }
                    Spacer()
                    Button("Revert") { draft = device.macros }.disabled(!dirty)
                    Button("Save to keyboard") { device.saveMacros(draft) }
                        .buttonStyle(.borderedProminent).disabled(!dirty)
                        .keyboardShortcut("s")
                }
            }
            .padding(20)
            .frame(minWidth: 480)
        }
        .onAppear { if !loaded { draft = device.macros; selectedID = draft.first?.id; loaded = true } }
        .onChange(of: device.macros) { if !dirty { draft = device.macros } }
    }

    func add() {
        let id = (1...UInt16(LightMountDevice.maxMacros)).first { n in !draft.contains { $0.id == n } } ?? 1
        draft.append(Macro(id: id, name: "Macro \(id)"))
        selectedID = id
    }

    func remove() {
        draft.removeAll { $0.id == selectedID }
        selectedID = draft.first?.id
    }
}

struct MacroEditor: View {
    @Binding var macro: Macro
    @State private var recording = false
    @State private var monitor: Any?
    @State private var lastEventTime: Date?
    @State private var lastFlags: NSEvent.ModifierFlags = []
    @State private var typeText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Name", text: $macro.name).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Picker("Playback", selection: $macro.playback) {
                    ForEach(MacroPlayback.allCases) { Text($0.displayName).tag($0) }
                }
                .frame(width: 300)
            }
            HStack {
                Button { recording ? stop() : record() } label: {
                    Label(recording ? "Stop recording" : "Record keystrokes", systemImage: recording ? "stop.circle.fill" : "record.circle")
                }
                .tint(recording ? .red : nil)
                .buttonStyle(.bordered)
                if recording { Text("Type now… keystrokes in this window are recorded").foregroundStyle(.red).font(.callout) }
                Spacer()
                Button("Clear") { macro.events.removeAll() }.disabled(macro.events.isEmpty)
            }
            HStack {
                TextField("…or type text to generate key presses", text: $typeText).textFieldStyle(.roundedBorder)
                Button("Add text") { macro.events += Macro.typing(typeText); typeText = "" }.disabled(typeText.isEmpty)
            }
            Table(macro.events) {
                TableColumn("Step") { e in Text(e.displayName) }
                TableColumn("Delay after (ms)") { e in
                    if let i = macro.events.firstIndex(where: { $0.id == e.id }) {
                        TextField("", value: $macro.events[i].delayMs, format: .number).textFieldStyle(.roundedBorder).frame(width: 90)
                    }
                }
                .width(130)
                TableColumn("") { e in
                    Button { macro.events.removeAll { $0.id == e.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                }
                .width(30)
            }
            .frame(minHeight: 220)
            if macro.events.count > LightMountDevice.maxMacroEvents {
                Text("Only the first \(LightMountDevice.maxMacroEvents) steps fit on the keyboard.").foregroundStyle(.orange).font(.callout)
            }
        }
        .onDisappear(perform: stop)
    }

    func record() {
        recording = true
        lastEventTime = nil
        lastFlags = NSEvent.modifierFlags
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { e in
            if e.type == .keyDown && e.isARepeat { return nil }
            let now = Date()
            if let last = lastEventTime, let i = macro.events.indices.last {
                macro.events[i].delayMs = UInt32(min(60_000, max(1, now.timeIntervalSince(last) * 1000)))
            }
            lastEventTime = now
            switch e.type {
            case .keyDown: if let u = HIDUsage.fromMacKeyCode(e.keyCode) { macro.events.append(MacroEvent(.keyDown(u))) }
            case .keyUp: if let u = HIDUsage.fromMacKeyCode(e.keyCode) { macro.events.append(MacroEvent(.keyUp(u))) }
            case .flagsChanged:
                if let u = HIDUsage.fromMacKeyCode(e.keyCode) {
                    let down = HIDUsage.modifierBit(u).map { bit -> Bool in
                        switch bit {
                        case .leftCtrl, .rightCtrl: return e.modifierFlags.contains(.control)
                        case .leftShift, .rightShift: return e.modifierFlags.contains(.shift)
                        case .leftAlt, .rightAlt: return e.modifierFlags.contains(.option)
                        default: return e.modifierFlags.contains(.command)
                        }
                    } ?? false
                    macro.events.append(MacroEvent(down ? .keyDown(u) : .keyUp(u)))
                }
            default: break
            }
            return nil
        }
    }

    func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

struct DeviceView: View {
    @EnvironmentObject var device: DeviceController
    @State private var exporting = false
    @State private var importing = false

    var body: some View {
        Form {
            Section("Keyboard") {
                LabeledContent("Model", value: device.deviceName)
                LabeledContent("Firmware", value: device.firmware)
                LabeledContent("Serial number", value: device.serial)
                LabeledContent("Polling rate", value: "\(device.pollingRate) Hz")
                Picker("Physical layout", selection: $device.physicalLayout) {
                    Text("ANSI (US)").tag(PhysicalLayout.ansi)
                    Text("ISO (UK / EU)").tag(PhysicalLayout.iso)
                }
            }
            Section("Backup") {
                HStack {
                    Button("Export settings…") { exporting = true }
                    Button("Import settings…") { importing = true }
                    Button("Re-read from keyboard") { device.reload() }
                }
                Text("Saves lighting, per-key colours, key bindings and macros to a JSON file.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("About") {
                Text("OpenMount is an unofficial, open-source configurator. It isn't affiliated with or endorsed by be quiet!. It never updates firmware.")
                    .font(.footnote)
                SupportLink()
                Text("OpenMount is free. If it's useful to you, a tip helps keep it going.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileExporter(isPresented: $exporting, document: BackupDocument(backup: device.makeBackup()),
                      contentType: .json, defaultFilename: "OpenMount backup") { _ in }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard let url = try? result.get() else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            do {
                let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
                device.restore(try dec.decode(DeviceController.Backup.self, from: Data(contentsOf: url)))
            } catch { device.lastError = "Couldn't read that backup: \(error.localizedDescription)" }
        }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var backup: DeviceController.Backup
    init(backup: DeviceController.Backup) { self.backup = backup }
    init(configuration: ReadConfiguration) throws { throw CocoaError(.fileReadUnsupportedScheme) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        return FileWrapper(regularFileWithContents: try enc.encode(backup))
    }
}
