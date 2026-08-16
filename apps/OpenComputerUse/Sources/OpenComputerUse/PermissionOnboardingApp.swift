import AppKit
import ApplicationServices
import OpenComputerUseKit
import QuartzCore

@MainActor
enum PermissionOnboardingApp {
    private static var presentedWindowController: PermissionWindowController?
    private static var presentedConsentController: TelemetryConsentWindowController?
    private static let appDelegate = PermissionOnboardingAppDelegate()

    static func launch() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.applicationIconImage = Branding.makeAppIconImage(size: 256)
        application.delegate = appDelegate
        application.run()
    }

    static func present(terminateOnCompletion: Bool = true) {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.applicationIconImage = Branding.makeAppIconImage(size: 256)
        if TelemetryStore().consent == .undecided {
            presentConsent(terminateOnCompletion: terminateOnCompletion)
        } else {
            presentPermissions(terminateOnCompletion: terminateOnCompletion)
        }
    }

    fileprivate static func presentFirstRunOrPermissions() {
        if TelemetryStore().consent == .undecided {
            presentConsent(terminateOnCompletion: true)
        } else {
            NativeUpdatePrompt.checkAtLaunch()
            presentPermissions(terminateOnCompletion: true)
        }
    }

    private static func presentConsent(terminateOnCompletion: Bool) {
        let controller = TelemetryConsentWindowController { optedIn in
            if optedIn {
                TelemetryCoordinator().optIn()
            } else {
                TelemetryStore().decline()
            }
            presentedConsentController = nil
            NativeUpdatePrompt.checkAtLaunch()
            if PermissionDiagnostics.current().allGranted {
                NSApp.terminate(nil)
            } else {
                presentPermissions(terminateOnCompletion: terminateOnCompletion)
            }
        }
        presentedConsentController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func presentPermissions(terminateOnCompletion: Bool) {
        guard !PermissionDiagnostics.current().allGranted else {
            if terminateOnCompletion { NSApp.terminate(nil) }
            return
        }
        let controller = PermissionWindowController(terminateOnCompletion: terminateOnCompletion)
        presentedWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class PermissionOnboardingAppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        PermissionOnboardingApp.presentFirstRunOrPermissions()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@MainActor
final class TelemetryConsentWindowController: NSWindowController {
    private let onChoice: (Bool) -> Void
    private var didChoose = false

    init(onChoice: @escaping (Bool) -> Void) {
        self.onChoice = onChoice
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = PermissionSupport.bundleDisplayName
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func buildContent() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.055, alpha: 1).cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let eyebrow = NSTextField(labelWithString: "PRIVACY / FIRST RUN")
        eyebrow.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        eyebrow.textColor = NSColor(calibratedRed: 0.66, green: 0.48, blue: 0.95, alpha: 1)
        let title = NSTextField(labelWithString: "Share anonymous usage?")
        title.font = NSFont.systemFont(ofSize: 28, weight: .bold)
        let body = NSTextField(wrappingLabelWithString: "If you accept, \(PermissionSupport.bundleDisplayName) sends a random installation ID, app version, macOS architecture, UTC day, launch/heartbeat events, and fixed-category tool success/error totals. Usage batches also carry a random UUIDv4 batch ID solely for retry deduplication.")
        body.font = NSFont.systemFont(ofSize: 14)
        body.textColor = NSColor(calibratedWhite: 0.74, alpha: 1)
        body.maximumNumberOfLines = 5
        let detail = NSTextField(wrappingLabelWithString: "Never sent: prompts, screenshots, coordinates, app or window names, arguments, paths, command text, user content, or hardware identifiers. Identifier rows expire within 34 UTC days; ID-free daily totals within 360 days. Change later with `overseer computer-use telemetry enable|disable`.")
        detail.font = NSFont.systemFont(ofSize: 12)
        detail.textColor = NSColor(calibratedWhite: 0.52, alpha: 1)
        detail.maximumNumberOfLines = 6

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.alignment = .centerY
        buttons.translatesAutoresizingMaskIntoConstraints = false
        let decline = NSButton(title: "No thanks", target: self, action: #selector(handleDecline))
        decline.bezelStyle = .rounded
        decline.contentTintColor = NSColor(calibratedWhite: 0.82, alpha: 1)
        let accept = NSButton(title: "Share anonymous usage", target: self, action: #selector(handleAccept))
        accept.bezelStyle = .rounded
        accept.keyEquivalent = "\r"
        accept.contentTintColor = NSColor(calibratedRed: 0.70, green: 0.56, blue: 1, alpha: 1)
        buttons.addArrangedSubview(decline)
        buttons.addArrangedSubview(accept)

        stack.addArrangedSubview(eyebrow)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(body)
        stack.addArrangedSubview(detail)
        stack.addArrangedSubview(buttons)
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 36),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -36),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 32),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -28),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return root
    }

    @objc private func handleAccept() { choose(true) }
    @objc private func handleDecline() { choose(false) }

    private func choose(_ optedIn: Bool) {
        guard !didChoose else { return }
        didChoose = true
        onChoice(optedIn)
        close()
    }
}

extension TelemetryConsentWindowController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        choose(false)
        return true
    }
}

@MainActor
final class PermissionWindowController: NSWindowController {
    private let contentController = PermissionContentController()
    private lazy var accessoryPanelController = PermissionAccessoryPanelController { [weak self] in
        self?.handleAccessoryPanelBack()
    }
    private let terminateOnCompletion: Bool

    init(terminateOnCompletion: Bool = true) {
        self.terminateOnCompletion = terminateOnCompletion

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: PermissionOnboardingLayout.windowWidth,
                height: PermissionOnboardingLayout.windowHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = PermissionSupport.currentBundleDisplayName()
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        contentViewController = contentController
        contentController.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
extension PermissionWindowController: PermissionContentControllerDelegate {
    func permissionContentController(
        _ controller: PermissionContentController,
        didRequestPermission permission: SystemPermissionKind,
        sourceFrameInScreen: CGRect?
    ) {
        if permission == .accessibility {
            PermissionSupport.requestAccessibilityPrompt()
        }

        PermissionSupport.openSystemSettings(for: permission)
        accessoryPanelController.show(for: permission, sourceFrameInScreen: sourceFrameInScreen)
        contentController.setActiveGuidance(permission)
    }

    func permissionContentControllerDidResolveGuidance(_ controller: PermissionContentController) {
        accessoryPanelController.hide()
    }

    func permissionContentControllerDidRequestRelaunch(_ controller: PermissionContentController) {
        accessoryPanelController.hide()
        relaunchCurrentAppBundle()
    }

    func permissionContentControllerDidCompleteAllPermissions(_ controller: PermissionContentController) {
        accessoryPanelController.hide()
        close()
        if terminateOnCompletion {
            NSApp.terminate(nil)
        }
    }

    private func handleAccessoryPanelBack() {
        accessoryPanelController.hide()
        contentController.setActiveGuidance(nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func relaunchCurrentAppBundle() {
        guard let appURL = PermissionSupport.currentAppBundleURL() else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }
        NSApp.terminate(nil)
    }
}

@MainActor
protocol PermissionContentControllerDelegate: AnyObject {
    func permissionContentController(
        _ controller: PermissionContentController,
        didRequestPermission permission: SystemPermissionKind,
        sourceFrameInScreen: CGRect?
    )
    func permissionContentControllerDidResolveGuidance(_ controller: PermissionContentController)
    func permissionContentControllerDidRequestRelaunch(_ controller: PermissionContentController)
    func permissionContentControllerDidCompleteAllPermissions(_ controller: PermissionContentController)
}

private enum PermissionOnboardingLayout {
    static let windowWidth: CGFloat = 880
    static let windowHeight: CGFloat = 648
    static let outerHorizontalInset: CGFloat = 48
    static let outerTopInset: CGFloat = 40
    static let outerBottomInset: CGFloat = 32
    static let headerIconSize: CGFloat = 96
    static let cardWidth: CGFloat = 744
    static let cardHeight: CGFloat = 106
    static let cardCornerRadius: CGFloat = 24
    static let cardHorizontalInset: CGFloat = 20
    static let cardVerticalInset: CGFloat = 18
    static let cardIconSize: CGFloat = 54
    static let actionButtonWidth: CGFloat = 104
    static let actionButtonHeight: CGFloat = 44
}

@MainActor
final class PermissionContentController: NSViewController {
    weak var delegate: PermissionContentControllerDelegate?

    private let backgroundView = ControlRoomBackgroundView()
    private let stackView = NSStackView()
    private let iconView = AppGlyphView()
    private let titleLabel = NSTextField(labelWithString: "Connect \(PermissionSupport.currentBundleDisplayName())")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "A one-time permission grant lets \(PermissionSupport.currentBundleDisplayName()) work across your Mac. The status below is read from macOS—not inferred from opening Settings.")
    private let diagramLabel = NSTextField(labelWithString: "AGENT  →  ACCESSIBILITY  →  TARGET APP\n                 ↘  SCREEN CAPTURE  →  SAFE SNAPSHOT")
    private let cardsContainer = NSStackView()
    private let completionLabel = NSTextField(labelWithString: "SYSTEM READY")
    private let refreshTimerInterval: TimeInterval = 0.5
    private let relaunchPromptDelay: TimeInterval = 1.5

    private var activeGuidance: SystemPermissionKind?
    private var refreshTimer: Timer?
    private var diagnostics = PermissionDiagnostics.current()
    private var hasReportedCompletion = false
    private var requestedPermissions: [SystemPermissionKind: Date] = [:]

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        refreshUI()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshTimerInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshState()
            }
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        refreshTimer?.invalidate()
    }

    func setActiveGuidance(_ permission: SystemPermissionKind?) {
        activeGuidance = permission
        refreshUI()
    }

    private func refreshState() {
        let updated = PermissionDiagnostics.current()
        let previousGuidance = activeGuidance
        let wasAllGranted = diagnostics.allGranted
        diagnostics = updated

        if let activeGuidance, updated.isGranted(activeGuidance) {
            self.activeGuidance = nil
        }

        for permission in SystemPermissionKind.allCases where updated.isGranted(permission) {
            requestedPermissions[permission] = nil
        }

        refreshUI()

        if previousGuidance != nil, activeGuidance == nil {
            delegate?.permissionContentControllerDidResolveGuidance(self)
        }

        if updated.allGranted, !wasAllGranted, !hasReportedCompletion {
            hasReportedCompletion = true
            delegate?.permissionContentControllerDidCompleteAllPermissions(self)
        }
    }

    private func configureUI() {
        view.wantsLayer = true

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backgroundView)

        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 32, weight: .bold)
        titleLabel.textColor = NSColor(calibratedWhite: 0.95, alpha: 1)
        titleLabel.maximumNumberOfLines = 1
        subtitleLabel.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.textColor = NSColor(calibratedWhite: 0.68, alpha: 1)
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 3
        diagramLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        diagramLabel.textColor = NSColor(calibratedRed: 0.70, green: 0.56, blue: 1, alpha: 1)
        diagramLabel.alignment = .center
        diagramLabel.maximumNumberOfLines = 2

        cardsContainer.orientation = .vertical
        cardsContainer.alignment = .centerX
        cardsContainer.spacing = 12
        cardsContainer.translatesAutoresizingMaskIntoConstraints = false

        completionLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        completionLabel.textColor = NSColor(calibratedRed: 0.70, green: 0.56, blue: 1, alpha: 1)
        completionLabel.isHidden = true

        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.addArrangedSubview(diagramLabel)
        stackView.addArrangedSubview(cardsContainer)
        stackView.addArrangedSubview(completionLabel)
        stackView.setCustomSpacing(12, after: iconView)
        stackView.setCustomSpacing(8, after: titleLabel)
        stackView.setCustomSpacing(12, after: subtitleLabel)
        stackView.setCustomSpacing(20, after: diagramLabel)
        stackView.setCustomSpacing(12, after: cardsContainer)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PermissionOnboardingLayout.outerHorizontalInset),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PermissionOnboardingLayout.outerHorizontalInset),
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: PermissionOnboardingLayout.outerTopInset),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -PermissionOnboardingLayout.outerBottomInset),

            iconView.widthAnchor.constraint(equalToConstant: PermissionOnboardingLayout.headerIconSize),
            iconView.heightAnchor.constraint(equalToConstant: PermissionOnboardingLayout.headerIconSize),
            cardsContainer.widthAnchor.constraint(equalToConstant: PermissionOnboardingLayout.cardWidth),
        ])
    }

    private func refreshUI() {
        cardsContainer.arrangedSubviews.forEach { subview in
            cardsContainer.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let orderedPermissions = SystemPermissionKind.allCases
        for permission in orderedPermissions {
            let restartRequired = restartRequired(for: permission)
            if activeGuidance == permission, !diagnostics.isGranted(permission), !restartRequired {
                let placeholder = GuidancePlaceholderView()
                cardsContainer.addArrangedSubview(placeholder)
                placeholder.widthAnchor.constraint(equalToConstant: PermissionOnboardingLayout.cardWidth).isActive = true
                continue
            }

            let card = PermissionCardView(permission: permission, diagnostics: diagnostics, restartRequired: restartRequired)
            card.onAllow = { [weak self] requestedPermission, sourceFrameInScreen in
                guard let self else {
                    return
                }

                if self.restartRequired(for: requestedPermission) {
                    self.delegate?.permissionContentControllerDidRequestRelaunch(self)
                    return
                }

                self.requestedPermissions[requestedPermission] = Date()
                self.delegate?.permissionContentController(
                    self,
                    didRequestPermission: requestedPermission,
                    sourceFrameInScreen: sourceFrameInScreen
                )
            }
            cardsContainer.addArrangedSubview(card)
            card.widthAnchor.constraint(equalToConstant: PermissionOnboardingLayout.cardWidth).isActive = true
        }

        completionLabel.isHidden = !diagnostics.allGranted
    }

    private func restartRequired(for permission: SystemPermissionKind) -> Bool {
        guard !diagnostics.isGranted(permission), let requestedAt = requestedPermissions[permission] else {
            return false
        }

        return Date().timeIntervalSince(requestedAt) >= relaunchPromptDelay
    }
}

@MainActor
final class PermissionCardView: NSView {
    var onAllow: ((SystemPermissionKind, CGRect?) -> Void)?

    private let permission: SystemPermissionKind
    private let diagnostics: PermissionDiagnostics
    private let restartRequired: Bool
    private weak var actionButton: PrimaryActionButton?

    init(permission: SystemPermissionKind, diagnostics: PermissionDiagnostics, restartRequired: Bool = false) {
        self.permission = permission
        self.diagnostics = diagnostics
        self.restartRequired = restartRequired
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func configure() {
        wantsLayer = true
        layer?.cornerRadius = PermissionOnboardingLayout.cardCornerRadius
        layer?.backgroundColor = NSColor(calibratedWhite: 0.095, alpha: 1).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 0.20, alpha: 1).cgColor

        let content = NSStackView()
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false

        let iconBackground = NSView()
        iconBackground.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.wantsLayer = true
        iconBackground.layer?.cornerRadius = PermissionOnboardingLayout.cardIconSize / 2
        iconBackground.layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 1).cgColor
        iconBackground.layer?.borderWidth = 1
        iconBackground.layer?.borderColor = NSColor(calibratedRed: 0.70, green: 0.56, blue: 1, alpha: 0.55).cgColor

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentTintColor = NSColor(calibratedRed: 0.76, green: 0.68, blue: 1, alpha: 1)
        icon.image = NSImage(systemSymbolName: permission.symbolName, accessibilityDescription: permission.title)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        iconBackground.addSubview(icon)

        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2

        let title = NSTextField(labelWithString: permission.title)
        title.font = NSFont.systemFont(ofSize: 19, weight: .semibold)
        title.textColor = NSColor(calibratedWhite: 0.94, alpha: 1)

        let subtitle = NSTextField(labelWithString: restartRequired ? "Restart to finish enabling this permission" : permission.subtitle)
        subtitle.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        subtitle.textColor = NSColor(calibratedWhite: 0.60, alpha: 1)

        labels.addArrangedSubview(title)
        labels.addArrangedSubview(subtitle)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        content.addArrangedSubview(iconBackground)
        content.addArrangedSubview(labels)
        content.addArrangedSubview(spacer)

        if diagnostics.isGranted(permission) {
            let done = StatusChipView(text: "READY", foreground: NSColor(calibratedRed: 0.73, green: 0.64, blue: 1, alpha: 1), background: NSColor(calibratedRed: 0.24, green: 0.18, blue: 0.36, alpha: 1))
            content.addArrangedSubview(done)
        } else {
            let button = PrimaryActionButton(title: restartRequired ? "Restart" : "Allow", target: self, action: #selector(handleAllow))
            actionButton = button
            content.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: PermissionOnboardingLayout.actionButtonWidth).isActive = true
            button.heightAnchor.constraint(equalToConstant: PermissionOnboardingLayout.actionButtonHeight).isActive = true
        }

        addSubview(content)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: PermissionOnboardingLayout.cardHeight),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PermissionOnboardingLayout.cardHorizontalInset),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PermissionOnboardingLayout.cardHorizontalInset),
            content.topAnchor.constraint(equalTo: topAnchor, constant: PermissionOnboardingLayout.cardVerticalInset),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -PermissionOnboardingLayout.cardVerticalInset),

            iconBackground.widthAnchor.constraint(equalToConstant: PermissionOnboardingLayout.cardIconSize),
            iconBackground.heightAnchor.constraint(equalToConstant: PermissionOnboardingLayout.cardIconSize),
            icon.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 12),
        ])
    }

    @objc
    private func handleAllow() {
        onAllow?(permission, actionButtonScreenFrame())
    }

    private func actionButtonScreenFrame() -> CGRect? {
        guard let actionButton, let window = actionButton.window else {
            return nil
        }

        let frameInWindow = actionButton.convert(actionButton.bounds, to: nil)
        return window.convertToScreen(frameInWindow)
    }
}

@MainActor
final class GuidancePlaceholderView: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.085, alpha: 1).cgColor

        let label = NSTextField(labelWithString: "COMPLETE IN SYSTEM SETTINGS")
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 82),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let borderRect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(
            roundedRect: borderRect,
            xRadius: PermissionOnboardingLayout.cardCornerRadius,
            yRadius: PermissionOnboardingLayout.cardCornerRadius
        )
        path.setLineDash([6, 6], count: 2, phase: 0)
        path.lineWidth = 1.5
        NSColor(calibratedWhite: 0.82, alpha: 1).setStroke()
        path.stroke()
    }
}

@MainActor
final class PermissionAccessoryPanelController {
    private let onBack: () -> Void
    private let trackingInterval: TimeInterval = 0.15
    private let launchAnimationDuration: TimeInterval = 0.72
    private let launchAnimationResponse = 0.72
    private let launchAnimationDampingFraction = 1.0
    private let launchInitialAlpha: CGFloat = 0.9
    private var panel: NSPanel?
    private var currentPermission: SystemPermissionKind?
    private var workspaceObserver: NSObjectProtocol?
    private var globalDragMonitor: Any?
    private var localDragMonitor: Any?
    private var orderedWindowNumber: Int?
    private var trackingTimer: Timer?
    private var pendingSourceFrameInScreen: CGRect?
    private var didPresentCurrentPanel = false
    private var launchDisplayLink: CADisplayLink?
    private var launchStartTime: CFTimeInterval = 0
    private var launchFromFrame = NSRect.zero
    private var launchToFrame = NSRect.zero
    private var isAnimatingLaunch = false
    private var launchSettleGeneration = 0

    private enum Layout {
        static let panelWidth: CGFloat = 530
        static let panelHeight: CGFloat = 109
        static let screenHorizontalInset: CGFloat = 16
        static let screenBottomInset: CGFloat = 12
        static let windowBottomOverlap: CGFloat = 6
        static let contentLeadingInset: CGFloat = 26
        static let contentTrailingInset: CGFloat = 28
        static let sidebarWidthRatio: CGFloat = 0.29
        static let sidebarWidthMin: CGFloat = 214
        static let sidebarWidthMax: CGFloat = 272
    }

    private struct PanelAnchor {
        let windowBounds: CGRect
        let contentTrackRect: CGRect
    }

    private struct SystemSettingsWindowContext {
        let bounds: CGRect
        let windowNumber: Int
    }

    init(onBack: @escaping () -> Void) {
        self.onBack = onBack
    }

    func show(for permission: SystemPermissionKind, sourceFrameInScreen: CGRect?) {
        currentPermission = permission
        pendingSourceFrameInScreen = sourceFrameInScreen
        didPresentCurrentPanel = false

        let panel = panel ?? makePanel()
        self.panel = panel

        if let contentView = panel.contentView as? PermissionAccessoryPanelView {
            contentView.configure(permission: permission)
        }

        installObserversIfNeeded()
        startTrackingTimer()
        updatePanelVisibility()
    }

    func hide() {
        stopLaunchAnimation()
        stopTrackingTimer()
        removeObservers()
        panel?.orderOut(nil)
        panel?.alphaValue = 1
        currentPermission = nil
        orderedWindowNumber = nil
        pendingSourceFrameInScreen = nil
        didPresentCurrentPanel = false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Layout.panelWidth, height: Layout.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.contentView = PermissionAccessoryPanelView(onBack: onBack)
        return panel
    }

    private func installObserversIfNeeded() {
        if workspaceObserver == nil {
            workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updatePanelVisibility()
                    self?.refreshPosition()
                }
            }
        }

        if globalDragMonitor == nil {
            globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshPosition()
                }
            }
        }

        if localDragMonitor == nil {
            localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.refreshPosition()
                }
                return event
            }
        }
    }

    private func removeObservers() {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }

        if let globalDragMonitor {
            NSEvent.removeMonitor(globalDragMonitor)
            self.globalDragMonitor = nil
        }

        if let localDragMonitor {
            NSEvent.removeMonitor(localDragMonitor)
            self.localDragMonitor = nil
        }
    }

    private func startTrackingTimer() {
        stopTrackingTimer()
        let timer = Timer(timeInterval: trackingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTrackingTick()
            }
        }
        timer.tolerance = 0.03
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    private func stopTrackingTimer() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    private func handleTrackingTick() {
        updatePanelVisibility()
        refreshPosition()
    }

    private func refreshPosition() {
        guard let panel, currentPermission != nil, panel.isVisible, let windowContext = systemSettingsWindowContext() else {
            return
        }

        position(panel: panel, windowBounds: windowContext.bounds)
    }

    private func updatePanelVisibility() {
        guard let panel, currentPermission != nil else {
            return
        }

        guard isSystemSettingsFrontmost, let windowContext = systemSettingsWindowContext() else {
            stopLaunchAnimation()
            panel.orderOut(nil)
            return
        }

        let panelWasVisible = panel.isVisible

        if didPresentCurrentPanel == false {
            presentPanel(
                panel: panel,
                from: pendingSourceFrameInScreen,
                relativeTo: windowContext
            )
            didPresentCurrentPanel = true
        } else {
            let previousOrderedWindowNumber = orderedWindowNumber
            orderedWindowNumber = windowContext.windowNumber
            position(panel: panel, windowBounds: windowContext.bounds)
            if previousOrderedWindowNumber != windowContext.windowNumber || panelWasVisible == false {
                panel.order(.above, relativeTo: windowContext.windowNumber)
            }
        }

    }

    private func position(panel: NSPanel, windowBounds: CGRect) {
        guard let origin = preferredPanelOrigin(
            for: panel.frame.size,
            windowBounds: windowBounds
        ) else {
            return
        }

        if isAnimatingLaunch {
            launchToFrame.origin = origin
            return
        }

        if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
        }
    }

    private func presentPanel(
        panel: NSPanel,
        from sourceFrameInScreen: CGRect?,
        relativeTo windowContext: SystemSettingsWindowContext
    ) {
        guard let targetOrigin = preferredPanelOrigin(
            for: panel.frame.size,
            windowBounds: windowContext.bounds
        ) else {
            return
        }

        let targetFrame = NSRect(origin: targetOrigin, size: panel.frame.size)
        orderedWindowNumber = windowContext.windowNumber

        guard let sourceFrameInScreen, sourceFrameInScreen.isEmpty == false else {
            stopLaunchAnimation()
            panel.alphaValue = 1
            panel.setFrame(targetFrame, display: false)
            panel.order(.above, relativeTo: windowContext.windowNumber)
            return
        }

        stopLaunchAnimation()
        isAnimatingLaunch = true
        launchFromFrame = sourceFrameInScreen
        launchToFrame = targetFrame
        launchStartTime = CACurrentMediaTime()
        launchSettleGeneration += 1

        panel.alphaValue = launchInitialAlpha
        panel.setFrame(sourceFrameInScreen, display: false)
        panel.order(.above, relativeTo: windowContext.windowNumber)
        stepLaunchAnimation()

        let displayLink = panel.displayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        displayLink.add(to: .main, forMode: .common)
        launchDisplayLink = displayLink
        scheduleLaunchSettlePasses(for: launchSettleGeneration)
    }

    @objc
    private func displayLinkDidFire(_ displayLink: CADisplayLink) {
        stepLaunchAnimation()
    }

    private func stepLaunchAnimation() {
        guard let panel else {
            stopLaunchAnimation()
            return
        }

        let elapsed = max(0, CACurrentMediaTime() - launchStartTime)
        if elapsed >= launchAnimationDuration {
            isAnimatingLaunch = false
            stopLaunchAnimation()
            panel.alphaValue = 1
            updateLaunchTargetFrameIfNeeded()
            panel.setFrame(launchToFrame, display: true)
            if let orderedWindowNumber {
                panel.order(.above, relativeTo: orderedWindowNumber)
            }
            return
        }

        let progress = springProgress(at: elapsed)
        panel.alphaValue = launchInitialAlpha + ((1 - launchInitialAlpha) * progress)
        panel.setFrame(curvedFrame(from: launchFromFrame, to: launchToFrame, progress: progress), display: true)
        if let orderedWindowNumber {
            panel.order(.above, relativeTo: orderedWindowNumber)
        }
    }

    private func stopLaunchAnimation() {
        isAnimatingLaunch = false
        launchDisplayLink?.invalidate()
        launchDisplayLink = nil
    }

    private func updateLaunchTargetFrameIfNeeded() {
        guard
            let panel,
            let windowContext = systemSettingsWindowContext(),
            let origin = preferredPanelOrigin(for: panel.frame.size, windowBounds: windowContext.bounds)
        else {
            return
        }

        orderedWindowNumber = windowContext.windowNumber
        launchToFrame = NSRect(origin: origin, size: panel.frame.size)
    }

    private func scheduleLaunchSettlePasses(for generation: Int) {
        let delays: [TimeInterval] = [0.18, 0.42, 0.84, 1.2]

        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.currentPermission != nil, self.launchSettleGeneration == generation else {
                        return
                    }
                    self.updatePanelVisibility()
                    self.refreshPosition()
                }
            }
        }
    }

    private func springProgress(at elapsed: TimeInterval) -> CGFloat {
        let omega = (2 * Double.pi) / launchAnimationResponse
        let t = max(0, elapsed)
        let progress: Double

        if abs(launchAnimationDampingFraction - 1) < 0.0001 {
            progress = 1 - exp(-omega * t) * (1 + (omega * t))
        } else {
            progress = min(1, t / launchAnimationDuration)
        }

        return min(max(progress, 0), 1)
    }

    private func curvedFrame(from: NSRect, to: NSRect, progress: CGFloat) -> NSRect {
        let size = NSSize(
            width: from.size.width + ((to.size.width - from.size.width) * progress),
            height: from.size.height + ((to.size.height - from.size.height) * progress)
        )

        let startCenter = CGPoint(x: from.midX, y: from.midY)
        let endCenter = CGPoint(x: to.midX, y: to.midY)
        let midPoint = CGPoint(
            x: (startCenter.x + endCenter.x) * 0.5,
            y: max(startCenter.y, endCenter.y)
        )
        let distance = hypot(endCenter.x - startCenter.x, endCenter.y - startCenter.y)
        let lift = min(140, max(44, distance * 0.18))
        let controlPoint = CGPoint(x: midPoint.x, y: midPoint.y + lift)
        let inverse = 1 - progress
        let center = CGPoint(
            x: (inverse * inverse * startCenter.x) + (2 * inverse * progress * controlPoint.x) + (progress * progress * endCenter.x),
            y: (inverse * inverse * startCenter.y) + (2 * inverse * progress * controlPoint.y) + (progress * progress * endCenter.y)
        )

        return NSRect(
            x: center.x - (size.width * 0.5),
            y: center.y - (size.height * 0.5),
            width: size.width,
            height: size.height
        )
    }

    private func preferredPanelOrigin(
        for panelSize: CGSize,
        windowBounds: CGRect
    ) -> CGPoint? {
        guard let anchor = preferredPanelAnchor(windowBounds: windowBounds) else {
            return nil
        }

        let referenceRect = anchor.windowBounds
        let visibleFrame = targetVisibleScreenFrame(for: referenceRect) ?? referenceRect
        let trackRect = anchor.contentTrackRect
        let x = clamp(
            trackRect.midX - (panelSize.width / 2),
            lower: visibleFrame.minX + Layout.screenHorizontalInset,
            upper: visibleFrame.maxX - panelSize.width - Layout.screenHorizontalInset
        )
        let desiredY = referenceRect.minY - panelSize.height + Layout.windowBottomOverlap
        let y = max(
            visibleFrame.minY + Layout.screenBottomInset,
            desiredY
        )
        return CGPoint(x: x, y: y)
    }

    private func preferredPanelAnchor(windowBounds: CGRect) -> PanelAnchor? {
        let referenceRect = windowBounds

        return PanelAnchor(
            windowBounds: referenceRect,
            contentTrackRect: systemSettingsContentTrackRect(in: referenceRect)
        )
    }

    private func systemSettingsContentTrackRect(in windowBounds: CGRect) -> CGRect {
        // Keep the panel centered under the content area even when the
        // vertical anchor comes from a specific controls row.
        let sidebarWidth = clamp(
            windowBounds.width * Layout.sidebarWidthRatio,
            lower: Layout.sidebarWidthMin,
            upper: Layout.sidebarWidthMax
        )
        let contentMinX = min(
            windowBounds.maxX - Layout.contentTrailingInset - 1,
            windowBounds.minX + sidebarWidth + Layout.contentLeadingInset
        )
        let contentMaxX = max(contentMinX + 1, windowBounds.maxX - Layout.contentTrailingInset)
        return CGRect(
            x: contentMinX,
            y: windowBounds.minY,
            width: contentMaxX - contentMinX,
            height: windowBounds.height
        )
    }

    private func targetVisibleScreenFrame(for rect: CGRect) -> CGRect? {
        NSScreen.screens.first(where: { $0.visibleFrame.intersects(rect) })?.visibleFrame
    }

    private func appKitRect(fromCGWindowBounds bounds: CGRect) -> CGRect {
        guard let screen = NSScreen.screens.first(where: { screen in
            let screenBoundsInQuartz = CGRect(
                x: screen.frame.minX,
                y: screen.frame.minY,
                width: screen.frame.width,
                height: screen.frame.height
            )
            return screenBoundsInQuartz.intersects(bounds)
        }) ?? NSScreen.main else {
            return bounds
        }

        let convertedY = screen.frame.maxY - bounds.maxY
        return CGRect(x: bounds.minX, y: convertedY, width: bounds.width, height: bounds.height)
    }

    private var isSystemSettingsFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences"
    }

    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard lower <= upper else {
            return lower
        }

        return min(max(value, lower), upper)
    }

    private func systemSettingsWindowContext() -> SystemSettingsWindowContext? {
        guard let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.systempreferences" }) else {
            return nil
        }

        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let windows = windowInfoList.compactMap { info -> (SystemSettingsWindowContext, Int)? in
            guard
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                ownerPID == runningApp.processIdentifier,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                let windowNumber = info[kCGWindowNumber as String] as? Int,
                let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else {
                return nil
            }

            let appKitBounds = appKitRect(fromCGWindowBounds: bounds)
            return (SystemSettingsWindowContext(bounds: appKitBounds, windowNumber: windowNumber), Int(appKitBounds.width * appKitBounds.height))
        }

        return windows.sorted(by: { $0.1 > $1.1 }).first?.0
    }

}

@MainActor
final class PermissionAccessoryPanelView: NSView {
    private let onBack: () -> Void
    private let instructionLabel = NSTextField(labelWithString: "")
    private let dragTileView = DraggableAppTileView()

    init(onBack: @escaping () -> Void) {
        self.onBack = onBack
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }

    private func setup() {
        let materialView = NSVisualEffectView()
        materialView.translatesAutoresizingMaskIntoConstraints = false
        materialView.material = .popover
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = 20
        materialView.layer?.masksToBounds = true
        materialView.layer?.borderWidth = 0.5
        materialView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.18).cgColor
        addSubview(materialView)

        let tintView = NSView()
        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.8).cgColor
        materialView.addSubview(tintView)

        let backChrome = NSView()
        backChrome.translatesAutoresizingMaskIntoConstraints = false
        backChrome.wantsLayer = true
        backChrome.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.95).cgColor
        backChrome.layer?.cornerRadius = 16
        materialView.addSubview(backChrome)

        let backButton = AccessoryBackButton(target: self, action: #selector(handleBack))
        backChrome.addSubview(backButton)

        let arrow = NSImageView()
        arrow.translatesAutoresizingMaskIntoConstraints = false
        arrow.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "Drag upward")
        arrow.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 26, weight: .bold)
        arrow.contentTintColor = NSColor(calibratedRed: 0.70, green: 0.56, blue: 1, alpha: 1)

        instructionLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        instructionLabel.textColor = NSColor(calibratedWhite: 0.68, alpha: 1)
        instructionLabel.lineBreakMode = .byTruncatingTail
        instructionLabel.maximumNumberOfLines = 1
        instructionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        dragTileView.translatesAutoresizingMaskIntoConstraints = false

        materialView.addSubview(arrow)
        materialView.addSubview(instructionLabel)
        materialView.addSubview(dragTileView)

        NSLayoutConstraint.activate([
            materialView.leadingAnchor.constraint(equalTo: leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: trailingAnchor),
            materialView.topAnchor.constraint(equalTo: topAnchor),
            materialView.bottomAnchor.constraint(equalTo: bottomAnchor),

            tintView.leadingAnchor.constraint(equalTo: materialView.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: materialView.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: materialView.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: materialView.bottomAnchor),

            backChrome.leadingAnchor.constraint(equalTo: materialView.leadingAnchor, constant: 18),
            backChrome.topAnchor.constraint(equalTo: materialView.topAnchor, constant: 52),
            backChrome.widthAnchor.constraint(equalToConstant: 32),
            backChrome.heightAnchor.constraint(equalToConstant: 32),

            backButton.centerXAnchor.constraint(equalTo: backChrome.centerXAnchor),
            backButton.centerYAnchor.constraint(equalTo: backChrome.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 14),
            backButton.heightAnchor.constraint(equalToConstant: 14),

            arrow.leadingAnchor.constraint(equalTo: materialView.leadingAnchor, constant: 35),
            arrow.topAnchor.constraint(equalTo: materialView.topAnchor, constant: 10),
            arrow.widthAnchor.constraint(equalToConstant: 28),
            arrow.heightAnchor.constraint(equalToConstant: 28),

            instructionLabel.leadingAnchor.constraint(equalTo: arrow.trailingAnchor, constant: 10),
            instructionLabel.centerYAnchor.constraint(equalTo: arrow.centerYAnchor),
            instructionLabel.trailingAnchor.constraint(equalTo: materialView.trailingAnchor, constant: -22),

            dragTileView.leadingAnchor.constraint(equalTo: materialView.leadingAnchor, constant: 64),
            dragTileView.trailingAnchor.constraint(equalTo: materialView.trailingAnchor, constant: -21),
            dragTileView.topAnchor.constraint(equalTo: materialView.topAnchor, constant: 47),
            dragTileView.heightAnchor.constraint(equalToConstant: 43)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(permission: SystemPermissionKind) {
        instructionLabel.stringValue = permission.dragInstruction
    }

    @objc
    private func handleBack() {
        onBack()
    }
}

@MainActor
final class DraggableAppTileView: NSView, NSDraggingSource {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 0.86, alpha: 1).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let iconRect = CGRect(x: 12, y: 8, width: 28, height: 28)
        let icon = currentIcon()
        icon.draw(in: iconRect)

        let title = currentTitle()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.26, alpha: 1),
        ]
        title.draw(at: CGPoint(x: 52, y: 12), withAttributes: attributes)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let bundleURL = PermissionSupport.currentAppBundleURL() else {
            NSSound.beep()
            return
        }

        let draggingItem = NSDraggingItem(pasteboardWriter: bundleURL as NSURL)
        draggingItem.setDraggingFrame(bounds, contents: snapshotImage())
        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    private func currentIcon() -> NSImage {
        if let bundleURL = PermissionSupport.currentAppBundleURL() {
            if let bundle = Bundle(url: bundleURL),
               PermissionSupport.isOpenComputerUseBundleIdentifier(bundle.bundleIdentifier)
            {
                return Branding.makeAppIconImage(size: 128)
            }

            return NSWorkspace.shared.icon(forFile: bundleURL.path)
        }

        return Branding.makeAppIconImage(size: 128)
    }

    private func currentTitle() -> String {
        if let bundleURL = PermissionSupport.currentAppBundleURL() {
            if let bundle = Bundle(url: bundleURL) {
                let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                let bundleName = bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
                return displayName ?? bundleName ?? PermissionSupport.bundleDisplayName
            }

            return PermissionSupport.bundleDisplayName
        }

        return PermissionSupport.bundleDisplayName
    }

    private func snapshotImage() -> NSImage {
        let bitmap = bitmapImageRepForCachingDisplay(in: bounds) ?? NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width), pixelsHigh: Int(bounds.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        cacheDisplay(in: bounds, to: bitmap)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)
        return image
    }
}

@MainActor
enum Branding {
    static func makeAppIconImage(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let inset = size * 0.09
        let tileRect = CGRect(origin: .zero, size: image.size).insetBy(dx: inset, dy: inset)
        let tile = NSBezierPath(roundedRect: tileRect, xRadius: size * 0.20, yRadius: size * 0.20)
        NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
        tile.fill()
        NSColor(calibratedWhite: 0.23, alpha: 1).setStroke()
        tile.lineWidth = max(1, size * 0.012)
        tile.stroke()

        let center = CGPoint(x: size / 2, y: size / 2)
        let radius = size * 0.285
        let ring = NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        ring.lineWidth = max(1.5, size * 0.045)
        NSColor(calibratedRed: 0.70, green: 0.56, blue: 1, alpha: 1).setStroke()
        ring.stroke()

        let diamondRadius = size * 0.13
        let diamond = NSBezierPath()
        diamond.move(to: CGPoint(x: center.x, y: center.y + diamondRadius))
        diamond.line(to: CGPoint(x: center.x + diamondRadius, y: center.y))
        diamond.line(to: CGPoint(x: center.x, y: center.y - diamondRadius))
        diamond.line(to: CGPoint(x: center.x - diamondRadius, y: center.y))
        diamond.close()
        NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
        diamond.fill()

        image.unlockFocus()
        return image
    }
}

@MainActor
final class ControlRoomBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
        bounds.fill()
        NSColor(calibratedWhite: 0.13, alpha: 1).setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }
}

@MainActor
final class AppGlyphView: NSImageView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        image = Branding.makeAppIconImage(size: PermissionOnboardingLayout.headerIconSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
final class StatusChipView: NSView {
    init(text: String, foreground: NSColor, background: NSColor) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.backgroundColor = background.cgColor

        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = foreground
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        let check = NSImageView()
        check.translatesAutoresizingMaskIntoConstraints = false
        check.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: text)
        check.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        check.contentTintColor = foreground
        addSubview(check)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            check.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            check.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            check.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
final class PrimaryActionButton: NSButton {
    override var isHighlighted: Bool {
        didSet {
            updateAppearance()
        }
    }

    init(title: String, target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        self.title = title
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        isBordered = false
        focusRingType = .none
        setButtonType(.momentaryPushIn)
        updateAttributedTitle()
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    private func updateAttributedTitle() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraphStyle,
            ]
        )
    }

    private func updateAppearance() {
        layer?.backgroundColor = (
            isHighlighted
            ? NSColor(calibratedRed: 0.05, green: 0.45, blue: 0.94, alpha: 1)
            : NSColor(calibratedRed: 0.06, green: 0.49, blue: 0.99, alpha: 1)
        ).cgColor
        alphaValue = isEnabled ? 1 : 0.45
    }
}

@MainActor
final class AccessoryBackButton: NSButton {
    override var isHighlighted: Bool {
        didSet {
            alphaValue = isHighlighted ? 0.66 : 1
        }
    }

    init(target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        focusRingType = .none
        image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
        contentTintColor = NSColor.labelColor.withAlphaComponent(0.72)
        if let cell = cell as? NSButtonCell {
            cell.imagePosition = .imageOnly
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
