import SwiftUI
import UIKit

/// The base and the selection use separate native materials: regular glass for
/// the base, clear glass for the lens. The lens remains present while idle.
@MainActor struct NativeNavigationControl: UIViewRepresentable {
    @Binding var selection: Int
    var minimized: Bool
    var expandedWidth: CGFloat
    var accent: Color
    var expand: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> GlassNavigationView { GlassNavigationView() }
    func updateUIView(_ view: GlassNavigationView, context: Context) {
        view.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        view.configure(selection: selection, minimized: minimized, expandedWidth: expandedWidth,
                       accent: UIColor(accent), reduceMotion: reduceMotion)
        view.onSelect = { value in selection = value; expand() }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: GlassNavigationView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? (minimized ? 60 : expandedWidth), height: 60)
    }
}

@MainActor final class GlassNavigationView: UIView, UIGestureRecognizerDelegate {
    private let base = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let lens: UIVisualEffectView = {
        let effect = UIGlassEffect(style: .clear)
        effect.isInteractive = true
        return UIVisualEffectView(effect: effect)
    }()
    private let labels = UIView()
    private let values = [0, 3, 2]
    private let titles = ["课表", "待办", "设置"]
    private let symbols = ["calendar", "checklist", "slider.horizontal.3"]
    private var buttons: [NavigationItemButton] = []
    private var selected = 0
    private var minimized = false
    private var expandedWidth: CGFloat = 280
    private var accent = UIColor.systemBlue
    private var reduceMotion = false
    private var dragX: CGFloat?
    private var selectedIndex: Int { values.firstIndex(of: selected) ?? 0 }
    var onSelect: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "native-navigation-segments"
        // Keep both effect views at alpha 1. No bitmap background, blur overlay
        // or selected fill is used; UIKit renders the clear lens at rest too.
        base.isUserInteractionEnabled = true
        lens.isUserInteractionEnabled = false
        addSubview(base)
        base.contentView.addSubview(lens)
        base.contentView.addSubview(labels)
        labels.clipsToBounds = true
        for index in values.indices {
            let button = NavigationItemButton(title: titles[index], symbol: symbols[index])
            button.tag = index
            button.accessibilityIdentifier = "navigation-\(values[index])"
            button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            labels.addSubview(button)
            buttons.append(button)
        }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = true
        addGestureRecognizer(pan)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 60) }

    func configure(selection: Int, minimized: Bool, expandedWidth: CGFloat, accent: UIColor, reduceMotion: Bool) {
        let selectionChanged = selected != selection
        let modeChanged = self.minimized != minimized
        selected = selection
        self.minimized = minimized
        self.expandedWidth = max(60, expandedWidth)
        self.accent = accent
        self.reduceMotion = reduceMotion
        if modeChanged { dragX = nil }
        refreshLabels()
        setNeedsLayout()
        // SwiftUI owns the width transition. Do not start a second UIKit resize
        // animation when the bar collapses or expands.
        if selectionChanged && !modeChanged && window != nil && !reduceMotion {
            UIView.animate(withDuration: 0.24, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]) { self.layoutIfNeeded() }
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        base.frame = bounds
        labels.frame = base.contentView.bounds
        let progress = min(1, max(0, (bounds.width - 60) / max(1, expandedWidth - 60)))
        let fullWidth = (expandedWidth - 8) / 3
        let collapsed = CGRect(x: 4, y: 4, width: 52, height: 52)
        for index in buttons.indices {
            let full = CGRect(x: 4 + CGFloat(index) * fullWidth, y: 4, width: fullWidth, height: 52)
            let target = CGRect(x: 4, y: 4, width: 52, height: 52)
            buttons[index].frame = interpolate(target, full, progress)
            buttons[index].contentProgress = progress
            buttons[index].alpha = index == selectedIndex ? 1 : progress
            buttons[index].isUserInteractionEnabled = !minimized || index == selectedIndex
            buttons[index].accessibilityElementsHidden = minimized && index != selectedIndex
        }
        let fullLens = CGRect(x: 4 + CGFloat(selectedIndex) * fullWidth, y: 4, width: fullWidth, height: 52)
        var frame = interpolate(collapsed, fullLens, progress)
        if let dragX, !minimized {
            frame.origin.x = min(max(4, dragX - frame.width / 2), max(4, bounds.width - 4 - frame.width))
        }
        lens.frame = frame
        accessibilityValue = minimized ? "已收起，\(titles[selectedIndex])" : "已展开，\(titles[selectedIndex])"
    }
    private func interpolate(_ a: CGRect, _ b: CGRect, _ progress: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * progress,
               y: a.minY + (b.minY - a.minY) * progress,
               width: a.width + (b.width - a.width) * progress,
               height: a.height + (b.height - a.height) * progress)
    }
    private func refreshLabels() {
        for index in buttons.indices {
            buttons[index].isSelected = index == selectedIndex
            buttons[index].accessibilityTraits = index == selectedIndex ? [.button, .selected] : [.button]
            buttons[index].accessibilityValue = minimized ? "导航已收起" : "导航已展开"
            buttons[index].ink = index == selectedIndex ? accent : .label
        }
    }
    @objc private func tapped(_ button: UIButton) { select(button.tag) }
    private func select(_ index: Int) {
        guard values.indices.contains(index) else { return }
        selected = values[index]
        dragX = nil
        refreshLabels(); setNeedsLayout()
        if reduceMotion { layoutIfNeeded() }
        else { UIView.animate(withDuration: 0.24, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]) { self.layoutIfNeeded() } }
        onSelect?(selected)
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: self)
        return !minimized && abs(velocity.x) > abs(velocity.y)
    }
    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        guard !minimized else { return }
        let x = min(max(0, gesture.location(in: self).x), bounds.width)
        switch gesture.state {
        case .began, .changed:
            dragX = x
            setNeedsLayout(); layoutIfNeeded()
        case .ended:
            select(min(2, max(0, Int(x / max(1, bounds.width) * 3))))
        case .cancelled, .failed:
            dragX = nil; setNeedsLayout()
            if reduceMotion { layoutIfNeeded() }
            else { UIView.animate(withDuration: 0.2) { self.layoutIfNeeded() } }
        default: break
        }
    }
}

@MainActor private final class NavigationItemButton: UIButton {
    private let symbol = UIImageView()
    private let caption = UILabel()
    var contentProgress: CGFloat = 1 { didSet { setNeedsLayout() } }
    var ink: UIColor = .label { didSet { symbol.tintColor = ink; caption.textColor = ink } }
    init(title: String, symbol name: String) {
        super.init(frame: .zero)
        symbol.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .medium))
        symbol.contentMode = .scaleAspectFit
        caption.text = title; caption.font = .systemFont(ofSize: 11.5, weight: .medium); caption.textAlignment = .center
        addSubview(symbol); addSubview(caption)
        isAccessibilityElement = true; accessibilityLabel = title
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        symbol.frame = CGRect(x: (bounds.width - 24) / 2, y: 14 - 10 * contentProgress, width: 24, height: 24)
        caption.frame = CGRect(x: 0, y: 32, width: bounds.width, height: 15)
        caption.alpha = contentProgress
    }
}
