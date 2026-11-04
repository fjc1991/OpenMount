import SwiftUI
import AppKit
import CryptoKit
import OpenMountKit

/// Checks GitHub Releases for a newer OpenMount and installs it in place.
///
/// Safety: the DMG is downloaded over HTTPS from github.com, its SHA-256 must match the digest GitHub
/// publishes for the release asset, and the app inside must have OpenMount's bundle id and the expected
/// version. Otherwise nothing is installed and the release page is offered instead.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "fjc1991/OpenMount"
    static let checkInterval: TimeInterval = 6 * 3600

    struct Release: Equatable {
        var version: String
        var notes: String
        var pageURL: URL
        var dmgURL: URL?
        var sha256: String?
    }

    enum State: Equatable {
        case idle, checking, upToDate, available(Release), downloading(Double), installing, failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published var showSheet = false
    /// The release being installed (kept so the sheet still shows it while downloading).
    @Published private(set) var inProgress: Release?
    @Published var automatic: Bool { didSet { UserDefaults.standard.set(automatic, forKey: "update.automatic") } }

    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    var available: Release? { if case .available(let r) = state { return r }; return nil }
    var shown: Release? { available ?? inProgress }

    private init() {
        automatic = UserDefaults.standard.object(forKey: "update.automatic") as? Bool ?? true
    }

    // MARK: Checking

    func checkOnLaunch() {
        guard automatic else { return }
        let last = UserDefaults.standard.double(forKey: "update.lastCheck")
        guard Date().timeIntervalSince1970 - last > Self.checkInterval else { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        if case .downloading = state { return }
        state = .checking
        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("OpenMount/\(current)", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 15
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let rel = try Self.parse(data)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "update.lastCheck")
            if Self.isNewer(rel.version, than: current) {
                state = .available(rel)
                if userInitiated { showSheet = true }
            } else {
                state = .upToDate
            }
        } catch {
            state = userInitiated ? .failed("Couldn't check for updates (\(error.localizedDescription)).") : .idle
        }
    }

    /// True when the update badge should show (a newer version the user hasn't skipped).
    var badgeVisible: Bool {
        guard let r = available else { return false }
        return UserDefaults.standard.string(forKey: "update.skipped") != r.version
    }

    func skip() {
        if let r = available { UserDefaults.standard.set(r.version, forKey: "update.skipped") }
        showSheet = false
        objectWillChange.send()
    }

    static func parse(_ data: Data) throws -> Release {
        struct Asset: Decodable { let name: String; let browser_download_url: URL; let digest: String? }
        struct R: Decodable { let tag_name: String; let body: String?; let html_url: URL; let assets: [Asset]; let draft: Bool?; let prerelease: Bool? }
        let r = try JSONDecoder().decode(R.self, from: data)
        let dmg = r.assets.first { $0.name.hasSuffix(".dmg") }
        let sha = dmg?.digest.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)).lowercased() : nil }
        let version = r.tag_name.hasPrefix("v") ? String(r.tag_name.dropFirst()) : r.tag_name
        return Release(version: version, notes: r.body ?? "", pageURL: r.html_url, dmgURL: dmg?.browser_download_url, sha256: sha)
    }

    static func isNewer(_ a: String, than b: String) -> Bool { Versioning.isNewer(a, than: b) }

    // MARK: Installing

    /// The bundle we'd replace; nil when we can't update in place (e.g. running from the disk image).
    var installTarget: URL? {
        let url = Bundle.main.bundleURL
        let p = url.path
        guard url.pathExtension == "app", !p.hasPrefix("/Volumes/"), !p.contains("/AppTranslocation/"),
              FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path) else { return nil }
        return url
    }

    func install() {
        guard let rel = available ?? inProgress else { return }
        guard let dmgURL = rel.dmgURL, let expected = rel.sha256, let target = installTarget else {
            NSWorkspace.shared.open(rel.pageURL); return
        }
        inProgress = rel
        state = .downloading(0)
        Task {
            do {
                let dmg = try await download(dmgURL)
                state = .installing
                let digest = try await Task.detached { () -> String in
                    let data = try Data(contentsOf: dmg, options: .mappedIfSafe)
                    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                }.value
                guard digest == expected else { try? FileManager.default.removeItem(at: dmg); throw UpdateError.checksum }
                let newApp = try await Task.detached { try Self.extractAndStage(dmg: dmg, nextTo: target, expectedVersion: rel.version) }.value
                try await Task.detached { _ = try FileManager.default.replaceItemAt(target, withItemAt: newApp) }.value
                relaunch(target)
            } catch {
                // Keep the release on screen so the user can retry or open the release page.
                state = .failed((error as? UpdateError)?.description ?? "Update failed: \(error.localizedDescription)")
            }
        }
    }

    enum UpdateError: Error, CustomStringConvertible {
        case checksum, mount, notOpenMount, wrongVersion(String)
        var description: String {
            switch self {
            case .checksum: return "The download didn't match GitHub's checksum, so it wasn't installed."
            case .mount: return "Couldn't open the downloaded disk image."
            case .notOpenMount: return "The download didn't contain OpenMount, so it wasn't installed."
            case .wrongVersion(let v): return "The download contained version \(v) instead of the expected one, so it wasn't installed."
            }
        }
    }

    private func download(_ url: URL) async throws -> URL {
        let delegate = DownloadProgress { [weak self] p in Task { @MainActor in self?.state = .downloading(p) } }
        let (tmp, resp) = try await URLSession.shared.download(from: url, delegate: delegate)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMount-update-\(UUID().uuidString).dmg")
        try FileManager.default.moveItem(at: tmp, to: out)
        return out
    }

    private final class DownloadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let onProgress: (Double) -> Void
        private var observation: NSKeyValueObservation?
        init(_ f: @escaping (Double) -> Void) { onProgress = f }
        func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
            observation = task.progress.observe(\.fractionCompleted) { [onProgress] p, _ in onProgress(p.fractionCompleted) }
        }
    }

    /// Mounts the DMG, checks the app inside and copies it next to the current app (same volume, so the
    /// final swap is atomic). Returns the staged copy.
    nonisolated static func extractAndStage(dmg: URL, nextTo target: URL, expectedVersion: String) throws -> URL {
        let mountDir = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMount-mount-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mountDir, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mountDir.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mountDir.path, "-quiet", "-force"]); try? FileManager.default.removeItem(at: dmg) }
        let app = mountDir.appendingPathComponent("OpenMount.app")
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else { throw UpdateError.notOpenMount }
        let v = info["CFBundleShortVersionString"] as? String ?? "?"
        guard v == expectedVersion else { throw UpdateError.wrongVersion(v) }
        let staged = target.deletingLastPathComponent().appendingPathComponent(".OpenMount-update-\(UUID().uuidString).app")
        try FileManager.default.copyItem(at: app, to: staged)
        return staged
    }

    @discardableResult
    nonisolated private static func run(_ tool: String, _ args: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 && args.first == "attach" { throw UpdateError.mount }
        return p.terminationStatus
    }

    private func relaunch(_ app: URL) {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        showSheet = false
        NSWorkspace.shared.openApplication(at: app, configuration: cfg) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
        }
    }
}

// MARK: - UI

struct UpdateBadge: View {
    @ObservedObject var updater = Updater.shared
    var body: some View {
        if updater.badgeVisible, let r = updater.available {
            Button { updater.showSheet = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Update available").font(.callout.weight(.medium))
                        Text("Version \(r.version)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.14)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Update available, version \(r.version)")
        }
    }
}

struct UpdateSheet: View {
    @ObservedObject var updater = Updater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                AppIconImage().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(updater.shown.map { "OpenMount \($0.version) is available" } ?? "Software update").font(.title3.weight(.semibold))
                    Text("You have version \(updater.current).").foregroundStyle(.secondary)
                }
            }
            if let r = updater.shown, !r.notes.isEmpty {
                ScrollView {
                    Text(Self.markdown(r.notes))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 180)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
            }
            switch updater.state {
            case .downloading(let p):
                ProgressView(value: p) { Text("Downloading…") }
            case .installing:
                ProgressView { Text("Checking and installing…") }
            case .failed(let msg):
                Text(msg).foregroundStyle(.orange).font(.callout)
            default:
                EmptyView()
            }
            if updater.installTarget == nil {
                Text("OpenMount isn't running from Applications, so it can't update itself here. Use the release page to download it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            HStack {
                Button("Skip this version") { updater.skip() }
                Spacer()
                if let r = updater.shown { Button("Release page") { NSWorkspace.shared.open(r.pageURL) } }
                Button("Later") { updater.showSheet = false }.keyboardShortcut(.cancelAction)
                Button("Update now") { updater.install() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(updater.shown == nil || updater.installTarget == nil || busy)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    var busy: Bool {
        switch updater.state { case .downloading, .installing: return true; default: return false }
    }

    static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

struct UpdateSettings: View {
    @ObservedObject var updater = Updater.shared
    var body: some View {
        LabeledContent("Version", value: updater.current)
        Toggle("Check for updates automatically", isOn: $updater.automatic)
        HStack {
            Button("Check now") { Task { await updater.check(userInitiated: true) } }
                .disabled(updater.state == .checking)
            switch updater.state {
            case .checking: ProgressView().controlSize(.small)
            case .upToDate: Text("OpenMount is up to date.").foregroundStyle(.secondary)
            case .available(let r): Button("Version \(r.version) is available…") { updater.showSheet = true }
            case .failed(let m): Text(m).foregroundStyle(.orange).font(.footnote)
            default: EmptyView()
            }
        }
        Text("Checks github.com once every few hours. Nothing about you or your keyboard is sent.")
            .font(.footnote).foregroundStyle(.secondary)
    }
}
