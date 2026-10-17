import SwiftUI

// A small "heads-up display" design language shared by the event overview,
// rankings controls, and OPR leader charts: monospaced micro-labels, hairline
// panels with a faint accent edge, and crisp press feedback.

extension Animation {
    /// Strong ease-out for press feedback and content that appears.
    static var hudEaseOut: Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: 0.16)
    }

    /// Strong ease-in-out for elements that move on screen, such as a selection indicator.
    static var hudEaseInOut: Animation {
        .timingCurve(0.77, 0, 0.175, 1, duration: 0.22)
    }

    /// Gentle ease for hover color changes.
    static var hudHover: Animation {
        .timingCurve(0.25, 0.1, 0.25, 1, duration: 0.15)
    }
}

extension Font {
    /// Monospaced figures used for every table and chart value so columns scan as a grid.
    static func hudNumeric(size: CGFloat = 14, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// A tracked, monospaced micro-label. Pass text in the exact case to display so
/// terms such as "npOPR" keep their conventional capitalization.
struct HUDLabel: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.9)
            .lineLimit(1)
    }
}

/// A hairline panel with a faint accent edge in its top-leading corner.
struct HUDPanelBackground: ViewModifier {
    var cornerRadius: CGFloat = 10
    var isHighlighted = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                ZStack {
                    shape.fill(Color.primary.opacity(0.035))
                    shape.fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(isHighlighted ? 0.12 : 0.05), .clear],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(isHighlighted ? 0.7 : 0.32),
                            Color.primary.opacity(isHighlighted ? 0.14 : 0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
    }
}

extension View {
    func hudPanel(cornerRadius: CGFloat = 10, highlighted: Bool = false) -> some View {
        modifier(HUDPanelBackground(cornerRadius: cornerRadius, isHighlighted: highlighted))
    }
}

/// A pressable HUD card: it brightens its edge on hover and scales down slightly on press.
/// With Reduce Motion enabled, the press dims instead of scaling.
struct HUDCardButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        HUDCardButton(configuration: configuration, cornerRadius: cornerRadius)
    }
}

private struct HUDCardButton: View {
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        let isPressed = configuration.isPressed && isEnabled

        configuration.label
            .hudPanel(cornerRadius: cornerRadius, highlighted: isHovering && isEnabled)
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isPressed && reduceMotion ? 0.75 : 1)
            .animation(.hudEaseOut, value: isPressed)
            .animation(.hudHover, value: isHovering)
            .onHover { isHovering = $0 }
    }
}

/// A capsule that marks whether the dashboard shows live results or a historical preview.
struct HUDModeBadge: View {
    let mode: EventMode
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .shadow(color: tint.opacity(0.9), radius: 3)
            Text(verbatim: mode == .live ? "LIVE" : "PREVIEW")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode == .live ? "Live event data" : "Historical preview")
    }

    // System green and orange are too light for small text on a light background.
    private var tint: Color {
        switch (mode, colorScheme) {
        case (.live, .dark): Color(red: 0.30, green: 0.85, blue: 0.45)
        case (.live, _): Color(red: 0.05, green: 0.52, blue: 0.22)
        case (.preview, .dark): .orange
        case (.preview, _): Color(red: 0.72, green: 0.38, blue: 0.0)
        }
    }
}

/// A thin magnitude gauge: a faint track with an accent fill scaled to the event leader.
struct HUDGauge: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.07))
                if fraction > 0 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.35), Color.accentColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(proxy.size.width * fraction, 3))
                }
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

/// A compact segmented switcher with a sliding selection indicator.
/// VoiceOver sees it as a standard segmented picker.
struct HUDSegmentedControl<Value: Hashable & Identifiable>: View {
    let accessibilityTitle: String
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                segment(for: option)
            }
        }
        .padding(2)
        .hudPanel(cornerRadius: 8)
        .accessibilityRepresentation {
            Picker(accessibilityTitle, selection: $selection) {
                ForEach(options) { option in
                    Text(verbatim: title(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func segment(for option: Value) -> some View {
        let isSelected = option == selection

        return Button {
            guard option != selection else { return }
            withAnimation(reduceMotion ? nil : .hudEaseInOut) {
                selection = option
            }
        } label: {
            Text(verbatim: title(option))
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(0.16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1)
                            }
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
