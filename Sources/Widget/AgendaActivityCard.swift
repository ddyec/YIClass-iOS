import SwiftUI
import YIClassCore

/// Shared by lock screen, expanded island and production ImageRenderer checks.
/// The timer owns a bounded column; it cannot push the title outside the card.
struct AgendaActivityCard: View {
    let items: [AgendaActivityItem]
    let referenceDate: Date
    var compact = false
    var body: some View {
        ViewThatFits(in: .vertical) {
            content(tight: compact)
            content(tight: true)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func content(tight: Bool) -> some View {
        let visible = Array(items.prefix(compact ? 1 : 2))
        return HStack(alignment: .top, spacing: 16) {
            ForEach(visible) { item in
                VStack(alignment: .leading, spacing: tight ? 4 : 7) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.kind == .course ? "book.closed.fill" : "checklist")
                            .font(.system(size: tight ? 13 : 16, weight: .semibold))
                            .foregroundStyle(tint(item))
                            .frame(width: 20, height: tight ? 18 : 22)
                            .accessibilityHidden(true)
                        Text(item.title)
                            .font(.system(size: tight ? 15 : 18, weight: .semibold))
                            .lineLimit(tight ? 1 : 2, reservesSpace: !tight)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)
                        if visible.count == 1 && !compact {
                            AgendaActivityCountdown(item: item, referenceDate: referenceDate)
                                .frame(width: 82, alignment: .trailing)
                        }
                    }
                    Text("\(item.start.formatted(date: .omitted, time: .shortened)) – \(item.end.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: tight ? 11 : 13).monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .foregroundStyle(.white.opacity(0.8))
                    if !item.location.isEmpty {
                        Text(item.location)
                            .font(.system(size: tight ? 11 : 12))
                            .lineLimit(1).truncationMode(.tail)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, tight ? 12 : 16)
        .padding(.vertical, tight ? 9 : 14)
    }
    private func tint(_ item: AgendaActivityItem) -> Color {
        if item.phase(at: referenceDate) == .ending { return .orange }
        return item.kind == .course ? .cyan : .mint
    }
}

struct AgendaActivityCountdown: View {
    let item: AgendaActivityItem
    let referenceDate: Date
    var label = true
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if item.start > referenceDate {
                Text(item.start, style: .time)
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                if label { Text("开始时间").font(.system(size: 10)).foregroundStyle(.secondary) }
            } else if item.end > referenceDate && item.end > item.start {
                Text(timerInterval: item.start...item.end, countsDown: true)
                    .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.trailing)
                if label { Text("距结束").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
        }
        .lineLimit(1).minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
    }
}
