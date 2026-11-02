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
                teams

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
            Spacer()
            if match.isScored {
                let scores = ManualEventBuilder.scoreBreakdowns(for: match, season: event.season)
                HStack(spacing: 6) {
                    Text(scoreText(scores.red.finalScore))
                        .foregroundStyle(AllianceColor.red.displayColor)
                    Text("–").foregroundStyle(.secondary)
                    Text(scoreText(scores.blue.finalScore))
                        .foregroundStyle(AllianceColor.blue.displayColor)
                }
                .font(.scoutNumeric(size: 22, weight: .bold))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Red \(scoreText(scores.red.finalScore)), Blue \(scoreText(scores.blue.finalScore))")
            }
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

            Toggle("Scored", isOn: $match.isScored)
                .toggleStyle(.switch)
        }
        .textFieldStyle(.roundedBorder)
    }

    private var teams: some View {
        HStack(spacing: 12) {
            teamPanel(.red, first: $match.red1, second: $match.red2)
            teamPanel(.blue, first: $match.blue1, second: $match.blue2)
        }
    }

    private func teamPanel(_ alliance: AllianceColor, first: Binding<Int?>, second: Binding<Int?>) -> some View {
        HStack(spacing: 8) {
            Text(alliance == .red ? "Red" : "Blue")
                .font(.headline)
                .foregroundStyle(alliance.displayColor)
                .frame(width: 40, alignment: .leading)
            TeamNumberField(title: "\(alliance == .red ? "Red" : "Blue") 1", value: first)
            TeamNumberField(title: "\(alliance == .red ? "Red" : "Blue") 2", value: second)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .alliancePanelBackground(alliance)
    }

    private func scoreText(_ value: Double?) -> String {
        value.map { String(Int($0)) } ?? "—"
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
        .alliancePanelBackground(alliance)
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
                Text("Bottom to top · shared by both alliances")
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
        .alliancePanelBackground(alliance)
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
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
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

private struct TeamNumberField: View {
    let title: String
    @Binding var value: Int?

    var body: some View {
        TextField(title, text: Binding(
            get: { value.map(String.init) ?? "" },
            set: { value = Int($0.filter(\.isNumber).prefix(6)) }
        ))
        .textFieldStyle(.roundedBorder)
        .font(.scoutNumeric(size: 13))
        .frame(width: 80)
        .accessibilityLabel("\(title) team number")
    }
}
