import SwiftUI

#if os(tvOS)
/// A focusable UIKit view that reports the remote's arrows going down and up. SwiftUI on tvOS
/// sees the Siri Remote's arrows only as move commands, with no release to tell a tap from a hold
/// and nothing to tell a press on the clickpad's edge from a swipe. Swipes reach this view as
/// focus moves, never as presses.
struct RemotePresses: UIViewRepresentable {
    /// Left or right going down (true) or up (false).
    let arrow: (Bool, PlayerFeature.Direction) -> Void
    /// Up or down pressed, by which. Without it they move focus.
    var vertical: ((UIPress.PressType) -> Void)?
    let select: () -> Void

    func makeUIView(context: Context) -> PressView { PressView() }

    func updateUIView(_ view: PressView, context: Context) {
        view.arrow = arrow
        view.vertical = vertical
        view.select = select
    }

    final class PressView: UIView {
        var arrow: (Bool, PlayerFeature.Direction) -> Void = { _, _ in }
        var vertical: ((UIPress.PressType) -> Void)?
        var select: () -> Void = {}

        override var canBecomeFocused: Bool { true }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            super.pressesBegan(presses.filter { !handle($0, isDown: true) }, with: event)
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            super.pressesEnded(presses.filter { !handle($0, isDown: false) }, with: event)
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            super.pressesCancelled(presses.filter { !handle($0, isDown: false) }, with: event)
        }

        private func handle(_ press: UIPress, isDown: Bool) -> Bool {
            switch press.type {
            case .leftArrow: arrow(isDown, .backward)
            case .rightArrow: arrow(isDown, .forward)
            case .upArrow, .downArrow:
                guard let vertical else { return false }
                if isDown { vertical(press.type) }
            case .select: if !isDown { select() }
            default: return false
            }
            return true
        }
    }
}
#endif
