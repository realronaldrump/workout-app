import SwiftUI
import CoreLocation
import MapKit

private struct DetectedGymCandidate: Identifiable {
    let coordinate: CLLocationCoordinate2D
    let visitCount: Int
    let latestWorkoutDate: Date
    let suggestedName: String
    let suggestedAddress: String?

    var id: String {
        "\(coordinate.latitude)|\(coordinate.longitude)|\(visitCount)"
    }
}

private struct CoordinateCluster {
    var center: CLLocationCoordinate2D
    var count: Int
    var latestWorkoutDate: Date

    mutating func add(point: CLLocationCoordinate2D, workoutDate: Date) {
        let currentCount = Double(count)
        center = CLLocationCoordinate2D(
            latitude: ((center.latitude * currentCount) + point.latitude) / (currentCount + 1),
            longitude: ((center.longitude * currentCount) + point.longitude) / (currentCount + 1)
        )
        count += 1
        if workoutDate > latestWorkoutDate {
            latestWorkoutDate = workoutDate
        }
    }
}

struct GymProfilesView: View {
    @EnvironmentObject var dataManager: WorkoutDataManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager
    @EnvironmentObject var healthManager: HealthKitManager

    @State private var showingAddSheet = false
    @State private var editingGym: GymProfile?
    @State private var showingDeleteAlert = false
    @State private var gymToDelete: GymProfile?
    @State private var isDetectingCandidateGyms = false
    @State private var didAutoDetectCandidateGyms = false
    @State private var candidateGyms: [DetectedGymCandidate] = []
    @State private var candidateGymError: String?

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Keep Progress Clean")
                            .font(Theme.Typography.headline)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("Tag workouts by gym to avoid misleading trends caused by different equipment.")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)

                    NavigationLink(destination: GymBulkAssignView()) {
                        HStack {
                            Image(systemName: "square.stack.3d.up.fill")
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Theme.Colors.accent)
                                .cornerRadius(6)

                            VStack(alignment: .leading) {
                                Text("Bulk Assign Gyms")
                                    .font(Theme.Typography.body)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text("Tag historical workouts")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }

                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .padding()
                        .softCard(elevation: 1)
                    }
                    .buttonStyle(PlainButtonStyle())

                    discoverySection

                    if gymProfilesManager.gyms.isEmpty {
                        ContentUnavailableView(
                            "No gyms yet",
                            systemImage: "mappin.and.ellipse",
                            description: Text("Add your first gym profile.")
                        )
                        .padding(.top, Theme.Spacing.xl)
                    } else {
                        VStack(spacing: Theme.Spacing.md) {
                            ForEach(gymProfilesManager.sortedGyms) { gym in
                                gymRow(for: gym)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .navigationTitle("Gym Profiles")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !didAutoDetectCandidateGyms else { return }
            didAutoDetectCandidateGyms = true
            runGymDiscovery()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                AppPillIconButton(systemImage: "plus", accessibilityLabel: "Add gym") {
                    showingAddSheet = true
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            GymProfileEditorView(mode: .create) { name, address, latitude, longitude in
                _ = gymProfilesManager.addGym(
                    name: name,
                    address: address,
                    latitude: latitude,
                    longitude: longitude
                )
            }
        }
        .sheet(item: $editingGym) { gym in
            GymProfileEditorView(mode: .edit(gym)) { name, address, latitude, longitude in
                gymProfilesManager.updateGym(
                    id: gym.id,
                    name: name,
                    address: address,
                    latitude: latitude,
                    longitude: longitude
                )
            }
        }
        .alert("Delete Gym?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let gym = gymToDelete {
                    gymProfilesManager.deleteGym(gym)
                }
                gymToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                gymToDelete = nil
            }
        } message: {
            Text("Deleting this gym will unassign workouts currently tagged with it.")
        }
    }

    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Auto Detect From Workouts")
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer()

                if isDetectingCandidateGyms {
                    ProgressView()
                        .tint(Theme.Colors.accent)
                        .scaleEffect(0.9)
                } else {
                    Button("Refresh") {
                        runGymDiscovery()
                    }
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.accent)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .buttonStyle(.plain)
                }
            }

            Text("Scans Apple Health workout start locations and suggests new gym profiles.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            if let candidateGymError, !candidateGymError.isEmpty {
                Text(candidateGymError)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.warning)
            }

            if candidateGyms.isEmpty {
                Text(isDetectingCandidateGyms ? "Scanning…" : "No new gym locations detected yet.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(candidateGyms.prefix(5)) { candidate in
                        candidateGymRow(for: candidate)
                    }
                }

                if candidateGyms.count > 5 {
                    Text("Showing 5 of \(candidateGyms.count) detected locations.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Button {
                    addAllDetectedGyms()
                } label: {
                    Text("Add All Detected Gyms")
                        .font(Theme.Typography.captionBold)
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.accent)
                        .foregroundStyle(.white)
                        .cornerRadius(Theme.CornerRadius.large)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private func candidateGymRow(for candidate: DetectedGymCandidate) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.suggestedName)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                if let address = candidate.suggestedAddress, !address.isEmpty {
                    Text(address)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }

                Text("\(candidate.visitCount) workouts detected")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Spacer()

            Button("Add") {
                addDetectedGym(candidate)
            }
            .font(Theme.Typography.captionBold)
            .foregroundStyle(Theme.Colors.accent)
            .textCase(.uppercase)
            .tracking(0.8)
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.md)
        .glassBackground(cornerRadius: Theme.CornerRadius.large, elevation: 1)
    }

    private func runGymDiscovery() {
        guard !isDetectingCandidateGyms else { return }
        isDetectingCandidateGyms = true
        candidateGymError = nil

        Task {
            var healthSnapshot = await MainActor.run { Array(healthManager.healthDataStore.values) }
            let cachedRoutePointCount = healthSnapshot.reduce(into: 0) { partialResult, entry in
                if entry.workoutRouteStartLatitude != nil && entry.workoutRouteStartLongitude != nil {
                    partialResult += 1
                }
            }

            if cachedRoutePointCount == 0 {
                let workoutsSnapshot = await MainActor.run { dataManager.workouts }
                do {
                    _ = try await healthManager.hydrateRouteStartLocationsForRecentWorkouts(workoutsSnapshot, maxWorkouts: 180)
                    healthSnapshot = await MainActor.run { Array(healthManager.healthDataStore.values) }
                } catch {
                    await MainActor.run {
                        candidateGymError = error.localizedDescription
                    }
                }
            }

            let gymsSnapshot = await MainActor.run { gymProfilesManager.gyms }
            let candidates = await discoverGymCandidates(from: healthSnapshot, existingGyms: gymsSnapshot)
            let finalRoutePointCount = healthSnapshot.reduce(into: 0) { partialResult, entry in
                if entry.workoutRouteStartLatitude != nil && entry.workoutRouteStartLongitude != nil {
                    partialResult += 1
                }
            }

            await MainActor.run {
                candidateGyms = candidates
                if candidateGyms.isEmpty && candidateGymError == nil && healthSnapshot.isEmpty {
                    candidateGymError = "No synced Health workouts found yet. Run Health Sync first."
                } else if candidateGyms.isEmpty && candidateGymError == nil && finalRoutePointCount == 0 {
                    candidateGymError = "No workout route location points were available from Apple Health for these workouts."
                }
                isDetectingCandidateGyms = false
            }
        }
    }

    private func discoverGymCandidates(
        from healthData: [WorkoutHealthData],
        existingGyms: [GymProfile]
    ) async -> [DetectedGymCandidate] {
        let routePoints: [(coordinate: CLLocationCoordinate2D, workoutDate: Date)] = healthData.compactMap { entry in
            guard let latitude = entry.workoutRouteStartLatitude, let longitude = entry.workoutRouteStartLongitude else {
                return nil
            }
            return (CLLocationCoordinate2D(latitude: latitude, longitude: longitude), entry.workoutDate)
        }

        guard !routePoints.isEmpty else { return [] }

        let existingCoordinates: [CLLocationCoordinate2D] = existingGyms.compactMap { gym in
            guard let latitude = gym.latitude, let longitude = gym.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        let clusters = clusterRoutePoints(routePoints, maxDistanceMeters: 120)
            .filter { $0.count >= 2 }
            .filter { cluster in
                !existingCoordinates.contains(where: { distanceMeters(from: $0, to: cluster.center) <= 120 })
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.latestWorkoutDate > rhs.latestWorkoutDate
            }

        var candidates: [DetectedGymCandidate] = []
        candidates.reserveCapacity(clusters.count)

        for (index, cluster) in clusters.enumerated() {
            let suggestion = await nearestFitnessCenter(around: cluster.center)
            let suggestedName = suggestion?.name ?? "Detected Gym \(index + 1)"
            candidates.append(
                DetectedGymCandidate(
                    coordinate: cluster.center,
                    visitCount: cluster.count,
                    latestWorkoutDate: cluster.latestWorkoutDate,
                    suggestedName: suggestedName,
                    suggestedAddress: suggestion?.address
                )
            )
        }

        return candidates
    }

    private func clusterRoutePoints(
        _ points: [(coordinate: CLLocationCoordinate2D, workoutDate: Date)],
        maxDistanceMeters: Double
    ) -> [CoordinateCluster] {
        var clusters: [CoordinateCluster] = []

        for point in points {
            if let existingIndex = clusters.firstIndex(where: {
                distanceMeters(from: $0.center, to: point.coordinate) <= maxDistanceMeters
            }) {
                clusters[existingIndex].add(point: point.coordinate, workoutDate: point.workoutDate)
            } else {
                clusters.append(
                    CoordinateCluster(
                        center: point.coordinate,
                        count: 1,
                        latestWorkoutDate: point.workoutDate
                    )
                )
            }
        }

        return clusters
    }

    private func nearestFitnessCenter(around coordinate: CLLocationCoordinate2D) async -> (name: String, address: String?)? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "gym"
        request.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        request.resultTypes = [.pointOfInterest, .address]
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.fitnessCenter])

        do {
            let response = try await MKLocalSearch(request: request).start()
            let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let sorted = response.mapItems.sorted { lhs, rhs in
                let lhsDistance = origin.distance(from: lhs.location)
                let rhsDistance = origin.distance(from: rhs.location)
                return lhsDistance < rhsDistance
            }

            guard let closest = sorted.first else { return nil }
            let name = (closest.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                ? "Gym"
                : (closest.name ?? "Gym")
            return (name, formatAddress(for: closest))
        } catch {
            return nil
        }
    }

    private func distanceMeters(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> Double {
        let lhsLocation = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
        let rhsLocation = CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
        return lhsLocation.distance(from: rhsLocation)
    }

    private func addDetectedGym(_ candidate: DetectedGymCandidate) {
        _ = gymProfilesManager.upsertGymFromMapSelection(
            name: candidate.suggestedName,
            address: candidate.suggestedAddress,
            coordinate: candidate.coordinate
        )
        candidateGyms.removeAll { $0.id == candidate.id }
    }

    private func addAllDetectedGyms() {
        let snapshot = candidateGyms
        guard !snapshot.isEmpty else { return }

        for candidate in snapshot {
            _ = gymProfilesManager.upsertGymFromMapSelection(
                name: candidate.suggestedName,
                address: candidate.suggestedAddress,
                coordinate: candidate.coordinate
            )
        }
        candidateGyms.removeAll()
    }

    private func gymRow(for gym: GymProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(gym.name)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)

                if let address = gym.address, !address.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.Colors.textTertiary)
                        Text(address)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
            }

            Spacer()

            Menu {
                Button("Edit") {
                    editingGym = gym
                }
                Button("Delete", role: .destructive) {
                    gymToDelete = gym
                    showingDeleteAlert = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }
}

private struct GymProfileEditorView: View {
    enum Mode: Identifiable {
        case create
        case edit(GymProfile)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let gym): return gym.id.uuidString
            }
        }

        var title: String {
            switch self {
            case .create: return "New Gym"
            case .edit: return "Edit Gym"
            }
        }
    }

    @Environment(\.dismiss) var dismiss
    let mode: Mode
    let onSave: (String, String?, Double?, Double?) -> Void

    @State private var name: String = ""
    @State private var address: String = ""
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var showingMapPicker = false

    init(mode: Mode, onSave: @escaping (String, String?, Double?, Double?) -> Void) {
        self.mode = mode
        self.onSave = onSave
        if case .edit(let gym) = mode {
            _name = State(initialValue: gym.name)
            _address = State(initialValue: gym.address ?? "")
            if let latitude = gym.latitude, let longitude = gym.longitude {
                _coordinate = State(initialValue: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    TextField("Gym name", text: $name)
                        .textInputAutocapitalization(.words)
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.surface.opacity(0.6))
                        .cornerRadius(Theme.CornerRadius.medium)

                    TextField("Address (optional)", text: $address)
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.surface.opacity(0.6))
                        .cornerRadius(Theme.CornerRadius.medium)

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Button {
                            showingMapPicker = true
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "magnifyingglass")
                                Text("Search Gym on Map")
                                    .textCase(.uppercase)
                                    .tracking(0.8)
                                Spacer()
                                Image(systemName: "map")
                            }
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.accent)
                            .padding(Theme.Spacing.md)
                            .frame(maxWidth: .infinity)
                            .glassBackground(cornerRadius: Theme.CornerRadius.large, elevation: 1)
                        }
                        .buttonStyle(.plain)

                        if let coordinate {
                            Text(
                                "Selected location: \(coordinate.latitude, specifier: "%.5f"), \(coordinate.longitude, specifier: "%.5f")"
                            )
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                        } else {
                            Text("No location selected yet")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }

                    Button {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedName.isEmpty else { return }
                        onSave(trimmedName, sanitized(address), coordinate?.latitude, coordinate?.longitude)
                        dismiss()
                    } label: {
                        Text("Save")
                            .font(Theme.Typography.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.Colors.accent)
                            .foregroundColor(.white)
                            .cornerRadius(Theme.CornerRadius.large)
                    }
                    .buttonStyle(.plain)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()
                }
                .padding(Theme.Spacing.xl)
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    AppPillButton(title: "Cancel", systemImage: "xmark", variant: .subtle) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingMapPicker) {
            GymMapSearchSheet(
                title: "Find Gym",
                initialQuery: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Gym"
                    : "\(name) gym",
                initialCenter: coordinate
            ) { place in
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    name = place.name
                }
                if let placeAddress = place.address {
                    address = placeAddress
                }
                coordinate = place.coordinate
            }
        }
    }

    private func sanitized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
