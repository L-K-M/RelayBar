import AppKit
import SwiftUI

/// The part of the menu's frame a resize drag moves.
enum PopoverResizeEdge {
    /// The bottom edge, which changes only the height.
    case bottom
    /// The bottom-trailing corner, which changes the width and the height.
    case bottomTrailingCorner
}

/// The sizes the menu popover may take on one screen.
struct PopoverSizeLimits: Equatable {
    let minimum: CGSize
    let maximum: CGSize

    /// `visibleScreenSize` is the size of the screen's visible frame, which
    /// already excludes the menu bar and the Dock. `nil` means the screen is
    /// not known yet, so only the fixed limits apply.
    init(visibleScreenSize: CGSize?) {
        minimum = RelayBarPopoverLayout.minimumSize
        let margin = RelayBarPopoverLayout.screenMargin
        let screenWidth = visibleScreenSize.map { $0.width - (margin * 2) }
            ?? RelayBarPopoverLayout.maximumWidth
        let screenHeight = visibleScreenSize.map { $0.height - margin }
            ?? RelayBarPopoverLayout.fallbackMaximumHeight
        // A screen too small for the minimum still gets the minimum: every
        // screen was verified at that size, and AppKit keeps the popover on
        // screen as far as it can.
        maximum = CGSize(
            width: max(
                minimum.width,
                min(RelayBarPopoverLayout.maximumWidth, screenWidth)
            ),
            height: max(minimum.height, screenHeight)
        )
    }

    func clamped(_ size: CGSize) -> CGSize {
        CGSize(
            width: min(max(size.width.rounded(), minimum.width), maximum.width),
            height: min(max(size.height.rounded(), minimum.height), maximum.height)
        )
    }

    /// The size a drag of `edge` asks for, from pointer locations in screen
    /// coordinates (y grows upward). The popover hangs from the menu bar
    /// centered on its icon, so its bottom edge moves one point per point of
    /// height while each side moves half the width change; doubling the
    /// horizontal travel keeps the corner under the pointer. Screen
    /// coordinates stay still while the view under the pointer resizes.
    static func resized(
        _ startSize: CGSize,
        from startPointer: CGPoint,
        to pointer: CGPoint,
        by edge: PopoverResizeEdge
    ) -> CGSize {
        let height = startSize.height + (startPointer.y - pointer.y)
        switch edge {
        case .bottom:
            return CGSize(width: startSize.width, height: height)
        case .bottomTrailingCorner:
            return CGSize(
                width: startSize.width + ((pointer.x - startPointer.x) * 2),
                height: height
            )
        }
    }
}

/// Owns the menu popover's size: the user's persisted preference and the
/// effective size after clamping it to the current screen. The application
/// delegate applies `size` to the popover through `sizeDidChange`; the root
/// view only fills whatever size the popover has.
@MainActor
final class PopoverSizeModel: ObservableObject {
    enum Step {
        case larger
        case smaller
    }

    static let storageKey = "popover.contentSize.v1"
    static let accessibilityStep = CGSize(width: 40, height: 60)

    @Published private(set) var size: CGSize

    /// Called with each new effective size. `isLive` is true while a drag is
    /// in progress, when the change should track the pointer unanimated.
    var sizeDidChange: ((CGSize, _ isLive: Bool) -> Void)?

    private struct ActiveDrag {
        let edge: PopoverResizeEdge
        let startSize: CGSize
        let startPointer: CGPoint
    }

    private let defaults: UserDefaults
    private var limits = PopoverSizeLimits(visibleScreenSize: nil)
    /// Kept apart from `size` so opening the menu once on a small screen
    /// does not shrink the size it opens at on a larger one.
    private var preferredSize: CGSize
    private var activeDrag: ActiveDrag?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let preferred = PopoverSizeModel.storedSize(in: defaults)
            ?? RelayBarPopoverLayout.defaultSize
        preferredSize = preferred
        size = PopoverSizeLimits(visibleScreenSize: nil).clamped(preferred)
    }

    var isResizing: Bool { activeDrag != nil }

    func updateVisibleScreenSize(_ visibleScreenSize: CGSize?) {
        limits = PopoverSizeLimits(visibleScreenSize: visibleScreenSize)
        setSize(limits.clamped(preferredSize), isLive: false)
    }

    func beginResize(_ edge: PopoverResizeEdge, at pointer: CGPoint) {
        activeDrag = ActiveDrag(edge: edge, startSize: size, startPointer: pointer)
    }

    func continueResize(to pointer: CGPoint) {
        guard let activeDrag else { return }
        let proposed = PopoverSizeLimits.resized(
            activeDrag.startSize,
            from: activeDrag.startPointer,
            to: pointer,
            by: activeDrag.edge
        )
        setSize(limits.clamped(proposed), isLive: true)
    }

    /// Persists once per drag rather than on every pointer event.
    func endResize() {
        guard activeDrag != nil else { return }
        activeDrag = nil
        remember(size)
    }

    /// The VoiceOver adjustable action's route to the same resize.
    func step(_ direction: Step) {
        let sign: CGFloat = direction == .larger ? 1 : -1
        let proposed = CGSize(
            width: size.width + (Self.accessibilityStep.width * sign),
            height: size.height + (Self.accessibilityStep.height * sign)
        )
        setSize(limits.clamped(proposed), isLive: false)
        remember(size)
    }

    private func setSize(_ newSize: CGSize, isLive: Bool) {
        guard newSize != size else { return }
        size = newSize
        sizeDidChange?(newSize, isLive)
    }

    private func remember(_ size: CGSize) {
        preferredSize = size
        defaults.set(
            ["width": Double(size.width), "height": Double(size.height)],
            forKey: Self.storageKey
        )
    }

    /// A missing, malformed, or non-positive value falls back to the default
    /// rather than opening the menu at a size nobody chose.
    private static func storedSize(in defaults: UserDefaults) -> CGSize? {
        guard
            let stored = defaults.dictionary(forKey: storageKey),
            let width = stored["width"] as? Double,
            let height = stored["height"] as? Double,
            width.isFinite, height.isFinite,
            width > 0, height > 0
        else {
            return nil
        }
        return CGSize(width: width, height: height)
    }
}

/// The menu's resize handles: its whole bottom edge, and a grip in its
/// bottom-trailing corner. NSPopover has no resizable frame of its own, so
/// these are the only way to change its size.
struct PopoverResizeHandles: View {
    @ObservedObject var model: PopoverSizeModel

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Thin enough to stay below the Quit, Cancel, and Save buttons,
            // which sit at least 10 points above the bottom edge.
            PopoverResizeTarget(edge: .bottom, model: model)
                .frame(maxWidth: .infinity)
                .frame(height: 6)
                .accessibilityHidden(true)
            grip
        }
    }

    private var grip: some View {
        // The glyph sits far enough inside the popover's rounded corner to
        // survive the larger corner radii of newer macOS releases, and the
        // 14-point target stays clear of the trailing Quit and Save buttons
        // on the screens above it.
        GripLines()
            .stroke(Color.secondary, lineWidth: 1)
            .frame(width: 9, height: 9)
            .padding([.trailing, .bottom], 5)
            .frame(width: 14, height: 14, alignment: .bottomTrailing)
            .allowsHitTesting(false)
            .overlay(PopoverResizeTarget(edge: .bottomTrailingCorner, model: model))
            .accessibilityElement()
            .accessibilityLabel("Resize menu")
            .accessibilityValue(
                "\(Int(model.size.width)) by \(Int(model.size.height)) points"
            )
            .accessibilityAdjustableAction { direction in
                if direction == .increment {
                    model.step(.larger)
                } else if direction == .decrement {
                    model.step(.smaller)
                }
            }
    }
}

/// The drag target of a resize handle. It is an AppKit view because
/// SwiftUI offers no resize cursor on macOS 13, and because AppKit delivers
/// every drag event to the view the drag began in, however far the popover
/// moves and resizes under the pointer.
private struct PopoverResizeTarget: NSViewRepresentable {
    let edge: PopoverResizeEdge
    let model: PopoverSizeModel

    func makeNSView(context: Context) -> PopoverResizeTargetView {
        PopoverResizeTargetView(edge: edge, model: model)
    }

    func updateNSView(_ view: PopoverResizeTargetView, context: Context) {
        view.edge = edge
        view.model = model
    }
}

private final class PopoverResizeTargetView: NSView {
    var edge: PopoverResizeEdge
    var model: PopoverSizeModel

    init(edge: PopoverResizeEdge, model: PopoverSizeModel) {
        self.edge = edge
        self.model = model
        super.init(frame: .zero)
        toolTip = "Drag to resize"
        // The grip's SwiftUI element carries the label and the adjustable
        // action; the bottom edge only duplicates them.
        setAccessibilityElement(false)
        // `.inVisibleRect` keeps the area matched to the view while the
        // popover resizes around it.
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The window frame cursors that macOS 15 introduced, so the handles
    /// read like a window edge. macOS 13 and 14 have a vertical resize
    /// cursor but no public diagonal one, so the corner keeps the arrow.
    private var cursor: NSCursor? {
        switch edge {
        case .bottom:
            if #available(macOS 15, *) {
                return .frameResize(position: .bottom, directions: .all)
            }
            return .resizeUpDown
        case .bottomTrailingCorner:
            if #available(macOS 15, *) {
                return .frameResize(position: .bottomRight, directions: .all)
            }
            return nil
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        guard let cursor else {
            super.cursorUpdate(with: event)
            return
        }
        cursor.set()
    }

    // A drag starts on the first click even while the menu's window is not
    // key, rather than spending that click on activation.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    // The bottom edge lies over the bottom of the Settings scroll view, so
    // a scroll there goes to the scroll view beneath it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if NSApp.currentEvent?.type == .scrollWheel { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        model.beginResize(edge, at: NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        model.continueResize(to: NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        model.endResize()
    }
}

/// The classic three-stroke resize grip, parallel to the corner's diagonal.
private struct GripLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for fraction: CGFloat in [0, 0.4, 0.75] {
            path.move(
                to: CGPoint(x: rect.minX + (rect.width * fraction), y: rect.maxY)
            )
            path.addLine(
                to: CGPoint(x: rect.maxX, y: rect.minY + (rect.height * fraction))
            )
        }
        return path
    }
}
