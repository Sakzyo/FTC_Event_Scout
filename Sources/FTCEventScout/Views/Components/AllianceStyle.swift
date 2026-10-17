import SwiftUI

extension AllianceColor {
    var displayColor: Color {
        self == .red ? .red : .blue
    }

    var displayName: String {
        self == .red ? "Red Alliance" : "Blue Alliance"
    }
}

/// A tinted alliance container. The alliance the user is focused on gets a matching outline.
struct AlliancePanelBackground: ViewModifier {
    let alliance: AllianceColor
    var isOutlined = false

    func body(content: Content) -> some View {
        content
            .background(
                alliance.displayColor.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                if isOutlined {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(alliance.displayColor.opacity(0.5), lineWidth: 1)
                }
            }
    }
}

extension View {
    func alliancePanelBackground(_ alliance: AllianceColor, outlined: Bool = false) -> some View {
        modifier(AlliancePanelBackground(alliance: alliance, isOutlined: outlined))
    }
}

/// A compact, tinted capsule for categorical states such as Win, Loss, or Limited Data.
struct StatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.callout.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
    }
}
