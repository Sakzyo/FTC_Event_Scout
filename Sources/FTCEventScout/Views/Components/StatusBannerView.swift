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
    private let fractionLength: ClosedRange<Int>

    init(value: Double?, fractionDigits: Int = 2) {
        self.value = value
        fractionLength = fractionDigits ... fractionDigits
    }

    /// Use a range such as `0 ... 1` to drop redundant trailing zeros from whole-number scores.
    init(value: Double?, fractionLength: ClosedRange<Int>) {
        self.value = value
        self.fractionLength = fractionLength
    }

    var body: some View {
        if let value {
            Text(value, format: .number.precision(.fractionLength(fractionLength)))
                .monospacedDigit()
        } else {
            Text("—")
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Unavailable")
        }
    }
}
