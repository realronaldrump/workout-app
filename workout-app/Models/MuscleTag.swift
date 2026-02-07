import Foundation
import SwiftUI

/// A muscle tag can be one of the built-in `MuscleGroup`s, or a user-defined custom label.
///
/// Persisted in UserDefaults via `Codable` so it must remain stable across versions.
struct MuscleTag: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case builtIn
        case custom
    }

    let kind: Kind
    /// For `.builtIn`, this is `MuscleGroup.rawValue`. For `.custom`, this is the user-visible label.
    let value: String

    var id: String { "\(kind.rawValue):\(normalizedValue)" }

    private var normalizedValue: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func builtIn(_ group: MuscleGroup) -> MuscleTag {
        MuscleTag(kind: .builtIn, value: group.rawValue)
    }

    static func custom(_ name: String) -> MuscleTag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Collapse repeated whitespace so "Rear   Delts" and "Rear Delts" normalize the same.
        let collapsed = trimmed.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        return MuscleTag(kind: .custom, value: collapsed)
    }

    var builtInGroup: MuscleGroup? {
        guard kind == .builtIn else { return nil }
        return MuscleGroup(rawValue: value)
    }

    var displayName: String {
        if let group = builtInGroup { return group.displayName }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var shortName: String {
        if let group = builtInGroup { return group.shortName }
        return displayName
    }

    var iconName: String {
        if let group = builtInGroup { return group.iconName }
        return "tag.fill"
    }

    var tint: Color {
        if let group = builtInGroup { return group.color }
        return Theme.Colors.accentSecondary
    }
}
