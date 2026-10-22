import SwiftUI
import YIClassCore

struct CourseEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tableID: UUID
    let course: Course?
    @State private var draft = Course(name: "", schedules: [])
    @State private var deleteConfirmation = false
    private let palette: [UInt32] = [0xFF637EEA, 0xFF298F84, 0xFFB77938, 0xFFAE65A3, 0xFFD36D71, 0xFF658AAB]

    var body: some View {
        NavigationStack {
            Form {
                Section("课程信息") {
                    TextField("课程名称", text: $draft.name)
                    TextField("教室 / 地点", text: $draft.location)
                    TextField("教师", text: $draft.teacher)
                    HStack {
                        ForEach(palette, id: \.self) { color in
                            Button { draft.color = color } label: {
                                Circle().fill(Color(argb: color)).frame(width: 32, height: 32)
                                    .overlay { if draft.color == color { Image(systemName: "checkmark").foregroundStyle(.white) } }
                            }.buttonStyle(.plain).accessibilityLabel("课程颜色 \(palette.firstIndex(of: color)! + 1)")
                        }
                    }.padding(.vertical, 4)
                }
                if let weeks = draft.unscheduledWeeks {
                    Section("未排时间") {
                        Text("第 \(weeks.map(String.init).joined(separator: ",")) 周")
                        Text("补充上课安排后，会转为正常排课课程。").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                ForEach(draft.schedules.indices, id: \.self) { index in
                    Section {
                        Picker("星期", selection: $draft.schedules[index].weekday) {
                            ForEach(1...7, id: \.self) { Text(weekdayNames[$0 - 1]).tag($0) }
                        }
                        Text("节次").font(.subheadline).foregroundStyle(.secondary)
                        choiceGrid(values: Array(1...store.profile.periods.count), selection: $draft.schedules[index].periods)
                        DisclosureGroup("上课周次（已选 \(draft.schedules[index].weekPattern.count) 周）") {
                            HStack {
                                Button("全周") { draft.schedules[index].weekPattern = Array(1...store.table.totalWeeks) }
                                Button("单周") { draft.schedules[index].weekPattern = (1...store.table.totalWeeks).filter { $0 % 2 == 1 } }
                                Button("双周") { draft.schedules[index].weekPattern = (1...store.table.totalWeeks).filter { $0 % 2 == 0 } }
                            }.buttonStyle(.bordered)
                            choiceGrid(values: Array(1...store.table.totalWeeks), selection: $draft.schedules[index].weekPattern)
                        }
                        Button("删除这条安排", role: .destructive) { draft.schedules.remove(at: index) }
                    } header: { Text("上课安排 \(index + 1)") }
                }
                Button("增加上课安排", systemImage: "plus") {
                    draft.unscheduledWeeks = nil
                    draft.schedules.append(CourseSchedule(weekday: 1, periods: [1, 2].filter { $0 <= store.profile.periods.count },
                                                         weekPattern: Array(1...store.table.totalWeeks)))
                }
                if conflictCount > 0 {
                    Label("有 \(conflictCount) 组课程时间冲突，仍可保存并在周视图并排查看。", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).font(.footnote)
                }
                if course != nil {
                    Button("删除课程", role: .destructive) { deleteConfirmation = true }
                }
            }
            .navigationTitle(course == nil ? "添加课程" : "编辑课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do { try store.saveCourse(draft, tableID: tableID); dismiss() }
                        catch { store.error = error.localizedDescription }
                    }.disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (draft.schedules.isEmpty && draft.unscheduledWeeks == nil))
                }
            }
            .confirmationDialog("删除这门课程？", isPresented: $deleteConfirmation, titleVisibility: .visible) {
                Button("删除课程", role: .destructive) {
                    do { try store.deleteCourse(draft.id); dismiss() } catch { store.error = error.localizedDescription }
                }
            }
            .onAppear {
                draft = course ?? Course(name: "", schedules: [CourseSchedule(weekday: 1,
                    periods: [1, 2].filter { $0 <= store.profile.periods.count }, weekPattern: Array(1...store.table.totalWeeks))])
            }
        }
    }
    private var conflictCount: Int {
        ScheduleEngine.conflictCount(courses: store.table.courses.filter { $0.id != draft.id } + [draft])
    }
    private func choiceGrid(values: [Int], selection: Binding<[Int]>) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 42))], spacing: 8) {
            ForEach(values, id: \.self) { value in
                let selected = selection.wrappedValue.contains(value)
                Button {
                    if selected { selection.wrappedValue.removeAll { $0 == value } }
                    else { selection.wrappedValue.append(value); selection.wrappedValue.sort() }
                } label: {
                    Text("\(value)").font(.subheadline.monospacedDigit()).frame(maxWidth: .infinity, minHeight: 40)
                        .background(selected ? Color.indigo.opacity(0.17) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).foregroundStyle(selected ? Color.indigo : Color.secondary)
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }.padding(.vertical, 6)
    }
}
