//
//  PostmarkApp.swift
//  Postmark
//
//  Created by Marcus Schmidt on 2026-04-14.
//

import AppKit
import Combine
import FirebaseCore
import MenuBarExtraAccess
import SwiftUI

@main
struct PostmarkApp: App {
    private let uiTestInboxArgument = "--uitest-inbox"
    @StateObject private var appState = AppState.bootstrap()
    @State private var statusController = MenuBarStatusController()
    @State private var isMenuPresented: Bool
    @State private var uiTestWindowController: NSWindowController?

    init() {
        let isUITestInboxMode = ProcessInfo.processInfo.arguments.contains(
            uiTestInboxArgument
        )
        _isMenuPresented = State(initialValue: isUITestInboxMode)
        configureFirebaseIfNeeded()
    }

    private var isUITestInboxMode: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestInboxArgument)
    }

    private var loggedMenuPresentedBinding: Binding<Bool> {
        Binding(
            get: { isMenuPresented },
            set: { newValue in
                isMenuPresented = newValue
            }
        )
    }

    var body: some Scene {
        MenuBarExtra("Postmark", systemImage: "tray.full") {
            Color.clear.frame(width: 1, height: 1)
        }
        .menuBarExtraAccess(isPresented: loggedMenuPresentedBinding) {
            statusItem in
            statusController.configure(
                with: statusItem,
                isMenuPresented: loggedMenuPresentedBinding
            )
            statusController.bind(to: appState)
            if isUITestInboxMode {
                DispatchQueue.main.async {
                    statusController.showPanelIfPossible()
                }
                presentUITestWindowIfNeeded()
            }
        }
        .menuBarExtraStyle(.menu)
    }

    private func presentUITestWindowIfNeeded() {
        guard isUITestInboxMode else { return }
        guard uiTestWindowController == nil else { return }
        let rootView = RootView()
            .environmentObject(appState)
            .frame(width: 420, height: 560)
            .background(.ultraThinMaterial)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Postmark"
        window.setContentSize(NSSize(width: 420, height: 560))
        window.center()
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        uiTestWindowController = controller
        appState.updatePurchaseConfirmWindow(window)
    }

    private func configureFirebaseIfNeeded() {
        // guard FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()
        // For local event verification, run with:
        // -FIRDebugEnabled
        // Then inspect Firebase Analytics DebugView.
    }
}

@MainActor
final class MenuBarStatusController: NSObject {
    private let panelSize = NSSize(width: 420, height: 560)
    private let panelHorizontalInset: CGFloat = 12
    private weak var statusItem: NSStatusItem?
    private weak var statusButton: NSStatusBarButton?
    private weak var badgeView: BadgeDotView?
    private weak var boundAppState: AppState?
    private var isMenuPresented: Binding<Bool>?
    private var panelController: NSWindowController?
    private var statusClickMonitor: Any?
    private var isBadgeVisible = false
    private var cancellables = Set<AnyCancellable>()
    private var hasBoundState = false

    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(
                title: "Open Postmark",
                action: #selector(openPostmark),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit Postmark",
                action: #selector(quitPostmark),
                keyEquivalent: "q"
            )
        )
        menu.items.forEach { $0.target = self }
        return menu
    }()

    func configure(
        with statusItem: NSStatusItem,
        isMenuPresented: Binding<Bool>
    ) {
        self.statusItem = statusItem
        self.isMenuPresented = isMenuPresented
        guard let button = statusItem.button else { return }
        statusButton = button
        button.target = self
        button.action = #selector(handleStatusButtonAction(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        installBadgeIfNeeded(on: button)
        applyBadgeVisibility()
        installStatusClickMonitorIfNeeded()
    }

    func setBadgeVisible(_ isVisible: Bool) {
        isBadgeVisible = isVisible
        applyBadgeVisibility()
    }

    func showPanelIfPossible() {
        showPanel()
    }

    func bind(to appState: AppState) {
        boundAppState = appState
        guard !hasBoundState else {
            applyBadgeVisibility(
                for: appState.authState,
                messages: appState.inboxViewModel.messages
            )
            return
        }
        hasBoundState = true

        appState.$authState
            .removeDuplicates()
            .sink { [weak self, weak appState] authState in
                guard let self else { return }
                let messages = appState?.inboxViewModel.messages ?? []
                self.applyBadgeVisibility(for: authState, messages: messages)
            }
            .store(in: &cancellables)

        appState.$inboxViewModel
            .map { $0.$messages }
            .switchToLatest()
            .sink { [weak self, weak appState] messages in
                guard let self else { return }
                let authState = appState?.authState ?? .signedOut
                self.applyBadgeVisibility(for: authState, messages: messages)
            }
            .store(in: &cancellables)

        appState.$paywallState
            .removeDuplicates()
            .sink { [weak self] newPaywallState in
                guard let self else { return }
                let isInProgress: Bool
                switch newPaywallState {
                case .purchasing, .restoring:
                    isInProgress = true
                default:
                    isInProgress = false
                }
                self.handleBillingPresentationState(
                    isInProgress: isInProgress
                )
            }
            .store(in: &cancellables)

        applyBadgeVisibility(
            for: appState.authState,
            messages: appState.inboxViewModel.messages
        )
        handleBillingPresentationState(
            isInProgress: appState.isBillingInProgress
        )
    }

    private func presentContextMenu(using button: NSStatusBarButton) {
        guard let statusItem else { return }
        statusItem.popUpMenu(contextMenu)
    }

    @objc private func togglePanelFromStatusItem() {
        guard let button = statusButton else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            hidePanel()
            presentContextMenu(using: button)
            return
        }
        if panelController?.window?.isVisible == true {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func installStatusClickMonitorIfNeeded() {
        guard statusClickMonitor == nil else { return }
        statusClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp]
        ) { [weak self] event in
            guard let self else { return event }
            guard let button = self.statusButton else { return event }
            guard self.isEvent(event, on: button) else { return event }
            self.handleStatusItemMouseUp(event)
            return nil
        }
    }

    private func handleStatusItemMouseUp(_ event: NSEvent) {
        guard let button = statusButton else { return }
        handleStatusToggle(eventType: event.type, button: button)
    }

    @objc private func handleStatusButtonAction(_ sender: NSStatusBarButton) {
        let eventType = NSApp.currentEvent?.type ?? .applicationDefined
        handleStatusToggle(eventType: eventType, button: sender)
    }

    private func showPanel() {
        guard let appState = boundAppState else { return }
        if panelController == nil {
            let rootView = RootView()
                .environmentObject(appState)
                .frame(width: panelSize.width)
                .frame(
                    minHeight: panelSize.height,
                    maxHeight: .infinity,
                    alignment: .top
                )
                .background(.ultraThinMaterial)
                .ignoresSafeArea(.container, edges: .top)
            let hostingController = NSHostingController(rootView: rootView)
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isReleasedWhenClosed = false
            panel.level = .statusBar
            panel.setContentSize(panelSize)
            panel.contentViewController = hostingController
            panelController = NSWindowController(window: panel)
        }
        positionPanel()
        if let window = panelController?.window, !window.isVisible {
            let targetOrigin = window.frame.origin
            let startOrigin = NSPoint(x: targetOrigin.x, y: targetOrigin.y + 12)
            window.setFrameOrigin(startOrigin)
            window.alphaValue = 0
            panelController?.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
                window.animator().setFrameOrigin(targetOrigin)
            }
        } else {
            panelController?.showWindow(nil)
            panelController?.window?.makeKeyAndOrderFront(nil)
        }
        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        if let window = panelController?.window {
            appState.updatePurchaseConfirmWindow(window)
        }
    }

    private func hidePanel() {
        panelController?.window?.orderOut(nil)
    }

    private func positionPanel() {
        guard let panel = panelController?.window else { return }
        guard let button = statusButton else { return }
        guard let buttonWindow = button.window else { return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        let screenFrame = buttonWindow.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        let effectiveWidth = max(panel.frame.width, panelSize.width)
        let effectiveHeight = max(panel.frame.height, panelSize.height)
        let rawX = screenRect.midX - (effectiveWidth / 2)
        let rawY = screenRect.minY - effectiveHeight - 8
        let minX = screenFrame.minX + panelHorizontalInset
        let maxX = screenFrame.maxX - effectiveWidth - panelHorizontalInset
        let clampedX = min(max(rawX, minX), maxX)
        let clampedY = max(rawY, screenFrame.minY)
        panel.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
    }

    private func isEvent(_ event: NSEvent, on button: NSStatusBarButton) -> Bool {
        guard let buttonWindow = button.window else { return false }
        let buttonRect = button.convert(button.bounds, to: nil)
        let buttonScreenRect = buttonWindow.convertToScreen(buttonRect)
        let mouse = NSEvent.mouseLocation
        return buttonScreenRect.contains(mouse)
    }

    private func handleStatusToggle(
        eventType: NSEvent.EventType,
        button: NSStatusBarButton
    ) {
        if eventType == .rightMouseUp {
            hidePanel()
            presentContextMenu(using: button)
            return
        }
        if panelController?.window?.isVisible == true {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func installBadgeIfNeeded(on button: NSStatusBarButton) {
        if badgeView != nil {
            return
        }
        let badge = BadgeDotView(frame: .zero)
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isHidden = true
        button.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 8),
            badge.heightAnchor.constraint(equalToConstant: 8),
            badge.topAnchor.constraint(equalTo: button.topAnchor, constant: 2),
            badge.trailingAnchor.constraint(
                equalTo: button.trailingAnchor,
                constant: -2
            )
        ])
        badgeView = badge
    }

    private func applyBadgeVisibility() {
        badgeView?.isHidden = !isBadgeVisible
    }

    private func applyBadgeVisibility(
        for authState: AuthState,
        messages: [EmailMessage]
    ) {
        setBadgeVisible(authState == .signedIn && !messages.isEmpty)
    }

    private func handleBillingPresentationState(isInProgress: Bool) {
        guard isInProgress else { return }
        showPanel()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openPostmark() {
        showPanel()
    }

    @objc private func quitPostmark() {
        NSApplication.shared.terminate(nil)
    }

    deinit {
        if let statusClickMonitor {
            NSEvent.removeMonitor(statusClickMonitor)
        }
    }
}

private final class BadgeDotView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(Color.stateDestructive).cgColor
        layer?.cornerRadius = 4
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
