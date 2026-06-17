import AppKit
import SwiftUI

final class GanttTimelineClipView: NSClipView {
    var lockedOriginX: CGFloat?

    override func scroll(to point: NSPoint) {
        if let lockedOriginX {
            super.scroll(to: NSPoint(x: lockedOriginX, y: point.y))
        } else {
            super.scroll(to: point)
        }
    }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        if let lockedOriginX {
            rect.origin.x = lockedOriginX
        }
        return rect
    }
}

struct GanttHorizontalScrollView<Content: View>: NSViewRepresentable {
    @Binding var scrollOffsetX: CGFloat
    let contentSize: CGSize
    let scrollApplyToken: UInt
    let scrollTargetX: CGFloat
    var scrollToXOnLoad: CGFloat?
    var isHorizontalScrollLocked: Bool
    var lockedScrollX: CGFloat
    var suppressUserScroll: Bool
    var onUserScroll: (() -> Void)?
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(scrollOffsetX: $scrollOffsetX, onUserScroll: onUserScroll)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.scrollerStyle = .overlay
        scrollView.usesPredominantAxisScrolling = true
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.allowsMagnification = false

        let clipView = GanttTimelineClipView()
        clipView.postsBoundsChangedNotifications = true
        scrollView.contentView = clipView

        let hosting = NSHostingView(rootView: content())
        hosting.frame = CGRect(origin: .zero, size: contentSize)
        scrollView.documentView = hosting
        context.coordinator.hostingView = hosting
        context.coordinator.attach(to: scrollView)
        if let scrollToXOnLoad {
            context.coordinator.applyScroll(
                to: scrollToXOnLoad,
                contentWidth: contentSize.width,
                token: scrollApplyToken,
                in: scrollView
            )
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let hosting: NSHostingView<Content>
        if let existing = context.coordinator.hostingView {
            hosting = existing
            hosting.rootView = content()
        } else {
            hosting = NSHostingView(rootView: content())
            context.coordinator.hostingView = hosting
        }

        if hosting.frame.size != contentSize {
            hosting.setFrameSize(contentSize)
        }
        if scrollView.documentView !== hosting {
            scrollView.documentView = hosting
        }

        let clipView = scrollView.contentView as? GanttTimelineClipView
        clipView?.lockedOriginX = isHorizontalScrollLocked ? lockedScrollX : nil

        scrollView.hasHorizontalScroller = !isHorizontalScrollLocked
        scrollView.horizontalScrollElasticity = isHorizontalScrollLocked ? .none : .allowed

        context.coordinator.isUpdatingContent = true

        if isHorizontalScrollLocked {
            if context.coordinator.shouldApplyLockedScroll(
                x: lockedScrollX,
                token: scrollApplyToken,
                contentWidth: contentSize.width
            ) {
                context.coordinator.applyScroll(
                    to: lockedScrollX,
                    contentWidth: contentSize.width,
                    token: scrollApplyToken,
                    in: scrollView
                )
            } else {
                context.coordinator.publishOffset(
                    from: scrollView,
                    suppressUserScroll: true
                )
            }
        } else if context.coordinator.lastAppliedScrollToken != scrollApplyToken {
            context.coordinator.lastAppliedScrollToken = scrollApplyToken
            context.coordinator.lastLockedScrollX = nil
            context.coordinator.applyScroll(
                to: scrollTargetX,
                contentWidth: contentSize.width,
                token: scrollApplyToken,
                in: scrollView
            )
        } else {
            context.coordinator.publishOffset(
                from: scrollView,
                suppressUserScroll: suppressUserScroll
            )
        }

        context.coordinator.isUpdatingContent = false
    }

    final class Coordinator {
        var hostingView: NSHostingView<Content>?
        var lastAppliedScrollToken: UInt = 0
        var lastLockedScrollX: CGFloat?
        fileprivate var isUpdatingContent = false

        private var scrollOffsetX: Binding<CGFloat>
        private let onUserScroll: (() -> Void)?
        private weak var scrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?
        private var ignoreUserScrollUntil: Date?

        init(scrollOffsetX: Binding<CGFloat>, onUserScroll: (() -> Void)?) {
            self.scrollOffsetX = scrollOffsetX
            self.onUserScroll = onUserScroll
        }

        func shouldApplyLockedScroll(x: CGFloat, token: UInt, contentWidth: CGFloat) -> Bool {
            if lastAppliedScrollToken != token { return true }
            guard let last = lastLockedScrollX else { return true }
            return abs(last - x) > 0.5
        }

        func applyScroll(to x: CGFloat, contentWidth: CGFloat, token: UInt, in scrollView: NSScrollView) {
            let clipView = scrollView.contentView
            let visibleWidth = clipView.bounds.width
            let maxX = max(0, contentWidth - visibleWidth)
            let clampedX = min(max(0, x), maxX)

            if abs(clipView.bounds.origin.x - clampedX) < 0.5,
               abs(scrollOffsetX.wrappedValue - clampedX) < 0.5 {
                lastLockedScrollX = clampedX
                lastAppliedScrollToken = token
                return
            }

            ignoreUserScrollUntil = Date().addingTimeInterval(0.35)

            var bounds = clipView.bounds
            bounds.origin.x = clampedX
            bounds.origin.y = 0
            clipView.bounds = bounds
            scrollView.reflectScrolledClipView(clipView)

            lastLockedScrollX = clampedX
            lastAppliedScrollToken = token

            if abs(scrollOffsetX.wrappedValue - clampedX) > 0.5 {
                scrollOffsetX.wrappedValue = clampedX
            }
        }

        func attach(to scrollView: NSScrollView) {
            self.scrollView = scrollView
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                guard let self, let scrollView = self.scrollView else { return }
                let locked = (scrollView.contentView as? GanttTimelineClipView)?.lockedOriginX != nil
                self.publishOffset(from: scrollView, suppressUserScroll: locked)
            }
            publishOffset(from: scrollView, suppressUserScroll: true)
        }

        func publishOffset(from scrollView: NSScrollView, suppressUserScroll: Bool) {
            let x = max(0, scrollView.contentView.bounds.origin.x)
            let ignoreUntil = ignoreUserScrollUntil.map { Date() < $0 } ?? false
            let suppress = suppressUserScroll || isUpdatingContent || ignoreUntil

            if !suppress, scrollOffsetX.wrappedValue != x {
                onUserScroll?()
            }
            if abs(scrollOffsetX.wrappedValue - x) > 0.5 {
                scrollOffsetX.wrappedValue = x
            }
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
        }
    }
}
