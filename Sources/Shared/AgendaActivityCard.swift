import SwiftUI
import YIClassCore

/// Shared by lock screen, expanded island and production ImageRenderer checks.
/// The timer owns a bounded column; it cannot push the title outside the card.
struct AgendaActivityCard: View {
    let items: [AgendaActivityItem]
    let referenceDate: Date
    var compact = false
    var island = false
    @ScaledMetric(relativeTo: .headline) private var titleSize = 18.0
    var body: some View {
        ViewThatFits(in: .vertical) {
            content(tight: compact)
            content(tight: true)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
    private func content(tight: Bool) -> some View {
        let visible = Array(items.prefix(compact ? 1 : 2))
        return HStack(alignment: .top, spacing: 16) {
            ForEach(visible) { item in
                VStack(alignment: .leading, spacing: tight ? 2 : 7) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.kind == .course ? "book.closed.fill" : "checklist")
                            .font(.system(size: tight ? 13 : 16, weight: .semibold))
                            .foregroundStyle(tint(item))
                            .frame(width: 20, height: tight ? 18 : 22)
                            .accessibilityHidden(true)
                        Text(item.title)
                            .font(.system(size: min(titleSize, tight ? 15 : 22), weight: .semibold))
                            .lineLimit(tight ? 1 : 2, reservesSpace: !tight)
                            .truncationMode(.tail)
                            .accessibilityLabel("\(item.kind == .course ? "课程" : "待办")，\(item.title)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .clipped()
                        if visible.count == 1 && (!compact || island) {
                            AgendaActivityCountdown(item: item, referenceDate: referenceDate)
                                .frame(width: island ? 68 : 76, alignment: .trailing)
                                .clipped()
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
                .clipped()
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, island ? 18 : tight ? 14 : 20)
        .padding(.vertical, island ? 10 : tight ? 6 : 14)
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
    var small = false
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if item.start > referenceDate {
                Text(item.start, style: .time)
                    .font(.system(size: small ? 12 : 15, weight: .semibold).monospacedDigit())
                if label { Text("开始时间").font(.system(size: 10)).foregroundStyle(.secondary) }
            } else if item.end > referenceDate && item.end > item.start {
                Text(timerInterval: item.start...item.end, countsDown: true, showsHours: !small)
                    .font(.system(size: small ? 12 : 18, weight: .semibold, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.trailing)
                if label { Text(item.kind == .course ? "整课剩余" : "距结束").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
        }
        .lineLimit(1).minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
    }
}

/// The upper regions sit beside the camera; details and progress belong below.
struct AgendaActivityIslandTitle: View {
    let item: AgendaActivityItem
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: item.kind == .course ? "book.closed.fill" : "checklist")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(item.kind == .course ? Color.cyan : Color.mint)
                .accessibilityHidden(true)
            Text(item.title).font(.system(size: 14, weight: .semibold))
                .lineLimit(2).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.foregroundStyle(.white)
    }
}

struct AgendaActivityIslandBottom: View {
    let item: AgendaActivityItem
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(item.start.formatted(date: .omitted, time: .shortened))–\(item.end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.75)
                if !item.location.isEmpty {
                    Text(item.location).font(.system(size: 11)).lineLimit(2).truncationMode(.tail)
                }
            }.foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)
            AgendaActivityProgress(item: item).frame(width: 144)
        }.padding(.top, 5)
    }
}

/// Each bar uses an actual small-period interval. Past periods are empty,
/// upcoming periods are full, and only the running period drains. This also
/// leaves a truthful break state without a background timer or polling.
struct AgendaActivityProgress: View {
    let item: AgendaActivityItem
    private var periods: [AgendaActivityPeriod] { item.progressPeriods }
    private var tint: Color { item.kind == .course ? .cyan : .mint }
    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if periods.count <= 4 {
                ForEach(Array(periods.enumerated()), id: \.element.id) { index, period in
                    HStack(spacing: 5) {
                        if period.number > 0 {
                            Text("\(period.number)").font(.system(size: 9)).foregroundStyle(.white.opacity(0.65))
                        }
                        bar(period)
                        Text("\(period.end.formatted(date: .omitted, time: .shortened))\(boundaryLabel(index))")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .frame(width: 64, alignment: .trailing)
                    }
                }
            } else {
                // Very long blocks retain every timed segment without growing
                // the island beyond its allotted height.
                HStack(spacing: 3) { ForEach(periods) { bar($0) } }
                Text("\(periods.count)小节 · \(item.end.formatted(date: .omitted, time: .shortened))下课")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
            }
        }
        .accessibilityLabel(item.kind == .course ? "按小节倒计时，条空后到达对应节次结束时间" : "待办剩余时间")
    }
    private func bar(_ period: AgendaActivityPeriod) -> some View {
        ProgressView(timerInterval: period.start...period.end, countsDown: true)
            .progressViewStyle(.linear).tint(tint).labelsHidden()
            .frame(maxWidth: .infinity)
            .accessibilityLabel(period.number > 0 ? "第\(period.number)节" : "剩余时间")
    }
    private func boundaryLabel(_ index: Int) -> String {
        guard item.kind == .course else { return "结束" }
        guard index + 1 < periods.count else { return "下课" }
        return periods[index + 1].start > periods[index].end ? "休息" : "换节"
    }
}

/// In-app acceptance uses the same three components as the island regions.
struct AgendaActivityIslandPreview: View {
    let item: AgendaActivityItem
    let referenceDate: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 24) {
                AgendaActivityIslandTitle(item: item)
                AgendaActivityCountdown(item: item, referenceDate: referenceDate)
                    .frame(width: 76, alignment: .trailing).clipped()
            }
            AgendaActivityIslandBottom(item: item)
        }.padding(16).foregroundStyle(.white)
    }
}
