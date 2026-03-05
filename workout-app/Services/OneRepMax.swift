
/// Epley-formula one-rep max estimator used throughout the app.
/// Centralised here so the formula is never duplicated.
enum OneRepMax {
    /// Estimate the one-rep max for a given weight and rep count (Epley formula).
    static func estimate(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        return weight * (1 + 0.0333 * Double(reps))
    }
}
