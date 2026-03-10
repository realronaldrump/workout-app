import SwiftUI

struct HealthPermissionAuditView: View {
    @EnvironmentObject private var healthManager: HealthKitManager

    @State private var sections: [HealthPermissionAuditSection] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionMessage: String?
    @State private var isRequestingAuthorization = false

    private var totalRequestedCount: Int {
        sections.reduce(into: 0) { partialResult, section in
            partialResult += section.items.count
        }
    }

    private var needsReviewCount: Int {
        sections.reduce(into: 0) { partialResult, section in
            partialResult += section.items.filter { $0.status == .needsReview }.count
        }
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    headerCard

                    if let actionMessage {
                        statusMessageCard(
                            message: actionMessage,
                            tint: Theme.Colors.success
                        )
                    }

                    if let errorMessage {
                        statusMessageCard(
                            message: errorMessage,
                            tint: Theme.Colors.error
                        )
                    }

                    if isLoading {
                        loadingCard
                    } else {
                        summaryCard

                        ForEach(sections) { section in
                            permissionSectionCard(section)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.xl)
            }
        }
        .navigationTitle("Health Permissions")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAudit()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Per-Type Health Access")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(
                "Apple lets apps see whether a read permission still needs an authorization prompt, " +
                "but not whether a specific read type is currently granted or denied. " +
                "Use this screen to catch newly added Health types after app updates, then confirm final toggles in Health."
            )
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Button(action: requestAuthorization) {
                HStack(spacing: Theme.Spacing.sm) {
                    if isRequestingAuthorization {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "heart.text.square.fill")
                    }

                    Text(isRequestingAuthorization ? "Checking Permissions..." : "Request Health Access Again")
                        .font(Theme.Typography.bodyBold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            }
            .buttonStyle(.plain)
            .disabled(isRequestingAuthorization || healthManager.authorizationStatus == .unavailable)

            Text("Health app verification path: open the Health app and review this app under its data-access screen.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.lg)
        .softCard()
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Summary")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)

            HStack(spacing: Theme.Spacing.md) {
                summaryMetric(
                    title: "Requested",
                    value: "\(totalRequestedCount)",
                    tint: Theme.Colors.accent
                )

                summaryMetric(
                    title: "Needs Review",
                    value: "\(needsReviewCount)",
                    tint: needsReviewCount == 0 ? Theme.Colors.success : Theme.Colors.warning
                )
            }

            Text(
                needsReviewCount == 0
                    ? "No newly added Health types currently require the authorization sheet."
                    : "\(needsReviewCount) type\(needsReviewCount == 1 ? "" : "s") still need review in the authorization flow or Health app."
            )
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.lg)
        .softCard()
    }

    private func summaryMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(Theme.Colors.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .strokeBorder(Theme.Colors.border.opacity(0.45), lineWidth: 1)
        )
    }

    private func permissionSectionCard(_ section: HealthPermissionAuditSection) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(section.title)
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)

            VStack(spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    permissionRow(item)

                    if index < section.items.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
            .softCard(elevation: 1)
        }
    }

    private func permissionRow(_ item: HealthPermissionAuditItem) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: statusIcon(for: item.status))
                .font(Theme.Typography.subheadlineStrong)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(statusColor(for: item.status))
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(item.summary)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Spacing.sm)

            Text(statusTitle(for: item.status))
                .font(Theme.Typography.captionBold)
                .foregroundStyle(statusColor(for: item.status))
                .multilineTextAlignment(.trailing)
        }
        .padding()
    }

    private var loadingCard: some View {
        HStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(Theme.Colors.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Checking Health permissions...")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Reviewing each requested HealthKit type.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .softCard()
    }

    private func statusMessageCard(message: String, tint: Color) -> some View {
        Text(message)
            .font(Theme.Typography.caption)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(tint.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            )
    }

    private func statusTitle(for status: HealthPermissionAuditItem.Status) -> String {
        switch status {
        case .needsReview:
            return "Needs Review"
        case .decisionRecorded:
            return "Decision Recorded"
        case .unavailable:
            return "Unavailable"
        }
    }

    private func statusIcon(for status: HealthPermissionAuditItem.Status) -> String {
        switch status {
        case .needsReview:
            return "exclamationmark.triangle.fill"
        case .decisionRecorded:
            return "checkmark.circle.fill"
        case .unavailable:
            return "slash.circle.fill"
        }
    }

    private func statusColor(for status: HealthPermissionAuditItem.Status) -> Color {
        switch status {
        case .needsReview:
            return Theme.Colors.warning
        case .decisionRecorded:
            return Theme.Colors.success
        case .unavailable:
            return Theme.Colors.textTertiary
        }
    }

    private func loadAudit() async {
        isLoading = true
        errorMessage = nil
        actionMessage = nil
        sections = await healthManager.permissionAuditSections()
        isLoading = false
    }

    private func requestAuthorization() {
        actionMessage = nil
        errorMessage = nil
        isRequestingAuthorization = true

        Task {
            defer { isRequestingAuthorization = false }

            do {
                try await healthManager.requestAuthorization()
                await loadAudit()
                actionMessage = "Health authorization flow completed. Review any remaining items marked Needs Review."
            } catch {
                errorMessage = error.localizedDescription
                await loadAudit()
            }
        }
    }
}
