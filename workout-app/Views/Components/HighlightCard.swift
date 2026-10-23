import SwiftUI

struct HighlightItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let subtitle: String?
    let icon: String
    let tint: Color
    let action: (() -> Void)?
    var isRecord = false
}

/// One noteworthy result, written as a log line: what happened, when, and a stamp
/// when it was a personal record.
struct HighlightCardView: View {
    let item: HighlightItem
    var showsRule = true

    var body: some View {
        Group {
            if let action = item.action {
                Button(
                    action: {
                        Haptics.selection()
                        action()
                    },
                    label: {
                        content
                    }
                )
                .buttonStyle(PressableCardButtonStyle())
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Theme.Spacing.sm) {
                    if item.isRecord {
                        PRTag()
                    } else {
                        TagLabel(text: item.title, tint: item.tint)
                    }
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }

                Text(item.value)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Spacing.sm)

            if item.action != nil {
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }
        }
        .ledgerRow(showsRule: showsRule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title): \(item.value)\(item.subtitle.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(item.action != nil ? .isButton : [])
        .accessibilityHint(item.action != nil ? "Opens details" : "")
    }
}

struct HighlightsSectionView: View {
    let title: String
    let items: [HighlightItem]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeading(title: title)

            if items.isEmpty {
                EmptyHighlightsView()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HighlightCardView(item: item, showsRule: true)
                            .overlay(alignment: .bottom) {
                                if index == items.count - 1 {
                                    Rectangle().fill(Theme.Colors.rule).frame(height: 1)
                                        .accessibilityHidden(true)
                                }
                            }
                    }
                }
            }
        }
    }
}

struct EmptyHighlightsView: View {
    var body: some View {
        Text("Records and big jumps show up here after a few sessions.")
            .font(Theme.Typography.subheadline)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .ledgerRow()
    }
}
