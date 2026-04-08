import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, PopoverViewDelegate, NSPopoverDelegate {
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
    private var refreshRetryCount = 0
    private static let maxRefreshRetries = 2
    private var showTimeRemaining = false
    private var alternateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        updateStatusBar()
        fetchStatusFeed()
        startStatusPolling()
        startAlternating()
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
        popover.delegate = self

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
            if showTimeRemaining, let reset = info.fiveHour.resetsAt {
                statusView.label = "RESET"
                statusView.value = formatTimeRemaining(until: reset)
            } else {
                statusView.label = "SESSION"
                statusView.value = String(format: "%.0f%%", pct)
            }
            statusView.valueColor = .labelColor
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

    private func startAlternating() {
        alternateTimer?.invalidate()
        alternateTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            guard let self = self, self.usageInfo != nil else { return }
            self.showTimeRemaining.toggle()
            self.updateStatusBar()
        }
    }

    private func formatTimeRemaining(until date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        if remaining <= 0 { return "0m" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 { return "\(hours)h\(String(format: "%02d", minutes))" }
        return "\(minutes)m"
    }

    private func refresh() {
        guard config.isConnected else { return }

        // Proactively refresh token if expiring soon
        if config.isTokenExpiringSoon && !config.refreshToken.isEmpty {
            refreshTokenAndRetry()
            return
        }

        apiClient.fetchUsage(token: config.accessToken) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let info):
                    self.usageInfo = info
                    self.lastUpdated = Date()
                    self.lastError = nil
                    self.refreshRetryCount = 0
                case .failure(let error):
                    let canRetry = self.refreshRetryCount < AppDelegate.maxRefreshRetries
                        && !Config.shared.refreshToken.isEmpty
                    if case APIError.unauthorized = error, canRetry {
                        self.refreshTokenAndRetry()
                        return
                    }
                    if case APIError.rateLimited = error, canRetry {
                        self.refreshTokenAndRetry()
                        return
                    }
                    self.lastError = error.localizedDescription
                    self.refreshRetryCount = 0
                }
                self.updateStatusBar()
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
        refreshRetryCount += 1
        OAuthClient.refreshAccessToken(config.refreshToken) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let tokens):
                    Config.shared.saveTokens(tokens)
                    self?.refresh()
                case .failure:
                    self?.refreshRetryCount = 0
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

    func popoverDidRequestUpdate() {
        checkForUpdate()
    }

    // MARK: - Auto-update

    private static let currentVersion = "1.4.0"
    private static let releasesAPI = "https://api.github.com/repos/etroadec/claude-monitor/releases/latest"

    private func checkForUpdate() {
        guard let url = URL(string: AppDelegate.releasesAPI) else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                DispatchQueue.main.async {
                    self.showAlert("Impossible de vérifier les mises à jour.")
                }
                return
            }

            let remoteVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            let isNew = remoteVersion.compare(AppDelegate.currentVersion, options: .numeric) == .orderedDescending

            guard isNew else {
                DispatchQueue.main.async {
                    self.showAlert("Vous êtes à jour (v\(AppDelegate.currentVersion)).")
                }
                return
            }

            // Find the .zip asset download URL
            guard let assets = json["assets"] as? [[String: Any]],
                  let zipAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
                  let downloadURL = zipAsset["browser_download_url"] as? String else {
                DispatchQueue.main.async {
                    self.showAlert("Mise à jour v\(remoteVersion) disponible mais pas de téléchargement trouvé.")
                }
                return
            }

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Mise à jour v\(remoteVersion)"
                alert.informativeText = "Installer automatiquement ? L'app va redémarrer."
                alert.addButton(withTitle: "Installer")
                alert.addButton(withTitle: "Plus tard")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn {
                    self.downloadAndInstall(urlString: downloadURL)
                }
            }
        }.resume()
    }

    private func downloadAndInstall(urlString: String) {
        guard let url = URL(string: urlString) else { return }

        let task = URLSession.shared.downloadTask(with: url) { tmpFile, _, error in
            guard let tmpFile = tmpFile, error == nil else {
                DispatchQueue.main.async { self.showAlert("Échec du téléchargement.") }
                return
            }

            do {
                let fm = FileManager.default
                let tmpDir = fm.temporaryDirectory.appendingPathComponent("claude-monitor-update")
                try? fm.removeItem(at: tmpDir)
                try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)

                // Unzip
                let zipPath = tmpDir.appendingPathComponent("update.zip")
                try fm.moveItem(at: tmpFile, to: zipPath)

                let unzipProcess = Process()
                unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzipProcess.arguments = ["-xk", zipPath.path, tmpDir.path]
                try unzipProcess.run()
                unzipProcess.waitUntilExit()

                // Find the .app in the unzipped contents
                let contents = try fm.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil)
                guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
                    DispatchQueue.main.async { self.showAlert("Mise à jour invalide.") }
                    return
                }

                // Replace current app
                let currentApp = Bundle.main.bundleURL
                let backupURL = currentApp.deletingLastPathComponent().appendingPathComponent("ClaudeMonitor.app.bak")
                try? fm.removeItem(at: backupURL)
                try fm.moveItem(at: currentApp, to: backupURL)
                try fm.copyItem(at: newApp, to: currentApp)
                try? fm.removeItem(at: backupURL)
                try? fm.removeItem(at: tmpDir)

                // Relaunch
                DispatchQueue.main.async {
                    let relaunchProcess = Process()
                    relaunchProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    relaunchProcess.arguments = ["-n", currentApp.path]
                    try? relaunchProcess.run()
                    NSApp.terminate(nil)
                }
            } catch {
                DispatchQueue.main.async { self.showAlert("Erreur: \(error.localizedDescription)") }
            }
        }
        task.resume()
    }

    private func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Claude Monitor"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
