import AppKit
import SwiftUI

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

    /// The size a drag of the bottom-trailing grip asks for, from pointer
    /// locations in screen coordinates (y grows upward). The popover hangs
    /// from the menu bar centered on its icon, so its bottom edge moves one
    /// point per point of height while each side moves half the width
    /// change; doubling the horizontal travel keeps the corner under the
    /// pointer. Screen coordinates, rather than the gesture's own
    /// translation, stay still while the view under the pointer resizes.
    static func resized(
        _ startSize: CGSize,
        from startPointer: CGPoint,
        to pointer: CGPoint
    ) -> CGSize {
        CGSize(
            width: startSize.width + ((pointer.x - startPointer.x) * 2),
            height: startSize.height + (startPointer.y - pointer.y)
        )
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

    func beginResize(at pointer: CGPoint) {
        activeDrag = ActiveDrag(startSize: size, startPointer: pointer)
    }

    func continueResize(to pointer: CGPoint) {
        guard let activeDrag else { return }
        let proposed = PopoverSizeLimits.resized(
            activeDrag.startSize,
            from: activeDrag.startPointer,
            to: pointer
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

/// The drag handle in the menu's bottom-trailing corner. NSPopover has no
/// resizable frame of its own, so this is the only way to enlarge it.
struct PopoverResizeGrip: View {
    @ObservedObject var model: PopoverSizeModel

    var body: some View {
        // The glyph sits inside the popover's rounded corner, and the
        // 13-point target stays clear of the trailing Quit and Save buttons
        // on the screens above it.
        GripLines()
            .stroke(Color.secondary.opacity(0.6), lineWidth: 1)
            .frame(width: 8, height: 8)
            .padding([.trailing, .bottom], 3)
            .frame(width: 13, height: 13, alignment: .bottomTrailing)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        let pointer = NSEvent.mouseLocation
                        if model.isResizing {
                            model.continueResize(to: pointer)
                        } else {
                            model.beginResize(at: pointer)
                        }
                    }
                    .onEnded { _ in
                        model.endResize()
                    }
            )
            .help("Drag to resize")
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
