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
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat = 88
    private var ink: Color { colorScheme == .dark ? .white : .black }
    var body: some View {
        Image("AssistantLogo")
            .resizable().renderingMode(.template).scaledToFit()
            // The approved artwork has roughly 16% transparent margins on each
            // side. Normalize its visible bounds before sizing the glyph.
            .scaleEffect(1.32)
            .frame(width: size, height: size)
            .clipped()
            .foregroundStyle(ink)
            // Thicken the existing alpha contour, preserving the book artwork.
            // Scale the added ink with the glyph, including the drawer logo.
            .shadow(color: ink, radius: 0, x: size * 0.008, y: 0)
            .shadow(color: ink, radius: 0, x: -size * 0.008, y: 0)
            .shadow(color: ink, radius: 0, x: 0, y: size * 0.008)
            .shadow(color: ink, radius: 0, x: 0, y: -size * 0.008)
            .accessibilityHidden(true)
    }
}

private struct FloatingNavigationScrollKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable (Bool) -> Void = { _ in }
}

extension EnvironmentValues {
    var minimizeFloatingNavigation: @MainActor @Sendable (Bool) -> Void {
        get { self[FloatingNavigationScrollKey.self] }
        set { self[FloatingNavigationScrollKey.self] = newValue }
    }
}

/// Attach to the vertical content scroller, never the week grid's horizontal wrapper.
private struct FloatingNavigationScrollTracking: ViewModifier {
    @Environment(\.minimizeFloatingNavigation) private var minimize
    @State private var scrolling = false
    @State private var travel: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, phase in
                scrolling = phase == .interacting || phase == .decelerating
                if !scrolling { travel = 0 }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                // Clamp rubber banding so a bottom bounce cannot reopen the bar.
                let maximum = max(0, geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom - geometry.containerSize.height)
                return min(maximum, max(0, geometry.contentOffset.y + geometry.contentInsets.top))
            } action: { old, new in
                guard scrolling else { return }
                let delta = new - old
                if new <= 0 { minimize(false); travel = 0; return }
                if delta * travel < 0 { travel = 0 }
                travel += delta
                if abs(travel) >= 18 {
                    minimize(travel > 0)
                    travel = 0
                }
            }
    }
}

extension View {
    func floatingNavigationScrollTracking() -> some View {
        modifier(FloatingNavigationScrollTracking())
    }
}
