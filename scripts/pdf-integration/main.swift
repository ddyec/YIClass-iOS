import Foundation
import PDFKit
import YIClassCore

let path = CommandLine.arguments[1]
guard let pdf = PDFDocument(url: URL(fileURLWithPath: path)), let grid = PDFGridReader.read(pdf) else { fatalError("PDF columns were not detected") }
let table = try PDFTimetableImporter.parse(grid, template: Timetable(), profile: .standard)
let expected = try JSONDecoder().decode([PDFExpectedRow].self, from: Data(contentsOf: URL(fileURLWithPath: "Tests/Core/Fixtures/timetable-grid-expected.json"))).sorted { $0.key < $1.key }
let actual = PDFExpectedRow.rows(table)
if actual != expected {
    for row in actual where !expected.contains(row) { print("Unexpected:", row) }
    for row in expected where !actual.contains(row) { print("Missing:", row) }
    fatalError("PDF contents did not exactly match the manually audited 26 records")
}
let scheduled = table.courses.filter { !$0.schedules.isEmpty }
let unscheduled = table.courses.filter { $0.unscheduledWeeks != nil }
let arrangements = scheduled.flatMap(\.schedules)
guard Set(scheduled.map(\.name)).count == 12, arrangements.count == 21, unscheduled.count == 5 else {
    print(grid.source)
    fatalError("Expected 12 course names, 21 arrangements, 5 unscheduled courses; got \(Set(scheduled.map(\.name)).count)/\(arrangements.count)/\(unscheduled.count)")
}
let odd = scheduled.first { $0.name == "习近平新时代中国特色社会主义思想概论" && $0.location == "未排地点" }
precondition(odd?.schedules.first?.weekday == 3)
precondition(odd?.schedules.first?.periods == [9,10])
precondition(odd?.schedules.first?.weekPattern == [5,7,9,11])
let even = scheduled.first { $0.name == "普通化学II" && $0.location == "致明楼_501" }
precondition(even?.schedules.first?.weekday == 5)
precondition(even?.schedules.first?.weekPattern == [4,6,8,10,12])
let crossPage = scheduled.first { $0.name == "新时代实践教育" && $0.location == "致明楼_2号多媒体教室" }
precondition(crossPage?.schedules.first?.weekPattern == [9])
let saturday = scheduled.filter { $0.name == "大学生职业发展与就业指导" }.flatMap(\.schedules)
precondition(saturday.count == 2)
precondition(saturday.contains { $0.periods == [1,2,3,4] && $0.weekPattern == [9] && $0.weekday == 6 })
let before = Timetable(courses: [Course(name: "原有课程", schedules: [.init(weekday: 1, periods: [1], weekPattern: [1])])])
var profile = TimeProfile.standard
try profile.moveStart(0, to: 500)
let existing = AppData(timeProfile: profile, timetables: [before], selectedID: before.id)
let imported = try TimetableTransfer.applying(ImportPreview(table: table, suggestedProfile: nil), to: existing)
precondition(imported.timeProfile == profile && imported.timetables[0] == before)
let bytes = try TimetableTransfer.encode(table: table, profile: profile)
let restored = try TimetableTransfer.decode(bytes)
precondition(restored.table.courses == table.courses)
let manifest: [String: Any] = ["scheduledCourseNames": Set(scheduled.map(\.name)).sorted(), "arrangements": arrangements.count,
                               "unscheduled": unscheduled.map(\.name).sorted(), "courseRecords": table.courses.count,
                               "crossPage": true, "oddEven": true, "customTimesPreserved": true, "existingTablePreserved": true]
let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted,.sortedKeys])
print(String(decoding: json, as: UTF8.self))
print("PASS: PDFKit extraction → column reconstruction → complete import preview → application → export/reload")
