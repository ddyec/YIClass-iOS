import SwiftUI
import YIClassCore

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: "跟随系统"; case .light: "浅色"; case .dark: "深色" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

extension Color {
    init(argb: UInt32) {
        self.init(.sRGB, red: Double((argb >> 16) & 255) / 255,
                  green: Double((argb >> 8) & 255) / 255, blue: Double(argb & 255) / 255, opacity: 1)
    }
}

struct AppBackdrop: View {
    var body: some View {
        LinearGradient(colors: [Color.indigo.opacity(0.09), Color(.systemGroupedBackground), Color.teal.opacity(0.06)],
                       startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
    }
}

/// Glass is reserved for controls floating above content. Course cards remain readable.
struct GlassPanel<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder var content: Content
    var body: some View {
        if reduceTransparency {
            content.padding(12).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        } else {
            content.padding(12).glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
    }
}

struct BrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground))
            Image("Brand").resizable().scaledToFit().padding(8)
        }.frame(width: 68, height: 68).accessibilityLabel("YIClass")
    }
}

let weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
