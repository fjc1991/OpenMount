import SwiftUI
import OpenMountKit

@main
struct OpenMountApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var device = DeviceController()
    @StateObject private var tips = TipJar()

    var body: some Scene {
        WindowGroup("OpenMount", id: "main") {
            ContentView()
                .environmentObject(device)
                .environmentObject(tips)
                .onAppear { device.onSuccess = { [weak tips] in tips?.recordSuccess() } }
                .frame(minWidth: 980, minHeight: 640)
                .tint(.orange)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {
                Button("OpenMount Help") { NSWorkspace.shared.open(URL(string: "https://github.com/fjc1991/OpenMount#readme")!) }
                Button("Report a Problem…") { NSWorkspace.shared.open(URL(string: "https://github.com/fjc1991/OpenMount/issues/new/choose")!) }
                Divider()
                Button("Support OpenMount on Ko-fi…") { NSWorkspace.shared.open(TipJar.url) }
            }
        }

        MenuBarExtra {
            MenuBarView().environmentObject(device)
        } label: {
            Image(systemName: device.isConnected ? "keyboard.fill" : "keyboard")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

enum AppSection: String, CaseIterable, Identifiable {
    case lighting = "Lighting", perKey = "Per-key colours", remap = "Key remapping", macros = "Macros", device = "Device"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .lighting: return "sparkles"
        case .perKey: return "paintbrush.pointed"
        case .remap: return "keyboard"
        case .macros: return "record.circle"
        case .device: return "info.circle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var device: DeviceController
    @State private var section: AppSection? = .lighting

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $section) { s in
                Label(s.rawValue, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) { ConnectionBadge().padding(12) }
        } detail: {
            Group {
                switch device.state {
                case .connected:
                    switch section ?? .lighting {
                    case .lighting: LightingView()
                    case .perKey: PerKeyView()
                    case .remap: RemapView()
                    case .macros: MacrosView()
                    case .device: DeviceView()
                    }
                case .searching:
                    ContentUnavailableView("Looking for your keyboard…", systemImage: "cable.connector",
                                           description: Text("Plug in your be quiet! Light Mount with its USB cable."))
                case .failed(let msg):
                    ContentUnavailableView("Can't talk to the keyboard", systemImage: "exclamationmark.triangle",
                                           description: Text(msg))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) { TipNudge().padding(.horizontal, 20) }
            .navigationTitle(section?.rawValue ?? "OpenMount")
        }
        .overlay(alignment: .bottom) { ToastView() }
        .alert("Something went wrong", isPresented: Binding(get: { device.lastError != nil }, set: { if !$0 { device.lastError = nil } })) {
            Button("OK") { device.lastError = nil }
        } message: { Text(device.lastError ?? "") }
    }
}

struct ConnectionBadge: View {
    @EnvironmentObject var device: DeviceController
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(device.isConnected ? Color.green : Color.secondary).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.isConnected ? device.deviceName : "Not connected").font(.callout.weight(.medium))
                if device.isConnected { Text("Firmware \(device.firmware)").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            if device.busy { ProgressView().controlSize(.small) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
    }
}

struct ToastView: View {
    @EnvironmentObject var device: DeviceController
    var body: some View {
        if let t = device.toast {
            Text(t)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 4, y: 2)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: t) {
                    try? await Task.sleep(for: .seconds(2.2))
                    withAnimation { device.toast = nil }
                }
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var device: DeviceController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ConnectionBadge()
            if device.isConnected {
                Picker("Effect", selection: $device.lighting.effect) {
                    ForEach(LightingEffect.allCases) { Text($0.displayName).tag($0) }
                }
                .onChange(of: device.lighting.effect) { device.applyLighting() }
                HStack {
                    Image(systemName: "sun.min")
                    Slider(value: Binding(get: { Double(device.lighting.brightness) },
                                          set: { device.lighting.brightness = UInt8($0); device.applyLighting() }), in: 0...100)
                    Image(systemName: "sun.max")
                }
                Button("Lights off") { device.lightsOff() }
            }
            Divider()
            Button("Open OpenMount…") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 280)
    }
}
