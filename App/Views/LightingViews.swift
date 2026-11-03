import SwiftUI
import OpenMountKit

extension RGB {
    var color: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
    init(_ c: Color) {
        let n = NSColor(c).usingColorSpace(.sRGB) ?? .black
        self.init(UInt8(max(0, min(255, (n.redComponent * 255).rounded()))),
                  UInt8(max(0, min(255, (n.greenComponent * 255).rounded()))),
                  UInt8(max(0, min(255, (n.blueComponent * 255).rounded()))))
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background.secondary))
    }
}

struct LightingView: View {
    @EnvironmentObject var device: DeviceController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                KeyboardCanvas(layout: device.layout, selection: .constant([]),
                               fill: { _ in previewColor }, lightBar: Array(repeating: previewColor, count: 45))
                    .allowsHitTesting(false)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.85)))

                Card(title: "Effect") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                        ForEach(LightingEffect.allCases) { e in
                            EffectTile(effect: e, selected: device.lighting.effect == e) {
                                device.lighting.effect = e
                                if !e.colorModes.contains(device.lighting.colorMode) || e.colorModes[0] == .gradient { device.lighting.colorMode = e.colorModes[0] }
                                if e.usesDirection && !e.directions.contains(device.lighting.direction) { device.lighting.direction = e.directions[0] }
                                device.applyLighting()
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    Card(title: "Colour") {
                        if device.lighting.effect.colorModes.count > 1 {
                            Picker("Colour mode", selection: $device.lighting.colorMode) {
                                ForEach(device.lighting.effect.colorModes) { Text($0.displayName).tag($0) }
                            }
                            .pickerStyle(.segmented).labelsHidden()
                            .onChange(of: device.lighting.colorMode) { device.applyLighting() }
                        }
                        if device.lighting.colorMode == .gradient && device.lighting.effect.colorModes.contains(.gradient) {
                            LinearGradient(colors: GlobalLighting.rainbow.map(\.color), startPoint: .leading, endPoint: .trailing)
                                .frame(height: 26).clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            ColorRow(label: "Main colour", color: $device.lighting.primary) { device.applyLighting() }
                            if device.lighting.colorMode == .dual && device.lighting.effect.colorModes.contains(.dual) {
                                ColorRow(label: "Second colour", color: $device.lighting.secondary) { device.applyLighting() }
                            }
                            SwatchRow { c in device.lighting.primary = c; device.applyLighting() }
                        }
                    }
                    Card(title: "Adjust") {
                        LabeledSlider(label: "Brightness", value: $device.lighting.brightness) { device.applyLighting() }
                        if device.lighting.effect.usesSpeed {
                            LabeledSlider(label: "Speed", value: $device.lighting.speed) { device.applyLighting() }
                        }
                        if device.lighting.effect.usesDirection {
                            Picker("Direction", selection: $device.lighting.direction) {
                                ForEach(device.lighting.effect.directions) { Text($0.displayName).tag($0) }
                            }
                            .onChange(of: device.lighting.direction) { device.applyLighting() }
                        }
                        HStack {
                            Button("Lights off") { device.lightsOff() }
                            Button("be quiet! default") { device.lighting = GlobalLighting(); device.applyLighting() }
                        }
                    }
                }
                Text("Effects are saved on the keyboard and keep running without OpenMount.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }

    var previewColor: Color {
        let l = device.lighting
        if l.colorMode == .gradient && l.effect.colorModes.contains(.gradient) { return Color(white: 0.75) }
        return l.primary.color.opacity(0.35 + 0.65 * Double(l.brightness) / 100)
    }
}

struct EffectTile: View {
    let effect: LightingEffect
    let selected: Bool
    let action: () -> Void
    var icon: String {
        switch effect {
        case .staticColor: return "circle.fill"
        case .colorWave: return "water.waves"
        case .tornado: return "tornado"
        case .breathing: return "lungs.fill"
        case .reactive: return "hand.tap.fill"
        case .matrix: return "chevron.down.2"
        }
    }
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title2)
                Text(effect.displayName).font(.callout)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(effect.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ColorRow: View {
    let label: String
    @Binding var color: RGB
    var onChange: () -> Void
    var body: some View {
        ColorPicker(label, selection: Binding(get: { color.color }, set: { color = RGB($0); onChange() }), supportsOpacity: false)
    }
}

struct SwatchRow: View {
    var pick: (RGB) -> Void
    static let swatches: [RGB] = [.beQuietOrange, RGB(255, 0, 0), RGB(255, 200, 0), RGB(0, 255, 0), RGB(0, 220, 255),
                                  RGB(0, 60, 255), RGB(170, 0, 255), RGB(255, 0, 140), RGB(255, 255, 255)]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.swatches, id: \.self) { s in
                Button { pick(s) } label: {
                    Circle().fill(s.color).frame(width: 20, height: 20).overlay(Circle().strokeBorder(.primary.opacity(0.2)))
                }
                .buttonStyle(.plain).help(s.hex)
            }
        }
    }
}

struct LabeledSlider: View {
    let label: String
    @Binding var value: UInt8
    var onChange: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(label); Spacer(); Text("\(value)%").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: Binding(get: { Double(value) }, set: { value = UInt8($0.rounded()); onChange() }), in: 0...100)
                .accessibilityLabel(label)
        }
    }
}

struct PerKeyView: View {
    @EnvironmentObject var device: DeviceController
    @State private var selection: Set<KeyID> = []
    @State private var brush: RGB = .beQuietOrange
    @State private var barColor: RGB = .beQuietOrange

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                KeyboardCanvas(layout: device.layout, selection: $selection,
                               fill: { k in color(of: k) },
                               lightBar: (0..<45).map { device.perKeyColors[$0]?.color ?? .black })
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.85)))
                Text("Click keys to select them (⌘-click to add, drag to box-select), then paint.")
                    .font(.footnote).foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 16) {
                    Card(title: "Brush") {
                        ColorRow(label: "Colour", color: $brush) {}
                        SwatchRow { brush = $0 }
                        HStack {
                            Button("Paint \(selection.count) selected") { paint(selection, brush) }
                                .disabled(selection.isEmpty).keyboardShortcut(.return, modifiers: [])
                            Button("Select all") { selection = Set(device.layout.keys.map(\.id)) }
                            Button("Clear selection") { selection = [] }
                        }
                    }
                    Card(title: "Quick fills") {
                        HStack {
                            Button("Fill all keys") { paint(Set(device.layout.keys.map(\.id)), brush) }
                            Button("All off") { device.perKeyColors = [:]; device.applyPerKey() }
                        }
                        HStack {
                            Button("WASD highlight") {
                                var c: [Int: RGB] = [:]
                                for k in device.layout.keys { if let i = k.id.ledIndex { c[i] = RGB(40, 40, 40) } }
                                for k in [KeyID.w, .a, .s, .d] { if let i = k.ledIndex { c[i] = brush } }
                                device.perKeyColors.merge(c) { _, n in n }
                                device.applyPerKey()
                            }
                            Button("Rainbow") { rainbow() }
                        }
                        ColorRow(label: "Light bar", color: $barColor) {}
                        Button("Paint light bar") {
                            for i in LightMountLEDs.lightBar { device.perKeyColors[i] = barColor }
                            device.applyPerKey()
                        }
                    }
                }
                Label("Per-key colours aren't stored on the keyboard. OpenMount re-applies them each time the keyboard connects while it's running. Choosing an effect on the Lighting page switches back to on-board lighting.",
                      systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }

    func color(of k: KeyID) -> Color {
        guard let i = k.ledIndex, let c = device.perKeyColors[i] else { return Color(white: 0.12) }
        return c.color
    }

    func paint(_ keys: Set<KeyID>, _ c: RGB) {
        for k in keys { if let i = k.ledIndex { device.perKeyColors[i] = c } }
        device.applyPerKey()
    }

    func rainbow() {
        let w = device.layout.width
        for k in device.layout.keys {
            guard let i = k.id.ledIndex else { continue }
            let h = (k.x / w)
            device.perKeyColors[i] = RGB(Color(hue: h, saturation: 1, brightness: 1))
        }
        for i in LightMountLEDs.lightBar { device.perKeyColors[i] = RGB(Color(hue: Double(i) / 45, saturation: 1, brightness: 1)) }
        device.applyPerKey()
    }
}
