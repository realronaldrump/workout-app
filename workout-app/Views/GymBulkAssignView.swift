import SwiftUI
import HealthKit
import CoreLocation

struct GymBulkAssignView: View {
    @EnvironmentObject var dataManager: WorkoutDataManager
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager
    @EnvironmentObject var healthManager: HealthKitManager

    @State private var searchText = ""
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var showUnassignedOnly = false
    @State private var selectedWorkouts: Set<UUID> = []
    @State private var didInitializeRange = false
    @State private var showingAssignPicker = false
    @State private var isAutoTagging = false
    @State private var autoTagProgress: Double = 0
    @State private var autoTagReport: AutoGymTaggingReport?
    @State private var showingAutoTagReport = false
    @State private var autoTagErrorMessage: String?

    private var earliestWorkoutDate: Date? {
        dataManager.workouts.map(\.date).min()
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
        }
        .sheet(isPresented: $showingAutoTagReport) {
            if let report = autoTagReport {
                AutoGymTaggingReportView(report: report)
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

            Text("Uses Apple Health workout route data (if present) to tag nearby gyms. Works best when your gym profiles have an address or lat/lon.")
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
            .disabled(isAutoTagging || targets.isEmpty || gymProfilesManager.gyms.isEmpty || !healthManager.isHealthKitAvailable())
            .opacity((isAutoTagging || targets.isEmpty || gymProfilesManager.gyms.isEmpty || !healthManager.isHealthKitAvailable()) ? 0.6 : 1)

            if gymProfilesManager.gyms.isEmpty {
                Text("Add at least one gym profile first.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            } else if !healthManager.isHealthKitAvailable() {
                Text("HealthKit isn’t available on this device.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
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
        let candidates = workoutsInScopeForAutoTag
        let targets = workoutsNeedingGymTag(in: candidates)
        guard !targets.isEmpty else { return }

        isAutoTagging = true
        autoTagProgress = 0
        autoTagReport = nil
        autoTagErrorMessage = nil

        Task { @MainActor in
            do {
                if healthManager.authorizationStatus != .authorized {
                    try await healthManager.requestAuthorization()
                }
                try await healthManager.requestWorkoutRouteAuthorization()

                let maxDistanceMeters: Double = 250
                let maxStartDiffSeconds: TimeInterval = 20 * 60

                // Resolve gym coordinates (including geocoding addresses when needed).
                let gymCoordinates = await gymProfilesManager.resolveGymCoordinates()

                // Build a time window for a single workouts query to HealthKit.
                let windows = targets.map { $0.estimatedWindow(defaultMinutes: 60) }
                let minStart = windows.map(\.start).min() ?? targets[0].date
                let maxEnd = windows.map(\.end).max() ?? targets[0].estimatedWindow(defaultMinutes: 60).end
                let queryStart = minStart.addingTimeInterval(-maxStartDiffSeconds)
                let queryEnd = maxEnd.addingTimeInterval(maxStartDiffSeconds)

                let appleWorkouts = try await healthManager.fetchAppleWorkouts(from: queryStart, to: queryEnd)
                let appleByUUID = Dictionary(uniqueKeysWithValues: appleWorkouts.map { ($0.uuid, $0) })

                var routeStartByAppleUUID: [UUID: CLLocation] = [:]
                var appleUUIDsWithNoRoute: Set<UUID> = []

                var assignments: [UUID: UUID?] = [:]
                var items: [AutoGymTaggingItem] = []
                items.reserveCapacity(targets.count)

                var skippedNoMatchingWorkout = 0
                var skippedNoRoute = 0
                var skippedNoGymMatch = 0
                var skippedGymsMissingLocation = 0

                for (index, workout) in targets.enumerated() {
                    autoTagProgress = Double(index) / Double(max(1, targets.count))

                    // Prefer cached Health sync info when present.
                    let cached = healthManager.getHealthData(for: workout.id)
                    if let lat = cached?.workoutRouteStartLatitude,
                       let lon = cached?.workoutRouteStartLongitude {
                        let location = CLLocation(latitude: lat, longitude: lon)
                        guard !gymCoordinates.isEmpty else {
                            skippedGymsMissingLocation += 1
                            items.append(.skipped(workout: workout, reason: "Gyms missing addresses/coordinates"))
                            continue
                        }
                        if let match = nearestGym(to: location, gymCoordinates: gymCoordinates, maxDistanceMeters: maxDistanceMeters) {
                            assignments[workout.id] = match.gymId
                            items.append(.assigned(workout: workout, gymName: match.gymName, distanceMeters: Int(match.distanceMeters.rounded())))
                        } else {
                            skippedNoGymMatch += 1
                            items.append(.skipped(workout: workout, reason: "No gym within \(Int(maxDistanceMeters))m"))
                        }
                        continue
                    }

                    let appleWorkout: HKWorkout?
                    if let appleUUID = cached?.appleWorkoutUUID, let exact = appleByUUID[appleUUID] {
                        appleWorkout = exact
                    } else {
                        appleWorkout = bestMatchingAppleWorkout(for: workout, candidates: appleWorkouts, maxStartDifferenceSeconds: maxStartDiffSeconds)
                    }

                    guard let appleWorkout else {
                        skippedNoMatchingWorkout += 1
                        items.append(.skipped(workout: workout, reason: "No matching Apple Watch workout"))
                        continue
                    }

                    let appleUUID = appleWorkout.uuid
                    let startLocation: CLLocation?
                    if let cachedLocation = routeStartByAppleUUID[appleUUID] {
                        startLocation = cachedLocation
                    } else if appleUUIDsWithNoRoute.contains(appleUUID) {
                        startLocation = nil
                    } else {
                        let location: CLLocation?
                        do {
                            location = try await healthManager.fetchWorkoutRouteStartLocation(for: appleWorkout)
                        } catch let error as HealthKitError {
                            // If the user declined route permission, surface that as a hard failure.
                            if case .authorizationFailed = error {
                                throw error
                            }
                            location = nil
                        } catch {
                            location = nil
                        }
                        if let location {
                            routeStartByAppleUUID[appleUUID] = location
                        } else {
                            appleUUIDsWithNoRoute.insert(appleUUID)
                        }
                        startLocation = location
                    }

                    guard let startLocation else {
                        skippedNoRoute += 1
                        items.append(.skipped(workout: workout, reason: "No route/start location in Apple Health"))
                        continue
                    }

                    guard !gymCoordinates.isEmpty else {
                        skippedGymsMissingLocation += 1
                        items.append(.skipped(workout: workout, reason: "Gyms missing addresses/coordinates"))
                        continue
                    }

                    guard let match = nearestGym(to: startLocation, gymCoordinates: gymCoordinates, maxDistanceMeters: maxDistanceMeters) else {
                        skippedNoGymMatch += 1
                        items.append(.skipped(workout: workout, reason: "No gym within \(Int(maxDistanceMeters))m"))
                        continue
                    }

                    assignments[workout.id] = match.gymId
                    items.append(.assigned(workout: workout, gymName: match.gymName, distanceMeters: Int(match.distanceMeters.rounded())))
                }

                autoTagProgress = 1

                // Apply the assignments in one persistence pass.
                let nonNilAssignments = assignments.compactMapValues { $0 }
                if !nonNilAssignments.isEmpty {
                    annotationsManager.applyGymAssignments(nonNilAssignments.mapValues { Optional($0) })
                }

                let report = AutoGymTaggingReport(
                    attempted: targets.count,
                    assigned: nonNilAssignments.count,
                    skippedNoMatchingWorkout: skippedNoMatchingWorkout,
                    skippedNoRoute: skippedNoRoute,
                    skippedNoGymMatch: skippedNoGymMatch,
                    skippedGymsMissingLocation: skippedGymsMissingLocation,
                    items: items.sorted { $0.workoutDate > $1.workoutDate }
                )

                autoTagReport = report
                showingAutoTagReport = true
            } catch {
                autoTagErrorMessage = error.localizedDescription
            }

            isAutoTagging = false
        }
    }

    private func bestMatchingAppleWorkout(
        for workout: Workout,
        candidates: [HKWorkout],
        maxStartDifferenceSeconds: TimeInterval
    ) -> HKWorkout? {
        let window = workout.estimatedWindow(defaultMinutes: 60)

        var best: HKWorkout?
        var bestScore: Double = Double.greatestFiniteMagnitude

        for candidate in candidates {
            let startDiff = abs(candidate.startDate.timeIntervalSince(window.start))
            guard startDiff <= maxStartDifferenceSeconds else { continue }

            let candidateInterval = DateInterval(start: candidate.startDate, end: candidate.endDate)
            let overlap = candidateInterval.intersection(with: window)?.duration ?? 0

            // Prefer overlap, then closeness to the internal workout start.
            // Lower score is better.
            let score = startDiff - (overlap * 0.25)
            if score < bestScore {
                bestScore = score
                best = candidate
            }
        }

        return best
    }

    private func nearestGym(
        to location: CLLocation,
        gymCoordinates: [UUID: CLLocationCoordinate2D],
        maxDistanceMeters: Double
    ) -> (gymId: UUID, gymName: String, distanceMeters: Double)? {
        var best: (UUID, String, Double)?

        for (gymId, coordinate) in gymCoordinates {
            let gymLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let distance = location.distance(from: gymLocation)
            guard distance <= maxDistanceMeters else { continue }

            let name = gymProfilesManager.gymName(for: gymId) ?? "Gym"
            if let existing = best {
                if distance < existing.2 {
                    best = (gymId, name, distance)
                }
            } else {
                best = (gymId, name, distance)
            }
        }

        guard let best else { return nil }
        return (best.0, best.1, best.2)
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
