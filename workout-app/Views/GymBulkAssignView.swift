import SwiftUI
import HealthKit
import CoreLocation
// swiftlint:disable type_body_length file_length

private struct AutoTagMapFallbackCandidate: Identifiable {
    let workoutId: UUID
    let workoutName: String
    let workoutDate: Date
    let startCoordinate: CLLocationCoordinate2D?

    var id: UUID { workoutId }
}

private struct GymDistanceMatch {
    let gymId: UUID
    let gymName: String
    let distanceMeters: Double
}

private struct GymNameMatch {
    let gymId: UUID
    let gymName: String
    let score: Int
    let distanceMeters: Double?
}

private struct AutoTaggingQueryWindow {
    let start: Date
    let end: Date
}

private struct CachedWorkoutLocationSnapshot {
    let workoutDate: Date
    let appleWorkoutUUID: UUID?
    let appleWorkoutType: String?
    let location: CLLocation
}

private struct AutoTaggingRuntime {
    let maxDistanceMeters: Double
    let relaxedMaxDistanceMeters: Double
    let maxStartDiffSeconds: TimeInterval
    let relaxedStartDiffSeconds: TimeInterval
    let gymCoordinates: [UUID: CLLocationCoordinate2D]
    let appleWorkouts: [HKWorkout]
    let appleByUUID: [UUID: HKWorkout]
    let cachedLocationByAppleUUID: [UUID: CLLocation]
    let historicalLocations: [CachedWorkoutLocationSnapshot]

    var routePermissionDenied: Bool
    var resolvedLocationByAppleUUID: [UUID: CLLocation] = [:]
    var appleUUIDsWithNoLocation: Set<UUID> = []

    var assignments: [UUID: UUID] = [:]
    var items: [AutoGymTaggingItem] = []
    var fallbackCandidates: [AutoTagMapFallbackCandidate] = []
    var fallbackCandidateIds: Set<UUID> = []

    var skippedNoMatchingWorkout = 0
    var skippedNoRoute = 0
    var skippedNoGymMatch = 0
    var skippedGymsMissingLocation = 0
}

struct GymBulkAssignView: View {
    @EnvironmentObject var dataManager: WorkoutDataManager
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager
    @EnvironmentObject var healthManager: HealthKitManager

    let autoStartAutoTagging: Bool

    @State private var searchText = ""
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var showUnassignedOnly = false
    @State private var selectedWorkouts: Set<UUID> = []
    @State private var didInitializeRange = false
    @State private var didAutoStartAutoTagging = false
    @State private var showingAssignPicker = false
    @State private var isAutoTagging = false
    @State private var autoTagProgress: Double = 0
    @State private var autoTagReport: AutoGymTaggingReport?
    @State private var showingAutoTagReport = false
    @State private var autoTagErrorMessage: String?
    @State private var routePermissionUnavailable = false
    @State private var mapFallbackCandidates: [AutoTagMapFallbackCandidate] = []
    @State private var mapFallbackTarget: AutoTagMapFallbackCandidate?

    init(autoStartAutoTagging: Bool = false) {
        self.autoStartAutoTagging = autoStartAutoTagging
    }

    private var earliestWorkoutDate: Date? {
        dataManager.workouts.map(\.date).min()
    }

    private var fallbackMapCenter: CLLocationCoordinate2D? {
        if let lastUsedId = gymProfilesManager.lastUsedGymProfileId,
           let gym = gymProfilesManager.gyms.first(where: { $0.id == lastUsedId }),
           let lat = gym.latitude,
           let lon = gym.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        if let gymCoordinate = gymProfilesManager.sortedGyms.compactMap({ gym -> CLLocationCoordinate2D? in
            guard let lat = gym.latitude, let lon = gym.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }).first {
            return gymCoordinate
        }

        if let healthCoordinate = healthManager.healthDataStore.values.compactMap({ entry -> CLLocationCoordinate2D? in
            entry.resolvedWorkoutLocationCoordinate
        }).first {
            return healthCoordinate
        }

        return nil
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    filterSection

                    selectionHeader

                    autoTagSection

                    if filteredWorkouts.isEmpty {
                        ContentUnavailableView(
                            "No workouts",
                            systemImage: "magnifyingglass",
                            description: Text("Adjust filters or date range.")
                        )
                        .padding(.top, Theme.Spacing.xl)
                    } else {
                        VStack(spacing: Theme.Spacing.md) {
                            ForEach(filteredWorkouts) { workout in
                                workoutRow(for: workout)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .navigationTitle("Bulk Assign Gyms")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            initializeDateRangeIfNeeded()
            guard autoStartAutoTagging, !didAutoStartAutoTagging else { return }
            didAutoStartAutoTagging = true
            startAutoTagging()
        }
        .sheet(isPresented: $showingAutoTagReport) {
            if let report = autoTagReport {
                AutoGymTaggingReportView(report: report)
            }
        }
        .sheet(item: $mapFallbackTarget) { candidate in
            GymMapSearchSheet(
                title: "Select Gym",
                initialQuery: "Gym",
                initialCenter: candidate.startCoordinate ?? fallbackMapCenter,
                startLocation: candidate.startCoordinate
            ) { place in
                handleMapFallbackSelection(place, for: candidate)
            }
        }
        .alert("Auto Tag Failed", isPresented: Binding(
            get: { autoTagErrorMessage != nil },
            set: { newValue in
                if !newValue { autoTagErrorMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(autoTagErrorMessage ?? "Unknown error")
        }
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Filters")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            searchField

            BrutalistDateRangePickerRow(
                title: "Date Range",
                startDate: $startDate,
                endDate: $endDate,
                earliestSelectableDate: earliestWorkoutDate.map { Calendar.current.startOfDay(for: $0) },
                latestSelectableDate: Date()
            )

            Toggle(isOn: $showUnassignedOnly) {
                Text("Unassigned only")
            }
            .toggleStyle(BrutalistToggleStyle())

            Text("Matches \(filteredWorkouts.count) workouts")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.subheadlineStrong)
                .foregroundStyle(Theme.Colors.textTertiary)

            TextField("Search workouts or exercises", text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tint(Theme.Colors.accent)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    Haptics.selection()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .glassBackground(cornerRadius: Theme.CornerRadius.xlarge, elevation: 1)
    }

    private var selectionHeader: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text("\(selectedWorkouts.count) selected")
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textSecondary)

            Spacer()

            Button("Select All") {
                selectedWorkouts = Set(filteredWorkouts.map(\.id))
            }
            .font(Theme.Typography.captionBold)
            .foregroundStyle(Theme.Colors.accent)
            .textCase(.uppercase)
            .tracking(0.8)
            .buttonStyle(.plain)

            Button("Clear") {
                selectedWorkouts.removeAll()
            }
            .font(Theme.Typography.captionBold)
            .foregroundStyle(Theme.Colors.textSecondary)
            .textCase(.uppercase)
            .tracking(0.8)
            .buttonStyle(.plain)

            Button {
                showingAssignPicker = true
            } label: {
                Label("Assign", systemImage: "mappin.and.ellipse")
                    .font(Theme.Typography.captionBold)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            .disabled(selectedWorkouts.isEmpty)
            .foregroundStyle(selectedWorkouts.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.accent)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .softCard(elevation: 1)
        .sheet(isPresented: $showingAssignPicker) {
            GymSelectionSheet(
                title: "Assign Gym",
                gyms: gymProfilesManager.sortedGyms,
                selected: .unassigned,
                showAllGyms: false,
                showUnassigned: true,
                lastUsedGymId: nil,
                showLastUsed: false,
                showAddNew: false,
                onSelect: handleBulkSelection,
                onAddNew: nil
            )
        }
    }

    private var autoTagSection: some View {
        let candidates = workoutsInScopeForAutoTag
        let targets = workoutsNeedingGymTag(in: candidates)

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Auto Tag")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                if isAutoTagging {
                    Text("\(Int(autoTagProgress * 100))%")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .monospacedDigit()
                }
            }

            Text(
                "Tries to detect gyms from Apple Health workout location data first. " +
                "If a workout can’t be matched, you can resolve it with searchable map selection."
            )
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            if isAutoTagging {
                ProgressView(value: autoTagProgress)
                    .tint(Theme.Colors.accent)
            } else {
                Text("Will attempt \(targets.count) workouts (scope: \(candidates.count)).")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Button {
                startAutoTagging()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    if isAutoTagging {
                        ProgressView()
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isAutoTagging ? "Tagging..." : "Auto Tag From Watch")
                        .font(Theme.Typography.subheadline)
                        .textCase(.uppercase)
                        .tracking(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .foregroundStyle(.white)
                .brutalistButtonChrome(
                    fill: isAutoTagging ? Theme.Colors.border : Theme.Colors.accent,
                    cornerRadius: Theme.CornerRadius.large
                )
            }
            .buttonStyle(.plain)
            .disabled(isAutoTagging || targets.isEmpty || !healthManager.isHealthKitAvailable())
            .opacity((isAutoTagging || targets.isEmpty || !healthManager.isHealthKitAvailable()) ? 0.6 : 1)

            if !healthManager.isHealthKitAvailable() {
                Text("HealthKit isn’t available on this device.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            } else if gymProfilesManager.gyms.isEmpty {
                Text("No gym profiles yet. Auto detection will still gather location-based fallbacks that you can map-select.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            if routePermissionUnavailable {
                Text("Workout route location permission was unavailable. Map fallback is enabled for unresolved workouts.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.warning)
            }

            if !mapFallbackCandidates.isEmpty {
                Divider()
                    .overlay(Theme.Colors.border)
                    .padding(.vertical, Theme.Spacing.xs)

                Text("\(mapFallbackCandidates.count) workouts need map confirmation")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textSecondary)

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(mapFallbackCandidates.prefix(6)) { candidate in
                        mapFallbackRow(for: candidate)
                    }
                }

                if mapFallbackCandidates.count > 6 {
                    Text("Showing 6 most recent. Resolve some to reveal the rest.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private func mapFallbackRow(for candidate: AutoTagMapFallbackCandidate) -> some View {
        Button {
            mapFallbackTarget = candidate
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.workoutName)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(candidate.workoutDate.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    if candidate.startCoordinate == nil {
                        Text(routePermissionUnavailable ? "Route location permission unavailable" : "No workout location returned by Apple Health")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }

                Spacer()

                Label("Pick on Map", systemImage: "map")
                    .font(Theme.Typography.captionBold)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(Theme.Colors.accent)
            }
            .padding(Theme.Spacing.md)
            .glassBackground(cornerRadius: Theme.CornerRadius.large, elevation: 1)
        }
        .buttonStyle(.plain)
    }

    private func handleBulkSelection(_ selection: GymSelection) {
        switch selection {
        case .unassigned:
            applySelection(gymProfileId: nil)
        case .gym(let id):
            applySelection(gymProfileId: id)
        case .allGyms:
            break
        }
    }

    private func workoutRow(for workout: Workout) -> some View {
        let isSelected = selectedWorkouts.contains(workout.id)
        let gymLabel = gymLabel(for: workout)
        let gymStyle = gymBadgeStyle(for: workout)

        return Button {
            toggleSelection(for: workout.id)
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? Theme.Colors.accent : Theme.Colors.textTertiary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(workout.name)
                            .font(Theme.Typography.headline)
                            .foregroundColor(Theme.Colors.textPrimary)

                        Spacer()

                        GymBadge(text: gymLabel, style: gymStyle)
                    }

                    Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 1)
        }
        .buttonStyle(.plain)
    }

    private var filteredWorkouts: [Workout] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate

        return dataManager.workouts.filter { workout in
            guard workout.date >= start && workout.date <= end else { return false }

            if showUnassignedOnly {
                let gymId = annotationsManager.annotation(for: workout.id)?.gymProfileId
                if let gymId, gymProfilesManager.gymName(for: gymId) != nil {
                    return false
                }
            }

            if searchText.isEmpty {
                return true
            }

            if workout.name.localizedCaseInsensitiveContains(searchText) {
                return true
            }

            return workout.exercises.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var workoutsInScopeForAutoTag: [Workout] {
        // If the user selected rows, respect that selection; otherwise, use the current filtered list.
        if !selectedWorkouts.isEmpty {
            return filteredWorkouts.filter { selectedWorkouts.contains($0.id) }
        }
        return filteredWorkouts
    }

    private func workoutsNeedingGymTag(in workouts: [Workout]) -> [Workout] {
        workouts.filter { workout in
            let gymId = annotationsManager.annotation(for: workout.id)?.gymProfileId
            if gymId == nil { return true }
            // Treat deleted gyms as unassigned, so we can fix history.
            return gymProfilesManager.gymName(for: gymId) == nil
        }
    }

    private func startAutoTagging() {
        guard let targets = autoTaggingTargets() else { return }
        resetAutoTaggingStateForRun()

        Task { @MainActor in
            defer { isAutoTagging = false }

            do {
                var runtime = try await prepareAutoTaggingRuntime(for: targets)
                await processAutoTaggingTargets(targets, runtime: &runtime)
                finalizeAutoTagging(runtime: runtime, attempted: targets.count)
            } catch {
                autoTagErrorMessage = error.localizedDescription
            }
        }
    }

    private func autoTaggingTargets() -> [Workout]? {
        guard !isAutoTagging else { return nil }

        let candidates = workoutsInScopeForAutoTag
        let targets = workoutsNeedingGymTag(in: candidates)
        guard !targets.isEmpty else { return nil }

        guard healthManager.isHealthKitAvailable() else {
            autoTagErrorMessage = "HealthKit isn’t available on this device."
            return nil
        }
        return targets
    }

    private func resetAutoTaggingStateForRun() {
        isAutoTagging = true
        autoTagProgress = 0
        autoTagReport = nil
        autoTagErrorMessage = nil
        routePermissionUnavailable = false
        mapFallbackCandidates = []
        mapFallbackTarget = nil
    }

    private func prepareAutoTaggingRuntime(for targets: [Workout]) async throws -> AutoTaggingRuntime {
        let maxDistanceMeters: Double = 250
        let relaxedMaxDistanceMeters: Double = 450
        let maxStartDiffSeconds: TimeInterval = 20 * 60
        let relaxedStartDiffSeconds: TimeInterval = 12 * 60 * 60

        let routePermissionDenied = try await requestAutoTaggingAuthorization()
        let gymCoordinates = await gymProfilesManager.resolveGymCoordinates()
        let window = autoTaggingQueryWindow(
            for: targets,
            padding: max(maxStartDiffSeconds, relaxedStartDiffSeconds)
        )
        let appleWorkouts = try await healthManager.fetchAppleWorkouts(from: window.start, to: window.end)
        let appleByUUID = Dictionary(uniqueKeysWithValues: appleWorkouts.map { ($0.uuid, $0) })
        let historicalLocations = healthManager.healthDataStore.values.compactMap(cachedWorkoutLocationSnapshot(from:))
        let cachedLocationByAppleUUID = historicalLocations.reduce(into: [UUID: CLLocation]()) { partialResult, snapshot in
            guard let appleWorkoutUUID = snapshot.appleWorkoutUUID else { return }
            partialResult[appleWorkoutUUID] = snapshot.location
        }

        var runtime = AutoTaggingRuntime(
            maxDistanceMeters: maxDistanceMeters,
            relaxedMaxDistanceMeters: relaxedMaxDistanceMeters,
            maxStartDiffSeconds: maxStartDiffSeconds,
            relaxedStartDiffSeconds: relaxedStartDiffSeconds,
            gymCoordinates: gymCoordinates,
            appleWorkouts: appleWorkouts,
            appleByUUID: appleByUUID,
            cachedLocationByAppleUUID: cachedLocationByAppleUUID,
            historicalLocations: historicalLocations,
            routePermissionDenied: routePermissionDenied
        )
        runtime.items.reserveCapacity(targets.count)
        return runtime
    }

    private func requestAutoTaggingAuthorization() async throws -> Bool {
        if healthManager.authorizationStatus != .authorized {
            try await healthManager.requestAuthorization()
        }

        do {
            try await healthManager.requestWorkoutRouteAuthorization()
            return false
        } catch {
            // Route authorization is optional for this flow.
            // Continue so workouts can still be resolved with map fallback.
            return true
        }
    }

    private func autoTaggingQueryWindow(
        for targets: [Workout],
        padding: TimeInterval
    ) -> AutoTaggingQueryWindow {
        let windows = targets.map { $0.estimatedWindow(defaultMinutes: 60) }
        let minStart = windows.map(\.start).min() ?? targets[0].date
        let maxEnd = windows.map(\.end).max() ?? targets[0].estimatedWindow(defaultMinutes: 60).end
        return AutoTaggingQueryWindow(
            start: minStart.addingTimeInterval(-padding),
            end: maxEnd.addingTimeInterval(padding)
        )
    }

    private func processAutoTaggingTargets(
        _ targets: [Workout],
        runtime: inout AutoTaggingRuntime
    ) async {
        for (index, workout) in targets.enumerated() {
            autoTagProgress = Double(index) / Double(max(1, targets.count))
            await processAutoTaggingWorkout(workout, runtime: &runtime)
        }
        autoTagProgress = 1
    }

    private func processAutoTaggingWorkout(
        _ workout: Workout,
        runtime: inout AutoTaggingRuntime
    ) async {
        let cached = healthManager.getHealthData(for: workout.id)
        if let cachedLocation = cachedWorkoutLocation(from: cached) {
            applyResolvedAssignment(for: workout, location: cachedLocation, runtime: &runtime)
            return
        }

        let appleWorkout = resolveAppleWorkout(for: workout, cachedHealthData: cached, runtime: runtime)
        if appleWorkout == nil,
           let historicalLocation = historicalCachedLocation(for: workout, appleWorkout: nil, runtime: runtime) {
            applyResolvedAssignment(for: workout, location: historicalLocation, runtime: &runtime)
            return
        }

        guard let appleWorkout else {
            if applyWorkoutNameAssignmentIfPossible(for: workout, location: nil, runtime: &runtime) {
                return
            }
            runtime.skippedNoMatchingWorkout += 1
            runtime.items.append(.skipped(workout: workout, reason: "No matching Apple workout near this timestamp"))
            queueFallbackCandidate(for: workout, location: nil, runtime: &runtime)
            return
        }

        guard let startLocation = await fetchWorkoutLocation(for: workout, appleWorkout: appleWorkout, runtime: &runtime) else {
            if applyWorkoutNameAssignmentIfPossible(for: workout, location: nil, runtime: &runtime) {
                return
            }
            runtime.skippedNoRoute += 1
            let reason = runtime.routePermissionDenied
                ? "No workout location available (route permission unavailable)"
                : "No workout location returned by Apple Health"
            runtime.items.append(.skipped(workout: workout, reason: reason))
            queueFallbackCandidate(for: workout, location: nil, runtime: &runtime)
            return
        }

        applyResolvedAssignment(for: workout, location: startLocation, runtime: &runtime)
    }

    private func cachedWorkoutLocation(from cachedHealthData: WorkoutHealthData?) -> CLLocation? {
        guard let coordinate = cachedHealthData?.resolvedWorkoutLocationCoordinate else { return nil }
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func cachedWorkoutLocationSnapshot(
        from healthData: WorkoutHealthData
    ) -> CachedWorkoutLocationSnapshot? {
        guard let coordinate = healthData.resolvedWorkoutLocationCoordinate else { return nil }
        return CachedWorkoutLocationSnapshot(
            workoutDate: healthData.workoutDate,
            appleWorkoutUUID: healthData.appleWorkoutUUID,
            appleWorkoutType: healthData.appleWorkoutType,
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )
    }

    private func resolveAppleWorkout(
        for workout: Workout,
        cachedHealthData: WorkoutHealthData?,
        runtime: AutoTaggingRuntime
    ) -> HKWorkout? {
        if let appleUUID = cachedHealthData?.appleWorkoutUUID, let exact = runtime.appleByUUID[appleUUID] {
            return exact
        }
        return healthManager.bestMatchingAppleWorkout(
            for: workout,
            candidates: runtime.appleWorkouts,
            strictStartDifferenceSeconds: runtime.maxStartDiffSeconds,
            relaxedStartDifferenceSeconds: runtime.relaxedStartDiffSeconds
        )
    }

    private func fetchWorkoutLocation(
        for workout: Workout,
        appleWorkout: HKWorkout,
        runtime: inout AutoTaggingRuntime
    ) async -> CLLocation? {
        let appleUUID = appleWorkout.uuid
        if let cachedLocation = runtime.resolvedLocationByAppleUUID[appleUUID] {
            return cachedLocation
        }
        if let cachedLocation = runtime.cachedLocationByAppleUUID[appleUUID] {
            runtime.resolvedLocationByAppleUUID[appleUUID] = cachedLocation
            return cachedLocation
        }
        if let historicalLocation = historicalCachedLocation(for: workout, appleWorkout: appleWorkout, runtime: runtime) {
            runtime.resolvedLocationByAppleUUID[appleUUID] = historicalLocation
            return historicalLocation
        }
        if runtime.appleUUIDsWithNoLocation.contains(appleUUID) {
            return nil
        }

        do {
            if let location = try await healthManager.fetchWorkoutLocation(for: appleWorkout)?.location {
                runtime.resolvedLocationByAppleUUID[appleUUID] = location
                return location
            }
        } catch let error as HealthKitError {
            if case .authorizationFailed = error {
                runtime.routePermissionDenied = true
            }
        } catch {
            // Keep processing with map fallback.
        }

        runtime.appleUUIDsWithNoLocation.insert(appleUUID)
        return nil
    }

    private func historicalCachedLocation(
        for workout: Workout,
        appleWorkout: HKWorkout?,
        runtime: AutoTaggingRuntime
    ) -> CLLocation? {
        let preferredAppleType = appleWorkout?.workoutActivityType.name
        let strictCandidates = runtime.historicalLocations.filter { snapshot in
            abs(snapshot.workoutDate.timeIntervalSince(workout.date)) <= runtime.maxStartDiffSeconds
        }
        if let exact = bestHistoricalLocation(
            from: strictCandidates,
            workoutDate: workout.date,
            preferredAppleType: preferredAppleType
        ) {
            return exact
        }

        guard let preferredAppleType else { return nil }

        let relaxedCandidates = runtime.historicalLocations.filter { snapshot in
            guard snapshot.appleWorkoutType == preferredAppleType else { return false }
            return abs(snapshot.workoutDate.timeIntervalSince(workout.date)) <= runtime.relaxedStartDiffSeconds
        }
        return bestHistoricalLocation(
            from: relaxedCandidates,
            workoutDate: workout.date,
            preferredAppleType: preferredAppleType
        )
    }

    private func bestHistoricalLocation(
        from snapshots: [CachedWorkoutLocationSnapshot],
        workoutDate: Date,
        preferredAppleType: String?
    ) -> CLLocation? {
        let sorted = snapshots.sorted { lhs, rhs in
            let lhsTypeMatch = preferredAppleType != nil && lhs.appleWorkoutType == preferredAppleType
            let rhsTypeMatch = preferredAppleType != nil && rhs.appleWorkoutType == preferredAppleType
            if lhsTypeMatch != rhsTypeMatch {
                return lhsTypeMatch
            }
            return abs(lhs.workoutDate.timeIntervalSince(workoutDate)) < abs(rhs.workoutDate.timeIntervalSince(workoutDate))
        }
        return sorted.first?.location
    }

    private func applyResolvedAssignment(
        for workout: Workout,
        location: CLLocation,
        runtime: inout AutoTaggingRuntime
    ) {
        if applyWorkoutNameAssignmentIfPossible(for: workout, location: location, runtime: &runtime) {
            return
        }

        guard !runtime.gymCoordinates.isEmpty else {
            runtime.skippedGymsMissingLocation += 1
            runtime.items.append(.skipped(workout: workout, reason: "Gyms missing addresses/coordinates"))
            queueFallbackCandidate(for: workout, location: location, runtime: &runtime)
            return
        }

        guard let match = nearestGym(
            to: location,
            gymCoordinates: runtime.gymCoordinates,
            maxDistanceMeters: runtime.maxDistanceMeters
        ) ?? uniqueNearbyGym(
            to: location,
            gymCoordinates: runtime.gymCoordinates,
            maxDistanceMeters: runtime.relaxedMaxDistanceMeters
        ) else {
            runtime.skippedNoGymMatch += 1
            let nearestDistance = nearestGym(
                to: location,
                gymCoordinates: runtime.gymCoordinates,
                maxDistanceMeters: .greatestFiniteMagnitude
            )?.distanceMeters
            let reason: String
            if let nearestDistance {
                reason = "No confident gym match (nearest saved gym is \(Int(nearestDistance.rounded()))m away)"
            } else {
                reason = "No saved gym coordinates were close enough"
            }
            runtime.items.append(.skipped(workout: workout, reason: reason))
            queueFallbackCandidate(for: workout, location: location, runtime: &runtime)
            return
        }

        runtime.assignments[workout.id] = match.gymId
        runtime.items.append(
            .assigned(
                workout: workout,
                detail: "Tagged by location: \(match.gymName) (\(Int(match.distanceMeters.rounded()))m)"
            )
        )
    }

    private func applyWorkoutNameAssignmentIfPossible(
        for workout: Workout,
        location: CLLocation?,
        runtime: inout AutoTaggingRuntime
    ) -> Bool {
        guard let match = inferredGymFromWorkoutName(workout.name, location: location, runtime: runtime) else {
            return false
        }

        runtime.assignments[workout.id] = match.gymId
        runtime.items.append(
            .assigned(
                workout: workout,
                detail: "Tagged from workout name: \(match.gymName)"
            )
        )
        return true
    }

    private func queueFallbackCandidate(
        for workout: Workout,
        location: CLLocation?,
        runtime: inout AutoTaggingRuntime
    ) {
        guard runtime.fallbackCandidateIds.insert(workout.id).inserted else { return }
        runtime.fallbackCandidates.append(
            AutoTagMapFallbackCandidate(
                workoutId: workout.id,
                workoutName: workout.name,
                workoutDate: workout.date,
                startCoordinate: location?.coordinate
            )
        )
    }

    private func finalizeAutoTagging(runtime: AutoTaggingRuntime, attempted: Int) {
        if !runtime.assignments.isEmpty {
            annotationsManager.applyGymAssignments(runtime.assignments.mapValues { Optional($0) })
        }
        routePermissionUnavailable = runtime.routePermissionDenied
        mapFallbackCandidates = runtime.fallbackCandidates.sorted { $0.workoutDate > $1.workoutDate }

        autoTagReport = AutoGymTaggingReport(
            attempted: attempted,
            assigned: runtime.assignments.count,
            skippedNoMatchingWorkout: runtime.skippedNoMatchingWorkout,
            skippedNoRoute: runtime.skippedNoRoute,
            skippedNoGymMatch: runtime.skippedNoGymMatch,
            skippedGymsMissingLocation: runtime.skippedGymsMissingLocation,
            items: runtime.items.sorted { $0.workoutDate > $1.workoutDate }
        )
        showingAutoTagReport = true
    }

    private func nearestGym(
        to location: CLLocation,
        gymCoordinates: [UUID: CLLocationCoordinate2D],
        maxDistanceMeters: Double
    ) -> GymDistanceMatch? {
        var best: GymDistanceMatch?

        for (gymId, coordinate) in gymCoordinates {
            let gymLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let distance = location.distance(from: gymLocation)
            guard distance <= maxDistanceMeters else { continue }

            let name = gymProfilesManager.gymName(for: gymId) ?? "Gym"
            let candidate = GymDistanceMatch(gymId: gymId, gymName: name, distanceMeters: distance)
            guard let existing = best else {
                best = candidate
                continue
            }
            if candidate.distanceMeters < existing.distanceMeters {
                best = candidate
            }
        }

        return best
    }

    private func uniqueNearbyGym(
        to location: CLLocation,
        gymCoordinates: [UUID: CLLocationCoordinate2D],
        maxDistanceMeters: Double
    ) -> GymDistanceMatch? {
        let candidates = gymCoordinates.compactMap { gymId, coordinate -> GymDistanceMatch? in
            let gymLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let distance = location.distance(from: gymLocation)
            guard distance <= maxDistanceMeters else { return nil }
            let name = gymProfilesManager.gymName(for: gymId) ?? "Gym"
            return GymDistanceMatch(gymId: gymId, gymName: name, distanceMeters: distance)
        }
        .sorted { $0.distanceMeters < $1.distanceMeters }

        guard let best = candidates.first else { return nil }
        guard candidates.count > 1 else { return best }

        let secondBest = candidates[1]
        return (secondBest.distanceMeters - best.distanceMeters) >= 125 ? best : nil
    }

    private func inferredGymFromWorkoutName(
        _ workoutName: String,
        location: CLLocation?,
        runtime: AutoTaggingRuntime
    ) -> GymNameMatch? {
        let normalizedWorkoutName = normalizedGymLookupText(workoutName)
        let workoutTokens = meaningfulGymLookupTokens(from: workoutName)
        guard !normalizedWorkoutName.isEmpty, !workoutTokens.isEmpty else { return nil }

        let matches = gymProfilesManager.gyms.compactMap { gym -> GymNameMatch? in
            let normalizedGymName = normalizedGymLookupText(gym.name)
            let normalizedAddress = normalizedGymLookupText(gym.address ?? "")
            let gymNameTokens = meaningfulGymLookupTokens(from: gym.name)
            let addressTokens = meaningfulGymLookupTokens(from: gym.address ?? "")

            let matchedNameTokens = workoutTokens.intersection(gymNameTokens)
            let matchedAddressTokens = workoutTokens.intersection(addressTokens)
            let namePhraseMatch = !normalizedGymName.isEmpty && normalizedWorkoutName.contains(normalizedGymName)
            let addressPhraseMatch = !normalizedAddress.isEmpty && normalizedWorkoutName.contains(normalizedAddress)

            let hasMeaningfulMatch =
                namePhraseMatch ||
                addressPhraseMatch ||
                matchedNameTokens.count >= max(1, min(gymNameTokens.count, 2)) ||
                (!matchedNameTokens.isEmpty && !matchedAddressTokens.isEmpty)

            guard hasMeaningfulMatch else { return nil }

            var score = matchedNameTokens.count * 14 + matchedAddressTokens.count * 10
            if namePhraseMatch {
                score += 40
            }
            if addressPhraseMatch {
                score += 25
            }
            if !gymNameTokens.isEmpty && matchedNameTokens.count == gymNameTokens.count {
                score += 12
            }

            var distanceMeters: Double?
            if let location, let latitude = gym.latitude, let longitude = gym.longitude {
                let gymLocation = CLLocation(latitude: latitude, longitude: longitude)
                let distance = location.distance(from: gymLocation)
                distanceMeters = distance

                if distance <= runtime.maxDistanceMeters {
                    score += 20
                } else if distance <= runtime.relaxedMaxDistanceMeters {
                    score += 12
                } else if distance <= runtime.relaxedMaxDistanceMeters * 2 {
                    score += 4
                } else {
                    score -= 30
                }
            }

            return GymNameMatch(
                gymId: gym.id,
                gymName: gym.name,
                score: score,
                distanceMeters: distanceMeters
            )
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }

            switch (lhs.distanceMeters, rhs.distanceMeters) {
            case let (left?, right?):
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.gymName.localizedCaseInsensitiveCompare(rhs.gymName) == .orderedAscending
            }
        }

        guard let best = matches.first, best.score >= 28 else { return nil }
        if let distance = best.distanceMeters,
           location != nil,
           distance > runtime.relaxedMaxDistanceMeters * 2,
           best.score < 60 {
            return nil
        }

        guard matches.count > 1 else { return best }

        let secondBest = matches[1]
        if best.score - secondBest.score >= 12 {
            return best
        }

        if let bestDistance = best.distanceMeters,
           let secondDistance = secondBest.distanceMeters,
           secondDistance - bestDistance >= 125 {
            return best
        }

        return nil
    }

    private func normalizedGymLookupText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func meaningfulGymLookupTokens(from value: String) -> Set<String> {
        let ignoredTokens: Set<String> = [
            "am", "and", "at", "club", "day", "evening", "for", "gym", "in", "lift",
            "morning", "night", "of", "pm", "session", "the", "training", "workout"
        ]

        let normalized = normalizedGymLookupText(value)
        let tokens = normalized.split(separator: " ").map(String.init)
        return Set(
            tokens.filter { token in
                token.count >= 2 && !ignoredTokens.contains(token)
            }
        )
    }

    private func toggleSelection(for id: UUID) {
        if selectedWorkouts.contains(id) {
            selectedWorkouts.remove(id)
        } else {
            selectedWorkouts.insert(id)
        }
    }

    private func applySelection(gymProfileId: UUID?) {
        let ids = Array(selectedWorkouts)
        guard !ids.isEmpty else { return }
        annotationsManager.setGym(for: ids, gymProfileId: gymProfileId)
        if gymProfileId != nil {
            gymProfilesManager.setLastUsedGymProfileId(gymProfileId)
        }
        selectedWorkouts.removeAll()
    }

    private func handleMapFallbackSelection(_ place: GymMapPlace, for candidate: AutoTagMapFallbackCandidate) {
        let gym = gymProfilesManager.upsertGymFromMapSelection(
            name: place.name,
            address: place.address,
            coordinate: place.coordinate
        )
        annotationsManager.setGym(for: candidate.workoutId, gymProfileId: gym.id)
        gymProfilesManager.setLastUsedGymProfileId(gym.id)
        mapFallbackCandidates.removeAll { $0.workoutId == candidate.workoutId }
    }

    private func gymLabel(for workout: Workout) -> String {
        let gymId = annotationsManager.annotation(for: workout.id)?.gymProfileId
        if let name = gymProfilesManager.gymName(for: gymId) {
            return name
        }
        return gymId == nil ? "Unassigned" : "Deleted gym"
    }

    private func gymBadgeStyle(for workout: Workout) -> GymBadgeStyle {
        let gymId = annotationsManager.annotation(for: workout.id)?.gymProfileId
        if gymId == nil {
            return .unassigned
        }
        return gymProfilesManager.gymName(for: gymId) == nil ? .deleted : .assigned
    }

    private func initializeDateRangeIfNeeded() {
        guard !didInitializeRange else { return }
        didInitializeRange = true
        guard let earliest = earliestWorkoutDate else { return }
        let calendar = Calendar.current
        startDate = calendar.startOfDay(for: earliest)
        endDate = Date()
    }
}

// swiftlint:enable type_body_length file_length
