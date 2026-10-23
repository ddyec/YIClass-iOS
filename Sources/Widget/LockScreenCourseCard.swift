import SwiftUI

/// Shared by the WidgetKit view and the native SwiftUI visual-review renderer.
struct LockScreenCourseCard: View {
    let title: String
    let time: String
    let location: String
    var tomorrow = false
    var single = true
    var active = false
    var remainingFraction: Double = 1
    var emphasis = 1.0

    var body: some View {
        GeometryReader { geometry in
            let short = geometry.size.height < 64
            let tiny = geometry.size.height < 54
            let twoLines = !single && geometry.size.height >= 76
            let titleSize: CGFloat = tiny ? 13 : short ? 15 : single ? 18 : 15
            let titleHeight: CGFloat = tiny ? 16 : short ? 18 : twoLines ? 36 : single ? 22 : 19
            let timeHeight: CGFloat = tiny ? 13 : short ? 14 : 16
            let roomHeight: CGFloat = tiny ? 11 : short ? 12 : 14
            VStack(alignment: .leading, spacing: short ? 1 : 2) {
                Text(title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .lineLimit(twoLines ? 2 : 1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: titleHeight, alignment: .topLeading)
                HStack(spacing: 3) {
                    Text(time).monospacedDigit().layoutPriority(1)
                    if tomorrow { Spacer(minLength: 0); Text("明天").font(.system(size: tiny ? 9 : 10)) }
                }
                .font(.system(size: tiny ? 11 : short ? 12 : 13))
                .lineLimit(1)
                .frame(height: timeHeight, alignment: .leading)
                Text(location)
                    .font(.system(size: tiny ? 9 : short ? 10 : 11))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: roomHeight, alignment: .leading)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, tiny ? 3 : short ? 4 : twoLines ? 3 : 5)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            .overlay {
                let outline = LessonOutline()
                if single {
                    outline.stroke(.primary.opacity(active ? 0.25 : 0.5), lineWidth: 1.6)
                        .padding(2)
                }
                if active {
                    outline.trim(from: 1 - min(1, max(0, remainingFraction)), to: 1)
                        .stroke(.primary, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .padding(2)
                }
            }
            .foregroundStyle(.primary.opacity(emphasis))
        }
    }
}

/// Starts and ends at the bottom centre, so the time outline recedes consistently.
private struct LessonOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(10, min(rect.width, rect.height) / 4)
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}
