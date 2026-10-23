import AppKit
import SwiftUI

@main struct VisualReview {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let output = root.appendingPathComponent("dist/visual-review")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
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
