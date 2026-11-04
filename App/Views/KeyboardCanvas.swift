import SwiftUI
import OpenMountKit

/// Draws the keyboard and lets the user select keys (click, ⌘-click / shift-click to add, drag to box-select).
struct KeyboardCanvas: View {
    let layout: KeyboardLayout
    @Binding var selection: Set<KeyID>
    var fill: (KeyID) -> Color = { _ in Color(nsColor: .controlBackgroundColor) }
    var badge: (KeyID) -> String? = { _ in nil }
    var lightBar: [Color]? = nil
    /// Optional second-language legend drawn large in the centre of the key.
    var legend: (KeyID) -> LanguageLayout.Legend? = { _ in nil }
    var showShift = false

    @State private var dragStart: CGPoint?
    @State private var dragRect: CGRect?

    var body: some View {
        GeometryReader { geo in
            let barH: Double = lightBar == nil ? 0 : 0.35
            let unit = min(geo.size.width / layout.width, geo.size.height / (layout.height + barH))
            let yOff = barH * unit
            ZStack(alignment: .topLeading) {
                if let bar = lightBar {
                    HStack(spacing: 1) {
                        ForEach(bar.indices, id: \.self) { i in Rectangle().fill(bar[i]) }
                    }
                    .frame(width: layout.width * unit - 4, height: unit * 0.18)
                    .clipShape(Capsule())
                    .offset(x: 2, y: unit * 0.05)
                }
                ForEach(layout.keys) { key in
                    let rect = CGRect(x: key.x * unit + 2, y: key.y * unit + 2 + yOff,
                                      width: key.width * unit - 4, height: key.height * unit - 4)
                    Button { toggle(key.id) } label: {
                        KeyCapView(key: key, selected: selection.contains(key.id), fill: fill(key.id), badge: badge(key.id), unit: unit,
                                   legend: legend(key.id), showShift: showShift)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(legend(key.id).map { "\(key.id.rawValue), \($0.base)" } ?? key.id.rawValue)
                    .accessibilityValue(badge(key.id) ?? "")
                    .accessibilityAddTraits(selection.contains(key.id) ? .isSelected : [])
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                }
                if let r = dragRect {
                    Rectangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .background(Color.accentColor.opacity(0.08))
                        .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 12)
                .onChanged { v in
                    dragRect = CGRect(x: min(v.startLocation.x, v.location.x), y: min(v.startLocation.y, v.location.y),
                                      width: abs(v.location.x - v.startLocation.x), height: abs(v.location.y - v.startLocation.y))
                }
                .onEnded { _ in
                    if let r = dragRect {
                        let hit = layout.keys.filter {
                            r.intersects(CGRect(x: $0.x * unit, y: $0.y * unit + yOff, width: $0.width * unit, height: $0.height * unit))
                        }.map(\.id)
                        if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
                            selection.formUnion(hit)
                        } else { selection = Set(hit) }
                    }
                    dragRect = nil
                })
        }
        .aspectRatio(layout.width / (layout.height + (lightBar == nil ? 0 : 0.35)), contentMode: .fit)
    }

    private func toggle(_ id: KeyID) {
        let mods = NSEvent.modifierFlags
        if mods.contains(.command) || mods.contains(.shift) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = selection == [id] ? [] : [id]
        }
    }
}

struct KeyCapView: View {
    let key: KeyCap
    let selected: Bool
    let fill: Color
    let badge: String?
    let unit: Double
    var legend: LanguageLayout.Legend? = nil
    var showShift = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: key.isRound ? unit : unit * 0.12, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(fill)
            shape.strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.18), lineWidth: selected ? 2.5 : 1)
            let ink = fill.isLight ? Color.black : Color.white
            Text(key.label)
                .font(.system(size: max(8, unit * (legend == nil ? 0.22 : 0.17)), weight: .medium))
                .lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(ink.opacity(legend == nil ? 0.9 : 0.45))
                .padding(unit * 0.08)
            if let legend {
                let main = showShift ? (legend.shift ?? legend.base) : legend.base
                Text(main)
                    .font(.system(size: unit * 0.42, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .foregroundStyle(ink.opacity(0.95))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: unit * 0.04)
                if let shift = legend.shift, !showShift {
                    Text(shift)
                        .font(.system(size: unit * 0.2, weight: .medium))
                        .foregroundStyle(Color.orange.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(unit * 0.07)
                }
            }
            if let badge {
                Text(badge)
                    .font(.system(size: max(7, unit * 0.17), weight: .semibold))
                    .padding(.horizontal, 3).background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(2)
            }
        }
        .help(key.id.rawValue)
    }
}

extension Color {
    var isLight: Bool {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return true }
        return (0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent) > 0.6
    }
}
