import SwiftUI
import AppKit

/// Optional Ko-fi tip. Shown permanently (and quietly) in About and the Help menu.
/// The in-window nudge appears at most once, and only after someone has clearly got value from the app:
/// used on at least 3 separate days and at least 5 successful changes, shown right after a change succeeds.
@MainActor
final class TipJar: ObservableObject {
    static let url = URL(string: "https://ko-fi.com/fjc91")!
    static let minDays = 3
    static let minChanges = 5

    @Published private(set) var showNudge = false

    private let defaults = UserDefaults.standard
    private var finished: Bool {
        get { defaults.bool(forKey: "tip.finished") }
        set { defaults.set(newValue, forKey: "tip.finished") }
    }
    private var changes: Int {
        get { defaults.integer(forKey: "tip.changes") }
        set { defaults.set(newValue, forKey: "tip.changes") }
    }
    private var days: Set<String> {
        get { Set(defaults.stringArray(forKey: "tip.days") ?? []) }
        set { defaults.set(Array(newValue), forKey: "tip.days") }
    }

    init() {
        let day = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        days.insert(day)
    }

    /// Call after a change was successfully written to the keyboard.
    func recordSuccess() {
        guard !finished else { return }
        changes += 1
        if changes >= Self.minChanges && days.count >= Self.minDays {
            // Let the success toast show first, then offer the card.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.spring(duration: 0.4)) { self.showNudge = true }
            }
        }
    }

    func open() {
        NSWorkspace.shared.open(Self.url)
        dismiss()
    }

    func dismiss() {
        finished = true
        withAnimation { showNudge = false }
    }
}

struct TipNudge: View {
    @EnvironmentObject var tips: TipJar

    var body: some View {
        if tips.showNudge {
            HStack(spacing: 12) {
                Image(systemName: "cup.and.saucer.fill").font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enjoying OpenMount?").font(.callout.weight(.semibold))
                    Text("It's free and made in spare time. If it's useful to you, a tip on Ko-fi helps keep it going.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Tip on Ko-fi") { tips.open() }.buttonStyle(.borderedProminent)
                Button("No thanks") { tips.dismiss() }
            }
            .padding(14)
            .frame(maxWidth: 620)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain)
        }
    }
}

struct SupportLink: View {
    var body: some View {
        Link(destination: TipJar.url) {
            Label("Support OpenMount on Ko-fi", systemImage: "cup.and.saucer")
        }
    }
}
