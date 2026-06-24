//
//  FloatingToastController.swift
//  Postmark
//
//  Hosts the Triage Deck new-mail toast in a borderless, non-activating
//  floating window so it appears on screen even when the menu-bar panel is
//  closed. This is the on-screen replacement for the macOS system banner: it
//  shows up in the top-right of the active screen, stays for the configured
//  duration, and routes its Open / Archive / Close actions back into AppState.
//

import AppKit
import SwiftUI

@MainActor
final class FloatingToastController {
    /// Invoked when the user clicks "Open" on the floating toast.
    var onOpen: ((NewMailItem) -> Void)?
    /// Invoked when the user clicks "Archive" on the floating toast.
    var onArchive: ((NewMailItem) -> Void)?

    /// Horizontal width reserved for the hosted card, including breathing room
    /// for the card's drop shadow so it isn't clipped by the window bounds.
    private let contentWidth: CGFloat = 360
    /// Gap from the screen's visible edges, mirroring system banner placement.
    private let screenInset: CGFloat = 14

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    /// Presents (or replaces) the floating toast for `item`, auto-dismissing
    /// after `duration` seconds.
    func present(_ item: NewMailItem, duration: Double) {
        dismissTask?.cancel()

        let panel = panel ?? makePanel()
        self.panel = panel

        let root = FloatingToastContent(
            item: item,
            onOpen: { [weak self] in
                self?.dismiss()
                self?.onOpen?(item)
            },
            onArchive: { [weak self] in
                self?.dismiss()
                self?.onArchive?(item)
            },
            onClose: { [weak self] in self?.dismiss() }
        )
        .frame(width: contentWidth)
        .fixedSize(horizontal: false, vertical: true)

        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
        panel.layoutIfNeeded()

        let fitting = hosting.view.fittingSize
        let size = NSSize(
            width: contentWidth,
            height: max(fitting.height, 1)
        )
        panel.setContentSize(size)
        position(panel, size: size)

        if !panel.isVisible {
            panel.alphaValue = 0
            let target = panel.frame.origin
            panel.setFrameOrigin(NSPoint(x: target.x, y: target.y + 12))
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrameOrigin(target)
            }
        } else {
            panel.orderFrontRegardless()
        }

        scheduleDismiss(after: duration)
    }

    /// Animates the floating toast out and tears down the window.
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        guard let panel, panel.isVisible else {
            panel?.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
        })
    }

    private func scheduleDismiss(after duration: Double) {
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        return panel
    }

    /// Pins the panel to the top-right of the active screen, where macOS
    /// notifications normally appear.
    private func position(_ panel: NSPanel, size: NSSize) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let x = frame.maxX - size.width - screenInset
        let y = frame.maxY - size.height - screenInset
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// SwiftUI wrapper that renders `NewMailToastView` with padding so its drop
/// shadow has room inside the borderless window.
private struct FloatingToastContent: View {
    let item: NewMailItem
    let onOpen: () -> Void
    let onArchive: () -> Void
    let onClose: () -> Void

    var body: some View {
        NewMailToastView(
            item: item,
            onOpen: onOpen,
            onArchive: onArchive,
            onClose: onClose
        )
        .padding(.init(top: 8, leading: 6, bottom: 20, trailing: 6))
    }
}
