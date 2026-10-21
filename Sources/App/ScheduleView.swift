import SwiftUI
import YIClassCore

private enum ScheduleMode: String, CaseIterable { case week = "周", day = "日", list = "列表" }
private struct CourseSelection: Identifiable { let course: Course; var id: UUID { course.id } }

struct ScheduleView: View {
    @Environment(AppStore.self) private var store
    @State private var week = 1
    @State private var day = (Calendar.current.component(.weekday, from: Date()) + 5) % 7 + 1
    @State private var mode = ScheduleMode.week
    @State private var selection: CourseSelection?
    @State private var newCourse = false
    @State private var newTable = false
    @State private var tableName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()
                VStack(spacing: 12) {
                    controls.padding(.horizontal, 16)
                    if store.table.courses.isEmpty {
                        ContentUnavailableView {
                            Label("把这一周安排好", systemImage: "calendar.badge.plus")
                        } description: {
                            Text("添加第一门课，或在设置中导入旧版 JSON 课表。")
                        } actions: { Button("添加课程") { newCourse = true }.buttonStyle(.glassProminent) }
                    } else if mode == .week {
                        WeekGrid(table: store.table, profile: store.profile, week: week) { selection = CourseSelection(course: $0) }
                    } else {
                        agenda
                    }
                }.padding(.top, 8)
            }
            .navigationTitle(store.table.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(store.data.timetables) { table in
                            Button { store.perform { try store.select(table.id) } } label: {
                                Label(table.name, systemImage: table.id == store.table.id ? "checkmark" : "calendar")
                            }
                        }
                        Button("新建课表", systemImage: "plus") { newTable = true }
                    } label: { Image(systemName: "square.stack").accessibilityLabel("切换课表") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加课程", systemImage: "plus") { newCourse = true }
                }
            }
            .sheet(isPresented: $newCourse) { CourseEditor(tableID: store.table.id, course: nil) }
            .sheet(item: $selection) { CourseEditor(tableID: store.table.id, course: $0.course) }
            .alert("新建课表", isPresented: $newTable) {
                TextField("课表名称", text: $tableName)
                Button("取消", role: .cancel) {}
                Button("创建") { store.perform { try store.create(name: tableName) }; tableName = "" }
            } message: { Text("新课表沿用设置中保存的统一课节时间。") }
            .onAppear { jumpToCurrentWeek() }
            .onChange(of: store.table.id) { _, _ in jumpToCurrentWeek() }
            .onChange(of: store.table.totalWeeks) { _, value in week = min(week, value) }
        }
    }
    private var controls: some View {
        GlassEffectContainer {
            GlassPanel {
                VStack(spacing: 12) {
                    HStack {
                        Button("上一周", systemImage: "chevron.left") { changeWeek(-1) }
                            .labelStyle(.iconOnly).frame(width: 44, height: 32).disabled(week == 1)
                        Spacer()
                        Menu {
                            ForEach(1...store.table.totalWeeks, id: \.self) { value in
                                Button("第 \(value) 周") { week = value }
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text("第 \(week) 周").font(.headline)
                                Text(ScheduleEngine.date(week: week, weekday: 1, table: store.table), format: .dateTime.month().day())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("下一周", systemImage: "chevron.right") { changeWeek(1) }
                            .labelStyle(.iconOnly).frame(width: 44, height: 32).disabled(week == store.table.totalWeeks)
                    }
                    HStack {
                        Picker("显示方式", selection: $mode) {
                            ForEach(ScheduleMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                        Button("本周") { jumpToCurrentWeek() }.font(.subheadline).buttonStyle(.glass)
                    }
                }
            }
        }
    }
    private var agenda: some View {
        List {
            if mode == .day {
                Picker("星期", selection: $day) {
                    ForEach(1...7, id: \.self) { Text(weekdayNames[$0 - 1]).tag($0) }
                }.pickerStyle(.menu)
            }
            let blocks = ScheduleEngine.blocks(table: store.table, week: week)
            let days = mode == .day ? [day] : Array(1...7)
            ForEach(days, id: \.self) { weekday in
                Section {
                    let courses = blocks.filter { $0.weekday == weekday }
                    if courses.isEmpty { Text("没有课程，留点时间给自己").foregroundStyle(.secondary) }
                    ForEach(courses) { block in
                        Button { selection = CourseSelection(course: block.course) } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 3).fill(Color(argb: block.course.color)).frame(width: 4)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(block.course.name).font(.headline).foregroundStyle(.primary)
                                    Text([block.course.location, block.course.teacher].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    Text(timeLabel(block)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: { Text(weekdayNames[weekday - 1]) }
            }
        }.scrollContentBackground(.hidden)
    }
    private func timeLabel(_ block: CourseBlock) -> String {
        let times = store.profile.periods
        return "第 \(block.first)–\(block.last) 节 · \(PeriodTime.clock(times[block.first - 1].start))–\(PeriodTime.clock(times[block.last - 1].end))"
    }
    private func changeWeek(_ offset: Int) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { week = max(1, min(store.table.totalWeeks, week + offset)) }
    }
    private func jumpToCurrentWeek() {
        week = max(1, min(store.table.totalWeeks, ScheduleEngine.week(on: Date(), table: store.table)))
    }
}

struct WeekGrid: View {
    let table: Timetable
    let profile: TimeProfile
    let week: Int
    let onSelect: (Course) -> Void
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 83
    @ScaledMetric(relativeTo: .body) private var minimumWidth: CGFloat = 76
    private var days: Int { table.showWeekend ? 7 : 5 }
    private var blocks: [CourseBlock] { ScheduleEngine.blocks(table: table, week: week) }

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = max(minimumWidth, (geometry.size.width - 54) / CGFloat(days))
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("节次").font(.caption2).foregroundStyle(.secondary).frame(width: 54)
                        ForEach(1...days, id: \.self) { day in dateHeader(day).frame(width: columnWidth) }
                    }.frame(height: 62)
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 0) {
                            VStack(spacing: 0) {
                                ForEach(profile.periods) { time in
                                    VStack(spacing: 4) {
                                        Text("\(time.period)").font(.subheadline.weight(.semibold))
                                        Text(PeriodTime.clock(time.start)).font(.system(size: 10, design: .rounded)).monospacedDigit()
                                        Text(PeriodTime.clock(time.end)).font(.system(size: 10, design: .rounded)).foregroundStyle(.tertiary).monospacedDigit()
                                    }.foregroundStyle(.secondary).frame(width: 54, height: rowHeight)
                                }
                            }
                            ForEach(1...days, id: \.self) { day in
                                dayColumn(day, width: columnWidth)
                            }
                        }.padding(.bottom, 24)
                    }
                }.frame(width: 54 + columnWidth * CGFloat(days))
            }
            .scrollIndicators(.automatic)
        }
    }
    private func dateHeader(_ day: Int) -> some View {
        let date = ScheduleEngine.date(week: week, weekday: day, table: table)
        let today = Calendar.current.isDateInToday(date)
        return VStack(spacing: 5) {
            Text(weekdayNames[day - 1]).font(.caption).foregroundStyle(.secondary)
            Text(date, format: .dateTime.day()).font(.subheadline.weight(.semibold))
                .frame(width: 30, height: 30)
                .background(today ? Color.indigo : Color.clear, in: Circle())
                .foregroundStyle(today ? Color.white : Color.primary)
        }.accessibilityElement(children: .combine)
    }
    private func dayColumn(_ day: Int, width: CGFloat) -> some View {
        let dayBlocks = blocks.filter { $0.weekday == day }
        let groups = ScheduleEngine.overlapGroups(dayBlocks)
        let date = ScheduleEngine.date(week: week, weekday: day, table: table)
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(profile.periods) { _ in
                    Rectangle().fill(Color.primary.opacity(0.045)).frame(height: 0.5)
                        .frame(height: rowHeight, alignment: .top)
                }
            }
            ForEach(groups.indices, id: \.self) { index in
                let group = groups[index]
                ForEach(Array(group.enumerated()), id: \.element.id) { lane, block in
                    let laneWidth = width / CGFloat(group.count)
                    Button { onSelect(block.course) } label: {
                        CourseTile(block: block, conflict: group.count > 1)
                    }
                    .buttonStyle(.plain)
                    .frame(width: max(1, laneWidth - 5), height: CGFloat(block.last - block.first + 1) * rowHeight - 6)
                    .offset(x: CGFloat(lane) * laneWidth + 2, y: CGFloat(block.first - 1) * rowHeight + 3)
                    .accessibilityLabel("\(block.course.name)，\(weekdayNames[day - 1])，第 \(block.first) 到 \(block.last) 节，\(block.course.location)\(group.count > 1 ? "，有时间冲突" : "")")
                }
            }
        }
        .frame(width: width, height: CGFloat(profile.periods.count) * rowHeight)
        .background(Calendar.current.isDateInToday(date) ? Color.indigo.opacity(0.035) : Color.clear)
    }
}

private struct CourseTile: View {
    let block: CourseBlock
    let conflict: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if conflict { Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.orange) }
            Text(block.course.name).font(.caption.weight(.semibold)).lineLimit(4)
            if !block.course.location.isEmpty { Text(block.course.location).font(.caption2).lineLimit(3).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            Text("\(block.first)–\(block.last) 节").font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: block.course.color).opacity(scheme == .dark ? 0.24 : 0.13), in: RoundedRectangle(cornerRadius: 13))
        .overlay(alignment: .top) { Capsule().fill(Color(argb: block.course.color)).frame(height: 3).padding(.horizontal, 10) }
        .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(Color(argb: block.course.color).opacity(0.13)) }
        .contentShape(RoundedRectangle(cornerRadius: 13))
    }
}
