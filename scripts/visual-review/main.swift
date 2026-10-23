import AppKit
import SwiftUI
import YIClassCore

@main struct VisualReview {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let output = root.appendingPathComponent("dist/visual-review")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let day = calendar.startOfDay(for: Date())
        let weekday = (calendar.component(.weekday, from: day) + 5) % 7 + 1
        let course = Course(name: "高等数学", location: "蘭榕楼 2 号多媒体教室", color: 0xFFAE65A3,
            schedules: [CourseSchedule(weekday: weekday, periods: [1,2], weekPattern: [1])])
        let table = Timetable(name: "青大", startDate: ScheduleEngine.monday(of: day), courses: [course])
        let todo = TodoItem(title: "完成实验报告", notes: "整理实验数据，提交课程平台", deadline: day.addingTimeInterval(23*3600+59*60), importance: .high, createdAt: day)
        let task2 = TodoItem(title: "准备英语展示", deadline: day.addingTimeInterval(18*3600), createdAt: day)
        let document = DayAgendaDocument(todos: [todo, task2], placements: [TodoPlacement(todoID: todo.id, start: day.addingTimeInterval(9*3600), end: day.addingTimeInterval(10*3600))])
        let fixture = AppData(timeProfile: .standard, timetables: [table], selectedID: table.id, todos: document.todos)
        let dayItems = DayAgendaEngine.items(data: fixture, agenda: document, on: day)
        for dark in [false, true] {
            let sheet = VStack(alignment: .leading, spacing: 22) {
                Text("Lock screen · actual SwiftUI view").font(.title3.bold())
                ForEach([52, 56, 60, 68, 72, 76], id: \.self) { height in
                    HStack(alignment: .center, spacing: 18) {
                        Text("160 × \(height)").font(.system(size: 12).monospaced()).frame(width: 75)
                        LockScreenCourseCard(title: "习近平新时代中国特色社会主义思想概论", time: "14:00–15:40", location: "蘭榕楼_2号多媒体教室", active: true, remainingFraction: 0.65)
                            .frame(width: 160, height: CGFloat(height))
                        LockScreenCourseCard(title: "普通化学实验", time: "10:50–12:30", location: "化工学院楼实验教室", tomorrow: true, single: false)
                            .frame(width: 160, height: CGFloat(height))
                        LockScreenCourseCard(title: "大学英语（一）", time: "08:30–10:10", location: "致明楼_501", single: false)
                            .frame(width: 160, height: CGFloat(height))
                    }
                }
                Text("Vector book · 20 / 34 / 88 pt; 34 pt inside 60 pt circle").font(.system(size: 12))
                HStack(spacing: 35) {
                    AssistantLogo(size: 20)
                    AssistantLogo(size: 34)
                    AssistantLogo(size: 88)
                    AssistantLogo(size: 34).frame(width: 60, height: 60)
                        .overlay { Circle().stroke(.secondary, lineWidth: 0.5) }
                }.frame(height: 100)
            }
            .padding(24)
            .background(dark ? Color(white: 0.08) : Color(white: 0.96))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            let agendaSheet = HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("日程 · 课程与待办").font(.title2.bold())
                    Text(day, format: .dateTime.month().day().weekday()).font(.headline).foregroundStyle(.secondary)
                    DayTimelineCanvas(items: dayItems, date: day, now: day.addingTimeInterval(9*3600+30*60))
                        .frame(width: 365, height: 390, alignment: .top).clipped()
                }.frame(width: 365)
                VStack(alignment: .leading, spacing: 14) {
                    Text("待办").font(.title2.bold())
                    TodoTaskCard(item: todo, reference: day.addingTimeInterval(12*3600), placement: document.placements.first, complete: {}, edit: {})
                    TodoTaskCard(item: task2, reference: day.addingTimeInterval(12*3600), complete: {}, edit: {})
                    Text("待办锁屏组件 · 160 × 56 / 76").font(.caption)
                    TodoWidgetContent(todos: document.todos, date: day.addingTimeInterval(12*3600))
                        .frame(width: 160, height: 56).border(.secondary.opacity(0.25))
                    TodoWidgetContent(todos: document.todos, date: day.addingTimeInterval(12*3600))
                        .frame(width: 160, height: 76).border(.secondary.opacity(0.25))
                }.frame(width: 340)
            }.padding(24)
                .background(dark ? Color(white: 0.08) : Color(white: 0.96))
                .environment(\.colorScheme, dark ? .dark : .light)
                .environment(\.locale, Locale(identifier: "zh_CN"))
            let agendaRenderer = ImageRenderer(content: agendaSheet)
            agendaRenderer.scale = 3
            guard let agendaImage = agendaRenderer.cgImage,
                  let agendaPNG = NSBitmapImageRep(cgImage: agendaImage).representation(using: .png, properties: [:]) else { fatalError("Agenda render failed") }
            try agendaPNG.write(to: output.appendingPathComponent(dark ? "agenda-dark.png" : "agenda-light.png"))
            let renderer = ImageRenderer(content: sheet)
            renderer.scale = 3
            guard let image = renderer.cgImage else { fatalError("SwiftUI image render failed") }
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encode failed") }
            try png.write(to: output.appendingPathComponent(dark ? "dark.png" : "light.png"))
        }
        print("Rendered production lock-screen card and logo with SwiftUI at 3x")
    }
}
