import SwiftUI

// An ftcscout.org-inspired design language for the Rankings tab: flat cards with hairline
// borders on a soft gray page, folder tabs, pill buttons, and color-grouped stat columns.

/// A color with explicit light and dark values, resolved from the view's color scheme.
struct ScoutColor: ShapeStyle {
    let light: Color
    let dark: Color

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        color(for: environment.colorScheme).resolve(in: environment)
    }

    func color(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? dark : light
    }

    func opacity(_ opacity: Double) -> ScoutColor {
        ScoutColor(light: light.opacity(opacity), dark: dark.opacity(opacity))
    }

    fileprivate init(light: Color, dark: Color) {
        self.light = light
        self.dark = dark
    }

    fileprivate init(_ light: (Double, Double, Double), _ dark: (Double, Double, Double)) {
        self.light = Color(.sRGB, red: light.0 / 255, green: light.1 / 255, blue: light.2 / 255)
        self.dark = Color(.sRGB, red: dark.0 / 255, green: dark.1 / 255, blue: dark.2 / 255)
    }
}

extension ShapeStyle where Self == ScoutColor {
    static var scoutPage: ScoutColor { ScoutColor((242, 242, 242), (22, 22, 22)) }
    static var scoutCard: ScoutColor { ScoutColor((255, 255, 255), (45, 45, 45)) }
    static var scoutSeparator: ScoutColor { ScoutColor((211, 211, 211), (74, 78, 81)) }
    static var scoutSecondaryText: ScoutColor { ScoutColor((99, 100, 102), (183, 183, 184)) }
    static var scoutRowHover: ScoutColor { ScoutColor((240, 240, 240), (58, 58, 58)) }
    static var scoutTabHover: ScoutColor { ScoutColor((251, 251, 251), (35, 35, 35)) }
    static var scoutFormBackground: ScoutColor { ScoutColor((239, 239, 239), (25, 25, 25)) }
    static var scoutFormHover: ScoutColor { ScoutColor((227, 227, 227), (35, 35, 35)) }
    static var scoutFormPressed: ScoutColor { ScoutColor((215, 215, 215), (45, 45, 45)) }
    /// The teal used for icons and selected controls.
    static var scoutTheme: ScoutColor { ScoutColor((44, 102, 110), (57, 132, 142)) }
    /// The purple outline that marks the hovered row.
    static var scoutFocus: ScoutColor { ScoutColor((170, 0, 255), (196, 79, 255)) }

    static var scoutZebra: ScoutColor {
        ScoutColor(light: Color.black.opacity(0.0396), dark: Color.white.opacity(0.041))
    }
}

/// The color group of a stats column. Headers are filled with the color, and
/// body cells carry a light tint of it, so related figures read as one block.
enum ScoutStatColor: Hashable {
    case white
    case red
    case blue
    case lightBlue
    case purple
    case green

    var headerFill: ScoutColor {
        switch self {
        case .white: .scoutCard
        case .red: ScoutColor((244, 67, 54), (204, 47, 47))
        case .blue: ScoutColor((25, 118, 210), (27, 87, 179))
        case .lightBlue: ScoutColor((33, 150, 243), (25, 118, 210))
        case .purple: ScoutColor((170, 0, 255), (127, 0, 190))
        case .green: ScoutColor((67, 160, 71), (46, 125, 50))
        }
    }

    var cellTint: ScoutColor? {
        self == .white ? nil : headerFill.opacity(0.15)
    }

    var headerText: Color {
        self == .white ? .primary : .white
    }
}

extension Font {
    /// System text with tabular digits, so numbers line up down a column.
    static func scoutNumeric(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

extension Animation {
    /// Hover and color changes, matching ftcscout's 120ms outline transition.
    static var scoutHover: Animation {
        .timingCurve(0.25, 0.1, 0.25, 1, duration: 0.12)
    }

    /// Strong ease-out for press feedback.
    static var scoutPress: Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: 0.16)
    }

    /// Strong ease-in-out for elements that move or rotate on screen.
    static var scoutMove: Animation {
        .timingCurve(0.77, 0, 0.175, 1, duration: 0.22)
    }
}

enum ScoutFormat {
    private static let ordinalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter
    }()

    /// "1st", "2nd", "11th", localized for the current locale.
    static func ordinal(_ value: Int) -> String {
        ordinalFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func ordinal(_ value: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

// MARK: - Cards

extension View {
    /// A flat white card with a hairline border and 8pt corners.
    func scoutCard(padding: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return self
            .padding(padding)
            .background(.scoutCard, in: shape)
            .overlay(shape.strokeBorder(.scoutSeparator, lineWidth: 1))
    }
}

/// A card with a folder tab on its top-leading edge, like ftcscout's event tabs.
struct ScoutTabbedCard<Accessory: View, Content: View>: View {
    let title: String
    let systemImage: String
    var contentPadding: CGFloat = 12
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    private let radius: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .labelStyle(ScoutTabLabelStyle())
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background {
                        FolderTabShape(radius: radius).fill(.scoutCard)
                        FolderTabShape(radius: radius).stroke(.scoutSeparator, lineWidth: 1)
                    }
                    // Overlap the card's top border so the tab and card read as one surface.
                    .offset(y: 1)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 8)

                accessory
                    .font(.system(size: 11))
                    .foregroundStyle(.scoutSecondaryText)
                    .lineLimit(1)
            }
            .zIndex(1)

            let shape = UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: radius,
                bottomTrailingRadius: radius,
                topTrailingRadius: radius,
                style: .continuous
            )
            content
                .padding(contentPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(.scoutCard, in: shape)
                .clipShape(shape)
                .overlay(shape.strokeBorder(.scoutSeparator, lineWidth: 1))
        }
    }
}

extension ScoutTabbedCard where Accessory == EmptyView {
    init(
        title: String,
        systemImage: String,
        contentPadding: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            systemImage: systemImage,
            contentPadding: contentPadding,
            accessory: { EmptyView() },
            content: content
        )
    }
}

private struct ScoutTabLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.icon
                .font(.system(size: 12, weight: .semibold))
            configuration.title
        }
    }
}

/// Three sides of a rounded rectangle; the open bottom joins the card below.
private struct FolderTabShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: 0.5, dy: 0.5)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY + 0.5))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY),
            radius: radius
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius),
            radius: radius
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY + 0.5))
        return path
    }
}

// MARK: - Controls

/// ftcscout's pill button: a gray capsule that darkens on hover and press.
/// It also scales down slightly on press; with Reduce Motion the color change alone remains.
struct ScoutPillButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        ScoutPillButton(configuration: configuration, isSelected: isSelected)
    }
}

private struct ScoutPillButton: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        let isPressed = configuration.isPressed && isEnabled

        configuration.label
            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            .lineLimit(1)
            .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(fill(isPressed: isPressed), in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? AnyShapeStyle(.scoutTheme) : AnyShapeStyle(.scoutSeparator),
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.scoutPress, value: isPressed)
            .animation(.scoutHover, value: isHovering)
            .animation(.scoutHover, value: isSelected)
            .onHover { isHovering = $0 }
    }

    private func fill(isPressed: Bool) -> AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.scoutTheme) }
        if isPressed { return AnyShapeStyle(.scoutFormPressed) }
        if isHovering && isEnabled { return AnyShapeStyle(.scoutFormHover) }
        return AnyShapeStyle(.scoutFormBackground)
    }
}

/// A bordered card that acts as a button. Hover draws the same purple outline as table rows;
/// press scales it down slightly, or only darkens it under Reduce Motion.
struct ScoutCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ScoutCardButton(configuration: configuration)
    }
}

private struct ScoutCardButton: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        let isPressed = configuration.isPressed && isEnabled
        let isHighlighted = isHovering && isEnabled
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        configuration.label
            .background(isPressed ? AnyShapeStyle(.scoutTabHover) : AnyShapeStyle(.scoutCard), in: shape)
            .overlay(shape.strokeBorder(.scoutSeparator, lineWidth: 1))
            .overlay(
                shape.strokeBorder(.scoutFocus, lineWidth: 2)
                    .opacity(isHighlighted ? 1 : 0)
            )
            .contentShape(shape)
            .scaleEffect(isPressed && !reduceMotion ? 0.985 : 1)
            .animation(.scoutPress, value: isPressed)
            .animation(.scoutHover, value: isHighlighted)
            .onHover { isHovering = $0 }
    }
}

/// A row of pills where one is selected. VoiceOver sees it as a standard segmented picker.
struct ScoutPillPicker<Value: Hashable & Identifiable>: View {
    let accessibilityTitle: String
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    var body: some View {
        ScoutFlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(options) { option in
                Button(title(option)) {
                    selection = option
                }
                .buttonStyle(ScoutPillButtonStyle(isSelected: option == selection))
            }
        }
        .accessibilityRepresentation {
            Picker(accessibilityTitle, selection: $selection) {
                ForEach(options) { option in
                    Text(verbatim: title(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

/// An icon in the theme color followed by a line of detail, as in ftcscout's event header.
struct ScoutInfoRow<Content: View>: View {
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.scoutTheme)
                .frame(width: 16)
                .accessibilityHidden(true)
            content
                .lineLimit(1)
        }
    }
}

/// Places children left to right and wraps them onto new lines when space runs out.
struct ScoutFlowLayout: Layout {
    var spacing: CGFloat = 16
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if proposedWidth > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
