import SwiftUI
import YIClassCore

struct TodoPendingSection<Content: View>: View {
    let count: Int
    var add: () -> Void
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("待完成").font(.system(size: 24, weight: .bold)).foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(count) 项").font(.system(size: 18, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.tint)
            }
            if count == 0 {
                VStack(spacing: 14) {
                    Image(systemName: "checklist").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
                    Text("暂无待办").font(.title3.weight(.medium)).foregroundStyle(.secondary)
                    Button("添加待办", systemImage: "plus", action: add)
                        .font(.headline).frame(minHeight: 44).buttonStyle(.borderless)
                }
                .frame(maxWidth: .infinity, minHeight: 190)
                .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 22))
            } else { content }
        }
        .padding(.top, 6).padding(.bottom, 12)
        .accessibilityIdentifier("todo-pending")
    }
}

struct TodoTaskCard: View {
    let item: TodoItem
    let reference: Date
    var placement: TodoPlacement?
    var complete: () -> Void
    var edit: () -> Void
    private var color: Color { Color(argb: TodoPalette.color(item.urgencyLevel(on: reference))) }
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
            Button(action: complete) {
                Image(systemName: item.completedAt == nil ? "circle" : "checkmark.circle.fill")
                    .font(.title3).foregroundStyle(item.completedAt == nil ? color : .secondary)
                    .frame(width: 44, height: 44)
            }.buttonStyle(.plain)
                .accessibilityLabel(item.completedAt == nil ? "完成：\(item.title)" : "重新打开：\(item.title)")
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.headline).foregroundStyle(.primary)
                        .strikethrough(item.completedAt != nil).lineLimit(3)
                    HStack(spacing: 6) {
                        Text(item.urgency(on: reference))
                        if item.importance == .high { Text("· 重要") }
                    }.font(.caption.weight(.medium)).foregroundStyle(color)
                    if let deadline = item.deadline {
                        (Text("截止 · ") + Text(deadline, format: .dateTime.month().day().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if let placement {
                        (Text("安排 · ") + Text(placement.start, format: .dateTime.month().day().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) + Text("–") + Text(placement.end, format: .dateTime.month().day().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if !item.notes.isEmpty { Text(item.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(14)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(color.opacity(0.12), lineWidth: 0.5) }
    }
}

struct DayTimelineCanvas: View {
    let items: [AgendaTimelineItem]
    let date: Date
    var now: Date = Date()
    var onSelect: (AgendaTimelineItem) -> Void = { _ in }
    private let hourHeight: CGFloat = 72
    private var firstHour: Int { max(0, min(7, (items.map(\.startMinute).min() ?? 420) / 60)) }
    private var lastHour: Int { min(24, max(22, ((items.map(\.endMinute).max() ?? 1260) + 59) / 60)) }
    private var height: CGFloat { CGFloat(lastHour - firstHour) * hourHeight }
    private var nowMinute: Int? {
        guard Calendar.current.isDate(date, inSameDayAs: now) else { return nil }
        return Calendar.current.component(.hour, from: now) * 60 + Calendar.current.component(.minute, from: now)
    }

    var body: some View {
        GeometryReader { geometry in
            let gutter: CGFloat = 48
            let width = max(1, geometry.size.width - gutter)
            ZStack(alignment: .topLeading) {
                ForEach(firstHour..<lastHour, id: \.self) { hour in
                    let y = CGFloat(hour - firstHour) * hourHeight
                    Text(String(format: "%02d:00", hour))
                        .font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing).offset(y: y - 7).id("agenda-hour-\(hour)")
                        .opacity(nowMinute.map { abs($0 - hour * 60) < 8 } == true ? 0 : 1)
                    Text(String(format: "%02d:30", hour))
                        .font(.system(size: 9).monospacedDigit()).foregroundStyle(.tertiary)
                        .frame(width: 40, alignment: .trailing).offset(y: y + hourHeight / 2 - 6)
                        .opacity(nowMinute.map { abs($0 - (hour * 60 + 30)) < 8 } == true ? 0 : 1)
                    Rectangle().fill(Color.primary.opacity(0.09)).frame(width: width, height: 0.5).offset(x: gutter, y: y)
                    Rectangle().fill(Color.primary.opacity(0.04)).frame(width: width, height: 0.5).offset(x: gutter, y: y + hourHeight / 2)
                }
                ForEach(DayAgendaEngine.lanes(items)) { lane in
                    let cardWidth = width / CGFloat(lane.columns) - 6
                    let cardHeight = max(42, CGFloat(lane.item.endMinute - lane.item.startMinute) / 60 * hourHeight - 3)
                    Button { onSelect(lane.item) } label: {
                        timelineCard(lane.item, height: cardHeight)
                            .frame(width: max(1, cardWidth), height: cardHeight, alignment: .topLeading)
                    }.buttonStyle(.plain)
                        .offset(x: gutter + CGFloat(lane.column) * width / CGFloat(lane.columns),
                                y: CGFloat(lane.item.startMinute - firstHour * 60) / 60 * hourHeight)
                        .accessibilityLabel("\(lane.item.title)，\(lane.item.start.formatted(date: .omitted, time: .shortened))至\(lane.item.end.formatted(date: .omitted, time: .shortened))，\(lane.item.subtitle)")
                }
                if Calendar.current.isDate(date, inSameDayAs: now) {
                    let minute = Calendar.current.component(.hour, from: now) * 60 + Calendar.current.component(.minute, from: now)
                    if minute >= firstHour * 60 && minute < lastHour * 60 {
                        HStack(spacing: 0) {
                            Text(now, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.red).frame(width: gutter - 2, alignment: .trailing)
                            Circle().fill(.red).frame(width: 4, height: 4)
                            Rectangle().fill(.red.opacity(0.8)).frame(height: 1)
                        }.offset(y: CGFloat(minute - firstHour * 60) / 60 * hourHeight - 6)
                            .allowsHitTesting(false)
                    }
                }
            }
        }.frame(height: height + 42).padding(.top, 8)
    }
    private func timelineCard(_ item: AgendaTimelineItem, height: CGFloat) -> some View {
        let color = Color(argb: item.color)
        return HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 4) {
                    if item.kind == .todo {
                        Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 10)).padding(.top, 2)
                    }
                    Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(height >= 76 ? 2 : 1)
                        .strikethrough(item.completed)
                }.foregroundStyle(.primary)
                if height >= 54 {
                    (Text(item.start, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) + Text("–") + Text(item.end, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                        .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                }
                if height >= 84 && !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(color.opacity(item.kind == .course ? 0.17 : 0.10), in: RoundedRectangle(cornerRadius: 12))
        .opacity(item.completed ? 0.55 : 1)
    }
}
