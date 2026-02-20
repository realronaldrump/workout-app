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
                    HStack {
                        Button("Select All") {
                            localSelection = Set(items)
                        }
                        .foregroundStyle(Theme.Colors.accent)
                        .font(Theme.Typography.captionBold)

                        Spacer()

                        Button("Deselect All") {
                            localSelection.removeAll()
                        }
                        .foregroundStyle(Theme.Colors.accent)
                        .font(Theme.Typography.captionBold)
                    }
                    .padding()
                    .background(Theme.Colors.elevated)

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
                                            .font(.title3)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(Theme.Colors.textTertiary)
                                            .font(.title3)
                                    }
                                }
                                .padding(.vertical, Theme.Spacing.xs)
                            }
                            .listRowBackground(Theme.Colors.elevated)
                            .listRowSeparatorTint(Theme.Colors.border)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if localSelection.count == items.count {
                            selectedItems = nil // All selected
                        } else {
                            selectedItems = localSelection
                        }
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.accent)
                    .font(.headline)
                }
            }
        }
    }
}
