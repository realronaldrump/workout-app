import SwiftUI

struct MultiSelectSheet<Item: Hashable & Identifiable>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let items: [Item]
    @Binding var selectedItems: Set<Item>? // nil means all selected
    let itemTitle: (Item) -> String
    let itemSubtitle: ((Item) -> String)?

    @State private var localSelection: Set<Item>

    init(
        title: String,
        items: [Item],
        selectedItems: Binding<Set<Item>?>,
        itemTitle: @escaping (Item) -> String,
        itemSubtitle: ((Item) -> String)? = nil
    ) {
        self.title = title
        self.items = items
        self._selectedItems = selectedItems
        self.itemTitle = itemTitle
        self.itemSubtitle = itemSubtitle
        self._localSelection = State(initialValue: selectedItems.wrappedValue ?? Set(items))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                VStack(spacing: 0) {
                    ExportSelectionToolbar(
                        selectedCount: localSelection.count,
                        totalCount: items.count,
                        onSelectAll: { localSelection = Set(items) },
                        onClear: { localSelection.removeAll() }
                    )
                    .padding(.horizontal, Theme.Layout.screenGutter)
                    .padding(.vertical, Theme.Spacing.sm)

                    List {
                        ForEach(items) { item in
                            Button {
                                if localSelection.contains(item) {
                                    localSelection.remove(item)
                                } else {
                                    localSelection.insert(item)
                                }
                                Haptics.selection()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(itemTitle(item))
                                            .font(Theme.Typography.bodyBold)
                                            .foregroundStyle(Theme.Colors.textPrimary)
                                        if let subtitle = itemSubtitle?(item) {
                                            Text(subtitle)
                                                .font(Theme.Typography.caption)
                                                .foregroundStyle(Theme.Colors.textSecondary)
                                        }
                                    }
                                    Spacer()
                                    if localSelection.contains(item) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Theme.Colors.accent)
                                            .font(Theme.Iconography.title3)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(Theme.Colors.textTertiary)
                                            .font(Theme.Iconography.title3)
                                    }
                                }
                                .padding(.vertical, Theme.Spacing.xs)
                            }
                            .buttonStyle(PressableCardButtonStyle())
                            .accessibilityAddTraits(localSelection.contains(item) ? .isSelected : [])
                            .loadedListRow()
                        }
                    }
                    .loadedListStyle()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppToolbarItem(placement: .cancellationAction) {
                    AppToolbarButton(title: "Cancel", systemImage: "xmark", variant: .subtle) {
                        dismiss()
                    }
                }
                AppToolbarItem(placement: .confirmationAction) {
                    AppToolbarButton(title: "Done", systemImage: "checkmark", variant: .accent) {
                        if localSelection.count == items.count {
                            selectedItems = nil // All selected
                        } else {
                            selectedItems = localSelection
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
