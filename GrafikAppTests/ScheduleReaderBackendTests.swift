import XCTest
@testable import GrafikApp

final class ScheduleReaderBackendTests: XCTestCase {
    func testSampleScheduleXLSXDiagnosticsAndICSCounts() throws {
        let backend = ScheduleReaderBackend()
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TestFixtures/sample_schedule.xlsx")

        let result = try backend.diagnoseXLSX(sourceURL: fixtureURL)
        let report = result.diagnostic

        XCTAssertFalse(report.selectedSheetName.isEmpty)
        XCTAssertFalse(report.recognizedDates.isEmpty)
        XCTAssertEqual(Set(report.recognizedEmployees.map(\.interpretedAs)).count, 8)

        let employee = "Aleksander Vizváry"
        let employeeAssignments = report.assignments.filter { $0.employee == employee }
        XCTAssertFalse(employeeAssignments.isEmpty)

        for assignment in report.assignments {
            XCTAssertEqual(columnLetters(assignment.dateReference), columnLetters(assignment.shiftReference))
            XCTAssertLessThan(assignment.shift.startHour, assignment.shift.endHour)
        }

        let events = backend.makeCalendarEvents(schedule: result.schedule, client: employee)
        let ics = backend.makeICS(events: events)
        XCTAssertEqual(ics.components(separatedBy: "BEGIN:VEVENT").count - 1, employeeAssignments.count)

        let preview = report.assignments.prefix(10).map {
            "dateCell=\($0.dateReference) employeeCell=\($0.employeeReference) shiftCell=\($0.shiftReference) date=\($0.date) employee=\($0.employee) hours=\($0.shift.displayText)"
        }.joined(separator: "\n")
        print("[Diagnostic first 10 assignments]\n\(preview)")
    }

    private func columnLetters(_ reference: String) -> String {
        String(reference.prefix { $0.isLetter })
    }
}
