import AppKit
import SwiftUI

/// A SwiftUI view that is only there to be looked at: clicks pass through.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The panel's content: backdrop at the back, boards in the middle, and the
/// toolbar and launcher on top.
final class OverlayRootView: FlippedView {
    let boardContainer = FlippedView()
    var onBackgroundClick: (() -> Void)?

    /// Height of the strip along the top that tiles stay out of.
    var topInset: CGFloat = Theme.minimumTopInset {
        didSet {
            if topInset != oldValue { needsLayout = true }
        }
    }

    private let blur = NSVisualEffectView()
    private let tint = NSView()
    private let vignette = CAGradientLayer()
    private var toolbar: NSView?
    private var brand: NSView?
    private var launcher: NSView?
    private(set) var shelf: NSView?
    private var notice: NSView?

    init() {
        super.init(frame: .zero)

        // Smoked glass rather than a blackout: what is behind stays faintly
        // visible, so the overlay reads as a layer over your work.
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        addSubview(blur)

        tint.wantsLayer = true
        // Slightly darker toward the edges, which draws the eye to the tiles.
        vignette.type = .radial
        vignette.colors = [NSColor.clear.cgColor, NSColor(white: 0, alpha: 0.3).cgColor]
        vignette.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignette.endPoint = CGPoint(x: 1.1, y: 1.1)
        tint.layer?.addSublayer(vignette)
        addSubview(tint)

        boardContainer.wantsLayer = true
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

    /// The controls at the right of the top strip.
    func setToolbar(_ view: NSView?) {
        toolbar?.removeFromSuperview()
        toolbar = view
        if let view {
            addSubview(view)
            needsLayout = true
        }
    }

    /// The name and hint at the left of the top strip.
    func setBrand(_ view: NSView?) {
        brand?.removeFromSuperview()
        brand = view
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

    /// The shelf of templates along the bottom.
    func setShelf(_ view: NSView?) {
        shelf?.removeFromSuperview()
        shelf = view
        if let view {
            addSubview(view)
            // Placed now, and again only when the screen changes size, so
            // the way it slides in is not cut short by other layout.
            view.frame = shelfFrame
            shelfLaidOutFor = bounds.size
        }
    }

    private var shelfLaidOutFor: CGSize = .zero

    /// Where the shelf sits, whether or not it is showing.
    var shelfFrame: CGRect {
        let width = TemplateShelf.width(in: bounds.width)
        let height = TemplateShelf.height(width)
        return CGRect(
            x: ((bounds.width - width) / 2).rounded(),
            y: bounds.height - height - TemplateShelf.bottomMargin,
            width: width,
            height: height
        )
    }

    /// "Using My Day · Undo", in the middle of the top strip.
    func setNotice(_ view: NSView?) {
        notice?.removeFromSuperview()
        notice = view
        if let view {
            addSubview(view)
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        blur.frame = bounds
        tint.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        vignette.frame = tint.bounds
        CATransaction.commit()

        boardContainer.frame = bounds
        for board in boardContainer.subviews {
            board.frame = boardContainer.bounds
        }
        if let toolbar {
            let size = toolbar.fittingSize
            toolbar.frame = CGRect(
                x: bounds.width - size.width - 14,
                y: max((topInset - size.height) / 2, 3),
                width: size.width,
                height: size.height
            )
        }
        if let brand {
            let size = brand.fittingSize
            brand.frame = CGRect(
                x: 18,
                y: max((topInset - size.height) / 2, 3),
                width: size.width,
                height: size.height
            )
        }
        if let shelf, bounds.size != shelfLaidOutFor {
            shelf.frame = shelfFrame
            shelfLaidOutFor = bounds.size
        }
        if let notice {
            let size = notice.fittingSize
            notice.frame = CGRect(
                x: ((bounds.width - size.width) / 2).rounded(),
                y: max((topInset - size.height) / 2, 3),
                width: size.width,
                height: size.height
            )
        }
        if let launcher {
            // The launcher draws its own card with room around it for a shadow.
            let size = CGSize(
                width: min(LauncherView.cardWidth + 2 * LauncherView.margin, bounds.width),
                height: min(LauncherView.maxHeight + 2 * LauncherView.margin, bounds.height - topInset)
            )
            launcher.frame = CGRect(
                x: (bounds.width - size.width) / 2,
                y: max(bounds.height * 0.16 - LauncherView.margin, topInset),
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
