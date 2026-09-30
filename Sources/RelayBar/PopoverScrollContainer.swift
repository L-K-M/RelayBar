import SwiftUI

enum RelayBarPopoverLayout {
    /// The smallest size every popover screen was laid out and verified at,
    /// so no drag can shrink the menu into an unverified layout.
    static let minimumSize = CGSize(width: 380, height: 440)
    /// The size before the user resizes the menu for the first time.
    static let defaultSize = CGSize(width: 420, height: 580)
    /// Rows are single-line cards; past this width they only gain padding.
    static let maximumWidth: CGFloat = 720
    /// Used only until the menu first opens on a known screen.
    static let fallbackMaximumHeight: CGFloat = 1_200
    /// Kept clear between the menu and the edges of the screen's visible
    /// frame, which also leaves room for the popover arrow.
    static let screenMargin: CGFloat = 40
    static let contentInset: CGFloat = 16

    static func contentWidth(
        for viewportWidth: CGFloat,
        horizontalInset: CGFloat = contentInset
    ) -> CGFloat {
        max(0, viewportWidth - (horizontalInset * 2))
    }
}

/// A vertical popover scroller whose document width is always derived from
/// the viewport. Focus rings and intrinsically wide controls therefore cannot
/// create a horizontal scroll range or shift the document away from its
/// leading inset.
struct PopoverScrollContainer<Content: View>: View {
    let fillsViewport: Bool
    let horizontalInset: CGFloat
    let verticalInset: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        fillsViewport: Bool = false,
        horizontalInset: CGFloat = RelayBarPopoverLayout.contentInset,
        verticalInset: CGFloat = RelayBarPopoverLayout.contentInset,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.fillsViewport = fillsViewport
        self.horizontalInset = horizontalInset
        self.verticalInset = verticalInset
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = RelayBarPopoverLayout.contentWidth(
                for: geometry.size.width,
                horizontalInset: horizontalInset
            )
            let minimumContentHeight = max(
                0,
                geometry.size.height - (verticalInset * 2)
            )

            ScrollView(.vertical) {
                content()
                    .frame(width: contentWidth, alignment: .topLeading)
                    .frame(
                        minHeight: fillsViewport ? minimumContentHeight : nil,
                        alignment: .topLeading
                    )
                    .padding(.horizontal, horizontalInset)
                    .padding(.vertical, verticalInset)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}
