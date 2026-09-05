import CoreGraphics
import PDFKit
import XCTest
@testable import workout_app

final class WorkoutPDFExporterTests: XCTestCase {
    func testSessionTotalsAndMuscleExposureDoNotDoubleCountWorkoutDuration() throws {
        let document = try fixture(workoutCount: 4, setsPerExercise: 5)
        let summary = WorkoutPDFAnalytics(document)
        XCTAssertEqual(summary.sessions.count, 4)
        XCTAssertEqual(summary.durationCount, 4)
        XCTAssertEqual(summary.durationSeconds, 4 * 1800)
        XCTAssertEqual(summary.exercises.reduce(0) { $0 + $1.count }, 40)
        XCTAssertEqual(summary.mappedSetCount, 20)
        XCTAssertEqual(summary.muscles.first { $0.name == "Chest" }?.count, 20)
        XCTAssertEqual(summary.muscles.first { $0.name == "Triceps" }?.secondary, 10)
    }

    func testBucketsAdaptFromDaysToDecadesWithoutDroppingWorkouts() throws {
        for span in [1, 21, 180, 720, 2400, 36500] {
            let document = try fixture(workoutCount: 40, dayStride: max(1, span / 39), setsPerExercise: 1)
            let summary = WorkoutPDFAnalytics(document)
            XCTAssertLessThanOrEqual(summary.buckets.count, 32)
            XCTAssertEqual(summary.buckets.reduce(0) { $0 + $1.workouts }, 40)
            XCTAssertEqual(summary.buckets.reduce(0) { $0 + $1.sets }, 80)
            XCTAssertEqual(summary.weekdays.reduce(0, +), 40)
        }
    }

    func testTrendsRequireRepeatedExercisesAndPreserveMissingIntervals() throws {
        let document = try fixture(workoutCount: 3, dayStride: 5, setsPerExercise: 1)
        let summary = WorkoutPDFAnalytics(document)
        XCTAssertEqual(summary.trends.count, 2)
        XCTAssertTrue(summary.trends.allSatisfy { $0.sessionCount == 3 && $0.values.contains(where: { $0 == nil }) })
        XCTAssertTrue(summary.trends.allSatisfy { $0.values.compactMap { $0 }.count == 3 })
        XCTAssertTrue(WorkoutPDFAnalytics(try fixture(workoutCount: 2)).trends.isEmpty)
        XCTAssertTrue(WorkoutPDFAnalytics(try fixture(workoutCount: 4, dayStride: 0)).trends.isEmpty)
    }

    func testLongNumericValuesStayInTheJournalWithoutTruncation() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let weight = Double.greatestFiniteMagnitude
        let set = WorkoutSet(date: date, workoutName: "Precision", duration: "unknown", exerciseName: "Measured set",
                             setOrder: 1, weight: weight, reps: 1, distance: 0.000000125, seconds: 0.125)
        let workout = Workout(date: date, name: "Precision", duration: "unknown", exercises: [Exercise(name: "Measured set", sets: [set])])
        let document = try WorkoutExportDocument(workouts: [workout], startDate: date, endDateInclusive: date)
        try render(document, journal: true) { pdf, audit, _ in
            let characters = (pdf.string ?? "").filter { !$0.isWhitespace }
            XCTAssertTrue(characters.contains(WorkoutExportValue.number(weight).text))
            XCTAssertEqual(audit.overflowingText, 0)
            XCTAssertEqual(audit.setRows, 1)
        }
    }

    func testExcludedFieldsDoNotReappearInChartsOrPDFText() throws {
        let document = try fixture(workoutCount: 6, columns: [.setNumber])
        let summary = WorkoutPDFAnalytics(document)
        XCTAssertTrue(summary.exercises.isEmpty)
        XCTAssertTrue(summary.muscles.isEmpty)
        XCTAssertTrue(summary.buckets.isEmpty)
        XCTAssertTrue(summary.trends.isEmpty)
        XCTAssertEqual(summary.durationCount, 0)
        XCTAssertNil(summary.totalReps)
        try render(document, journal: true) { pdf, audit, _ in
            let text = pdf.string ?? ""
            for excluded in ["PRIVATE WORKOUT", "PRIVATE GYM", "Chest Press", "Triceps", "100.125"] {
                XCTAssertFalse(text.contains(excluded), excluded)
            }
            XCTAssertEqual(audit.overflowingText, 0)
            XCTAssertEqual(audit.outOfBounds, 0)
        }
    }

    func testSingleSessionHasOneUsefulOverviewPageAndOptionalJournal() throws {
        let document = try fixture(workoutCount: 1, setsPerExercise: 1)
        try render(document, journal: false) { pdf, audit, _ in
            XCTAssertEqual(pdf.pageCount, 1)
            XCTAssertEqual(audit.setRows, 0)
            XCTAssertTrue(pdf.string?.contains("Selected sets by exercise") == true)
            XCTAssertFalse(pdf.string?.contains("Exercise history charts") == true)
            XCTAssertEqual(audit.overflowingText, 0)
        }
        try render(document, journal: true) { pdf, audit, _ in
            XCTAssertEqual(pdf.pageCount, 2)
            XCTAssertEqual(audit.setRows, 2)
            XCTAssertEqual(audit.workoutHeadings, 1)
            XCTAssertTrue(pdf.string?.contains("100.125") == true)
        }
    }

    func testLargeHistoryKeepsOverviewBoundedAndFullJournalIncludesEverySet() throws {
        let document = try fixture(workoutCount: 240, dayStride: 15, setsPerExercise: 2)
        try render(document, journal: false) { pdf, audit, _ in
            XCTAssertLessThanOrEqual(pdf.pageCount, 3)
            XCTAssertEqual(audit.overflowingText, 0)
            XCTAssertEqual(audit.outOfBounds, 0)
        }
        try render(document, journal: true) { pdf, audit, url in
            XCTAssertGreaterThan(pdf.pageCount, 20)
            XCTAssertEqual(audit.setRows, 960)
            XCTAssertEqual(audit.workoutHeadings, 240)
            XCTAssertEqual(audit.overflowingText, 0)
            XCTAssertEqual(audit.outOfBounds, 0)
            let cgPDF = try XCTUnwrap(CGPDFDocument(url as CFURL))
            XCTAssertNotNil(cgPDF.outline)
            XCTAssertEqual(pdf.pageCount, audit.pages)
        }
    }

    func testVeryLongNamesAndLargeExercisesPaginateWithoutLosingRows() throws {
        let document = try fixture(workoutCount: 1, setsPerExercise: 150,
                                   longName: String(repeating: "Very long workout title with Unicode Café. ", count: 90))
        try render(document, journal: true) { pdf, audit, _ in
            XCTAssertEqual(audit.setRows, 300)
            XCTAssertEqual(audit.overflowingText, 0)
            XCTAssertEqual(audit.outOfBounds, 0)
            XCTAssertGreaterThan(pdf.pageCount, 8)
            XCTAssertTrue(pdf.string?.contains("continued") == true)
        }
    }

    func testPDFUsesSearchableTextAndBookmarks() throws {
        try render(try fixture(workoutCount: 4), journal: true) { pdf, audit, _ in
            XCTAssertTrue(pdf.string?.contains("Your training") == true)
            XCTAssertTrue(pdf.string?.contains("PRIVATE WORKOUT") == true)
            XCTAssertTrue(pdf.string?.contains("Muscle exposure") == true)
            XCTAssertNotNil(pdf.outlineRoot)
            XCTAssertGreaterThan(pdf.outlineRoot?.numberOfChildren ?? 0, 4)
            XCTAssertEqual(audit.overflowingText, 0)
            XCTAssertEqual(audit.outOfBounds, 0)
        }
    }

    func testWriteErrorsAreNotReportedAsSuccessfulPDFs() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.close()
        XCTAssertThrowsError(try WorkoutPDFRenderer.write(fixture(workoutCount: 1), to: handle))
    }

    private func render(
        _ document: WorkoutExportDocument, journal: Bool,
        verify: (PDFDocument, WorkoutPDFAudit, URL) throws -> Void
    ) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        let audit = try WorkoutPDFRenderer.write(document, to: handle, includeJournal: journal)
        try handle.close()
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        try verify(pdf, audit, url)
    }

    private func fixture(
        workoutCount: Int, dayStride: Int = 2, setsPerExercise: Int = 3,
        columns: [WorkoutExportColumn] = WorkoutExportColumn.defaultColumns, longName: String? = nil
    ) throws -> WorkoutExportDocument {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        let start = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1, hour: 10))!
        let workouts = (0..<workoutCount).map { index -> Workout in
            let date = calendar.date(byAdding: .day, value: index * dayStride, to: start)!
            return Workout(date: date, name: longName ?? "PRIVATE WORKOUT \(index)", duration: "30m", exercises:
                ["Chest Press", "Seated Row"].map { exercise in
                    Exercise(name: exercise, sets: (1...setsPerExercise).map { number in
                        WorkoutSet(date: date, workoutName: "PRIVATE WORKOUT", duration: "30m", exerciseName: exercise,
                                   setOrder: number, weight: 100.125 + Double(index), reps: 8, distance: 0, seconds: 0)
                    })
                })
        }
        return try WorkoutExportDocument(
            workouts: workouts, startDate: start, endDateInclusive: workouts.last!.date,
            exerciseTagsByName: ["Chest Press": "Primary: Chest; Secondary: Triceps"],
            exerciseMusclesByName: ["Chest Press": [.init(name: "Chest", role: "primary"), .init(name: "Triceps", role: "secondary")]],
            gymNamesByWorkoutID: Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, "PRIVATE GYM") }),
            selectedColumns: columns, weightUnit: "lbs", calendar: calendar
        )
    }
}
