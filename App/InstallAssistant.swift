import SwiftUI
import AppKit

/// First-launch help: offers to move the app into Applications when it's run from the disk image,
/// Downloads or anywhere else, and shows a one-time "installed" welcome once it runs from Applications.
@MainActor
final class InstallAssistant: ObservableObject {
    enum Step: Identifiable { case move, welcome; var id: Self { self } }

    @Published var step: Step?
    @Published var moving = false
    @Published var moveError: String?

    /// Where the app should live. OPENMOUNT_INSTALL_DIR overrides it for testing.
    let installDir: URL = {
        if let o = ProcessInfo.processInfo.environment["OPENMOUNT_INSTALL_DIR"] { return URL(fileURLWithPath: o) }
        return URL(fileURLWithPath: "/Applications")
    }()

    var bundleURL: URL { Bundle.main.bundleURL }
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    /// True when running from an Applications folder (system-wide or the user's own).
    var isInstalled: Bool {
        let parent = bundleURL.deletingLastPathComponent().standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return parent == installDir.standardizedFileURL.path || parent == "/Applications" || parent == home
    }

    /// Where the user probably launched it from, in plain words.
    var locationDescription: String {
        let p = bundleURL.path
        if p.hasPrefix("/Volumes/") { return "the disk image" }
        if p.contains("/AppTranslocation/") { return "a temporary location macOS uses for downloaded apps" }
        if p.contains("/Downloads/") { return "your Downloads folder" }
        return bundleURL.deletingLastPathComponent().lastPathComponent
    }

    func evaluate() {
        // Development builds run from .build or dist: don't nag developers.
        let p = bundleURL.path
        let devBuild = bundleURL.pathExtension != "app" || p.contains("/.build/") || (p.contains("/dist/") && ProcessInfo.processInfo.environment["OPENMOUNT_INSTALL_DIR"] == nil)
        if !isInstalled && !devBuild {
            step = .move
        } else if isInstalled && !UserDefaults.standard.bool(forKey: "install.welcomed") {
            step = .welcome
        }
    }

    func finishWelcome() {
        UserDefaults.standard.set(true, forKey: "install.welcomed")
        step = nil
    }

    func skipMove() { step = nil }

    /// Copies this app into Applications, launches the copy and quits this one.
    func moveToApplications() {
        moving = true
        moveError = nil
        let fm = FileManager.default
        let target = installDir.appendingPathComponent(bundleURL.lastPathComponent)
        Task.detached(priority: .userInitiated) { [bundleURL = bundleURL] in
            do {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: target.path) {
                    // An older version: move it to the Bin (recoverable) rather than deleting it.
                    try fm.trashItem(at: target, resultingItemURL: nil)
                }
                try fm.copyItem(at: bundleURL, to: target)
                // The user already allowed this app to run, so the copy shouldn't be held up by
                // the "downloaded from the internet" check a second time.
                removexattr(target.path, "com.apple.quarantine", XATTR_NOFOLLOW)
                await MainActor.run {
                    let cfg = NSWorkspace.OpenConfiguration()
                    cfg.createsNewApplicationInstance = true
                    cfg.environment = ProcessInfo.processInfo.environment
                    NSWorkspace.shared.openApplication(at: target, configuration: cfg) { _, error in
                        DispatchQueue.main.async {
                            if let error {
                                self.moving = false
                                self.moveError = "Copied to Applications, but couldn't open it: \(error.localizedDescription)"
                            } else {
                                // AppKit ignores terminate while a sheet is up: close it first.
                                self.step = nil
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.moving = false
                    self.moveError = "Couldn't copy OpenMount into Applications (\(error.localizedDescription)). You can drag it there yourself in Finder."
                }
            }
        }
    }
}

struct MoveToApplicationsView: View {
    @ObservedObject var assistant: InstallAssistant

    var body: some View {
        VStack(spacing: 16) {
            AppIconImage().frame(width: 88, height: 88)
            Text("Move OpenMount to Applications?").font(.title2.weight(.semibold))
            Text("OpenMount is running from \(assistant.locationDescription). Moving it to your Applications folder keeps it working properly and makes it easy to find in Launchpad and Spotlight.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let e = assistant.moveError {
                Text(e).font(.callout).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                Button("Not now") { assistant.skipMove() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    assistant.moveToApplications()
                } label: {
                    if assistant.moving { ProgressView().controlSize(.small).padding(.horizontal, 30) }
                    else { Text("Move to Applications") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(assistant.moving)
            }
            Text("If you opened it from the disk image, you can eject the disk image afterwards.")
                .font(.footnote).foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 440)
    }
}

struct WelcomeView: View {
    @ObservedObject var assistant: InstallAssistant
    @EnvironmentObject var device: DeviceController

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                AppIconImage().frame(width: 88, height: 88)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30)).foregroundStyle(.white, .green)
                    .offset(x: 6, y: 6)
            }
            Text("OpenMount is installed").font(.title2.weight(.semibold))
            Text("You're all set. macOS won't ask about OpenMount again for this version.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                Row(icon: device.isConnected ? "checkmark.circle.fill" : "cable.connector",
                    tint: device.isConnected ? .green : .secondary,
                    text: device.isConnected ? "\(device.deviceName) connected" : "Plug in your Light Mount with its USB cable")
                Row(icon: "sparkles", tint: .orange, text: "Pick an effect and colour under Lighting")
                Row(icon: "command", tint: .orange, text: "Key remapping › turn on the Mac modifier layout")
                Row(icon: "globe", tint: .orange, text: "Optional: a language switch key and on-screen layouts")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
            Button("Get started") { assistant.finishWelcome() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 420)
    }

    struct Row: View {
        let icon: String; let tint: Color; let text: String
        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(tint).frame(width: 20)
                Text(text)
            }
        }
    }
}

struct AppIconImage: View {
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage ?? NSImage())
            .resizable().aspectRatio(contentMode: .fit)
    }
}
