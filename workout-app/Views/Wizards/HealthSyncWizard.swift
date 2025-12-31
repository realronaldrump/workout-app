import SwiftUI
import HealthKit

struct HealthSyncWizard: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var healthManager: HealthKitManager
    let workouts: [Workout]
    
    @State private var step = 0
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()
                VStack {
                    // Progress Indicator
                    HStack(spacing: 8) {
                        ForEach(0..<4) { index in
                            Capsule()
                                .fill(index <= step ? Theme.Colors.error : Theme.Colors.surface) // Red/pink for Health
                                .frame(height: 4)
                                .animation(.spring(), value: step)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.top, Theme.Spacing.lg)
                    
                    TabView(selection: $step) {
                        introStep.tag(0)
                        authStep.tag(1)
                        syncStep.tag(2)
                        successStep.tag(3)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.spring(), value: step)
                }
            }
            .navigationTitle("Apple Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step < 2 { // Don't allow closing during sync
                        Button("Close") { isPresented = false }
                    }
                }
            }
        }
    }
    
    // MARK: - Steps
    
    private var introStep: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.red)
                .padding()
                .background(
                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 160, height: 160)
                )
            
            VStack(spacing: Theme.Spacing.md) {
                Text("Sync Health Data")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text("Enhance your workout logs with heart rate, calories, and other metrics from Apple Health.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            Button(action: {
                withAnimation { step = 1 }
            }) {
                Text("Next")
                    .font(Theme.Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(Theme.CornerRadius.large)
            }
            .padding(Theme.Spacing.xl)
        }
    }
    
    private var authStep: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.Colors.accent)
            
            VStack(spacing: Theme.Spacing.md) {
                Text("Privacy First")
                    .font(Theme.Typography.title2)
                
                Text("We only request read access to match health metrics with your existing workout times. Your data stays on your device.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            Button(action: requestAuthorization) {
                Text("Continue to Authorization")
                    .font(Theme.Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.Colors.accent)
                    .foregroundColor(.white)
                    .cornerRadius(Theme.CornerRadius.large)
            }
            .padding(Theme.Spacing.xl)
        }
    }
    
    private var syncStep: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            
            ZStack {
                Circle()
                    .stroke(Theme.Colors.surface, lineWidth: 8)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: healthManager.syncProgress)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(), value: healthManager.syncProgress)
                
                Text("\(Int(healthManager.syncProgress * 100))%")
                    .font(Theme.Typography.title2)
                    .monospacedDigit()
            }
            
            VStack(spacing: Theme.Spacing.sm) {
                Text("Syncing Workouts")
                    .font(Theme.Typography.headline)
                
                Text("\(healthManager.syncedWorkoutsCount) / \(workouts.count) processed")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            
            Spacer()
        }
        .onAppear {
            startSync()
        }
    }
    
    private var successStep: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80))
                .foregroundStyle(Theme.Colors.success)
                .symbolEffect(.bounce)
            
            Text("Health Sync Complete")
                .font(Theme.Typography.title)
            
            Text("Your workouts have been enriched with health data.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            Button(action: { isPresented = false }) {
                Text("Done")
                    .font(Theme.Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.Colors.success)
                    .foregroundColor(.white)
                    .cornerRadius(Theme.CornerRadius.large)
            }
            .padding(Theme.Spacing.xl)
        }
    }
    
    // MARK: - Logic
    
    private func requestAuthorization() {
        Task {
            do {
                try await healthManager.requestAuthorization()
                withAnimation { step = 2 }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func startSync() {
        Task {
            do {
                // The syncAllWorkouts method now updates published properties on healthManager
                // We don't need to manually poll, but we do need to wait for it to finish
                let _ = try await healthManager.syncAllWorkouts(workouts)
                
                // Slight delay to show completion before moving to success
                try await Task.sleep(nanoseconds: 500_000_000)
                
                withAnimation {
                    step = 3 // Success step
                }
                Haptics.notify(.success)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
