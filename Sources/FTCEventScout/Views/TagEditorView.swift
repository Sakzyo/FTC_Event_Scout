import SwiftUI

struct TagEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel
    let selection: TeamSelection
    @State private var tagName = ""
    @State private var selectedColor = TagColor.blue
    @FocusState private var nameIsFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Current Tags") {
                    let currentTags = model.tags(
                        eventCode: selection.eventCode,
                        teamNumber: selection.teamNumber
                    )
                    if currentTags.isEmpty {
                        Text("No tags have been added for this team.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(currentTags) { tag in
                            HStack {
                                TagPillView(tag: tag)
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    model.removeTag(
                                        eventCode: selection.eventCode,
                                        teamNumber: selection.teamNumber,
                                        tagID: tag.id
                                    )
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                ExistingTagsSection(model: model, selection: selection)

                Section("New Tag") {
                    TextField("Tag name", text: $tagName)
                        .focused($nameIsFocused)
                        .onSubmit(addTag)

                    Picker("Color", selection: $selectedColor) {
                        ForEach(TagColor.allCases) { color in
                            TagColorLabel(color: color)
                                .tag(color)
                        }
                    }
                    .pickerStyle(.menu)

                    LabeledContent("Preview") {
                        TagPillView(tag: TeamTag(
                            text: tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "Sample"
                                : tagName.trimmingCharacters(in: .whitespacesAndNewlines),
                            color: selectedColor
                        ))
                    }

                    HStack {
                        Spacer()
                        Button("Add Tag", action: addTag)
                            .buttonStyle(.borderedProminent)
                            .disabled(tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Tags for Team \(selection.teamNumber.teamNumberText)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .defaultFocus($nameIsFocused, true)
        }
        .frame(width: 520, height: 520)
    }

    private func addTag() {
        model.addTag(
            eventCode: selection.eventCode,
            teamNumber: selection.teamNumber,
            text: tagName,
            color: selectedColor
        )
        tagName = ""
        nameIsFocused = true
    }
}

private struct ExistingTagsSection: View {
    @Bindable var model: AppModel
    let selection: TeamSelection

    var body: some View {
        let existingTags = model.existingTags(
            eventCode: selection.eventCode,
            excludingTeam: selection.teamNumber
        )
        if !existingTags.isEmpty {
            Section("Reuse an Event Tag") {
                ForEach(existingTags) { tag in
                    Button {
                        model.reuseTag(
                            eventCode: selection.eventCode,
                            teamNumber: selection.teamNumber,
                            tag: tag
                        )
                    } label: {
                        HStack {
                            TagPillView(tag: tag)
                            Spacer()
                            Image(systemName: "plus")
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct TagColorLabel: View {
    let color: TagColor

    var body: some View {
        HStack {
            Circle()
                .fill(color.foregroundColor)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(color.rawValue.capitalized)
        }
    }
}
