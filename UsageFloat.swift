import AppKit
import Foundation

struct UsageWindow {
    let label: String
    let usedPercent: Double
    let remainingPercent: Double
    let resetAt: Date?
}

struct UsageSnapshot {
    let planType: String
    let credits: String
    let primary: UsageWindow?
    let secondary: UsageWindow?
    let fetchedAt: Date
}

enum AppearancePalette {
    static var foreground: NSColor {
        .labelColor
    }
}

final class UsageFetcher {
    private let codexPathCandidates = [
        "/Applications/ChatGPT.app/Contents/Resources/codex",
        "/Applications/Codex.app/Contents/Resources/codex"
    ]

    func fetch(completion: @escaping (Result<UsageSnapshot, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let initRequest = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-usage-float","title":"Codex Usage Float","version":"0.4.0"},"capabilities":{"experimentalApi":true,"requestAttestation":false}}}"#
            let readRequest = #"{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read"}"#
            let input = "\(initRequest)\n\(readRequest)\n"

            do {
                let text = try self.readRateLimits(input: input)

                guard let snapshot = Self.parseSnapshot(from: text) else {
                    throw NSError(domain: "UsageFetcher", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not read usage data"])
                }

                DispatchQueue.main.async {
                    completion(.success(snapshot))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    private func readRateLimits(input: String) throws -> String {
        var errors: [String] = []

        do {
            return try runCodexStdioWithDelay(timeout: 20)
        } catch {
            errors.append("stdio: \(error.localizedDescription)")
        }

        do {
            return try runCodex(arguments: ["app-server", "proxy"], input: input, timeout: 8)
        } catch {
            errors.append("proxy: \(error.localizedDescription)")
        }

        _ = try? runCodex(arguments: ["app-server", "daemon", "start"], input: nil, timeout: 6)

        do {
            return try runCodex(arguments: ["app-server", "proxy"], input: input, timeout: 8)
        } catch {
            errors.append("daemon proxy: \(error.localizedDescription)")
        }

        throw NSError(
            domain: "UsageFetcher",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: errors.joined(separator: "\n")]
        )
    }

    private func runCodexStdioWithDelay(timeout: TimeInterval) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try codexExecutablePath())
        process.arguments = ["app-server", "--listen", "stdio://"]

        let output = Pipe()
        let error = Pipe()
        let inputPipe = Pipe()
        process.standardOutput = output
        process.standardError = error
        process.standardInput = inputPipe

        let initRequest = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-usage-float","title":"Codex Usage Float","version":"0.4.0"},"capabilities":{"experimentalApi":true,"requestAttestation":false}}}"# + "\n"
        let readRequest = #"{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read"}"# + "\n"

        try process.run()

        inputPipe.fileHandleForWriting.write(Data(initRequest.utf8))
        Thread.sleep(forTimeInterval: 0.8)
        inputPipe.fileHandleForWriting.write(Data(readRequest.utf8))
        Thread.sleep(forTimeInterval: 15.0)
        try? inputPipe.fileHandleForWriting.close()

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            group.leave()
        }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw NSError(domain: "UsageFetcher", code: 3, userInfo: [NSLocalizedDescriptionKey: "Codex app-server timed out"])
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errData = error.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        let errText = String(data: errData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let message = errText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "UsageFetcher", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "No response" : message])
        }

        return text
    }

    private func runCodex(arguments: [String], input: String?, timeout: TimeInterval) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try codexExecutablePath())
        process.arguments = arguments

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        let inputPipe: Pipe?
        if input != nil {
            let pipe = Pipe()
            process.standardInput = pipe
            inputPipe = pipe
        } else {
            inputPipe = nil
        }

        try process.run()

        if let input, let inputPipe {
            inputPipe.fileHandleForWriting.write(Data(input.utf8))
            try? inputPipe.fileHandleForWriting.close()
        }

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            group.leave()
        }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw NSError(domain: "UsageFetcher", code: 3, userInfo: [NSLocalizedDescriptionKey: "Codex app-server timed out"])
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errData = error.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        let errText = String(data: errData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let message = errText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "UsageFetcher", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "No response" : message])
        }

        return text
    }

    private func codexExecutablePath() throws -> String {
        let manager = FileManager.default
        if let path = codexPathCandidates.first(where: { manager.isExecutableFile(atPath: $0) }) {
            return path
        }

        throw NSError(
            domain: "UsageFetcher",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Codex executable not found"]
        )
    }

    private static func parseSnapshot(from text: String) -> UsageSnapshot? {
        for line in text.split(separator: "\n").map(String.init) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["id"] as? Int,
                  id == 2,
                  let result = object["result"] as? [String: Any] else {
                continue
            }

            guard let rateLimits = preferredRateLimits(from: result) else { continue }

            let planType = (rateLimits["planType"] as? String) ?? "unknown"
            let creditsInfo = rateLimits["credits"] as? [String: Any]
            let credits = String(describing: creditsInfo?["balance"] ?? "0")
            let primary = parseWindow(rateLimits["primary"] as? [String: Any])
            let secondary = parseWindow(rateLimits["secondary"] as? [String: Any])

            return UsageSnapshot(
                planType: planType,
                credits: credits,
                primary: primary,
                secondary: secondary,
                fetchedAt: Date()
            )
        }
        return nil
    }

    private static func preferredRateLimits(from result: [String: Any]) -> [String: Any]? {
        if let byLimitId = result["rateLimitsByLimitId"] as? [String: Any] {
            if let codex = byLimitId["codex"] as? [String: Any] {
                return codex
            }

            let snapshots = byLimitId.values.compactMap { $0 as? [String: Any] }
            if let withWindows = snapshots.first(where: { $0["primary"] != nil || $0["secondary"] != nil }) {
                return withWindows
            }
        }

        return result["rateLimits"] as? [String: Any]
    }

    private static func parseWindow(_ value: [String: Any]?) -> UsageWindow? {
        guard let value else { return nil }
        let used = number(value["usedPercent"]) ?? 0
        let minutes = number(value["windowDurationMins"])
        let resetSeconds = number(value["resetsAt"])
        let resetAt = resetSeconds.map { Date(timeIntervalSince1970: $0) }
        let label = labelForWindow(minutes: minutes)
        return UsageWindow(label: label, usedPercent: used, remainingPercent: max(0, 100 - used), resetAt: resetAt)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func labelForWindow(minutes: Double?) -> String {
        guard let minutes else { return "-" }
        if minutes < 60 { return "\(Int(minutes)) min" }
        if minutes < 1440 { return "\(Int(minutes / 60))h" }
        if minutes < 10080 { return "\(Int(minutes / 1440))d" }
        return "\(Int(round(minutes / 10080)))w"
    }
}

final class UsageRow: NSView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "")
    private let resetLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        percentLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        resetLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        applyAppearance()
        nameLabel.alignment = .center
        percentLabel.alignment = .center
        resetLabel.alignment = .center

        let top = NSStackView(views: [nameLabel, percentLabel, resetLabel])
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = 5
        top.distribution = .gravityAreas
        top.setHuggingPriority(.defaultLow, for: .horizontal)
        percentLabel.setContentHuggingPriority(.required, for: .horizontal)
        resetLabel.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [top])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            top.widthAnchor.constraint(equalToConstant: 156)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyAppearance() {
        let color = AppearancePalette.foreground
        nameLabel.textColor = color
        percentLabel.textColor = color
        resetLabel.textColor = color
    }

    func update(with window: UsageWindow?) {
        guard let window else {
            nameLabel.stringValue = "-"
            percentLabel.stringValue = "--%"
            resetLabel.stringValue = "--:--"
            return
        }

        nameLabel.stringValue = window.label
        percentLabel.stringValue = "\(Int(round(window.remainingPercent)))%"
        resetLabel.stringValue = Self.formatReset(window.resetAt)
    }

    private static func formatReset(_ date: Date?) -> String {
        formatResetForCompact(date)
    }

    static func formatResetForCompact(_ date: Date?) -> String {
        guard let date else { return "--:--" }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "M/d"
        }
        return formatter.string(from: date)
    }
}

final class ProgressBarView: NSView {
    var value: Double = 0 {
        didSet {
            value = min(1, max(0, value))
            needsDisplay = true
        }
    }

    var tint: NSColor = .controlAccentColor {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        AppearancePalette.foreground.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        let width = max(bounds.height, bounds.width * value)
        let fillRect = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        tint.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
    }
}

final class DraggableVisualEffectView: NSVisualEffectView {
    var onMouseEntered: (() -> Void)?
    private var tracking: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

final class CompactUsageViewController: NSViewController {
    private let fetcher = UsageFetcher()
    private let titleLabel = NSTextField(labelWithString: "Codex")
    private let primaryLabel = NSTextField(labelWithString: "5h --%")
    private let secondaryLabel = NSTextField(labelWithString: "1w --%")
    private let resetLabel = NSTextField(labelWithString: "--:--")
    private let creditLabel = NSTextField(labelWithString: "credit 0")
    private let refreshLabel = NSTextField(labelWithString: "↻")
    private var isRefreshing = false
    var onSnapshot: ((UsageSnapshot) -> Void)?
    var onFailure: ((Error) -> Void)?

    override func loadView() {
        let visual = DraggableVisualEffectView(frame: NSRect(x: 0, y: 0, width: 330, height: 28))
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 9
        visual.layer?.masksToBounds = true
        visual.layer?.borderWidth = 0.6
        visual.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        visual.onMouseEntered = { [weak self] in
            self?.refresh()
        }
        view = visual
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    private func buildUI() {
        [titleLabel, primaryLabel, secondaryLabel, resetLabel, creditLabel, refreshLabel].forEach {
            $0.textColor = .labelColor
            $0.lineBreakMode = .byTruncatingTail
            $0.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        titleLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        creditLabel.font = .systemFont(ofSize: 9.5, weight: .regular)
        creditLabel.textColor = .white
        primaryLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        secondaryLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        resetLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        resetLabel.textColor = .white
        refreshLabel.font = .systemFont(ofSize: 11, weight: .medium)
        refreshLabel.textColor = .white

        let dot1 = separator()
        let dot2 = separator()
        let dot3 = separator()
        let dot4 = separator()

        let stack = NSStackView(views: [
            titleLabel,
            creditLabel,
            dot1,
            primaryLabel,
            dot2,
            secondaryLabel,
            dot3,
            resetLabel,
            dot4,
            refreshLabel
        ])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func separator() -> NSTextField {
        let label = NSTextField(labelWithString: "·")
        label.font = .systemFont(ofSize: 10, weight: .regular)
        label.textColor = .white
        return label
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshLabel.stringValue = "…"

        fetcher.fetch { [weak self] result in
            guard let self else { return }
            self.isRefreshing = false
            self.refreshLabel.stringValue = "↻"
            switch result {
            case .success(let snapshot):
                self.apply(snapshot)
                self.onSnapshot?(snapshot)
            case .failure(let error):
                NSLog("Codex Usage Float refresh failed: \(error.localizedDescription)")
                self.primaryLabel.stringValue = "unavailable"
                self.secondaryLabel.stringValue = ""
                self.resetLabel.stringValue = ""
                self.onFailure?(error)
            }
        }
    }

    private func apply(_ snapshot: UsageSnapshot) {
        titleLabel.stringValue = snapshot.planType.capitalized
        creditLabel.stringValue = "credit \(snapshot.credits)"
        primaryLabel.stringValue = formatted(snapshot.primary)
        secondaryLabel.stringValue = formatted(snapshot.secondary)
        resetLabel.stringValue = UsageRow.formatResetForCompact(snapshot.primary?.resetAt)

        let remaining = snapshot.primary?.remainingPercent ?? 100
        primaryLabel.textColor = color(for: remaining)
    }

    private func formatted(_ window: UsageWindow?) -> String {
        guard let window else { return "-- --%" }
        return "\(window.label) \(Int(round(window.remainingPercent)))%"
    }

    private func color(for remaining: Double) -> NSColor {
        return .white
    }
}

final class UsageViewController: NSViewController {
    private let fetcher = UsageFetcher()
    private let titleLabel = NSTextField(labelWithString: "Codex")
    private let subtitleLabel = NSTextField(labelWithString: "Loading")
    private let primaryRow = UsageRow()
    private let secondaryRow = UsageRow()
    private var actionButtons: [NSButton] = []
    private var isRefreshing = false
    var onSnapshot: ((UsageSnapshot) -> Void)?
    var onFailure: ((Error) -> Void)?
    var onRestart: (() -> Void)?
    var onQuit: (() -> Void)?

    override func loadView() {
        view = NSVisualEffectView()
        view.frame = NSRect(x: 0, y: 0, width: 226, height: 172)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    private func buildUI() {
        guard let visual = view as? NSVisualEffectView else { return }
        visual.material = .popover
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 12
        visual.layer?.masksToBounds = true

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        subtitleLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        titleLabel.alignment = .center
        subtitleLabel.alignment = .center

        let titleStack = NSStackView(views: [titleLabel, subtitleLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .centerX
        titleStack.spacing = 2

        let header = NSStackView(views: [titleStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 4
        titleStack.setHuggingPriority(.defaultLow, for: .horizontal)

        let actions = NSStackView(views: [
            iconButton(symbol: "arrow.clockwise", tooltip: "刷新", action: #selector(refreshTapped)),
            iconButton(symbol: "arrow.triangle.2.circlepath", tooltip: "重启", action: #selector(restartTapped)),
            iconButton(symbol: "xmark", tooltip: "退出", action: #selector(quitTapped))
        ])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 12

        let stack = NSStackView(views: [header, primaryRow, secondaryRow, actions])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 11
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -10),
            primaryRow.widthAnchor.constraint(equalToConstant: 180),
            secondaryRow.widthAnchor.constraint(equalToConstant: 180)
        ])
        applyAppearance()
    }

    private func iconButton(symbol: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage(), target: self, action: action)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
        actionButtons.append(button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 22),
            button.heightAnchor.constraint(equalToConstant: 22)
        ])
        return button
    }

    @objc private func refreshTapped() {
        refresh()
    }

    @objc private func restartTapped() {
        onRestart?()
    }

    @objc private func quitTapped() {
        onQuit?()
    }

    func applyAppearance() {
        let color = AppearancePalette.foreground
        titleLabel.textColor = color
        subtitleLabel.textColor = color
        primaryRow.applyAppearance()
        secondaryRow.applyAppearance()
        actionButtons.forEach { $0.contentTintColor = color }
        view.needsDisplay = true
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        subtitleLabel.stringValue = "Refreshing"

        fetcher.fetch { [weak self] result in
            guard let self else { return }
            self.isRefreshing = false
            switch result {
            case .success(let snapshot):
                self.primaryRow.update(with: snapshot.primary)
                self.secondaryRow.update(with: snapshot.secondary)
                self.secondaryRow.isHidden = snapshot.secondary == nil
                self.subtitleLabel.stringValue = "\(snapshot.planType) · \(snapshot.credits)"
                self.onSnapshot?(snapshot)
            case .failure(let error):
                NSLog("Codex Usage Float refresh failed: \(error.localizedDescription)")
                self.subtitleLabel.stringValue = "Unavailable"
                self.onFailure?(error)
            }
        }
    }
}

final class StatusHoverView: NSControl {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    private let imageView = NSImageView()
    private let textLabel = NSTextField(labelWithString: "Codex")
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true

        imageView.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: "Codex usage")
        imageView.contentTintColor = .labelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false

        textLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)
        addSubview(textLabel)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 15),
            imageView.heightAnchor.constraint(equalToConstant: 15),
            textLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 3),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }

    func updateTitle(_ title: String, warning: Bool) {
        textLabel.stringValue = title
        imageView.contentTintColor = warning ? .systemOrange : .labelColor
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: 62)
    private let popover = NSPopover()
    private let controller = UsageViewController()
    private var statusTitle = "--%"
    private var statusRemaining: Double?
    private var closeTimer: Timer?
    private var refreshTimer: Timer?
    private var trackingArea: NSTrackingArea?
    private lazy var statusMenu: NSMenu = {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "刷新", action: #selector(refreshFromMenu), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "重启", action: #selector(restartFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitFromMenu), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        return menu
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        buildStatusItem()
        buildPopover()

        controller.onSnapshot = { [weak self] snapshot in
            self?.updateStatusTitle(with: snapshot)
        }
        controller.onFailure = { [weak self] _ in
            self?.updateStatusButton(title: "--%", warning: true)
        }
        controller.onRestart = { [weak self] in
            self?.restartApp()
        }
        controller.onQuit = {
            NSApp.terminate(nil)
        }

        updateStatusButton(title: "--%", warning: false)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
        controller.refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.controller.refresh()
        }
    }

    private func buildStatusItem() {
        statusItem.length = 42

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            button.image = makeCapsuleBadge(title: "--%")
            button.toolTip = "Codex usage: hover to refresh and view details"
            button.target = self
            button.action = #selector(statusButtonPressed)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            button.addTrackingArea(area)
            trackingArea = area
        }
    }

    private func buildPopover() {
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true
    }

    private func showAndRefresh() {
        closeTimer?.invalidate()
        closeTimer = nil

        if let button = statusItem.button, !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }

        controller.refresh()
    }

    @objc private func statusButtonPressed() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            showAndRefresh()
        }
    }

    private func showMenu() {
        closeTimer?.invalidate()
        closeTimer = nil
        popover.performClose(nil)

        guard let button = statusItem.button else { return }
        statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
    }

    @objc private func refreshFromMenu() {
        showAndRefresh()
    }

    @objc private func restartFromMenu() {
        restartApp()
    }

    private func restartApp() {
        let appPath = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.3; open \"\(appPath)\""]
        try? process.run()
        NSApp.terminate(nil)
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    @objc func mouseEntered(with event: NSEvent) {
        showAndRefresh()
    }

    @objc func mouseExited(with event: NSEvent) {
        scheduleClose()
    }

    private func scheduleClose() {
        closeTimer?.invalidate()
        closeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    private func updateStatusTitle(with snapshot: UsageSnapshot) {
        let remaining = snapshot.primary?.remainingPercent ?? snapshot.secondary?.remainingPercent
        if let remaining {
            updateStatusButton(title: "\(Int(round(remaining)))%", remaining: remaining)
        } else {
            updateStatusButton(title: "--%", remaining: nil)
        }
    }

    private func updateStatusButton(title: String, warning: Bool) {
        updateStatusButton(title: title, remaining: statusRemaining)
    }

    private func updateStatusButton(title: String, remaining: Double?) {
        statusTitle = title
        statusRemaining = remaining
        let image = makeCapsuleBadge(title: title)
        statusItem.length = image.size.width + 6
        statusItem.button?.image = image
        statusItem.button?.title = ""
        statusItem.button?.attributedTitle = NSAttributedString(string: "")
    }

    @objc private func appearanceChanged() {
        controller.applyAppearance()
        updateStatusButton(title: statusTitle, remaining: statusRemaining)
    }

    private func makeCapsuleBadge(title: String) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let textSize = (title as NSString).size(withAttributes: attributes)
        let width = max(31, ceil(textSize.width + 10))
        let size = NSSize(width: width, height: 15)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let outlineRect = NSRect(x: 0.9, y: 1.2, width: size.width - 1.8, height: size.height - 2.4)
        let outline = NSBezierPath(roundedRect: outlineRect, xRadius: 4.2, yRadius: 4.2)
        outline.lineWidth = 1.25
        outline.stroke()

        let textPoint = NSPoint(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2 - 0.4
        )
        (title as NSString).draw(at: textPoint, withAttributes: attributes)

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
