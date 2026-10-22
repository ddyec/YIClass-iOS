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
    @AppStorage("theme.accent") private var accent = 0xFF637EEA
    @AppStorage("theme.background") private var backdrop = 0xFF298F84
    var body: some View {
        LinearGradient(colors: [Color(argb: UInt32(clamping: accent)).opacity(0.09), Color(.systemGroupedBackground), Color(argb: UInt32(clamping: backdrop)).opacity(0.06)],
                       startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
    }
}

/// Glass is reserved for controls floating above content. Course cards remain readable.
struct GlassPanel<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var inset: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        if reduceTransparency {
            content.padding(inset).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        } else {
            content.padding(inset).glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
    }
}


let weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

// Opaque sRGB values keep storage independent of display mode and Color's encoding.
extension Color {
    var opaqueARGB: UInt32 {
        let resolved = resolve(in: EnvironmentValues())
        let r = UInt32((min(1, max(0, resolved.red)) * 255).rounded())
        let g = UInt32((min(1, max(0, resolved.green)) * 255).rounded())
        let b = UInt32((min(1, max(0, resolved.blue)) * 255).rounded())
        return 0xFF000000 | (r << 16) | (g << 8) | b
    }
}

struct ThemeSettingsView: View {
    @AppStorage("theme.accent") private var accent = 0xFF637EEA
    @AppStorage("theme.background") private var backdrop = 0xFF298F84
    var body: some View {
        Form {
            Section("自由配色") {
                ColorPicker("主题色", selection: Binding(get: { Color(argb: UInt32(clamping: accent)) }, set: { accent = Int($0.opaqueARGB) }), supportsOpacity: false)
                ColorPicker("背景渐变色", selection: Binding(get: { Color(argb: UInt32(clamping: backdrop)) }, set: { backdrop = Int($0.opaqueARGB) }), supportsOpacity: false)
                Text("主题色用于按钮、选中状态和助手气泡。背景渐变用于课表与助手。课程颜色可在编辑课程时单独选择。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("预览") {
                VStack(spacing: 16) {
                    Label("今天的安排", systemImage: "calendar").font(.headline)
                    Button("主题色预览") {}.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity).padding(28).background { AppBackdrop() }.clipShape(RoundedRectangle(cornerRadius: 16))
            }
            Section { Button("恢复默认配色") { accent = 0xFF637EEA; backdrop = 0xFF298F84 } }
        }.navigationTitle("配色").navigationBarTitleDisplayMode(.inline)
    }
}

struct ProductLogo: View {
    var size: CGFloat = 72
    var body: some View {
        Image("Brand")
            .resizable().scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            .accessibilityHidden(true)
    }
}

struct AssistantLogo: View {
    var size: CGFloat = 88
    var body: some View {
        Image("AssistantLogo")
            .resizable().renderingMode(.template).scaledToFit()
            .foregroundStyle(.tint)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
