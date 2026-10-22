import SwiftUI
import UIKit
import YIClassCore

private enum ScheduleMode: String, CaseIterable { case week = "周", day = "日", list = "列表" }
private struct CourseSelection: Identifiable { let course: Course; var id: UUID { course.id } }

struct ScheduleView: View {
    @Environment(AppStore.self) private var store
    @State private var week = 1
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var choosingDate = false
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
                        ScrollView {
                            ContentUnavailableView {
                            Label(mode == .day ? "当天还没有课程" : "把这一周安排好", systemImage: "calendar.badge.plus")
                        } description: {
                            Text("添加课程，或在设置中导入课表。")
                        } actions: { Button("添加课程") { newCourse = true }.buttonStyle(.glassProminent) }
                                .containerRelativeFrame(.vertical)
                                .background { TabBarScrollConnection() }
                        }.scrollBounceBehavior(.always, axes: .vertical)
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
                        Divider()
                        Button("新建课表", systemImage: "plus") { newTable = true }
                    } label: { Image(systemName: "square.stack").accessibilityLabel("切换课表") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加课程", systemImage: "plus") { newCourse = true }
                }
            }
            .sheet(isPresented: $choosingDate) { dateCalendar }
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
            .onChange(of: mode) { old, value in
                if value == .day {
                    let weekday = (Calendar.current.component(.weekday, from: selectedDate) + 5) % 7 + 1
                    selectedDate = ScheduleEngine.date(week: week, weekday: weekday, table: store.table)
                } else if old == .day {
                    week = max(1, min(store.table.totalWeeks, ScheduleEngine.week(on: selectedDate, table: store.table)))
                }
            }
        }
    }
    private var controls: some View {
        VStack(spacing: 8) {
            if mode == .day { dayControls } else { HStack(spacing: 10) {
                Button("上一周", systemImage: "chevron.left") { changeWeek(-1) }
                    .labelStyle(.iconOnly).frame(width: 40, height: 36).disabled(week == 1)
                Menu {
                    ForEach(1...store.table.totalWeeks, id: \.self) { value in Button("第 \(value) 周") { week = value } }
                } label: {
                    HStack(spacing: 6) {
                        Text("第 \(week) 周").font(.headline)
                        Text(ScheduleEngine.date(week: week, weekday: 1, table: store.table), format: .dateTime.month().day())
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                }
                Button("本周") { jumpToCurrentWeek() }.font(.subheadline)
                Button("下一周", systemImage: "chevron.right") { changeWeek(1) }
                    .labelStyle(.iconOnly).frame(width: 40, height: 36).disabled(week == store.table.totalWeeks)
            } }
            Picker("显示方式", selection: $mode) {
                ForEach(ScheduleMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
        }
    }
    private var dayControls: some View {
        HStack(spacing: 10) {
            Button("前一天", systemImage: "chevron.left") { moveDay(-1) }
                .labelStyle(.iconOnly).frame(width: 40, height: 36)
            Button { choosingDate = true } label: {
                Text(selectedDate, format: .dateTime.month().day().weekday())
                    .font(.headline).frame(maxWidth: .infinity)
            }.accessibilityIdentifier("day-calendar")
            Button("本日") { selectedDate = Calendar.current.startOfDay(for: Date()) }.font(.subheadline)
            Button("后一天", systemImage: "chevron.right") { moveDay(1) }
                .labelStyle(.iconOnly).frame(width: 40, height: 36)
        }
    }
    private var dateCalendar: some View {
        NavigationStack {
            DatePicker("选择日期", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical).padding()
                .navigationTitle("选择日期").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { choosingDate = false } } }
        }.presentationDetents([.medium, .large])
    }
    private func moveDay(_ offset: Int) {
        if let date = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) { selectedDate = date }
    }
    private var agenda: some View {
        List {
            let unplaced = store.table.courses.filter { $0.unscheduledWeeks != nil }
            let shownWeek = mode == .day ? ScheduleEngine.week(on: selectedDate, table: store.table) : week
            let selectedDay = (Calendar.current.component(.weekday, from: selectedDate) + 5) % 7 + 1
            let blocks = ScheduleEngine.blocks(table: store.table, week: shownWeek)
            let days = mode == .day ? [selectedDay] : Array(1...7).filter { day in blocks.contains { $0.weekday == day } }
            if mode != .day && blocks.isEmpty { Text("本周暂无课程").foregroundStyle(Color.secondary) }
            ForEach(days, id: \.self) { weekday in
                Section {
                    let courses = blocks.filter { $0.weekday == weekday }
                    if courses.isEmpty { Text("当天暂无课程").foregroundStyle(Color.secondary) }
                    ForEach(courses) { block in
                        Button { selection = CourseSelection(course: block.course) } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 3).fill(Color(argb: block.course.color)).frame(width: 4)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(block.course.name).font(.headline).foregroundStyle(Color.primary)
                                    if !block.course.location.isEmpty || !block.course.teacher.isEmpty {
                                        Text([block.course.location, block.course.teacher].filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.subheadline).foregroundStyle(Color.secondary)
                                    }
                                    Text(timeLabel(block)).font(.caption.monospacedDigit()).foregroundStyle(Color.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                } header: { Text(weekdayNames[weekday - 1]) }
            }
            if mode == .list && !unplaced.isEmpty {
                Section {
                    DisclosureGroup {
                        ForEach(unplaced) { course in
                            Button { selection = CourseSelection(course: course) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(course.name).foregroundStyle(Color.primary)
                                    Text("第 \((course.unscheduledWeeks ?? []).map(String.init).joined(separator: ",")) 周 · \(course.location)")
                                        .font(.caption).foregroundStyle(Color.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    } label: {
                        Text("其他课程").font(.subheadline).foregroundStyle(Color.secondary)
                    }
                }
            }
        }.scrollContentBackground(.hidden)
            .scrollBounceBehavior(.always, axes: .vertical)
            .background { TabBarScrollConnection() }
    }
    private func timeLabel(_ block: CourseBlock) -> String {
        let times = store.profile.periods
        return "第 \(block.first)–\(block.last) 节 · \(PeriodTime.clock(times[block.first - 1].start))–\(PeriodTime.clock(times[block.last - 1].end))"
    }
    private func changeWeek(_ offset: Int) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { week = max(1, min(store.table.totalWeeks, week + offset)) }
    }
    private func jumpToCurrentWeek() {
        selectedDate = Calendar.current.startOfDay(for: Date())
        week = max(1, min(store.table.totalWeeks, ScheduleEngine.week(on: Date(), table: store.table)))
    }
}

struct WeekGrid: View {
    let table: Timetable
    let profile: TimeProfile
    let week: Int
    let onSelect: (Course) -> Void
    @ScaledMetric(relativeTo: .body) private var minimumRowHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var minimumWidth: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var sessionGap: CGFloat = 20
    @State private var showFullEvening = false
    private var days: Int { table.showWeekend ? 7 : 5 }
    private var daytimePeriodCount: Int { profile.counts[0] + profile.counts[1] }
    private var hasEveningCourses: Bool { blocks.contains { $0.last > daytimePeriodCount } }
    private var canCollapseEvening: Bool { profile.counts[2] > 0 && !hasEveningCourses }
    private var visiblePeriods: [PeriodTime] {
        let count = hasEveningCourses || showFullEvening ? profile.periods.count : max(1, daytimePeriodCount)
        return Array(profile.periods.prefix(count))
    }
    private var blocks: [CourseBlock] { ScheduleEngine.blocks(table: table, week: week) }

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = max(minimumWidth, minimumLaneWidth, (geometry.size.width - 44) / CGFloat(days))
            let daytimeCount = min(visiblePeriods.count, max(1, profile.counts[0] + profile.counts[1]))
            let daytimeGaps = CGFloat(visiblePeriods.prefix(daytimeCount).filter { isSessionStart($0.period) }.count) * sessionGap
            let footerHeight: CGFloat = canCollapseEvening ? 44 : 0
            let eveningPeek: CGFloat = visiblePeriods.count > daytimeCount ? sessionGap + 16 : 0
            let fittedHeight = (geometry.size.height - 72 - footerHeight - daytimeGaps - eveningPeek) / CGFloat(daytimeCount)
            let rowHeight = max(minimumRowHeight, min(64, fittedHeight))
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("节次").font(.caption2).foregroundStyle(.secondary).frame(width: 44)
                        ForEach(1...days, id: \.self) { day in dateHeader(day).frame(width: columnWidth) }
                    }.frame(height: 68)
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 0) {
                            VStack(spacing: 0) {
                                ForEach(visiblePeriods) { time in
                                    if isSessionStart(time.period) { Color.clear.frame(height: sessionGap) }
                                    VStack(spacing: 2) {
                                        Text("\(time.period)").font(.system(size: 12, weight: .semibold, design: .rounded))
                                        Text(PeriodTime.clock(time.start)).font(.system(size: 10, design: .rounded)).monospacedDigit()
                                        Text(PeriodTime.clock(time.end)).font(.system(size: 10, design: .rounded)).foregroundStyle(.tertiary).monospacedDigit()
                                    }.foregroundStyle(.secondary).frame(width: 44, height: rowHeight)
                                }
                            }
                            ForEach(1...days, id: \.self) { day in
                                dayColumn(day, width: columnWidth, rowHeight: rowHeight)
                            }
                        }.padding(.bottom, 4)
                            .background { TabBarScrollConnection() }
                    }.scrollBounceBehavior(.always, axes: .vertical)
                    if canCollapseEvening {
                        Button { showFullEvening.toggle() } label: {
                            Label(showFullEvening ? "收起晚间" : "晚间无课 · 展开", systemImage: showFullEvening ? "chevron.up" : "moon")
                                .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(.tint)
                    }
                }.frame(width: 44 + columnWidth * CGFloat(days))
            }
            .scrollIndicators(.automatic)
        }
        .onChange(of: week) { _, _ in showFullEvening = false }
        .onChange(of: table.id) { _, _ in showFullEvening = false }
    }
    private var minimumLaneWidth: CGFloat {
        let lanes = (1...days).flatMap { day in
            ScheduleEngine.overlapGroups(blocks.filter { $0.weekday == day }).map(\.count)
        }.max() ?? 1
        return lanes > 1 ? CGFloat(lanes) * (minimumWidth + 5) : minimumWidth
    }
    private func isSessionStart(_ period: Int) -> Bool {
        period > 1 && (period == profile.counts[0] + 1 || period == profile.counts[0] + profile.counts[1] + 1)
    }
    private func yPosition(_ period: Int, rowHeight: CGFloat) -> CGFloat {
        CGFloat(period - 1) * rowHeight + CGFloat((1...period).filter { isSessionStart($0) }.count) * sessionGap
    }
    private func dateHeader(_ day: Int) -> some View {
        let date = ScheduleEngine.date(week: week, weekday: day, table: table)
        let today = Calendar.current.isDateInToday(date)
        return VStack(spacing: 10) {
            Text(weekdayNames[day - 1]).font(.caption).foregroundStyle(.secondary)
            Text("\(Calendar.current.component(.day, from: date))").font(.subheadline.weight(.semibold))
                .frame(width: 30, height: 30)
                .background(today ? Color.indigo : Color.clear, in: Circle())
                .foregroundStyle(today ? Color.white : Color.primary)
        }.padding(.vertical, 6).accessibilityElement(children: .combine)
    }
    private func dayColumn(_ day: Int, width: CGFloat, rowHeight: CGFloat) -> some View {
        let dayBlocks = blocks.filter { $0.weekday == day }
        let groups = ScheduleEngine.overlapGroups(dayBlocks)
        let date = ScheduleEngine.date(week: week, weekday: day, table: table)
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(visiblePeriods) { time in
                    if isSessionStart(time.period) { Color.clear.frame(height: sessionGap) }
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
                    .frame(width: max(1, laneWidth - 5), height: yPosition(block.last, rowHeight: rowHeight) - yPosition(block.first, rowHeight: rowHeight) + rowHeight - 8)
                    .offset(x: CGFloat(lane) * laneWidth + 2, y: yPosition(block.first, rowHeight: rowHeight) + 4)
                    .accessibilityLabel("\(block.course.name)，\(weekdayNames[day - 1])，第 \(block.first) 到 \(block.last) 节，\(block.course.location)\(group.count > 1 ? "，有时间冲突" : "")")
                }
            }
        }
        .frame(width: width, height: yPosition(visiblePeriods.count, rowHeight: rowHeight) + rowHeight)
        .background(Calendar.current.isDateInToday(date) ? Color.indigo.opacity(0.035) : Color.clear)
    }
}

private struct CourseTile: View {
    let block: CourseBlock
    let conflict: Bool
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .caption) private var titleSize: CGFloat = 11
    @ScaledMetric(relativeTo: .caption2) private var locationSize: CGFloat = 10
    private func textHeight(_ text: String, size: CGFloat, width: CGFloat, weight: UIFont.Weight = .regular) -> CGFloat {
        ceil((text as NSString).boundingRect(
            with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.systemFont(ofSize: size, weight: weight)], context: nil).height)
    }
    var body: some View {
        GeometryReader { geometry in
            let contentHeight = max(0, geometry.size.height - 8 - (conflict ? 18 : 0))
            let titleLineHeight = UIFont.systemFont(ofSize: titleSize, weight: .semibold).lineHeight
            let measuredTitle = textHeight(block.course.name, size: titleSize, width: geometry.size.width - 8, weight: .semibold)
            let neededTitleLines = max(1, Int(ceil(measuredTitle / titleLineHeight)))
            let titleLines = min(neededTitleLines, max(1, Int(contentHeight / titleLineHeight)))
            let titleHeight = min(contentHeight, CGFloat(titleLines) * titleLineHeight)
            let locationBudget = max(0, contentHeight - titleHeight - 4)
            let locationLines = Int(locationBudget / UIFont.systemFont(ofSize: locationSize).lineHeight)
            VStack(alignment: .leading, spacing: 4) {
                if conflict { Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.orange) }
                Text(block.course.name).font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(Color.primary).lineLimit(titleLines)
                    .fixedSize(horizontal: false, vertical: true).layoutPriority(2)
                if !block.course.location.isEmpty && locationLines > 0 {
                    Text(block.course.location).font(.system(size: locationSize)).foregroundStyle(Color.secondary)
                        .lineLimit(locationLines).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 4).padding(.vertical, 4)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .background(Color(argb: block.course.color).opacity(scheme == .dark ? 0.3 : 0.16), in: RoundedRectangle(cornerRadius: 9))
        .overlay(alignment: .top) { Capsule().fill(Color(argb: block.course.color)).frame(height: 3).padding(.horizontal, 6) }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}
