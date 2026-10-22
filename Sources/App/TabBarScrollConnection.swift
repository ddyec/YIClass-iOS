import SwiftUI
import UIKit

// Explicitly identify the vertical scroll view for UIKit's native tab-bar
// minimization. Automatic discovery can pick a horizontal wrapper or miss a
// list behind SwiftUI layout containers. No scroll delegates are replaced.
@MainActor struct TabBarScrollConnection: UIViewRepresentable {
    func makeUIView(context: Context) -> Marker { Marker() }
    func updateUIView(_ view: Marker, context: Context) { view.setNeedsLayout() }
    static func dismantleUIView(_ view: Marker, coordinator: ()) { view.disconnect() }

    @MainActor final class Marker: UIView {
        private final class Target {
            weak var controller: UIViewController?
            init(_ controller: UIViewController) { self.controller = controller }
        }
        private weak var connectedScroll: UIScrollView?
        private var targets: [Target] = []

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { disconnect() } else { setNeedsLayout() }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            connect()
        }
        private func scrollView() -> UIScrollView? {
            var ancestor = superview
            // A marker inside the scroll content selects the nearest scrolling
            // ancestor, ensuring the week grid's vertical view wins over its
            // outer horizontal scroller.
            while let view = ancestor {
                if let scroll = view as? UIScrollView { return scroll }
                ancestor = view.superview
            }
            // List hosts its UICollectionView as a sibling of the background.
            // Search only inside this marker's owning view controller.
            guard let owner = owner else { return nil }
            ancestor = superview
            while let view = ancestor {
                if let scroll = verticalDescendant(of: view) { return scroll }
                if view === owner.view { break }
                ancestor = view.superview
            }
            return nil
        }
        private func verticalDescendant(of view: UIView) -> UIScrollView? {
            guard !view.isHidden, view.alpha > 0 else { return nil }
            if let scroll = view as? UIScrollView, scroll.isScrollEnabled,
               (scroll.alwaysBounceVertical || scroll.contentSize.height > scroll.bounds.height || scroll is UICollectionView || scroll is UITableView) {
                return scroll
            }
            for child in view.subviews {
                if let found = verticalDescendant(of: child) { return found }
            }
            return nil
        }
        private var owner: UIViewController? {
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController { return controller }
                responder = current.next
            }
            return nil
        }
        private func connect() {
            guard window != nil, let owner, let tab = owner.tabBarController,
                  let scroll = scrollView() else { return }
            var chain: [UIViewController] = []
            var current: UIViewController? = owner
            while let controller = current, controller !== tab {
                chain.append(controller); current = controller.parent
            }
            guard let selected = tab.selectedViewController, chain.contains(where: { $0 === selected }) else { return }
            if connectedScroll !== scroll || targets.compactMap(\.controller).map(ObjectIdentifier.init) != chain.map(ObjectIdentifier.init) {
                disconnect()
                connectedScroll = scroll
                targets = chain.map(Target.init)
            }
            for controller in chain where controller.contentScrollView(for: .bottom) !== scroll {
                controller.setContentScrollView(scroll, for: .bottom)
            }
        }
        func disconnect() {
            if let scroll = connectedScroll {
                for target in targets {
                    if let controller = target.controller, controller.contentScrollView(for: .bottom) === scroll {
                        controller.setContentScrollView(nil, for: .bottom)
                    }
                }
            }
            targets = []; connectedScroll = nil
        }
    }
}
