import SwiftUI

// MARK: - Guide Identity

struct FeatureGuide: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let category: GuideCategory
    let sections: [GuideSection]

    var completionKey: String { "guide_completed_\(id)" }
}

enum GuideCategory: String, CaseIterable {
    case essentials = "Essentials"
    case features = "Features"
    case advanced = "Advanced"

    var sortOrder: Int {
        switch self {
        case .essentials: return 0
        case .features: return 1
        case .advanced: return 2
        }
    }
}

// MARK: - Guide Sections

struct GuideSection: Identifiable {
    let id = UUID()
    let content: GuideSectionContent
}

enum GuideSectionContent {
    /// Large animated hero with icon and text
    case hero(icon: String, iconColor: Color, title: String, subtitle: String)

    /// Narrative paragraph
    case narrative(String)

    /// Section divider with title
    case sectionHeader(String)

    /// Feature highlight card
    case feature(icon: String, color: Color, title: String, description: String)

    /// Grid of feature items
    case featureGrid([FeatureGridItem])

    /// Numbered walkthrough steps
    case steps([GuideStep])

    /// Pro tip callout
    case tip(icon: String, text: String)

    /// Interactive set logger demo
    case demoSetLogger

    /// Interactive recovery signals demo
    case demoRecoverySignals

    /// Interactive chart type switcher demo
    case demoChartSwitcher

    /// Interactive health category explorer
    case demoHealthCategories

    /// Interactive time range selector demo
    case demoTimeRange

    /// Interactive session bar demo
    case demoSessionBar

    /// Visual mockup of a feature with labeled callouts
    case annotatedMockup(AnnotatedMockup)
}

struct FeatureGridItem: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let description: String
}

struct GuideStep: Identifiable {
    let id = UUID()
    let number: Int
    let icon: String
    let title: String
    let description: String
}

struct AnnotatedMockup: Identifiable {
    let id = UUID()
    let title: String
    let items: [MockupCallout]
}

struct MockupCallout: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let label: String
    let detail: String
}
