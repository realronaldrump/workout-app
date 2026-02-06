import SwiftUI

struct InsightCardView: View {
    let insight: Insight
    var onTap: (() -> Void)? = nil
    
    @State private var isAppearing = false
    
    private var iconColor: Color {
        switch insight.type.color {
        case "yellow": return Theme.Colors.gold
        case "green": return Theme.Colors.success
        case "orange": return Theme.Colors.warning
        case "purple": return Theme.Colors.accentTertiary
        case "blue": return Theme.Colors.accent
        case "cyan": return Theme.Colors.cardio
        case "red": return Theme.Colors.error
        default: return Theme.Colors.accent
        }
    }
    
    var body: some View {
        Button(action: {
            Haptics.selection()
            onTap?()
        }) {
            HStack(spacing: Theme.Spacing.lg) {
                // Icon
                Image(systemName: insight.type.iconName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 44, height: 44)
                
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(insight.title)
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)
                    
                    Text(insight.message)
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                if insight.actionLabel != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 2)
        }
        .buttonStyle(ScaleButtonStyle())
        .opacity(isAppearing ? 1 : 0)
        .offset(y: isAppearing ? 0 : 10)
        .onAppear {
            withAnimation(Theme.Animation.spring) {
                isAppearing = true
            }
        }
    }
}

// Subtle scale effect on press
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Insights Section View

struct InsightsSectionView: View {
    @ObservedObject var insightsEngine: InsightsEngine
    let dataManager: WorkoutDataManager
    var onInsightTap: ((Insight) -> Void)? = nil
    
    @State private var showAllInsights = false
    
    private var displayedInsights: [Insight] {
        if showAllInsights {
            return insightsEngine.insights
        } else {
            return Array(insightsEngine.insights.prefix(3))
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Text("Insights")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)
                
                Spacer()
                
                if insightsEngine.insights.count > 3 {
                    Button(action: { 
                        withAnimation(Theme.Animation.spring) {
                            showAllInsights.toggle() 
                        }
                    }) {
                        Text(showAllInsights ? "Less" : "All \(insightsEngine.insights.count)")
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.accent)
                    }
                }
            }
            
            if insightsEngine.insights.isEmpty {
                EmptyInsightsView()
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(Array(displayedInsights.enumerated()), id: \.element.id) { index, insight in
                        InsightCardView(insight: insight) {
                            onInsightTap?(insight)
                        }
                    }
                }
            }
        }
        .onAppear {
            Task {
                await insightsEngine.generateInsights()
            }
        }
    }
}

struct EmptyInsightsView: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundColor(Theme.Colors.textTertiary)
            
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("insights 0")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textSecondary)
                
                Text("min sessions 4")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            
            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .softCard()
    }
}

#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        
        ScrollView {
            VStack(spacing: 20) {
                InsightCardView(insight: Insight(
                    id: UUID(),
                    type: .personalRecord,
                    title: "PR",
                    message: "Bench Press 225 lbs | delta +10",
                    exerciseName: "Bench Press",
                    date: Date(),
                    priority: 10,
                    actionLabel: "Trend",
                    metric: 225
                ))
                
                InsightCardView(insight: Insight(
                    id: UUID(),
                    type: .plateau,
                    title: "Plateau",
                    message: "Shoulder Press max 50 lbs | delta 0 | n=4",
                    exerciseName: "Shoulder Press",
                    date: Date(),
                    priority: 6,
                    actionLabel: "History",
                    metric: 50
                ))
            }
            .padding()
        }
    }
    .preferredColorScheme(.dark)
}
