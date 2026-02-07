import SwiftUI

struct CollapsibleSection<Content: View>: View {
    let title: String
    var subtitle: String?
    @Binding var isExpanded: Bool
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        subtitle: String? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Button(action: toggle) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Theme.Typography.sectionHeader)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .tracking(1.0)

                        if let subtitle {
                            Text(subtitle)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.9), value: isExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeInOut(duration: 0.25), value: isExpanded)
    }

    private func toggle() {
        Haptics.selection()
        isExpanded.toggle()
    }
}
