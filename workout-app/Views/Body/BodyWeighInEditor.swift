import SwiftUI

enum BodyWeighInRequest: Identifiable {
    case new
    case edit(BodyRawSample)

    var id: String { reading?.id.uuidString ?? "new" }

    var reading: BodyRawSample? {
        if case .edit(let sample) = self { return sample }
        return nil
    }
}

struct BodyWeighInEditor: View {
    let request: BodyWeighInRequest
    var onSave: (Date) -> Void

    @EnvironmentObject private var store: BodyStore
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var timestamp: Date
    @State private var errorMessage: String?
    @State private var confirmingRemoval = false
    @FocusState private var weightFocused: Bool

    init(request: BodyWeighInRequest, onSave: @escaping (Date) -> Void = { _ in }) {
        self.request = request
        self.onSave = onSave
        _text = State(initialValue: Self.initialWeight(request.reading))
        _timestamp = State(initialValue: request.reading?.timestamp ?? Date())
    }

    private var savedEntry: BodyWeighIn? {
        request.reading.flatMap { store.savedWeighIn(id: $0.id) }
    }

    private var isHealthCorrection: Bool {
        savedEntry?.isHealthCorrection ?? (request.reading != nil)
    }

    private var pounds: Double? {
        if let reading = request.reading, text == Self.initialWeight(reading) {
            return reading.value
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")),
              BodyTrendEngine.isPlausible(value, kind: .weight) else { return nil }
        return value
    }

    private var removalTitle: String {
        isHealthCorrection ? "Restore Apple Health reading" : "Delete weigh-in"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Weight", text: $text)
                            .keyboardType(.decimalPad)
                            .font(Theme.Typography.title3)
                            .focused($weightFocused)
                            .accessibilityLabel("Weight in pounds")
                            .accessibilityIdentifier("body-weigh-in-value")
                        Text("lb")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    DatePicker("Date and time", selection: $timestamp, in: ...Date())
                        .accessibilityIdentifier("body-weigh-in-date")
                } footer: {
                    if isHealthCorrection {
                        Text("This correction applies in your workout app.")
                    }
                }

                if !text.isEmpty, pounds == nil {
                    Text("Enter a weight between 20 and 1,000 lb.")
                        .foregroundStyle(.secondary)
                }

                if let savedEntry {
                    Button(removalTitle, role: .destructive) {
                        confirmingRemoval = true
                    }
                    .confirmationDialog(removalTitle, isPresented: $confirmingRemoval, titleVisibility: .visible) {
                        Button(removalTitle, role: .destructive) { remove(savedEntry) }
                    }
                }
            }
            .navigationTitle(request.reading == nil ? "Log weight" : "Edit weigh-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppToolbarItem(placement: .cancellationAction) {
                    AppToolbarButton(title: "Cancel", systemImage: "xmark", variant: .subtle) { dismiss() }
                }
                AppToolbarItem(placement: .confirmationAction) {
                    AppToolbarButton(title: "Save", systemImage: "checkmark", variant: .accent, action: save)
                        .disabled(pounds == nil)
                        .accessibilityIdentifier("body-save-weigh-in")
                }
            }
            .alert("Couldn’t update the weigh-in", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                if request.reading == nil { weightFocused = true }
            }
        }
    }

    private static func initialWeight(_ reading: BodyRawSample?) -> String {
        reading?.value.formatted(.number.grouping(.never).precision(.fractionLength(0...3))) ?? ""
    }

    private func save() {
        guard let pounds else { return }
        do {
            try store.saveWeighIn(pounds: pounds, at: timestamp, editing: request.reading)
            onSave(timestamp)
            Haptics.notify(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ entry: BodyWeighIn) {
        do {
            try store.removeWeighIn(id: entry.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
