import SwiftUI

struct WorkoutLogPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let text: String
    let totalLines: Int

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    ScreenHeader(title: "Your training, condensed.", subtitle: totalLines > 60
                        ? "First 60 of \(totalLines.formatted()) lines. Copy and export include the complete log."
                        : "The complete log. Exercise references and repeated sets keep it compact.")
                    ScrollView(.horizontal) {
                        Text(text)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: true)
                            .padding(Theme.Spacing.md)
                    }
                    .background(Theme.Colors.panelInset, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                }
                .padding(Theme.Layout.screenGutter)
                .contentColumn()
            }
            .background(AdaptiveBackground())
            .navigationTitle("AI log preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppToolbarItem(placement: .confirmationAction) {
                    AppToolbarButton(title: "Done", systemImage: "checkmark", variant: .accent) { dismiss() }
                }
            }
        }
    }
}

/// Purpose-first format choices. The AI log gets a full row; the four conventional
/// formats share a grid that becomes a list at larger accessibility text sizes.
struct ExportFormatPicker: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selection: WorkoutExportFormat

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            option(.llm, detail: "For AI coaching and analysis")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: Theme.Spacing.sm) {
                option(.csv, detail: "Spreadsheets")
                option(.json, detail: "Structured data")
                option(.report, detail: "Browser journal")
                option(.pdf, detail: "Charts & journal")
            }
        }
    }

    private func option(_ format: WorkoutExportFormat, detail: String) -> some View {
        let selected = selection == format
        return Button {
            guard !selected else { return }
            selection = format
            Haptics.selection()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(format == .llm ? "AI training log" : format.title)
                        .font(Theme.Typography.headline)
                    Text(detail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(selected ? Theme.Colors.onAccent.opacity(0.8) : Theme.Colors.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : format.systemImage)
                    .font(Theme.Iconography.medium)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(selected ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(selected ? Theme.Colors.ink : Theme.Colors.panel, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .contentShape(.rect)
        }
        .buttonStyle(AppInteractionButtonStyle())
        .accessibilityLabel(format == .llm ? "AI training log" : format.title)
        .accessibilityValue(detail)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("export-format-\(format.rawValue)")
    }
}
