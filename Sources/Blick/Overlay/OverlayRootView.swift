import AppKit
import SwiftUI

/// The panel's content: backdrop at the back, boards in the middle, and the
/// toolbar and launcher on top.
final class OverlayRootView: FlippedView {
    let boardContainer = FlippedView()
    var onBackgroundClick: (() -> Void)?

    /// Height of the strip along the top that tiles stay out of.
    var topInset: CGFloat = 28 {
        didSet { needsLayout = true }
    }

    private let blur = NSVisualEffectView()
    private let tint = NSView()
    private var toolbar: NSView?
    private var launcher: NSView?

    init() {
        super.init(frame: .zero)

        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        addSubview(blur)

        tint.wantsLayer = true
        addSubview(tint)
        addSubview(boardContainer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setBackdrop(opacity: Double, blurred: Bool) {
        blur.isHidden = !blurred
        tint.layer?.backgroundColor = NSColor(white: 0, alpha: opacity).cgColor
    }

    func setToolbar(_ view: NSView?) {
        toolbar?.removeFromSuperview()
        toolbar = view
        if let view {
            addSubview(view)
            needsLayout = true
        }
    }

    var isShowingLauncher: Bool { launcher != nil }

    func setLauncher(_ view: NSView?) {
        launcher?.removeFromSuperview()
        launcher = view
        if let view {
            addSubview(view)
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        blur.frame = bounds
        tint.frame = bounds
        boardContainer.frame = bounds
        for board in boardContainer.subviews {
            board.frame = boardContainer.bounds
        }
        if let toolbar {
            let size = toolbar.fittingSize
            toolbar.frame = CGRect(
                x: bounds.width - size.width - 12,
                y: max((topInset - size.height) / 2, 2),
                width: size.width,
                height: size.height
            )
        }
        if let launcher {
            let size = CGSize(width: min(560, bounds.width - 40), height: min(440, bounds.height - 80))
            launcher.frame = CGRect(
                x: (bounds.width - size.width) / 2,
                y: max((bounds.height - size.height) / 2 - 40, topInset + 10),
                width: size.width,
                height: size.height
            )
        }
    }

    /// Clicks that land on nothing else reach here.
    override func mouseDown(with event: NSEvent) {
        onBackgroundClick?()
    }
}
