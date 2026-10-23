import SwiftUI

struct HealthPermissionAuditView: View {
    @Environment(\.openURL) private var openURL
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
                .contentColumn()
            }
        }
        .navigationTitle("Health permissions")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAudit()
        }
        .refreshable {
            await loadAudit()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeading(
                title: "Health access",
                help: "Apple reports whether an access decision was recorded, not whether each read permission is on. "
                    + "If readings are missing, review access here, then check the toggles in Apple Health."
            )

            AppPrimaryButton(
                title: isRequestingAuthorization ? "Checking access…" : "Review Health access",
                systemImage: isRequestingAuthorization ? nil : "heart.text.square.fill",
                isEnabled: !isRequestingAuthorization && healthManager.authorizationStatus != .unavailable
            ) {
                requestAuthorization()
            }

            if isRequestingAuthorization {
                ProgressView("Waiting for Apple Health…")
                    .font(Theme.Typography.caption)
            }

            Button("Open Settings", systemImage: "gear") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
            .frame(minHeight: Theme.Layout.minimumTapTarget)

        }
        .padding(Theme.Spacing.lg)
        .softCard()
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Summary")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.md) {
                    summaryMetrics
                }

                VStack(spacing: Theme.Spacing.md) {
                    summaryMetrics
                }
            }

        }
        .padding(Theme.Spacing.lg)
        .softCard()
    }

    @ViewBuilder
    private var summaryMetrics: some View {
        summaryMetric(
            title: "Requested",
            value: "\(totalRequestedCount)",
            tint: Theme.Colors.accent
        )

        summaryMetric(
            title: "Needs review",
            value: "\(needsReviewCount)",
            tint: needsReviewCount == 0 ? Theme.Colors.success : Theme.Colors.warning
        )
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
                .foregroundStyle(statusColor(for: item.status))
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)

            }

            AppHelpButton(title: item.title, message: item.summary)
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
            return "Needs review"
        case .decisionRecorded:
            return "Recorded"
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
                actionMessage = "Review complete. Check any items still marked Needs review."
            } catch {
                let message = error.localizedDescription
                await loadAudit()
                errorMessage = message
            }
        }
    }
}
