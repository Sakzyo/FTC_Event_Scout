import SwiftUI

struct TagPillView: View {
    let tag: TeamTag

    var body: some View {
        Text(tag.text)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(tag.color.foregroundColor)
            .background(tag.color.backgroundColor, in: Capsule())
            .accessibilityLabel("Tag: \(tag.text)")
    }
}

struct TeamTagsSummaryView: View {
    private let firstTag: TeamTag?
    private let additionalCount: Int

    init(tags: [TeamTag]) {
        firstTag = tags.first
        additionalCount = max(tags.count - 1, 0)
    }

    var body: some View {
        HStack(spacing: 5) {
            if let firstTag {
                TagPillView(tag: firstTag)
            }
            if additionalCount > 0 {
                Text("+\(additionalCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(additionalCount) more tags")
            }
        }
    }
}

extension TagColor {
    var backgroundColor: Color {
        switch self {
        case .blue: Color.blue.opacity(0.16)
        case .green: Color.green.opacity(0.17)
        case .red: Color.red.opacity(0.15)
        case .yellow: Color.yellow.opacity(0.23)
        case .purple: Color.purple.opacity(0.16)
        case .pink: Color.pink.opacity(0.17)
        case .orange: Color.orange.opacity(0.18)
        case .gray: Color.secondary.opacity(0.14)
        }
    }

    var foregroundColor: Color {
        switch self {
        case .blue: .blue
        case .green: .green
        case .red: .red
        case .yellow: .primary
        case .purple: .purple
        case .pink: .pink
        case .orange: .orange
        case .gray: .secondary
        }
    }
}
