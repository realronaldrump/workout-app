import SwiftUI
import Charts

struct ExerciseDetailView: View {
    let exerciseName: String
    @ObservedObject var dataManager: WorkoutDataManager
    @State private var selectedChart = ChartType.weight
    
    enum ChartType: String, CaseIterable {
        case weight = "Max Weight"
        case volume = "Volume"
        case oneRepMax = "1RM"
        case reps = "Reps"
    }
    
    private var exerciseHistory: [(date: Date, sets: [WorkoutSet])] {
        dataManager.getExerciseHistory(for: exerciseName)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ExerciseStatsCards(exerciseName: exerciseName, history: exerciseHistory)
                
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Progress Chart")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        Picker("Chart Type", selection: $selectedChart) {
                            ForEach(ChartType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    ExerciseProgressChart(history: exerciseHistory, chartType: selectedChart)
                        .frame(height: 250)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }
                
                PersonalRecordsView(history: exerciseHistory)
                
                RecentSetsView(history: exerciseHistory)
            }
            .padding()
        }
        .navigationTitle(exerciseName)
        .navigationBarTitleDisplayMode(.large)
    }
}

struct ExerciseStatsCards: View {
    let exerciseName: String
    let history: [(date: Date, sets: [WorkoutSet])]
    
    private var stats: (total: Int, maxWeight: Double, maxVolume: Double, avgReps: Double) {
        let allSets = history.flatMap { $0.sets }
        let maxWeight = allSets.map { $0.weight }.max() ?? 0
        let volumes = history.map { session in
            session.sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
        }
        let maxVolume = volumes.max() ?? 0
        let avgReps = allSets.isEmpty ? 0 : Double(allSets.reduce(0) { $0 + $1.reps }) / Double(allSets.count)
        
        return (allSets.count, maxWeight, maxVolume, avgReps)
    }
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            StatCard(
                title: "Total Sets",
                value: "\(stats.total)",
                icon: "number",
                color: .blue
            )
            
            StatCard(
                title: "Max Weight",
                value: "\(Int(stats.maxWeight)) lbs",
                icon: "scalemass.fill",
                color: .orange
            )
            
            StatCard(
                title: "Max Volume",
                value: formatVolume(stats.maxVolume),
                icon: "chart.bar.fill",
                color: .green
            )
            
            StatCard(
                title: "Avg Reps",
                value: String(format: "%.1f", stats.avgReps),
                icon: "repeat",
                color: .purple
            )
        }
    }
    
    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk lbs", volume / 1000)
        }
        return "\(Int(volume)) lbs"
    }
}

struct ExerciseProgressChart: View {
    let history: [(date: Date, sets: [WorkoutSet])]
    let chartType: ExerciseDetailView.ChartType
    
    @State private var isAppearing = false
    @State private var selectedDataPoint: (date: Date, value: Double)?
    
    private var chartData: [(date: Date, value: Double)] {
        history.map { session in
            let value: Double
            switch chartType {
            case .weight:
                value = session.sets.map { $0.weight }.max() ?? 0
            case .volume:
                value = session.sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
            case .oneRepMax:
                let bestSet = session.sets.max { set1, set2 in
                    calculateOneRepMax(weight: set1.weight, reps: set1.reps) <
                    calculateOneRepMax(weight: set2.weight, reps: set2.reps)
                }
                value = bestSet.map { calculateOneRepMax(weight: $0.weight, reps: $0.reps) } ?? 0
            case .reps:
                value = Double(session.sets.map { $0.reps }.max() ?? 0)
            }
            return (date: session.date, value: value)
        }
    }
    
    private var prDate: Date? {
        chartData.max(by: { $0.value < $1.value })?.date
    }
    
    private var chartColor: Color {
        switch chartType {
        case .weight: return Theme.Colors.push
        case .volume: return Theme.Colors.legs
        case .oneRepMax: return Theme.Colors.gold
        case .reps: return Theme.Colors.pull
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Selected point info
            if let selected = selectedDataPoint {
                selectedPointHeader(selected: selected)
            }
            
            chartView
        }
        .onAppear {
            withAnimation(Theme.Animation.chartAppear) {
                isAppearing = true
            }
        }
    }
    
    @ViewBuilder
    private func selectedPointHeader(selected: (date: Date, value: Double)) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(selected.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(formatValue(selected.value))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(chartColor)
            }
            
            Spacer()
            
            if selected.date == prDate {
                PRMarkerView(date: selected.date)
            }
        }
        .padding(.horizontal, 4)
        .transition(.opacity)
    }
    
    private var chartView: some View {
        Chart {
            areaMarks
            lineMarks
            pointMarks
            trendLineMarks
            selectionRuleMark
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = value.location.x - geometry[proxy.plotFrame!].origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    // Find closest data point
                                    if let closest = chartData.min(by: {
                                        abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                    }) {
                                        selectedDataPoint = closest
                                    }
                                }
                            }
                            .onEnded { _ in
                                // Keep selection visible for a moment
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation {
                                        selectedDataPoint = nil
                                    }
                                }
                            }
                    )
            }
        }
    }
    
    @ChartContentBuilder
    private var areaMarks: some ChartContent {
        ForEach(chartData, id: \.date) { dataPoint in
            AreaMark(
                x: .value("Date", dataPoint.date),
                y: .value(chartType.rawValue, isAppearing ? dataPoint.value : 0)
            )
            .foregroundStyle(chartColor.opacity(0.15))
            .interpolationMethod(.catmullRom)
        }
    }
    
    @ChartContentBuilder
    private var lineMarks: some ChartContent {
        ForEach(chartData, id: \.date) { dataPoint in
            LineMark(
                x: .value("Date", dataPoint.date),
                y: .value(chartType.rawValue, isAppearing ? dataPoint.value : 0)
            )
            .foregroundStyle(chartColor)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .interpolationMethod(.catmullRom)
        }
    }
    
    @ChartContentBuilder
    private var pointMarks: some ChartContent {
        ForEach(chartData, id: \.date) { dataPoint in
            PointMark(
                x: .value("Date", dataPoint.date),
                y: .value(chartType.rawValue, isAppearing ? dataPoint.value : 0)
            )
            .foregroundStyle(dataPoint.date == prDate ? Theme.Colors.gold : chartColor)
            .symbolSize(dataPoint.date == prDate ? 100 : 50)
            .annotation(position: .top) {
                if dataPoint.date == prDate {
                    Image(systemName: "trophy.fill")
                        .font(.caption2)
                        .foregroundColor(Theme.Colors.gold)
                        .opacity(isAppearing ? 1 : 0)
                }
            }
        }
    }
    
    @ChartContentBuilder
    private var trendLineMarks: some ChartContent {
        if let trend = calculateTrendLine(), isAppearing {
            LineMark(
                x: .value("Date", trend.start.date),
                y: .value("Trend", trend.start.value)
            )
            .foregroundStyle(Color.secondary.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            
            LineMark(
                x: .value("Date", trend.end.date),
                y: .value("Trend", trend.end.value)
            )
            .foregroundStyle(Color.secondary.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
    }
    
    @ChartContentBuilder
    private var selectionRuleMark: some ChartContent {
        if let selected = selectedDataPoint {
            RuleMark(x: .value("Selected", selected.date))
                .foregroundStyle(chartColor.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }
    
    private func formatValue(_ value: Double) -> String {
        switch chartType {
        case .weight, .oneRepMax:
            return "\(Int(value)) lbs"
        case .volume:
            if value >= 1000 {
                return String(format: "%.1fk lbs", value / 1000)
            }
            return "\(Int(value)) lbs"
        case .reps:
            return "\(Int(value)) reps"
        }
    }
    
    private func calculateOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        return weight * (1 + 0.0333 * Double(reps))
    }
    
    private func calculateTrendLine() -> (start: (date: Date, value: Double), end: (date: Date, value: Double))? {
        guard chartData.count >= 2 else { return nil }
        
        // Simple linear regression
        let n = Double(chartData.count)
        let sumX = chartData.enumerated().reduce(0.0) { $0 + Double($1.offset) }
        let sumY = chartData.reduce(0.0) { $0 + $1.value }
        let sumXY = chartData.enumerated().reduce(0.0) { $0 + (Double($1.offset) * $1.element.value) }
        let sumXX = chartData.enumerated().reduce(0.0) { $0 + (Double($1.offset) * Double($1.offset)) }
        
        let slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX)
        let intercept = (sumY - slope * sumX) / n
        
        let startValue = intercept
        let endValue = slope * (n - 1) + intercept
        
        return (
            start: (date: chartData.first!.date, value: startValue),
            end: (date: chartData.last!.date, value: endValue)
        )
    }
}

struct PersonalRecordsView: View {
    let history: [(date: Date, sets: [WorkoutSet])]
    
    private var records: [(title: String, value: String, date: Date)] {
        let allSets = history.flatMap { session in
            session.sets.map { (set: $0, date: session.date) }
        }
        
        var records: [(title: String, value: String, date: Date)] = []
        
        // Max weight
        if let maxWeightSet = allSets.max(by: { $0.set.weight < $1.set.weight }) {
            records.append(("Heaviest Weight", "\(Int(maxWeightSet.set.weight)) lbs × \(maxWeightSet.set.reps)", maxWeightSet.date))
        }
        
        // Max volume single set
        if let maxVolumeSet = allSets.max(by: { 
            $0.set.weight * Double($0.set.reps) < $1.set.weight * Double($1.set.reps)
        }) {
            let volume = maxVolumeSet.set.weight * Double(maxVolumeSet.set.reps)
            records.append(("Max Volume (Single Set)", "\(Int(volume)) lbs", maxVolumeSet.date))
        }
        
        // Max reps
        if let maxRepsSet = allSets.max(by: { $0.set.reps < $1.set.reps }) {
            records.append(("Most Reps", "\(maxRepsSet.set.reps) @ \(Int(maxRepsSet.set.weight)) lbs", maxRepsSet.date))
        }
        
        // Best 1RM
        if let best1RM = allSets.max(by: { 
            calculateOneRepMax(weight: $0.set.weight, reps: $0.set.reps) <
            calculateOneRepMax(weight: $1.set.weight, reps: $1.set.reps)
        }) {
            let orm = calculateOneRepMax(weight: best1RM.set.weight, reps: best1RM.set.reps)
            records.append(("Est. 1RM", "\(Int(orm)) lbs", best1RM.date))
        }
        
        return records
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Personal Records")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(spacing: 12) {
                ForEach(records, id: \.title) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.title)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(record.value)
                                .font(.headline)
                        }
                        
                        Spacer()
                        
                        Text(record.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    private func calculateOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        return weight * (1 + 0.0333 * Double(reps))
    }
}

struct RecentSetsView: View {
    let history: [(date: Date, sets: [WorkoutSet])]
    
    private var recentSessions: [(date: Date, sets: [WorkoutSet])] {
        Array(history.sorted { $0.date > $1.date }.prefix(5))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Sessions")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(spacing: 12) {
                ForEach(recentSessions, id: \.date) { session in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        ForEach(Array(session.sets.enumerated()), id: \.offset) { index, set in
                            HStack {
                                Text("Set \(index + 1)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 50, alignment: .leading)
                                
                                Text("\(Int(set.weight)) lbs × \(set.reps)")
                                    .font(.system(.body, design: .monospaced))
                                
                                Spacer()
                                
                                Text("\(Int(set.weight * Double(set.reps))) lbs")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
            }
        }
    }
}