import SwiftUI

struct MatchPredictionsView: View {
    let event: EventData

    var body: some View {
        if event.mode == .preview {
            ContentUnavailableView {
                Label("Predictions Unavailable", systemImage: "sparkles.rectangle.stack")
            } description: {
                Text("This historical preview has no current match schedule or completed scores for calculating OPRc.")
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    PredictionMethodSummary(analysis: event.oprcAnalysis)
                    ManualMatchPredictionSection(analysis: event.oprcAnalysis)

                    Text("Upcoming Matches")
                        .font(.title2.weight(.semibold))
                        .padding(.top, 4)

                    if event.oprcAnalysis.predictions.isEmpty {
                        NoUpcomingMatchesView()
                    } else {
                        ForEach(event.oprcAnalysis.predictions) { prediction in
                            MatchPredictionCard(
                                prediction: prediction,
                                teamMetrics: event.oprcAnalysis.teamMetrics,
                                analysis: event.oprcAnalysis
                            )
                        }
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct ManualMatchPredictionSection: View {
    let analysis: OPRcAnalysis
    @State private var redOne = ""
    @State private var redTwo = ""
    @State private var blueOne = ""
    @State private var blueTwo = ""
    @State private var submittedEntry: ManualMatchEntry?
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Enter two teams for each alliance to predict a custom matchup using the current event's OPRc values.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .top, spacing: 12) {
                        ManualAllianceInput(
                            alliance: .red,
                            firstTeam: $redOne,
                            secondTeam: $redTwo,
                            submit: generatePrediction
                        )

                        Text("VS")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 38)
                            .accessibilityHidden(true)

                        ManualAllianceInput(
                            alliance: .blue,
                            firstTeam: $blueOne,
                            secondTeam: $blueTwo,
                            submit: generatePrediction
                        )
                    }

                    HStack {
                        if let validationMessage {
                            Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(.red)
                        }

                        Spacer(minLength: 12)

                        Button("Clear", action: clear)
                            .disabled(inputValues.allSatisfy(\.isEmpty))

                        Button(action: generatePrediction) {
                            Label("Predict Match", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(5)
            } label: {
                Label("Custom Match Prediction", systemImage: "square.and.pencil")
            }

            if let prediction = manualPrediction {
                MatchPredictionCard(
                    prediction: prediction,
                    teamMetrics: analysis.teamMetrics,
                    analysis: analysis
                )
            }
        }
        .onChange(of: inputValues) { _, _ in
            submittedEntry = nil
            validationMessage = nil
        }
    }

    private var inputValues: [String] {
        [redOne, redTwo, blueOne, blueTwo]
    }

    private var manualPrediction: MatchPrediction? {
        guard let submittedEntry else { return nil }
        return MatchPredictionService.predict(
            matchID: "custom-match",
            displayTitle: "Custom Match",
            series: nil,
            matchNumber: nil,
            redTeams: submittedEntry.redTeams,
            blueTeams: submittedEntry.blueTeams,
            teamMetrics: analysis.teamMetrics,
            filteringWasApplied: analysis.filteringWasApplied,
            calculationIsRankDeficient: analysis.filteredIsRankDeficient
        )
    }

    private func generatePrediction() {
        do {
            submittedEntry = try ManualMatchEntry.parse(
                redTeamNumbers: [redOne, redTwo],
                blueTeamNumbers: [blueOne, blueTwo]
            )
            validationMessage = nil
        } catch {
            submittedEntry = nil
            validationMessage = error.localizedDescription
        }
    }

    private func clear() {
        redOne = ""
        redTwo = ""
        blueOne = ""
        blueTwo = ""
        submittedEntry = nil
        validationMessage = nil
    }
}

private struct ManualAllianceInput: View {
    let alliance: AllianceColor
    @Binding var firstTeam: String
    @Binding var secondTeam: String
    let submit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(
                alliance == .red ? "Red Alliance" : "Blue Alliance",
                systemImage: "circle.fill"
            )
            .font(.headline)
            .foregroundStyle(alliance == .red ? .red : .blue)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Team 1")
                    teamNumberField(
                        accessibilityLabel: "\(allianceName) alliance first team number",
                        text: $firstTeam
                    )
                }
                GridRow {
                    Text("Team 2")
                    teamNumberField(
                        accessibilityLabel: "\(allianceName) alliance second team number",
                        text: $secondTeam
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
    }

    private var allianceName: String {
        alliance == .red ? "Red" : "Blue"
    }

    private func teamNumberField(
        accessibilityLabel: String,
        text: Binding<String>
    ) -> some View {
        TextField("Team number", text: text)
            .textFieldStyle(.roundedBorder)
            .font(.body.monospacedDigit())
            .onSubmit(submit)
            .accessibilityLabel(accessibilityLabel)
    }
}

private struct NoUpcomingMatchesView: View {
    var body: some View {
        GroupBox {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No Upcoming Matches")
                        .font(.headline)
                    Text("No unplayed matches are present in the current event schedule. You can still predict a custom matchup above.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(5)
        }
    }
}

private struct PredictionMethodSummary: View {
    let analysis: OPRcAnalysis

    var body: some View {
        GroupBox {
            HStack(spacing: 20) {
                SummaryValue(
                    title: "Completed matches",
                    value: analysis.validCompletedMatchCount.formatted()
                )
                SummaryValue(
                    title: "Alliance observations",
                    value: analysis.validAllianceObservationCount.formatted()
                )
                SummaryValue(
                    title: "Outliers removed",
                    value: analysis.excludedOutlierCount.formatted()
                )
                Spacer(minLength: 0)
                Label(filterStatusText, systemImage: filterStatusSymbol)
                    .font(.callout)
                    .foregroundStyle(filterStatusColor)
            }
            .padding(4)
        } label: {
            Label("OPRc Prediction Model", systemImage: "function")
        }
        .accessibilityElement(children: .contain)
    }

    private var filterStatusText: String {
        if !analysis.filteringWasApplied { return "Limited sample · no IQR filtering" }
        if analysis.filteredIsRankDeficient { return "Limited schedule constraints" }
        return "Residual IQR filter applied"
    }

    private var filterStatusSymbol: String {
        analysis.filteringWasApplied && !analysis.filteredIsRankDeficient
            ? "checkmark.circle.fill"
            : "exclamationmark.triangle.fill"
    }

    private var filterStatusColor: Color {
        analysis.filteringWasApplied && !analysis.filteredIsRankDeficient
            ? .green
            : .orange
    }
}

private struct SummaryValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MatchPredictionCard: View {
    let prediction: MatchPrediction
    let teamMetrics: [Int: TeamOPRcMetric]
    let analysis: OPRcAnalysis

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    PredictionAlliancePanel(
                        alliance: .red,
                        teamNumbers: prediction.redTeams,
                        predictedScore: prediction.predictedRedScore,
                        teamMetrics: teamMetrics
                    )
                    PredictionAlliancePanel(
                        alliance: .blue,
                        teamNumbers: prediction.blueTeams,
                        predictedScore: prediction.predictedBlueScore,
                        teamMetrics: teamMetrics
                    )
                }

                Divider()

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    PredictionResultView(prediction: prediction)
                    Spacer(minLength: 12)
                    PredictionQualityView(prediction: prediction, analysis: analysis)
                }
            }
            .padding(5)
        } label: {
            HStack {
                Text(prediction.displayTitle)
                    .font(.headline)
                Spacer()
                PredictionStatusLabel(status: prediction.status)
            }
        }
    }
}

private struct PredictionAlliancePanel: View {
    let alliance: AllianceColor
    let teamNumbers: [Int]
    let predictedScore: Double?
    let teamMetrics: [Int: TeamOPRcMetric]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(
                alliance == .red ? "Red Alliance" : "Blue Alliance",
                systemImage: "circle.fill"
            )
            .font(.headline)
            .foregroundStyle(alliance == .red ? .red : .blue)

            ForEach(teamNumbers, id: \.self) { teamNumber in
                HStack {
                    Text("Team \(teamNumber.teamNumberText)")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Text("OPRc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    NumericValueView(
                        value: teamMetrics[teamNumber]?.oprc,
                        fractionDigits: 1
                    )
                    .font(.callout.monospacedDigit())
                }
                .accessibilityElement(children: .combine)
            }

            if teamNumbers.isEmpty {
                Text("Alliance teams unavailable")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(alignment: .firstTextBaseline) {
                Text("Predicted score")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                NumericValueView(value: predictedScore, fractionDigits: 1)
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(alliance == .red ? .red : .blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct PredictionResultView: View {
    let prediction: MatchPrediction

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Prediction")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let winner = prediction.predictedWinner,
               let margin = prediction.predictedMargin {
                Text(winnerText(winner, margin: margin))
                    .font(.title3.weight(.semibold))
                Text("Signed margin: \(signedMargin(margin))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("Unavailable")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func winnerText(_ winner: PredictedMatchWinner, margin: Double) -> String {
        switch winner {
        case .red:
            "Red by \(abs(margin).formatted(.number.precision(.fractionLength(1))))"
        case .blue:
            "Blue by \(abs(margin).formatted(.number.precision(.fractionLength(1))))"
        case .tie:
            "Predicted tie"
        }
    }

    private func signedMargin(_ margin: Double) -> String {
        let value = margin.formatted(.number.precision(.fractionLength(1)))
        return margin > 0 ? "+\(value)" : value
    }
}

private struct PredictionStatusLabel: View {
    let status: MatchPredictionStatus

    var body: some View {
        switch status {
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .limitedData:
            Label("Limited Data", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .unavailable:
            Label("Unavailable", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }
}

private struct PredictionQualityView: View {
    let prediction: MatchPrediction
    let analysis: OPRcAnalysis

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 360, alignment: .trailing)
    }

    private var message: String {
        switch prediction.status {
        case .ready:
            return "All teams have OPRc values with sufficient event history."
        case .unavailable:
            if prediction.unavailableTeamNumbers.isEmpty {
                return "The scheduled alliance data is incomplete."
            }
            let teams = prediction.unavailableTeamNumbers.map(\.teamNumberText)
                .joined(separator: ", ")
            return "No usable OPRc is available for team(s) \(teams)."
        case .limitedData:
            if !prediction.limitedDataTeamNumbers.isEmpty {
                let teams = prediction.limitedDataTeamNumbers.map(\.teamNumberText)
                    .joined(separator: ", ")
                return "Very little completed-match history is available for team(s) \(teams)."
            }
            if !analysis.filteringWasApplied {
                return "At least four valid alliance observations are required before IQR filtering."
            }
            if analysis.filteredIsRankDeficient {
                return "The completed schedule does not yet independently constrain every team estimate."
            }
            return "The prediction uses limited event data."
        }
    }
}
