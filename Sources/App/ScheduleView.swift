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
                    let unplaced = store.table.courses.filter { $0.unscheduledWeeks != nil }
                    if !unplaced.isEmpty {
                        Button("未排时间课程 \(unplaced.count) 门 · 列表中查看") { mode = .list }.font(.caption)
                    }
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
            .navigationBarTitleDisplayMode(.inline)
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
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button("上一周", systemImage: "chevron.left") { changeWeek(-1) }
                    .labelStyle(.iconOnly).frame(width: 40, height: 36).disabled(week == 1)
                Menu {
                    ForEach(1...store.table.totalWeeks, id: \.self) { value in Button("第 \(value) 周") { week = value } }
                } label: { Text("第 \(week) 周").font(.headline).frame(maxWidth: .infinity) }
                Button("本周") { jumpToCurrentWeek() }.font(.subheadline)
                Button("下一周", systemImage: "chevron.right") { changeWeek(1) }
                    .labelStyle(.iconOnly).frame(width: 40, height: 36).disabled(week == store.table.totalWeeks)
            }
            Picker("显示方式", selection: $mode) {
                ForEach(ScheduleMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
        }
    }
    private var agenda: some View {
        List {
            if mode == .day {
                Picker("星期", selection: $day) {
                    ForEach(1...7, id: \.self) { Text(weekdayNames[$0 - 1]).tag($0) }
                }.pickerStyle(.menu)
            }
            let unplaced = store.table.courses.filter { $0.unscheduledWeeks != nil }
            if !unplaced.isEmpty {
                Section("未排时间") {
                    ForEach(unplaced) { course in
                        Button { selection = CourseSelection(course: course) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(course.name).foregroundStyle(.primary)
                                Text("第 \((course.unscheduledWeeks ?? []).map(String.init).joined(separator: ",")) 周 · \(course.location)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
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
    @ScaledMetric(relativeTo: .body) private var minimumRowHeight: CGFloat = 42
    @ScaledMetric(relativeTo: .body) private var minimumWidth: CGFloat = 44
    private var days: Int { table.showWeekend ? 7 : 5 }
    private var blocks: [CourseBlock] { ScheduleEngine.blocks(table: table, week: week) }

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = max(minimumWidth, (geometry.size.width - 44) / CGFloat(days))
            let rowHeight = max(minimumRowHeight, min(64, (geometry.size.height - 52 - 24) / CGFloat(profile.periods.count)))
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("节次").font(.caption2).foregroundStyle(.secondary).frame(width: 44)
                        ForEach(1...days, id: \.self) { day in dateHeader(day).frame(width: columnWidth) }
                    }.frame(height: 48)
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 0) {
                            VStack(spacing: 0) {
                                ForEach(profile.periods) { time in
                                    if isSessionStart(time.period) { Color.clear.frame(height: 10) }
                                    VStack(spacing: 4) {
                                        Text("\(time.period)").font(.subheadline.weight(.semibold))
                                        Text(PeriodTime.clock(time.start)).font(.system(size: 10, design: .rounded)).monospacedDigit()
                                        Text(PeriodTime.clock(time.end)).font(.system(size: 10, design: .rounded)).foregroundStyle(.tertiary).monospacedDigit()
                                    }.foregroundStyle(.secondary).frame(width: 44, height: rowHeight)
                                }
                            }
                            ForEach(1...days, id: \.self) { day in
                                dayColumn(day, width: columnWidth, rowHeight: rowHeight)
                            }
                        }.padding(.bottom, 4)
                    }
                }.frame(width: 44 + columnWidth * CGFloat(days))
            }
            .scrollIndicators(.automatic)
        }
    }
    private func isSessionStart(_ period: Int) -> Bool {
        period > 1 && (period == profile.counts[0] + 1 || period == profile.counts[0] + profile.counts[1] + 1)
    }
    private func yPosition(_ period: Int, rowHeight: CGFloat) -> CGFloat {
        CGFloat(period - 1) * rowHeight + CGFloat((1...period).filter { isSessionStart($0) }.count) * 10
    }
    private func dateHeader(_ day: Int) -> some View {
        let date = ScheduleEngine.date(week: week, weekday: day, table: table)
        let today = Calendar.current.isDateInToday(date)
        return VStack(spacing: 5) {
            Text(weekdayNames[day - 1]).font(.caption).foregroundStyle(.secondary)
            Text("\(Calendar.current.component(.day, from: date))").font(.subheadline.weight(.semibold))
                .frame(width: 30, height: 30)
                .background(today ? Color.indigo : Color.clear, in: Circle())
                .foregroundStyle(today ? Color.white : Color.primary)
        }.accessibilityElement(children: .combine)
    }
    private func dayColumn(_ day: Int, width: CGFloat, rowHeight: CGFloat) -> some View {
        let dayBlocks = blocks.filter { $0.weekday == day }
        let groups = ScheduleEngine.overlapGroups(dayBlocks)
        let date = ScheduleEngine.date(week: week, weekday: day, table: table)
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(profile.periods) { time in
                    if isSessionStart(time.period) { Color.clear.frame(height: 10) }
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
                    .frame(width: max(1, laneWidth - 5), height: yPosition(block.last, rowHeight: rowHeight) - yPosition(block.first, rowHeight: rowHeight) + rowHeight - 4)
                    .offset(x: CGFloat(lane) * laneWidth + 2, y: yPosition(block.first, rowHeight: rowHeight) + 2)
                    .accessibilityLabel("\(block.course.name)，\(weekdayNames[day - 1])，第 \(block.first) 到 \(block.last) 节，\(block.course.location)\(group.count > 1 ? "，有时间冲突" : "")")
                }
            }
        }
        .frame(width: width, height: yPosition(profile.periods.count, rowHeight: rowHeight) + rowHeight)
        .background(Calendar.current.isDateInToday(date) ? Color.indigo.opacity(0.035) : Color.clear)
    }
}

private struct CourseTile: View {
    let block: CourseBlock
    let conflict: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 3) {
                if conflict && geometry.size.height > 60 { Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.orange) }
                Text(block.course.name).font(.caption.weight(.semibold)).lineLimit(geometry.size.height > 85 ? 3 : 2)
                if !block.course.location.isEmpty && geometry.size.height > 75 {
                    Text(block.course.location).font(.caption2).lineLimit(2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if geometry.size.height > 100 { Text("\(block.first)–\(block.last) 节").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 4).padding(.vertical, 6)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .background(Color(argb: block.course.color).opacity(scheme == .dark ? 0.3 : 0.16), in: RoundedRectangle(cornerRadius: 9))
        .overlay(alignment: .top) { Capsule().fill(Color(argb: block.course.color)).frame(height: 3).padding(.horizontal, 6) }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}
