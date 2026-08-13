import Foundation
import SwiftUI

/// A muscle tag can be one of the built-in `MuscleGroup`s, or a user-defined custom label.
///
/// Persisted in UserDefaults via `Codable` so it must remain stable across versions.
nonisolated struct MuscleTag: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
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

    @MainActor var shortName: String {
        if let group = builtInGroup { return group.shortName }
        return displayName
    }

    @MainActor var iconName: String {
        if let group = builtInGroup { return group.iconName }
        return "tag.fill"
    }

    @MainActor var tint: Color {
        if let group = builtInGroup { return group.color }
        return Theme.Colors.accentSecondary
    }
}

/// The role a muscle plays in an exercise. Role is intentionally categorical instead of
/// user-tunable so analytics remain understandable and comparable across the app.
nonisolated enum ExerciseMuscleRole: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case primary
    case secondary

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .primary: return "Primary"
        case .secondary: return "Secondary"
        }
    }

    var contributionWeight: Double {
        switch self {
        case .primary: return 1
        case .secondary: return 0.5
        }
    }
}

/// A role-aware muscle assignment for one exercise. Identity follows the underlying tag so
/// changing a role replaces the existing assignment instead of creating a duplicate muscle.
nonisolated struct ExerciseMuscleAssignment: Identifiable, Codable, Hashable, Sendable {
    let tag: MuscleTag
    let role: ExerciseMuscleRole

    var id: String { tag.id }
    var contributionWeight: Double { role.contributionWeight }

    static func primary(_ tag: MuscleTag) -> ExerciseMuscleAssignment {
        ExerciseMuscleAssignment(tag: tag, role: .primary)
    }

    static func secondary(_ tag: MuscleTag) -> ExerciseMuscleAssignment {
        ExerciseMuscleAssignment(tag: tag, role: .secondary)
    }
}

/// Shared policy for every quantitative muscle surface. A primary set counts as one effective
/// set and a secondary set counts as half an effective set.
nonisolated enum MuscleContributionPolicy {
    static func effectiveSets(
        setCount: Int,
        assignment: ExerciseMuscleAssignment
    ) -> Double {
        Double(max(setCount, 0)) * assignment.contributionWeight
    }

    static func exportDescription(_ assignments: [ExerciseMuscleAssignment]) -> String {
        let primary = assignments
            .filter { $0.role == .primary }
            .map(\.tag.displayName)
        let secondary = assignments
            .filter { $0.role == .secondary }
            .map(\.tag.displayName)

        var parts: [String] = []
        if !primary.isEmpty {
            parts.append("Primary: \(primary.joined(separator: ", "))")
        }
        if !secondary.isEmpty {
            parts.append("Secondary: \(secondary.joined(separator: ", "))")
        }
        return parts.joined(separator: "; ")
    }

    static func formattedEffectiveSets(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
