import Foundation
import HealthKit

struct HealthPermissionAuditSection: Identifiable, Sendable {
    let title: String
    let items: [HealthPermissionAuditItem]

    var id: String { title }
}

struct HealthPermissionAuditItem: Identifiable, Sendable {
    enum Status: String, Sendable {
        case needsReview
        case decisionRecorded
        case unavailable
    }

    let id: String
    let title: String
    let summary: String
    let status: Status
}

extension HealthKitManager {
    func permissionAuditSections() async -> [HealthPermissionAuditSection] {
        let descriptors = permissionAuditDescriptors()
        guard let healthStore else {
            return groupedPermissionAuditSections(
                from: descriptors.map { descriptor in
                    HealthPermissionAuditItem(
                        id: descriptor.id,
                        title: descriptor.title,
                        summary: descriptor.summary,
                        status: .unavailable
                    )
                },
                using: descriptors
            )
        }

        var itemsByID: [String: HealthPermissionAuditItem] = [:]
        itemsByID.reserveCapacity(descriptors.count)

        for descriptor in descriptors {
            let status = await permissionAuditStatus(
                for: descriptor,
                healthStore: healthStore
            )
            itemsByID[descriptor.id] = HealthPermissionAuditItem(
                id: descriptor.id,
                title: descriptor.title,
                summary: descriptor.summary,
                status: status
            )
        }

        return groupedPermissionAuditSections(
            from: descriptors.compactMap { itemsByID[$0.id] },
            using: descriptors
        )
    }

    private func permissionAuditStatus(
        for descriptor: PermissionAuditDescriptor,
        healthStore: HKHealthStore
    ) async -> HealthPermissionAuditItem.Status {
        guard let objectType = descriptor.makeType() else {
            return .unavailable
        }

        let readTypes = Self.normalizedAuthorizationReadTypes(for: [objectType])
        let (status, error): (HKAuthorizationRequestStatus, Error?) = await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(
                toShare: [],
                read: readTypes
            ) { status, error in
                continuation.resume(returning: (status, error))
            }
        }

        if error != nil {
            return .unavailable
        }

        switch status {
        case .shouldRequest:
            return .needsReview
        case .unnecessary, .unknown:
            // HealthKit does not expose read-granted vs read-denied per type.
            // "Decision recorded" only means iOS no longer needs to present the auth prompt.
            return .decisionRecorded
        @unknown default:
            return .unavailable
        }
    }

    private func groupedPermissionAuditSections(
        from items: [HealthPermissionAuditItem],
        using descriptors: [PermissionAuditDescriptor]
    ) -> [HealthPermissionAuditSection] {
        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let groupedDescriptors = Dictionary(grouping: descriptors, by: \.section)

        return permissionAuditSectionOrder.compactMap { section in
            guard let sectionDescriptors = groupedDescriptors[section] else { return nil }

            let sectionItems = sectionDescriptors.compactMap { itemsByID[$0.id] }
            guard !sectionItems.isEmpty else { return nil }

            let sortedItems = sectionItems.sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    return lhs.status == .needsReview
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

            return HealthPermissionAuditSection(title: section, items: sortedItems)
        }
    }

    private var permissionAuditSectionOrder: [String] {
        [
            "Workout",
            "Activity",
            "Cardio",
            "Vitals",
            "Body",
            "Recovery",
            "Events"
        ]
    }

    private func permissionAuditDescriptors() -> [PermissionAuditDescriptor] {
        [
            PermissionAuditDescriptor(
                id: "workouts",
                title: "Workouts",
                summary: "Workout sessions from Apple Health.",
                section: "Workout",
                makeType: { HKObjectType.workoutType() }
            ),
            PermissionAuditDescriptor(
                id: "workoutRoute",
                title: "Workout Routes",
                summary: "Location series attached to supported workouts.",
                section: "Workout",
                makeType: { HKSeriesType.workoutRoute() }
            ),
            PermissionAuditDescriptor(
                id: "activitySummary",
                title: "Activity Summary",
                summary: "Move, exercise, and stand ring totals.",
                section: "Activity",
                makeType: { HKObjectType.activitySummaryType() }
            ),
            quantityDescriptor(.stepCount, title: "Step Count", summary: "Daily steps.", section: "Activity"),
            quantityDescriptor(.distanceWalkingRunning, title: "Walking + Running Distance", summary: "Distance covered on foot.", section: "Activity"),
            quantityDescriptor(.distanceCycling, title: "Cycling Distance", summary: "Distance covered by bike rides.", section: "Activity"),
            quantityDescriptor(.flightsClimbed, title: "Flights Climbed", summary: "Stair climbing totals.", section: "Activity"),
            quantityDescriptor(.appleExerciseTime, title: "Exercise Time", summary: "Apple Exercise ring minutes.", section: "Activity"),
            quantityDescriptor(.appleMoveTime, title: "Move Time", summary: "Apple Move ring minutes.", section: "Activity"),
            quantityDescriptor(.appleStandTime, title: "Stand Time", summary: "Time spent standing.", section: "Activity"),
            categoryDescriptor(.appleStandHour, title: "Stand Hours", summary: "Stand-hour events.", section: "Activity"),
            quantityDescriptor(.heartRate, title: "Heart Rate", summary: "Measured beats per minute.", section: "Cardio"),
            quantityDescriptor(.restingHeartRate, title: "Resting Heart Rate", summary: "Resting heart rate samples.", section: "Cardio"),
            quantityDescriptor(.walkingHeartRateAverage, title: "Walking Heart Rate Average", summary: "Average heart rate while walking.", section: "Cardio"),
            quantityDescriptor(.heartRateVariabilitySDNN, title: "Heart Rate Variability", summary: "HRV (SDNN) samples.", section: "Recovery"),
            quantityDescriptor(.heartRateRecoveryOneMinute, title: "Heart Rate Recovery", summary: "One-minute recovery samples.", section: "Recovery"),
            quantityDescriptor(.activeEnergyBurned, title: "Active Energy Burned", summary: "Active calories.", section: "Activity"),
            quantityDescriptor(.basalEnergyBurned, title: "Basal Energy Burned", summary: "Resting calories.", section: "Activity"),
            quantityDescriptor(.runningSpeed, title: "Running Speed", summary: "Running pace and speed samples.", section: "Workout"),
            quantityDescriptor(.runningPower, title: "Running Power", summary: "Running power samples.", section: "Workout"),
            quantityDescriptor(.cyclingSpeed, title: "Cycling Speed", summary: "Cycling speed samples.", section: "Workout"),
            quantityDescriptor(.cyclingPower, title: "Cycling Power", summary: "Cycling power samples.", section: "Workout"),
            quantityDescriptor(.runningStrideLength, title: "Running Stride Length", summary: "Stride length during runs.", section: "Workout"),
            quantityDescriptor(.runningGroundContactTime, title: "Ground Contact Time", summary: "Ground contact during runs.", section: "Workout"),
            quantityDescriptor(.runningVerticalOscillation, title: "Vertical Oscillation", summary: "Vertical movement during runs.", section: "Workout"),
            quantityDescriptor(.oxygenSaturation, title: "Oxygen Saturation", summary: "Blood oxygen readings.", section: "Vitals"),
            quantityDescriptor(.respiratoryRate, title: "Respiratory Rate", summary: "Breaths per minute.", section: "Vitals"),
            quantityDescriptor(.bodyTemperature, title: "Body Temperature", summary: "Body temperature readings.", section: "Vitals"),
            quantityDescriptor(.bodyMass, title: "Body Mass", summary: "Weight measurements.", section: "Body"),
            quantityDescriptor(.bodyFatPercentage, title: "Body Fat Percentage", summary: "Body fat measurements.", section: "Body"),
            quantityDescriptor(.leanBodyMass, title: "Lean Body Mass", summary: "Lean mass measurements.", section: "Body"),
            quantityDescriptor(.bodyMassIndex, title: "Body Mass Index", summary: "BMI measurements.", section: "Body"),
            quantityDescriptor(.vo2Max, title: "VO2 Max", summary: "Cardio fitness estimates.", section: "Cardio"),
            quantityDescriptor(.walkingSpeed, title: "Walking Speed", summary: "Walking pace samples.", section: "Activity"),
            quantityDescriptor(.walkingStepLength, title: "Walking Step Length", summary: "Stride length while walking.", section: "Activity"),
            quantityDescriptor(.walkingAsymmetryPercentage, title: "Walking Asymmetry", summary: "Asymmetry percentage while walking.", section: "Activity"),
            quantityDescriptor(.walkingDoubleSupportPercentage, title: "Walking Double Support", summary: "Double-support percentage while walking.", section: "Activity"),
            quantityDescriptor(.stairAscentSpeed, title: "Stair Ascent Speed", summary: "Upstairs speed samples.", section: "Activity"),
            quantityDescriptor(.stairDescentSpeed, title: "Stair Descent Speed", summary: "Downstairs speed samples.", section: "Activity"),
            categoryDescriptor(.sleepAnalysis, title: "Sleep Analysis", summary: "Sleep stage and duration data.", section: "Recovery"),
            categoryDescriptor(.lowHeartRateEvent, title: "Low Heart Rate Events", summary: "Low heart-rate notifications.", section: "Events"),
            categoryDescriptor(.highHeartRateEvent, title: "High Heart Rate Events", summary: "High heart-rate notifications.", section: "Events"),
            categoryDescriptor(.irregularHeartRhythmEvent, title: "Irregular Rhythm Events", summary: "Irregular rhythm notifications.", section: "Events")
        ]
    }

    private func quantityDescriptor(
        _ identifier: HKQuantityTypeIdentifier,
        title: String,
        summary: String,
        section: String
    ) -> PermissionAuditDescriptor {
        PermissionAuditDescriptor(
            id: identifier.rawValue,
            title: title,
            summary: summary,
            section: section,
            makeType: { HKQuantityType.quantityType(forIdentifier: identifier) }
        )
    }

    private func categoryDescriptor(
        _ identifier: HKCategoryTypeIdentifier,
        title: String,
        summary: String,
        section: String
    ) -> PermissionAuditDescriptor {
        PermissionAuditDescriptor(
            id: identifier.rawValue,
            title: title,
            summary: summary,
            section: section,
            makeType: { HKCategoryType.categoryType(forIdentifier: identifier) }
        )
    }
}

private struct PermissionAuditDescriptor {
    let id: String
    let title: String
    let summary: String
    let section: String
    let makeType: () -> HKObjectType?
}
