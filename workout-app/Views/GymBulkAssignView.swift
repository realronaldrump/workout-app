import SwiftUI
import HealthKit
import CoreLocation

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

private struct AutoTaggingQueryWindow {
    let start: Date
    let end: Date
}

private struct AutoTaggingRuntime {
    let maxDistanceMeters: Double
    let maxStartDiffSeconds: TimeInterval
    let relaxedStartDiffSeconds: TimeInterval
    let gymCoordinates: [UUID: CLLocationCoordinate2D]
    let appleWorkouts: [HKWorkout]
    let appleByUUID: [UUID: HKWorkout]

    var routePermissionDenied: Bool
    var routeStartByAppleUUID: [UUID: CLLocation] = [:]
    var appleUUIDsWithNoRoute: Set<UUID> = []

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
            guard let lat = entry.workoutRouteStartLatitude, let lon = entry.workoutRouteStartLongitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
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
                .font(.system(size: 14, weight: .semibold))
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
                "Tries to detect gyms from Apple Health workout route data first. " +
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
                .background(isAutoTagging ? Theme.Colors.border : Theme.Colors.accent)
                .foregroundStyle(.white)
                .cornerRadius(Theme.CornerRadius.large)
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
        .buttonStyle(PlainButtonStyle())
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

        var runtime = AutoTaggingRuntime(
            maxDistanceMeters: maxDistanceMeters,
            maxStartDiffSeconds: maxStartDiffSeconds,
            relaxedStartDiffSeconds: relaxedStartDiffSeconds,
            gymCoordinates: gymCoordinates,
            appleWorkouts: appleWorkouts,
            appleByUUID: appleByUUID,
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
        if let cachedLocation = cachedRouteStartLocation(from: cached) {
            applyLocationAssignment(cachedLocation, to: workout, runtime: &runtime)
            return
        }

        guard let appleWorkout = resolveAppleWorkout(for: workout, cachedHealthData: cached, runtime: runtime) else {
            runtime.skippedNoMatchingWorkout += 1
            runtime.items.append(.skipped(workout: workout, reason: "No matching Apple workout near this timestamp"))
            queueFallbackCandidate(for: workout, location: nil, runtime: &runtime)
            return
        }

        guard let startLocation = await fetchRouteStartLocation(for: appleWorkout, runtime: &runtime) else {
            runtime.skippedNoRoute += 1
            let reason = runtime.routePermissionDenied
                ? "No route/start location available (route permission unavailable)"
                : "No route/start location in Apple Health"
            runtime.items.append(.skipped(workout: workout, reason: reason))
            queueFallbackCandidate(for: workout, location: nil, runtime: &runtime)
            return
        }

        applyLocationAssignment(startLocation, to: workout, runtime: &runtime)
    }

    private func cachedRouteStartLocation(from cachedHealthData: WorkoutHealthData?) -> CLLocation? {
        guard let lat = cachedHealthData?.workoutRouteStartLatitude,
              let lon = cachedHealthData?.workoutRouteStartLongitude else {
            return nil
        }
        return CLLocation(latitude: lat, longitude: lon)
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

    private func fetchRouteStartLocation(
        for appleWorkout: HKWorkout,
        runtime: inout AutoTaggingRuntime
    ) async -> CLLocation? {
        let appleUUID = appleWorkout.uuid
        if let cachedLocation = runtime.routeStartByAppleUUID[appleUUID] {
            return cachedLocation
        }
        if runtime.appleUUIDsWithNoRoute.contains(appleUUID) {
            return nil
        }

        do {
            if let location = try await healthManager.fetchWorkoutRouteStartLocation(for: appleWorkout) {
                runtime.routeStartByAppleUUID[appleUUID] = location
                return location
            }
        } catch let error as HealthKitError {
            if case .authorizationFailed = error {
                runtime.routePermissionDenied = true
            }
        } catch {
            // Keep processing with map fallback.
        }

        runtime.appleUUIDsWithNoRoute.insert(appleUUID)
        return nil
    }

    private func applyLocationAssignment(
        _ location: CLLocation,
        to workout: Workout,
        runtime: inout AutoTaggingRuntime
    ) {
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
        ) else {
            runtime.skippedNoGymMatch += 1
            runtime.items.append(.skipped(workout: workout, reason: "No gym within \(Int(runtime.maxDistanceMeters))m"))
            queueFallbackCandidate(for: workout, location: location, runtime: &runtime)
            return
        }

        runtime.assignments[workout.id] = match.gymId
        runtime.items.append(
            .assigned(
                workout: workout,
                gymName: match.gymName,
                distanceMeters: Int(match.distanceMeters.rounded())
            )
        )
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
