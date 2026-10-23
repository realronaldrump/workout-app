import SwiftUI

/// Optional context stays behind a tap instead of occupying the main screen.
struct AppHelpButton: View {
    let title: String
    let message: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(title)")
        .accessibilityIdentifier("app-help-\(title)")
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(Theme.Typography.title3)
                    .accessibilityAddTraits(.isHeader)
                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView {
                        Text(message)
                            .font(Theme.Typography.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text(message)
                        .font(Theme.Typography.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button("Done") { isPresented = false }
                        .font(Theme.Typography.headline)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("app-help-close")
                }
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(20)
            .presentationBackground(Theme.Colors.elevated)
            .frame(idealWidth: 300, maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 340)
            .presentationCompactAdaptation(dynamicTypeSize.isAccessibilitySize ? .sheet : .popover)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("app-help-content")
        }
    }
}
