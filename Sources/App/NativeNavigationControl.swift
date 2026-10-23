import SwiftUI
import UIKit

/// The system owns hit testing, dragging, the selection lens and its animation.
/// Only the icon/title artwork is supplied by the app; no selection layer is drawn.
@MainActor struct NativeNavigationControl: UIViewRepresentable {
    @Binding var selection: Int
    var minimized: Bool
    var accent: Color
    var expand: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> Segments {
        let control = Segments()
        control.apportionsSegmentWidthsByContent = false
        control.accessibilityIdentifier = "native-navigation-segments"
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.expand))
        tap.cancelsTouchesInView = false
        control.addGestureRecognizer(tap)
        context.coordinator.expandTap = tap
        return control
    }

    func updateUIView(_ control: Segments, context: Context) {
        context.coordinator.parent = self
        let entries = minimized ? Self.entries.filter { $0.value == selection } : Self.entries
        if context.coordinator.values != entries.map(\.value) {
            control.removeAllSegments()
            for (index, entry) in entries.enumerated() {
                control.insertSegment(withTitle: entry.title, at: index, animated: false)
            }
            context.coordinator.values = entries.map(\.value)
        }
        control.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        control.tintColor = UIColor(accent)
        // Keep the system background and selectedSegmentTintColor defaults.
        // Replacing either with bitmap backgrounds or a custom capsule removes
        // the interactive Liquid Glass selection supplied by iOS 26.
        for (index, entry) in entries.enumerated() {
            let ink = entry.value == selection ? UIColor(accent) : UIColor.label
            let image = Self.label(entry, compact: minimized, ink: ink, traits: control.traitCollection)
            control.setAction(UIAction(title: entry.title, image: image) { _ in }, forSegmentAt: index)
        }
        control.selectedSegmentIndex = entries.firstIndex { $0.value == selection } ?? 0
        context.coordinator.expandTap?.isEnabled = minimized
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: Segments, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? (minimized ? 60 : 280), height: 60)
    }

    struct Entry {
        let title: String
        let symbol: String
        let value: Int
    }
    private static let entries = [
        Entry(title: "课表", symbol: "calendar", value: 0),
        Entry(title: "待办", symbol: "checklist", value: 3),
        Entry(title: "设置", symbol: "slider.horizontal.3", value: 2)
    ]

    private static func label(_ entry: Entry, compact: Bool, ink: UIColor, traits: UITraitCollection) -> UIImage {
        let size = CGSize(width: compact ? 26 : 62, height: compact ? 26 : 44)
        let format = UIGraphicsImageRendererFormat(for: traits)
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            traits.performAsCurrent {
                let config = UIImage.SymbolConfiguration(pointSize: 21, weight: .medium)
                if let icon = UIImage(systemName: entry.symbol, withConfiguration: config)?.withTintColor(ink, renderingMode: .alwaysOriginal) {
                    let origin = CGPoint(x: (size.width - icon.size.width) / 2,
                                         y: compact ? (size.height - icon.size.height) / 2 : 1)
                    icon.draw(at: origin)
                }
                if !compact {
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.alignment = .center
                    (entry.title as NSString).draw(in: CGRect(x: 0, y: 29, width: size.width, height: 15),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 11.5, weight: .medium),
                                         .foregroundColor: ink, .paragraphStyle: paragraph])
                }
            }
        }.withRenderingMode(.alwaysOriginal)
    }

    final class Segments: UISegmentedControl {
        override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 60) }
    }

    @MainActor final class Coordinator: NSObject {
        var parent: NativeNavigationControl
        var values: [Int] = []
        weak var expandTap: UITapGestureRecognizer?
        init(_ parent: NativeNavigationControl) { self.parent = parent }
        @objc func changed(_ control: UISegmentedControl) {
            guard values.indices.contains(control.selectedSegmentIndex) else { return }
            parent.selection = values[control.selectedSegmentIndex]
            parent.expand()
        }
        @objc func expand() { parent.expand() }
    }
}
