import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, PopoverViewDelegate {
    private var statusItem: NSStatusItem!
    private var statusView: StatusItemView!
    private var popover: NSPopover!
    private var popoverView: PopoverView!
    private var eventMonitor: Any?
    private var timer: Timer?
    private var statusTimer: Timer?
    private let config = Config.shared
    private let apiClient = AnthropicAPIClient()
    private let statusFeed = StatusFeedClient()
    private var oauthClient: OAuthClient?

    private var usageInfo: UsageInfo?
    private var lastUpdated: Date?
    private var lastError: String?
    private var incidents: [StatusIncident] = []
    private var hasUnreadIncidents = false
    private var lastSeenIncidentDate: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        updateStatusBar()
        fetchStatusFeed()
        startStatusPolling()
        if config.isConnected {
            startPolling()
            refresh()
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        let itemWidth: CGFloat = 32
        statusItem = NSStatusBar.system.statusItem(withLength: itemWidth)
        statusView = StatusItemView(frame: NSRect(x: 0, y: 0, width: itemWidth, height: NSStatusBar.system.thickness))
        statusItem.button?.subviews.forEach { $0.removeFromSuperview() }
        statusItem.button?.addSubview(statusView)
        statusView.frame = statusItem.button!.bounds
        statusView.autoresizingMask = [.width, .height]
        statusItem.button?.title = ""
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let vc = NSViewController()
        popoverView = PopoverView(frame: NSRect(x: 0, y: 0, width: 280, height: 360))
        popoverView.delegate = self
        vc.view = popoverView
        popover.contentViewController = vc
        popover.contentSize = NSSize(width: 280, height: 360)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Mark incidents as read
            if hasUnreadIncidents {
                hasUnreadIncidents = false
                if let newest = incidents.filter({ $0.isRecent }).first {
                    lastSeenIncidentDate = newest.date
                }
                statusView.showBadge = false
                statusView.needsDisplay = true
            }

            popoverView.isConnected = config.isConnected
            popoverView.hasUnread = hasUnreadIncidents
            popoverView.updateUsage(usageInfo, lastUpdated: lastUpdated, error: lastError)
            popoverView.updateIncidents(incidents)
            popoverView.layoutAll()

            if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }

            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Status Bar

    private func updateStatusBar() {
        let connected = config.isConnected

        if !connected {
            statusView.label = ""
            statusView.value = "CL"
            statusView.valueColor = .labelColor
        } else if let info = usageInfo {
            let pct = info.fiveHour.utilization
            statusView.label = "SESSION"
            statusView.value = String(format: "%.0f%%", pct)
            if pct >= 80 { statusView.valueColor = .systemRed }
            else if pct >= 50 { statusView.valueColor = .systemOrange }
            else { statusView.valueColor = .labelColor }
        } else if lastError != nil {
            statusView.label = ""
            statusView.value = "CL!"
            statusView.valueColor = .systemYellow
        } else {
            statusView.label = ""
            statusView.value = "CL"
            statusView.valueColor = .labelColor
        }

        statusView.showBadge = hasUnreadIncidents
        statusView.invalidateIntrinsicContentSize()
        statusView.needsDisplay = true

        // Update popover if visible
        if popover.isShown {
            popoverView.isConnected = connected
            popoverView.hasUnread = hasUnreadIncidents
            popoverView.updateUsage(usageInfo, lastUpdated: lastUpdated, error: lastError)
            popoverView.updateIncidents(incidents)
        }
    }

    // MARK: - Polling

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func startStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.fetchStatusFeed()
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        guard config.isConnected else { return }
        apiClient.fetchUsage(token: config.accessToken) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    self?.usageInfo = info
                    self?.lastUpdated = Date()
                    self?.lastError = nil
                case .failure(let error):
                    if case APIError.unauthorized = error, !Config.shared.refreshToken.isEmpty {
                        self?.refreshTokenAndRetry()
                        return
                    }
                    if case APIError.rateLimited = error, !Config.shared.refreshToken.isEmpty {
                        self?.refreshTokenAndRetry()
                        return
                    }
                    self?.lastError = error.localizedDescription
                }
                self?.updateStatusBar()
            }
        }
    }

    private func fetchStatusFeed() {
        statusFeed.fetchIncidents { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .success(let newIncidents) = result {
                    let recentNew = newIncidents.filter { $0.isRecent }
                    if let newest = recentNew.first {
                        if let lastSeen = self.lastSeenIncidentDate {
                            if newest.date > lastSeen {
                                self.hasUnreadIncidents = true
                            }
                        } else if !recentNew.isEmpty {
                            self.lastSeenIncidentDate = newest.date
                        }
                    }
                    self.incidents = newIncidents
                    self.updateStatusBar()
                }
            }
        }
    }

    private func refreshTokenAndRetry() {
        OAuthClient.refreshAccessToken(config.refreshToken) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let tokens):
                    Config.shared.saveTokens(tokens)
                    self?.refresh()
                case .failure:
                    self?.lastError = "Session expirée — reconnectez-vous"
                    self?.updateStatusBar()
                }
            }
        }
    }

    // MARK: - PopoverViewDelegate

    func popoverDidRequestRefresh() {
        refresh()
        fetchStatusFeed()
    }

    func popoverDidRequestDisconnect() {
        popover.performClose(nil)
        config.disconnect()
        usageInfo = nil
        lastUpdated = nil
        lastError = nil
        stopPolling()
        updateStatusBar()
    }

    func popoverDidRequestConnect() {
        oauthClient = OAuthClient()
        oauthClient?.authorize { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let tokens):
                    Config.shared.saveTokens(tokens)
                    self?.lastError = nil
                    self?.updateStatusBar()
                    self?.startPolling()
                    self?.refresh()
                case .failure(let error):
                    let alert = NSAlert()
                    alert.messageText = "Connexion échouée"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                }
                self?.oauthClient = nil
            }
        }
    }

    func popoverDidRequestQuit() {
        NSApp.terminate(nil)
    }

    func popoverDidOpenIncident(link: String) {
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }
}
