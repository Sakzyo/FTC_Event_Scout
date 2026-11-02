import SwiftUI

/// Teams and results for one manual match. BIOBUZZ matches record what happened on the
/// field and calculate points; other seasons, and Totals Only matches, take period totals.
struct ManualMatchEditor: View {
    @Binding var match: ManualMatch
    let event: ManualEvent
    let onNext: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                matchSettings
                scoreboard

                let issues = match.validationIssues(in: event)
                if !issues.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(issues, id: \.self) { issue in
                            Label(issue, systemImage: "exclamationmark.triangle.fill")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.orange)
                }

                if match.isScored {
                    if usesDetailedForm {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach([AllianceColor.red, .blue], id: \.self) { alliance in
                                BiobuzzAllianceForm(
                                    alliance: alliance,
                                    input: alliance == .red ? $match.red.biobuzz : $match.blue.biobuzz,
                                    opponentInput: alliance == .red ? match.blue.biobuzz : match.red.biobuzz,
                                    flowers: match.flowers
                                )
                            }
                        }
                        BiobuzzFlowerEditor(flowers: $match.flowers)
                    } else {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach([AllianceColor.red, .blue], id: \.self) { alliance in
                                TotalsAllianceForm(
                                    alliance: alliance,
                                    totals: alliance == .red ? $match.red.totals : $match.blue.totals,
                                    season: event.season
                                )
                            }
                        }
                    }
                } else {
                    Label(
                        "This match is on the schedule. OPRc predicts its result on the Predictions page. Turn on Scored to enter what happened.",
                        systemImage: "calendar"
                    )
                    .foregroundStyle(.secondary)
                    .scoutCard()
                }

                HStack {
                    Spacer()
                    Button(action: onNext) {
                        Label("Next Match", systemImage: "arrow.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Go to the next match, adding one if needed (⌘↩)")
                }
            }
            .padding(16)
        }
    }

    private var usesDetailedForm: Bool {
        event.supportsDetailedEntry && match.entryStyle == .detailed
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(match.title)
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Toggle("Scored", isOn: $match.isScored)
                .toggleStyle(.switch)
                .help("Turn off for matches that haven't been played yet")
        }
    }

    private var matchSettings: some View {
        HStack(spacing: 16) {
            Picker("Level", selection: $match.level) {
                ForEach(ManualMatchLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            LabeledContent(match.level == .qualification ? "Match" : "Series") {
                TextField("", value: $match.number, format: .number)
                    .frame(width: 52)
            }

            if match.level == .playoff {
                LabeledContent("Game") {
                    TextField("", value: $match.game, format: .number)
                        .frame(width: 40)
                }
            }

            Spacer()

            if event.supportsDetailedEntry && match.isScored {
                Picker("Entry", selection: $match.entryStyle) {
                    ForEach(ManualEntryStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Totals Only skips the detailed form when you only know period scores")
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    /// The match as the field's audience display shows it: red and blue halves meeting in
    /// the middle, teams on the outer edges and final scores side by side at the seam.
    private var scoreboard: some View {
        let scores = match.isScored ? ManualEventBuilder.scoreBreakdowns(for: match, season: event.season) : nil
        let red = scores?.red.finalScore
        let blue = scores?.blue.finalScore

        return HStack(spacing: 0) {
            ScoreboardSide(
                alliance: .red,
                first: $match.red1,
                second: $match.red2,
                score: red,
                isLeading: red != nil && (red ?? 0) >= (blue ?? 0)
            )
            ScoreboardSide(
                alliance: .blue,
                first: $match.blue1,
                second: $match.blue2,
                score: blue,
                isLeading: blue != nil && (blue ?? 0) >= (red ?? 0)
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.scoutMove, value: match.isScored)
    }
}

// MARK: - Scoreboard

private struct ScoreboardSide: View {
    let alliance: AllianceColor
    @Binding var first: Int?
    @Binding var second: Int?
    let score: Double?
    let isLeading: Bool

    var body: some View {
        HStack(spacing: 12) {
            if alliance == .blue { scoreText }
            VStack(alignment: alliance == .red ? .leading : .trailing, spacing: 6) {
                Text(alliance == .red ? "Red" : "Blue")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 6) {
                    ScoreboardTeamField(title: "\(alliance == .red ? "Red" : "Blue") 1", value: $first)
                    ScoreboardTeamField(title: "\(alliance == .red ? "Red" : "Blue") 2", value: $second)
                }
            }
            .frame(maxWidth: .infinity, alignment: alliance == .red ? .leading : .trailing)
            if alliance == .red { scoreText }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(alliance.scoutTone)
    }

    private var scoreText: some View {
        Text(score.map { String(Int($0)) } ?? "–")
            .font(.system(size: 46, weight: .heavy).width(.compressed).monospacedDigit())
            .foregroundStyle(.white.opacity(score == nil ? 0.35 : isLeading ? 1 : 0.6))
            .contentTransition(.numericText())
            .frame(minWidth: 64, alignment: alliance == .red ? .trailing : .leading)
            .accessibilityLabel("\(alliance == .red ? "Red" : "Blue") score")
            .accessibilityValue(score.map { String(Int($0)) } ?? "Not scored")
    }
}

/// A team number plate on the scoreboard: white digits on a translucent well.
private struct ScoreboardTeamField: View {
    let title: String
    @Binding var value: Int?
    @FocusState private var isFocused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        TextField(title, text: Binding(
            get: { value.map(String.init) ?? "" },
            set: { value = Int($0.filter(\.isNumber).prefix(6)) }
        ), prompt: Text("Team"))
        .textFieldStyle(.plain)
        .focused($isFocused)
        .font(.scoutNumeric(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.vertical, 5)
        .frame(width: 76)
        .background(.black.opacity(isFocused ? 0.28 : 0.18), in: shape)
        .overlay(shape.strokeBorder(.white.opacity(isFocused ? 0.9 : 0.25), lineWidth: isFocused ? 1.5 : 1))
        .animation(.scoutHover, value: isFocused)
        .accessibilityLabel("\(title) team number")
    }
}

private extension View {
    /// An alliance's form: a plain card with a solid alliance rule along its top edge.
    func allianceSheet(_ alliance: AllianceColor) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return self
            .padding(.top, 3)
            .background(.scoutCard, in: shape)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(alliance.scoutTone)
                    .frame(height: 3)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.scoutSeparator, lineWidth: 1))
    }
}

// MARK: - BIOBUZZ

private struct BiobuzzAllianceForm: View {
    let alliance: AllianceColor
    @Binding var input: BiobuzzAllianceInput
    let opponentInput: BiobuzzAllianceInput
    let flowers: BiobuzzFlowers

    var body: some View {
        let calculated = BiobuzzScoring.calculatedScore(input, alliance: alliance, flowers: flowers)
        let result = BiobuzzScoring.score(input, alliance: alliance, flowers: flowers)
        let opponent = BiobuzzScoring.score(opponentInput, alliance: alliance == .red ? .blue : .red, flowers: flowers)

        VStack(alignment: .leading, spacing: 12) {
            Text(alliance.displayName)
                .font(.headline)
                .foregroundStyle(alliance.displayColor)

            FormGroup("Autonomous") {
                CountRow(title: "Hive tips", value: $input.autoHiveTips)
                RobotRow(title: "Leave", first: $input.autoRobot1Leave, second: $input.autoRobot2Leave)
                RobotRow(title: "Park", first: $input.autoRobot1Park, second: $input.autoRobot2Park)
            }

            FormGroup("Teleop") {
                CountRow(title: "Hive tips", value: $input.teleopHiveTips)
                CountRow(title: "Pollen / nectar left in hive", value: $input.teleopHivePollenNectar)
                CountRow(title: "Pollen / nectar in garden", value: $input.teleopGardenPollenNectar)
                RobotRow(title: "Park", first: $input.teleopRobot1Park, second: $input.teleopRobot2Park)
            }

            FormGroup("Fouls Committed") {
                CountRow(title: "Minor (\(BiobuzzScoring.minorFoulPoints) pts)", value: $input.minorFouls)
                CountRow(title: "Major (\(BiobuzzScoring.majorFoulPoints) pts)", value: $input.majorFouls)
            }

            FormGroup("Points") {
                ForEach(BiobuzzPointField.allCases) { field in
                    PointRow(
                        title: field.title,
                        calculated: calculated.value(for: field),
                        override: Binding(
                            get: { input.override(for: field) },
                            set: { input.setOverride($0, for: field) }
                        )
                    )
                }
                Divider()
                TotalRow(title: "Auto", value: result.autoPoints)
                TotalRow(title: "Teleop", value: result.teleopPoints)
                TotalRow(title: "Penalty received", value: opponent.foulPointsCommitted)
                TotalRow(title: "Final", value: result.preFoulTotal + opponent.foulPointsCommitted, emphasized: true)
                HStack(spacing: 6) {
                    RPBadge(title: "Swarm", earned: result.swarmRP)
                    RPBadge(title: "Pollinator 1", earned: result.pollinator1RP)
                    RPBadge(title: "Pollinator 2", earned: result.pollinator2RP)
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .allianceSheet(alliance)
    }
}

/// The four shared flowers, each listed bottom to top. The top-most nectar owns a flower.
private struct BiobuzzFlowerEditor: View {
    @Binding var flowers: BiobuzzFlowers

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Flowers")
                    .font(.headline)
                Text("Listed bottom to top. Both alliances share them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(BiobuzzFlower.allCases) { flower in
                    GridRow {
                        Text(flower.title)
                            .frame(minWidth: 140, alignment: .leading)
                        HStack(spacing: 4) {
                            ForEach(Array(flowers[flower].enumerated()), id: \.offset) { index, element in
                                Button {
                                    flowers[flower].remove(at: index)
                                } label: {
                                    FlowerChip(element: element)
                                }
                                .buttonStyle(.plain)
                                .help("Remove \(element.title)")
                            }
                            Menu {
                                ForEach(BiobuzzFlowerElement.allCases) { element in
                                    Button(element.title) { flowers[flower].append(element) }
                                }
                            } label: {
                                Image(systemName: "plus")
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help("Add the next element on top")
                        }
                        Text(ownerText(flowers[flower]))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .scoutCard()
    }

    private func ownerText(_ elements: [BiobuzzFlowerElement]) -> String {
        guard let owner = elements.compactMap(\.nectarAlliance).last else {
            return elements.isEmpty ? "Empty" : "Not owned"
        }
        return owner == .red ? "Red owns" : "Blue owns"
    }
}

private struct FlowerChip: View {
    let element: BiobuzzFlowerElement

    var body: some View {
        Text(element.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch element {
        case .pollen: .orange
        case .redNectar: .red
        case .blueNectar: .blue
        }
    }
}

// MARK: - Totals

private struct TotalsAllianceForm: View {
    let alliance: AllianceColor
    @Binding var totals: ManualTotals
    let season: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(alliance.displayName)
                .font(.headline)
                .foregroundStyle(alliance.displayColor)

            FormGroup("Points") {
                OptionalCountRow(title: "Auto", value: $totals.auto)
                OptionalCountRow(title: "Driver-Controlled (no endgame)", value: $totals.driverControlled)
                OptionalCountRow(title: season == BiobuzzScoring.season ? "Teleop park" : "Endgame", value: $totals.endgame)
                OptionalCountRow(title: "Penalty received", value: $totals.penaltyReceived)
                Divider()
                PointRow(
                    title: "Final",
                    calculated: totals.calculatedFinal ?? 0,
                    override: $totals.finalOverride,
                    emphasized: true
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .allianceSheet(alliance)
    }
}

// MARK: - Rows

private struct FormGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct CountRow: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            TextField(title, value: $value, format: .number)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
            Stepper(title, value: $value, in: 0 ... 999)
                .labelsHidden()
        }
    }
}

private struct OptionalCountRow: View {
    let title: String
    @Binding var value: Int?

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            TextField(title, text: Binding(
                get: { value.map(String.init) ?? "" },
                set: { value = Int($0.filter(\.isNumber)) }
            ))
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 64)
        }
    }
}

private struct RobotRow: View {
    let title: String
    @Binding var first: Bool
    @Binding var second: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Toggle("Robot 1", isOn: $first)
            Toggle("Robot 2", isOn: $second)
        }
        .toggleStyle(.checkbox)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// A calculated value that can be replaced by hand; overrides show in orange with a reset.
private struct PointRow: View {
    let title: String
    let calculated: Int
    @Binding var override: Int?
    var emphasized = false

    var body: some View {
        HStack {
            Text(title)
                .fontWeight(emphasized ? .semibold : .regular)
            Spacer(minLength: 8)
            if let current = override {
                TextField(title, value: Binding(get: { current }, set: { override = $0 }), format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .foregroundStyle(.orange)
                Button {
                    override = nil
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .buttonStyle(.borderless)
                .help("Use the calculated value, \(calculated)")
            } else {
                Text(String(calculated))
                    .font(.scoutNumeric(size: 13, weight: emphasized ? .bold : .medium))
                Button {
                    override = calculated
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Override the calculated value")
            }
        }
    }
}

private struct TotalRow: View {
    let title: String
    let value: Int
    var emphasized = false

    var body: some View {
        HStack {
            Text(title)
                .fontWeight(emphasized ? .semibold : .regular)
            Spacer()
            Text(String(value))
                .font(.scoutNumeric(size: emphasized ? 15 : 13, weight: emphasized ? .bold : .medium))
        }
    }
}

private struct RPBadge: View {
    let title: String
    let earned: Bool

    var body: some View {
        Label(title, systemImage: earned ? "checkmark.circle.fill" : "circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(earned ? Color.green : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background((earned ? Color.green : Color.secondary).opacity(0.12), in: Capsule())
            .accessibilityValue(earned ? "Earned" : "Not earned")
    }
}
