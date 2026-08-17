import SwiftUI

struct StatusBannerView: View {
    enum Kind {
        case information
        case success
        case error

        var symbol: String {
            switch self {
            case .information: "info.circle.fill"
            case .success: "checkmark.circle.fill"
            case .error: "exclamationmark.triangle.fill"
            }
        }

        var color: Color {
            switch self {
            case .information: .secondary
            case .success: .green
            case .error: .red
            }
        }
    }

    let message: String
    let kind: Kind

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.color)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

struct NumericValueView: View {
    let value: Double?
    var fractionDigits = 2

    var body: some View {
        if let value {
            Text(value, format: .number.precision(.fractionLength(fractionDigits)))
                .monospacedDigit()
        } else {
            Text("—")
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Unavailable")
        }
    }
}
