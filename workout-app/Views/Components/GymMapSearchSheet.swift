import SwiftUI
import MapKit
import CoreLocation

struct GymMapPlace: Identifiable {
    let id: String
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D
    let gymProfileId: UUID?
    let usageCount: Int

    var isSavedGym: Bool { gymProfileId != nil }

    init(
        name: String,
        address: String?,
        coordinate: CLLocationCoordinate2D,
        gymProfileId: UUID? = nil,
        usageCount: Int = 0
    ) {
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.gymProfileId = gymProfileId
        self.usageCount = usageCount
        if let gymProfileId {
            self.id = "profile:\(gymProfileId.uuidString)"
        } else {
            let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            self.id = "\(normalizedName)|\(coordinate.latitude)|\(coordinate.longitude)"
        }
    }
}

struct GymMapSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var gymProfilesManager: GymProfilesManager
    @EnvironmentObject private var annotationsManager: WorkoutAnnotationsManager

    let title: String
    let startLocation: CLLocationCoordinate2D?
    let onSelect: (GymMapPlace) -> Void
    private let shouldAutoRunInitialSearch: Bool

    @State private var query: String
    @State private var cameraPosition: MapCameraPosition
    @State private var visibleRegion: MKCoordinateRegion
    @State private var results: [GymMapPlace] = []
    @State private var selectedPlaceId: String?
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var didRunInitialSearch = false
    @State private var isShowingAllResults = false

    // Fallback to CONUS center when we don't have workout/gym coordinates yet.
    private static let fallbackCenter = CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795)
    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.045)
    private static let collapsedResultsLimit = 5

    init(
        title: String,
        initialQuery: String = "Gym",
        initialCenter: CLLocationCoordinate2D? = nil,
        startLocation: CLLocationCoordinate2D? = nil,
        onSelect: @escaping (GymMapPlace) -> Void
    ) {
        self.title = title
        self.startLocation = startLocation
        self.onSelect = onSelect

        let hasLocationContext = initialCenter != nil || startLocation != nil
        let initialQueryTrimmed = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let initialSearchQuery = hasLocationContext ? (initialQueryTrimmed.isEmpty ? "Gym" : initialQueryTrimmed) : ""
        let center = initialCenter ?? startLocation ?? Self.fallbackCenter
        let region = MKCoordinateRegion(center: center, span: Self.defaultSpan)
        self.shouldAutoRunInitialSearch = hasLocationContext
        _query = State(initialValue: initialSearchQuery)
        _cameraPosition = State(initialValue: .region(region))
        _visibleRegion = State(initialValue: region)
    }

    private var usageCountByGymId: [UUID: Int] {
        annotationsManager.annotations.values.reduce(into: [UUID: Int]()) { counts, annotation in
            guard let gymId = annotation.gymProfileId else { return }
            counts[gymId, default: 0] += 1
        }
    }

    private var anchorCoordinate: CLLocationCoordinate2D {
        startLocation ?? visibleRegion.center
    }

    private var savedGymsForCurrentQuery: [GymMapPlace] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let counts = usageCountByGymId
        let lastUsedGymId = gymProfilesManager.lastUsedGymProfileId
        let anchor = anchorCoordinate

        let places: [GymMapPlace] = gymProfilesManager.gyms.compactMap { gym in
            guard let latitude = gym.latitude, let longitude = gym.longitude else { return nil }

            if !trimmedQuery.isEmpty {
                let haystack = "\(gym.name) \(gym.address ?? "")".lowercased()
                guard haystack.contains(trimmedQuery) else { return nil }
            }

            return GymMapPlace(
                name: gym.name,
                address: gym.address,
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                gymProfileId: gym.id,
                usageCount: counts[gym.id] ?? 0
            )
        }

        return places.sorted { lhs, rhs in
            let lhsLastUsed = lhs.gymProfileId == lastUsedGymId
            let rhsLastUsed = rhs.gymProfileId == lastUsedGymId
            if lhsLastUsed != rhsLastUsed { return lhsLastUsed && !rhsLastUsed }

            if lhs.usageCount != rhs.usageCount { return lhs.usageCount > rhs.usageCount }

            let lhsDistance = distanceMeters(from: lhs.coordinate, to: anchor)
            let rhsDistance = distanceMeters(from: rhs.coordinate, to: anchor)
            if abs(lhsDistance - rhsDistance) > 0.1 { return lhsDistance < rhsDistance }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var combinedResults: [GymMapPlace] {
        var merged: [GymMapPlace] = []
        var seen = Set<String>()

        for place in savedGymsForCurrentQuery {
            if seen.insert(place.id).inserted {
                merged.append(place)
            }
        }

        for place in results {
            if seen.insert(place.id).inserted {
                merged.append(place)
            }
        }

        return merged
    }

    private var canExpandResults: Bool {
        combinedResults.count > Self.collapsedResultsLimit
    }

    private var collapsedResults: [GymMapPlace] {
        guard canExpandResults else { return combinedResults }

        let defaultCollapsed = Array(combinedResults.prefix(Self.collapsedResultsLimit))
        guard let selectedPlaceId,
              let selectedIndex = combinedResults.firstIndex(where: { $0.id == selectedPlaceId }),
              selectedIndex >= Self.collapsedResultsLimit,
              Self.collapsedResultsLimit > 0 else {
            return defaultCollapsed
        }

        var adjusted = Array(combinedResults.prefix(Self.collapsedResultsLimit - 1))
        adjusted.append(combinedResults[selectedIndex])
        return adjusted
    }

    private var displayedResults: [GymMapPlace] {
        isShowingAllResults ? combinedResults : collapsedResults
    }

    private var hiddenResultsCount: Int {
        max(0, combinedResults.count - Self.collapsedResultsLimit)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        searchCard
                        mapCard
                        resultsCard
                        selectButton
                    }
                    .padding(Theme.Spacing.xl)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    AppPillButton(title: "Close", systemImage: "xmark", variant: .subtle) {
                        dismiss()
                    }
                }
            }
        }
        .task {
            guard !didRunInitialSearch else { return }
            didRunInitialSearch = true
            guard shouldAutoRunInitialSearch else { return }
            runSearch()
        }
    }

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Search")
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textSecondary)

            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.Colors.textTertiary)

                TextField("Find nearby gyms", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(true)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .submitLabel(.search)
                    .onSubmit { runSearch() }

                Button {
                    runSearch()
                } label: {
                    if isSearching {
                        ProgressView()
                            .tint(Theme.Colors.accent)
                    } else {
                        Text("Search")
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.accent)
                            .textCase(.uppercase)
                            .tracking(0.8)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSearching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .glassBackground(cornerRadius: Theme.CornerRadius.xlarge, elevation: 1)

            if let searchError, !searchError.isEmpty {
                Text(searchError)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.warning)
            } else if !shouldAutoRunInitialSearch {
                Text("No workout location was available. Search by city, neighborhood, or exact gym name.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            } else if startLocation == nil {
                Text("Tip: If this opens far away, search by city/neighborhood first.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Map")
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textSecondary)

            Map(position: $cameraPosition) {
                if let startLocation {
                    Annotation("Workout Start", coordinate: startLocation) {
                        ZStack {
                            Circle()
                                .fill(Theme.Colors.accentSecondary)
                                .frame(width: 22, height: 22)
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }

                ForEach(combinedResults) { result in
                    Annotation(result.name, coordinate: result.coordinate) {
                        ZStack {
                            Circle()
                                .fill(selectedPlaceId == result.id ? Theme.Colors.accent : Theme.Colors.textSecondary)
                                .frame(width: 22, height: 22)
                            Image(systemName: "mappin")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .frame(minHeight: 240, maxHeight: 300)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous))
            .onMapCameraChange(frequency: .continuous) { context in
                visibleRegion = context.region
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Results")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text("\(combinedResults.count)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .monospacedDigit()
            }

            if combinedResults.isEmpty {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Start by searching for a city or gym name.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                } else {
                    Text("No matches yet. Move the map or refine search.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(displayedResults) { place in
                        resultRow(for: place)
                    }

                    if canExpandResults {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isShowingAllResults.toggle()
                            }
                        } label: {
                            Text(isShowingAllResults ? "Show less" : "Show \(hiddenResultsCount) more")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(Theme.Colors.accent)
                                .textCase(.uppercase)
                                .tracking(0.8)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, Theme.Spacing.xs)
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private var selectedPlace: GymMapPlace? {
        guard let selectedPlaceId else { return nil }
        return combinedResults.first { $0.id == selectedPlaceId }
    }

    private var selectButton: some View {
        Button {
            guard let selectedPlace else { return }
            onSelect(selectedPlace)
            dismiss()
        } label: {
            Text("Use Selected Gym")
                .font(Theme.Typography.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(selectedPlace == nil ? Theme.Colors.border : Theme.Colors.accent)
                .foregroundStyle(.white)
                .cornerRadius(Theme.CornerRadius.large)
        }
        .buttonStyle(.plain)
        .disabled(selectedPlace == nil)
    }

    private func resultRow(for place: GymMapPlace) -> some View {
        Button {
            selectedPlaceId = place.id
            focusMap(on: place.coordinate)
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Theme.Colors.accent.opacity(selectedPlaceId == place.id ? 0.25 : 0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: place.isSavedGym ? "bookmark.fill" : "dumbbell.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if place.isSavedGym {
                        Text(place.usageCount > 0 ? "Saved gym • \(place.usageCount) workouts" : "Saved gym")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    if let address = place.address, !address.isEmpty {
                        Text(address)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                if selectedPlaceId == place.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding(Theme.Spacing.md)
            .glassBackground(cornerRadius: Theme.CornerRadius.large, elevation: 1)
        }
        .buttonStyle(.plain)
    }

    private func focusMap(on coordinate: CLLocationCoordinate2D) {
        cameraPosition = .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        )
    }

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSearching = true
        searchError = nil
        let region = visibleRegion

        Task {
            do {
                let places = try await searchGyms(query: trimmed, region: region)
                await MainActor.run {
                    results = places
                    isShowingAllResults = false
                    if let first = combinedResults.first {
                        selectedPlaceId = first.id
                        focusMap(on: first.coordinate)
                    } else {
                        selectedPlaceId = nil
                    }
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    isSearching = false
                    searchError = error.localizedDescription
                }
            }
        }
    }

    private func searchGyms(query: String, region: MKCoordinateRegion) async throws -> [GymMapPlace] {
        let filtered = try await performSearch(query: query, region: region, filterToFitnessCenters: true)
        if !filtered.isEmpty {
            return filtered
        }
        return try await performSearch(query: query, region: region, filterToFitnessCenters: false)
    }

    private func performSearch(
        query: String,
        region: MKCoordinateRegion,
        filterToFitnessCenters: Bool
    ) async throws -> [GymMapPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        request.resultTypes = [.address, .pointOfInterest]
        if filterToFitnessCenters {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.fitnessCenter])
        }

        let response = try await MKLocalSearch(request: request).start()
        let places = response.mapItems.compactMap { item -> GymMapPlace? in
            let location = item.location
            let coordinate = location.coordinate
            guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
            let trimmedName = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = trimmedName.isEmpty ? "Gym" : trimmedName
            let address = formatAddress(for: item)
            let matchedGym = matchingSavedGym(for: coordinate, name: name, address: address)
            let gymId = matchedGym?.id
            let usageCount = gymId.flatMap { usageCountByGymId[$0] } ?? 0
            return GymMapPlace(
                name: name,
                address: address,
                coordinate: coordinate,
                gymProfileId: gymId,
                usageCount: usageCount
            )
        }

        var unique: [GymMapPlace] = []
        var seen = Set<String>()
        for place in places {
            if seen.insert(place.id).inserted {
                unique.append(place)
            }
        }
        return unique.sorted { lhs, rhs in
            if lhs.isSavedGym != rhs.isSavedGym { return lhs.isSavedGym && !rhs.isSavedGym }
            if lhs.usageCount != rhs.usageCount { return lhs.usageCount > rhs.usageCount }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func matchingSavedGym(
        for coordinate: CLLocationCoordinate2D,
        name: String,
        address: String?
    ) -> GymProfile? {
        let selectedLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedAddress = address?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        return gymProfilesManager.gyms.first { gym in
            if let latitude = gym.latitude, let longitude = gym.longitude {
                let gymLocation = CLLocation(latitude: latitude, longitude: longitude)
                if gymLocation.distance(from: selectedLocation) <= 120 {
                    return true
                }
            }

            let gymName = gym.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !normalizedName.isEmpty && gymName == normalizedName {
                return true
            }

            let gymAddress = gym.address?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            return !normalizedAddress.isEmpty && gymAddress == normalizedAddress
        }
    }

    private func distanceMeters(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> Double {
        let lhsLocation = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
        let rhsLocation = CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
        return lhsLocation.distance(from: rhsLocation)
    }
}
