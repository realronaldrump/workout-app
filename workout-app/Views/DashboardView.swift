import SwiftUI

// MARK: - Deprecated: DashboardView was replaced by the unified HomeView.
// This file is kept as a stub to prevent build errors from stale references.
// Safe to delete once confirmed no references exist.

@available(*, deprecated, message: "Use HomeView instead.")
struct DashboardView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    let annotationsManager: WorkoutAnnotationsManager
    let gymProfilesManager: GymProfilesManager

    init(
        dataManager: WorkoutDataManager,
        iCloudManager: iCloudDocumentManager,
        annotationsManager: WorkoutAnnotationsManager,
        gymProfilesManager: GymProfilesManager
    ) {
        self.dataManager = dataManager
        self.iCloudManager = iCloudManager
        self.annotationsManager = annotationsManager
        self.gymProfilesManager = gymProfilesManager
    }

    var body: some View {
        Text("Deprecated – Use HomeView")
    }
}
