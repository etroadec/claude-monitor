import Cocoa

protocol PopoverViewDelegate: AnyObject {
    func popoverDidRequestRefresh()
    func popoverDidRequestDisconnect()
    func popoverDidRequestConnect()
    func popoverDidRequestQuit()
    func popoverDidOpenIncident(link: String)
    func popoverDidRequestUpdate()
}

class PopoverView: NSView {
    weak var delegate: PopoverViewDelegate?

    private var selectedTab = 0 // 0 = Usage, 1 = Notifications
    private let tabUsage = TabButton(title: "Utilisation")
    private let tabNotif = TabButton(title: "Notifications")
    private let contentContainer = NSView()
    private var usageView: UsageTabView!
    private var notifView: NotifTabView!
    private let bottomBar = NSView()
    private let refreshBtn = LinkButton(title: "Rafraîchir")
    private let updateBtn = LinkButton(title: "Mise à jour")
    private let disconnectBtn = LinkButton(title: "Déconnecter")
    private let connectBtn = LinkButton(title: "Connecter mon compte Claude")
    private let quitBtn = LinkButton(title: "Quitter")
    private let badgeDot = NSView()

    var isConnected = false { didSet { layoutAll() } }
    var hasUnread = false { didSet { updateBadge() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true

        // Tabs
        tabUsage.target = self
        tabUsage.action = #selector(tabClicked(_:))
        tabUsage.tag = 0
        tabNotif.target = self
        tabNotif.action = #selector(tabClicked(_:))
        tabNotif.tag = 1
        addSubview(tabUsage)
        addSubview(tabNotif)

        // Badge dot on notification tab
        badgeDot.wantsLayer = true
        badgeDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
        badgeDot.layer?.cornerRadius = 3
        badgeDot.isHidden = true
        addSubview(badgeDot)

        // Content
        contentContainer.wantsLayer = true
        addSubview(contentContainer)

        usageView = UsageTabView(frame: .zero)
        notifView = NotifTabView(frame: .zero)
        notifView.onIncidentClick = { [weak self] link in
            self?.delegate?.popoverDidOpenIncident(link: link)
        }
        contentContainer.addSubview(usageView)
        contentContainer.addSubview(notifView)

        // Bottom
        addSubview(bottomBar)

        refreshBtn.target = self
        refreshBtn.action = #selector(refreshClicked)
        updateBtn.target = self
        updateBtn.action = #selector(updateClicked)
        disconnectBtn.target = self
        disconnectBtn.action = #selector(disconnectClicked)
        connectBtn.target = self
        connectBtn.action = #selector(connectClicked)
        quitBtn.target = self
        quitBtn.action = #selector(quitClicked)

        bottomBar.addSubview(refreshBtn)
        bottomBar.addSubview(updateBtn)
        bottomBar.addSubview(disconnectBtn)
        bottomBar.addSubview(connectBtn)
        bottomBar.addSubview(quitBtn)

        selectTab(0)
    }

    func layoutAll() {
        let w = bounds.width
        let topPad: CGFloat = 6
        let tabH: CGFloat = 28
        let bottomH: CGFloat = 24
        let sep: CGFloat = 1

        // Tabs (with top padding)
        let tabY = bounds.height - topPad - tabH
        let tabW = w / 2
        tabUsage.frame = NSRect(x: 0, y: tabY, width: tabW, height: tabH)
        tabNotif.frame = NSRect(x: tabW, y: tabY, width: tabW, height: tabH)
        badgeDot.frame = NSRect(x: tabW + tabNotif.titleSize.width / 2 + tabW / 2 + 4, y: tabY + tabH / 2 + 4, width: 6, height: 6)

        // Content
        let contentY = bottomH + sep
        let contentH = tabY - sep - contentY
        contentContainer.frame = NSRect(x: 0, y: contentY, width: w, height: contentH)
        usageView.frame = contentContainer.bounds
        notifView.frame = contentContainer.bounds

        // Bottom bar
        bottomBar.frame = NSRect(x: 0, y: 0, width: w, height: bottomH)
        layoutBottomBar()

        usageView.layoutAll()
        notifView.layoutAll()

        connectBtn.isHidden = isConnected
        disconnectBtn.isHidden = !isConnected
        refreshBtn.isHidden = !isConnected
    }

    private func layoutBottomBar() {
        let h = bottomBar.bounds.height
        let w = bottomBar.bounds.width
        let y: CGFloat = (h - 16) / 2

        // Evenly space all visible buttons
        let allBtns = [refreshBtn, updateBtn, connectBtn, disconnectBtn, quitBtn].filter { !$0.isHidden }
        for btn in allBtns { btn.sizeToFit() }
        let totalW = allBtns.reduce(CGFloat(0)) { $0 + $1.frame.width }
        let spacing = (w - totalW - 24) / max(CGFloat(allBtns.count - 1), 1)
        var x: CGFloat = 12
        for btn in allBtns {
            btn.frame.origin = NSPoint(x: x, y: y)
            x += btn.frame.width + spacing
        }
    }

    override func layout() {
        super.layout()
        layoutAll()
    }

    private func selectTab(_ index: Int) {
        selectedTab = index
        tabUsage.isSelected = index == 0
        tabNotif.isSelected = index == 1
        usageView.isHidden = index != 0
        notifView.isHidden = index != 1
    }

    private func updateBadge() {
        badgeDot.isHidden = !hasUnread
    }

    func updateUsage(_ info: UsageInfo?, lastUpdated: Date?, error: String?) {
        usageView.update(info, lastUpdated: lastUpdated, error: error)
    }

    func updateIncidents(_ incidents: [StatusIncident]) {
        notifView.update(incidents)
    }

    @objc private func tabClicked(_ sender: TabButton) {
        selectTab(sender.tag)
    }
    @objc private func refreshClicked() { delegate?.popoverDidRequestRefresh() }
    @objc private func updateClicked() { delegate?.popoverDidRequestUpdate() }
    @objc private func disconnectClicked() { delegate?.popoverDidRequestDisconnect() }
    @objc private func connectClicked() { delegate?.popoverDidRequestConnect() }
    @objc private func quitClicked() { delegate?.popoverDidRequestQuit() }
}

// MARK: - Tab Button

class TabButton: NSButton {
    var isSelected = false { didSet { needsDisplay = true } }

    var titleSize: NSSize {
        (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)])
    }

    convenience init(title: String) {
        self.init(frame: .zero)
        self.title = title
        self.isBordered = false
        self.bezelStyle = .inline
        self.setButtonType(.momentaryChange)
    }

    override func draw(_ dirtyRect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular),
            .foregroundColor: isSelected ? NSColor.white : NSColor.secondaryLabelColor,
        ]
        let size = (title as NSString).size(withAttributes: attrs)
        let x = (bounds.width - size.width) / 2
        let y = (bounds.height - size.height) / 2
        (title as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)

        if isSelected {
            let barRect = NSRect(x: x, y: 2, width: size.width, height: 2)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: barRect, xRadius: 1, yRadius: 1).fill()
        }
    }
}

// MARK: - Link Button

class LinkButton: NSButton {
    convenience init(title: String) {
        self.init(frame: .zero)
        self.isBordered = false
        self.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - Usage Tab

class UsageTabView: NSView {
    private var labels: [NSTextField] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ info: UsageInfo?, lastUpdated: Date?, error: String?) {
        labels.forEach { $0.removeFromSuperview() }
        labels = []

        guard let info = info else {
            if let err = error {
                addLabel("⚠ \(err)", color: .systemYellow, bold: false, size: 12, y: bounds.height - 40)
            }
            return
        }

        var y = bounds.height - 10
        y = addSection("SESSION", y: y)
        y = addRow("Utilisation", value: String(format: "%.0f%%", info.fiveHour.utilization), y: y)
        if let reset = info.fiveHour.resetsAt {
            y = addRow("Reset dans", value: formatTime(reset), y: y)
        }

        y -= 12
        y = addSection("SEMAINE", y: y)
        y = addRow("Utilisation", value: String(format: "%.0f%%", info.sevenDay.utilization), y: y)
        if let s = info.sevenDaySonnet {
            y = addRow("Sonnet", value: String(format: "%.0f%%", s.utilization), y: y)
        }
        if let o = info.sevenDayOpus {
            y = addRow("Opus", value: String(format: "%.0f%%", o.utilization), y: y)
        }
        if let reset = info.sevenDay.resetsAt {
            y = addRow("Reset dans", value: formatTime(reset), y: y)
        }

        if let extra = info.extraUsage, extra.isEnabled {
            y -= 12
            y = addSection("CRÉDITS EXTRA", y: y)
            y = addRow("Utilisés", value: "\(Int(extra.usedCredits)) / \(extra.monthlyLimit)", y: y)
            y = addRow("Utilisation", value: String(format: "%.0f%%", extra.utilization), y: y)
        }

        if let updated = lastUpdated {
            y -= 12
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm:ss"
            addLabel("Mis à jour: \(fmt.string(from: updated))", color: .tertiaryLabelColor, bold: false, size: 10, y: y - 14)
        }
    }

    func layoutAll() {
        // Re-render on layout change handled by update()
    }

    @discardableResult
    private func addSection(_ title: String, y: CGFloat) -> CGFloat {
        addLabel(title, color: .white, bold: true, size: 11, y: y - 16)
        return y - 22
    }

    @discardableResult
    private func addRow(_ label: String, value: String, y: CGFloat) -> CGFloat {
        let h: CGFloat = 18

        let lbl = NSTextField(labelWithString: label)
        lbl.font = .systemFont(ofSize: 12)
        lbl.textColor = .secondaryLabelColor
        lbl.frame = NSRect(x: 14, y: y - h, width: 140, height: h)
        addSubview(lbl)
        labels.append(lbl)

        let val = NSTextField(labelWithString: value)
        val.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        val.textColor = .white
        val.alignment = .right
        val.frame = NSRect(x: bounds.width - 100 - 14, y: y - h, width: 100, height: h)
        addSubview(val)
        labels.append(val)

        return y - h
    }

    @discardableResult
    private func addLabel(_ text: String, color: NSColor, bold: Bool, size: CGFloat, y: CGFloat) -> CGFloat {
        let lbl = NSTextField(labelWithString: text)
        lbl.font = bold ? .systemFont(ofSize: size, weight: .bold) : .systemFont(ofSize: size)
        lbl.textColor = color
        lbl.frame = NSRect(x: 14, y: y, width: bounds.width - 28, height: 16)
        addSubview(lbl)
        labels.append(lbl)
        return y
    }

    private func formatTime(_ date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        if remaining <= 0 { return "0m" }
        let h = Int(remaining) / 3600
        let m = (Int(remaining) % 3600) / 60
        if h > 0 { return "\(h)h\(String(format: "%02d", m))" }
        return "\(m)m"
    }
}

// MARK: - Notifications Tab

class NotifTabView: NSView {
    private var labels: [NSView] = []
    var onIncidentClick: ((String) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ incidents: [StatusIncident]) {
        labels.forEach { $0.removeFromSuperview() }
        labels = []

        let recent = incidents.filter { $0.isRecent }

        if recent.isEmpty && incidents.isEmpty {
            let lbl = NSTextField(labelWithString: "Aucun incident récent ✓")
            lbl.font = .systemFont(ofSize: 12)
            lbl.textColor = .secondaryLabelColor
            lbl.frame = NSRect(x: 14, y: bounds.height - 40, width: bounds.width - 28, height: 20)
            addSubview(lbl)
            labels.append(lbl)
            return
        }

        let toShow = recent.isEmpty ? Array(incidents.prefix(5)) : Array(recent.prefix(5))
        var y = bounds.height - 10

        if !recent.isEmpty {
            let badge = NSTextField(labelWithString: "\(recent.count) incident\(recent.count > 1 ? "s" : "") actif\(recent.count > 1 ? "s" : "")")
            badge.font = .systemFont(ofSize: 11, weight: .semibold)
            badge.textColor = .systemOrange
            badge.frame = NSRect(x: 14, y: y - 16, width: bounds.width - 28, height: 16)
            addSubview(badge)
            labels.append(badge)
            y -= 26
        }

        for incident in toShow {
            y = addIncidentRow(incident, y: y)
        }
    }

    func layoutAll() {}

    private func addIncidentRow(_ incident: StatusIncident, y: CGFloat) -> CGFloat {
        let fmt = DateFormatter()
        fmt.dateFormat = "dd MMM HH:mm"
        fmt.locale = Locale(identifier: "fr_FR")

        // Date
        let dateLbl = NSTextField(labelWithString: fmt.string(from: incident.date))
        dateLbl.font = .systemFont(ofSize: 10)
        dateLbl.textColor = .tertiaryLabelColor
        dateLbl.frame = NSRect(x: 14, y: y - 14, width: bounds.width - 28, height: 14)
        addSubview(dateLbl)
        labels.append(dateLbl)

        // Title (clickable)
        let titleBtn = NSButton(frame: NSRect(x: 14, y: y - 32, width: bounds.width - 28, height: 18))
        titleBtn.isBordered = false
        titleBtn.alignment = .left
        let titleStr = NSMutableAttributedString(string: incident.title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: incident.isRecent ? NSColor.systemOrange : NSColor.white,
        ])
        titleBtn.attributedTitle = titleStr
        titleBtn.target = self
        titleBtn.action = #selector(incidentClicked(_:))
        titleBtn.tag = labels.count
        titleBtn.toolTip = incident.link
        addSubview(titleBtn)
        labels.append(titleBtn)

        // Description snippet
        if !incident.description.isEmpty {
            let descLbl = NSTextField(wrappingLabelWithString: String(incident.description.prefix(100)))
            descLbl.font = .systemFont(ofSize: 10)
            descLbl.textColor = .secondaryLabelColor
            descLbl.frame = NSRect(x: 14, y: y - 56, width: bounds.width - 28, height: 24)
            descLbl.maximumNumberOfLines = 2
            addSubview(descLbl)
            labels.append(descLbl)
            return y - 66
        }

        return y - 42
    }

    @objc private func incidentClicked(_ sender: NSButton) {
        if let link = sender.toolTip {
            onIncidentClick?(link)
        }
    }
}
