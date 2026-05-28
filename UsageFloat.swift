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

final class UsageFetcher {
    private let codexPath = "/Applications/Codex.app/Contents/Resources/codex"

    func fetch(completion: @escaping (Result<UsageSnapshot, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let initRequest = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-usage-float","title":"Codex Usage Float","version":"0.2.0"},"capabilities":{"experimentalApi":true,"requestAttestation":false}}}"#
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

        do {
            return try runCodex(arguments: ["app-server", "--listen", "stdio://"], input: input, timeout: 8)
        } catch {
            errors.append("stdio: \(error.localizedDescription)")
        }

        throw NSError(
            domain: "UsageFetcher",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: errors.joined(separator: "\n")]
        )
    }

    private func runCodex(arguments: [String], input: String?, timeout: TimeInterval) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
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
    private let progress = ProgressBarView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        percentLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        resetLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        resetLabel.textColor = .secondaryLabelColor

        let top = NSStackView(views: [nameLabel, percentLabel, resetLabel])
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = 5
        top.setHuggingPriority(.defaultLow, for: .horizontal)
        percentLabel.setContentHuggingPriority(.required, for: .horizontal)
        resetLabel.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [top, progress])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            progress.heightAnchor.constraint(equalToConstant: 4)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(with window: UsageWindow?) {
        guard let window else {
            nameLabel.stringValue = "-"
            percentLabel.stringValue = "--%"
            resetLabel.stringValue = "--:--"
            progress.value = 0
            return
        }

        nameLabel.stringValue = window.label
        percentLabel.stringValue = "\(Int(round(window.remainingPercent)))%"
        resetLabel.stringValue = Self.formatReset(window.resetAt)
        progress.value = window.remainingPercent / 100
        progress.tint = tint(for: window.remainingPercent)
    }

    private func tint(for remaining: Double) -> NSColor {
        if remaining <= 15 { return NSColor.systemRed }
        if remaining <= 30 { return NSColor.systemOrange }
        return NSColor.controlAccentColor
    }

    private static func formatReset(_ date: Date?) -> String {
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
        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        let width = max(bounds.height, bounds.width * value)
        let fillRect = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        tint.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
    }
}

final class UsageViewController: NSViewController {
    private let fetcher = UsageFetcher()
    private let titleLabel = NSTextField(labelWithString: "Codex")
    private let subtitleLabel = NSTextField(labelWithString: "Loading")
    private let primaryRow = UsageRow()
    private let secondaryRow = UsageRow()
    private let refreshButton = NSButton()
    private let closeButton = NSButton()
    private var timer: Timer?
    private var isRefreshing = false

    override func loadView() {
        view = NSVisualEffectView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func buildUI() {
        guard let visual = view as? NSVisualEffectView else { return }
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 18
        visual.layer?.masksToBounds = true

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        subtitleLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor

        configureIconButton(refreshButton, symbol: "arrow.clockwise", action: #selector(refreshTapped))
        configureIconButton(closeButton, symbol: "xmark", action: #selector(closeTapped))

        let titleStack = NSStackView(views: [titleLabel, subtitleLabel])
        titleStack.orientation = .vertical
        titleStack.spacing = 2

        let header = NSStackView(views: [titleStack, refreshButton, closeButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 4
        titleStack.setHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [header, primaryRow, secondaryRow])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -10),
            refreshButton.widthAnchor.constraint(equalToConstant: 18),
            refreshButton.heightAnchor.constraint(equalToConstant: 18),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18)
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(refreshTapped))
        view.addGestureRecognizer(click)
    }

    private func configureIconButton(_ button: NSButton, symbol: String, action: Selector) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.contentTintColor = .secondaryLabelColor
    }

    @objc private func refreshTapped() {
        refresh()
    }

    @objc private func closeTapped() {
        NSApp.terminate(nil)
    }

    private func refresh() {
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
                self.subtitleLabel.stringValue = "\(snapshot.planType) · \(snapshot.credits)"
            case .failure(let error):
                NSLog("Codex Usage Float refresh failed: \(error.localizedDescription)")
                self.subtitleLabel.stringValue = "Unavailable"
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = UsageViewController()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 122, height: 190),
            styleMask: [.titled, .fullSizeContentView, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = controller
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.minSize = NSSize(width: 108, height: 160)
        panel.maxSize = NSSize(width: 180, height: 240)
        panel.setFrameAutosaveName("CodexUsageFloatFrame")
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        position(panel: panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func position(panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = visible.maxX - panel.frame.width - 24
        let y = visible.maxY - panel.frame.height - 24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
