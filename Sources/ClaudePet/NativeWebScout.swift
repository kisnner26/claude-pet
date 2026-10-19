import ApplicationServices
import AppKit
import SwiftUI

enum WebScoutAgent: String, CaseIterable {
    case claude
    case codex
}

enum WebScoutTone: Equatable {
    case info
    case warning
    case error
}

struct WebScoutAuditInput: Equatable {
    let role: String
    let title: String
    let description: String
    let help: String
    let frame: CGRect
}

struct WebScoutFinding: Equatable {
    let label: String
    let tone: WebScoutTone
}

enum WebScoutAudit {
    static let controls: Set<String> = [
        kAXButtonRole as String, kAXCheckBoxRole as String, kAXComboBoxRole as String,
        "AXLink", kAXPopUpButtonRole as String, kAXRadioButtonRole as String,
        kAXSliderRole as String, kAXTextFieldRole as String
    ]

    static func finding(for item: WebScoutAuditInput) -> WebScoutFinding? {
        let named = !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !item.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !item.help.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if controls.contains(item.role), !named {
            return WebScoutFinding(label: "control sin nombre accesible", tone: .error)
        }
        if item.role == kAXImageRole as String, !named {
            return WebScoutFinding(label: "imagen sin descripción accesible", tone: .error)
        }
        if controls.contains(item.role), (item.frame.width < 44 || item.frame.height < 44) {
            return WebScoutFinding(label: "objetivo interactivo menor de 44 pt", tone: .warning)
        }
        return nil
    }
}

private struct TrackedFinding {
    let element: AXUIElement
    let finding: WebScoutFinding
}

private struct TrackedLink {
    let element: AXUIElement
    let record: CrawledLink
}

private struct ScoutMark: Identifiable {
    let id: Int
    let rect: CGRect
    let tone: WebScoutTone
    let active: Bool
}

private struct ScoutScene {
    let agent: WebScoutAgent
    let marks: [ScoutMark]
    let label: String
}

@MainActor
final class NativeWebScoutController: ObservableObject {
    @Published var agent: WebScoutAgent = .claude
    @Published private(set) var status = "listo para señalar"
    @Published private(set) var issueCount = 0
    @Published private(set) var issueIndex = 0
    @Published private(set) var isCrawling = false
    @Published private(set) var hasReport = false
    /// Opt-in: contactar los destinos (HEAD/GET sin cookies) para detectar enlaces rotos.
    @Published var verifyLinks: Bool = UserDefaults.standard.bool(forKey: "claudwler.verify") {
        didSet { UserDefaults.standard.set(verifyLinks, forKey: "claudwler.verify") }
    }

    private var panel: NSPanel?
    private var findings: [TrackedFinding] = []
    private var selectedElement: AXUIElement?
    private var selectedRange: AXValue?
    private var trackingTask: Task<Void, Never>?
    private var lastExternalPID: pid_t?
    private var activationObserver: NSObjectProtocol?
    private var crawlerLinks: [TrackedLink] = []
    private var crawlerVisited = Set<Int>()
    private var crawlerIndex = 0
    private var crawlerPage = 0
    private var crawlerTask: Task<Void, Never>?
    private var crawlerRecords: [CrawledLink] = []
    private var crawlerSeen = Set<CrawledLink>()
    private var lastReport = ""
    private var lastReportURL: URL?
    private var crawlerChecks: [String: LinkCheck] = [:]
    private var pendingChecks: [String: Task<LinkCheck, Never>] = [:]
    private var crawlerURLTexts: [String: Set<String>] = [:]
    private var finishTask: Task<Void, Never>?
    private var visitedRecords = Set<CrawledLink>()

    var hasFindings: Bool { issueCount > 0 || isCrawling }
    var canNavigate: Bool { issueCount > 1 }

    init() {
        remember(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in self?.remember(app) }
        }
    }

    func requestAccess() {
        guard !Self.isTrusted(prompt: true) else {
            status = "accesibilidad autorizada"
            return
        }
        status = "autoriza claude pet en privacidad y seguridad"
    }

    func markSelection() {
        guard ensureAccess() else { return }
        guard let selection = WebScoutAX.selection(applicationPID: targetPID) else {
            status = "selecciona texto en el navegador y vuelve a intentarlo"
            clearOverlayOnly()
            return
        }
        findings = []
        issueCount = 1
        issueIndex = 0
        selectedElement = selection.element
        selectedRange = selection.range
        status = "selección marcada"
        refreshSelection()
        startTracking()
    }

    func auditVisibleControls() {
        guard ensureAccess() else { return }
        selectedElement = nil
        selectedRange = nil
        findings = WebScoutAX.visibleFindings(applicationPID: targetPID).prefix(24).map { $0 }
        issueCount = findings.count
        issueIndex = 0
        if findings.isEmpty {
            status = "sin problemas básicos en la interfaz visible"
            showMessage(status)
        } else {
            status = "\(findings.count) problemas; mostrando 1"
            refreshAudit()
            startTracking()
        }
    }

    func startCrawler() {
        guard ensureAccess() else { return }
        resetCurrentMode()
        crawlerPage = 1
        finishTask?.cancel()
        crawlerRecords = []
        crawlerSeen = []
        crawlerChecks = [:]
        pendingChecks.values.forEach { $0.cancel() }
        pendingChecks = [:]
        crawlerURLTexts = [:]
        visitedRecords = []
        crawlerLinks = track(WebScoutAX.visibleLinks(applicationPID: targetPID))
        guard !crawlerLinks.isEmpty else {
            status = "no encontré enlaces visibles"
            showMessage(status)
            return
        }
        isCrawling = true
        crawlerIndex = 0
        crawlerVisited = [0]
        status = "claudwler · página 1"
        refreshCrawler()
        startCrawlerLoop()
    }

    func copyReport() {
        guard hasReport else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastReport, forType: .string)
        status = "informe de claudwler copiado"
    }

    func openReport() {
        guard let lastReportURL else { return }
        NSWorkspace.shared.open(lastReportURL)
    }

    private func track(_ elements: [AXUIElement]) -> [TrackedLink] {
        elements.map { element in
            let link = WebScoutAX.crawledLink(element)
            if crawlerSeen.insert(link).inserted {
                crawlerRecords.append(link)
                if !link.url.isEmpty { crawlerURLTexts[link.url, default: []].insert(link.text) }
                enqueueCheck(link.url)
            }
            return TrackedLink(element: element, record: link)
        }
    }

    private func enqueueCheck(_ url: String) {
        guard verifyLinks, !url.isEmpty, pendingChecks[url] == nil, LinkChecker.isCheckable(url) else { return }
        let task = Task { await LinkChecker.check(url) }
        pendingChecks[url] = task
        Task { [weak self] in
            let result = await task.value
            guard !task.isCancelled else { return }
            self?.crawlerChecks[url] = result
        }
    }

    private func tone(for link: CrawledLink) -> (CrawlerTone, String?) {
        if let check = crawlerChecks[link.url], check.state == .broken { return (.broken, check.note) }
        let issues = WebCrawlerReport.problems(for: link, urlTexts: crawlerURLTexts)
        if let first = issues.first { return (.warn, first == "mismo destino con textos distintos" ? "duplicado" : String(first.prefix(14))) }
        if let check = crawlerChecks[link.url], check.state == .unknown { return (.warn, check.note) }
        return (.ok, nil)
    }

    private func finishCrawl(pages: Int, openWhenDone: Bool) {
        isCrawling = false
        finishTask?.cancel()
        guard !crawlerRecords.isEmpty else { status = "claudwler completo · \(pages) páginas"; return }
        let records = crawlerRecords
        let urlTexts = crawlerURLTexts
        let verified = verifyLinks
        let pending = pendingChecks
        status = verified ? "claudwler · verificando enlaces…" : "claudwler · armando informe…"
        finishTask = Task { [weak self] in
            // Espera las verificaciones en curso, con tope de tiempo.
            if verified {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { for task in pending.values { _ = await task.value } }
                    group.addTask { try? await Task.sleep(for: .seconds(20)) }
                    _ = await group.next()
                    group.cancelAll()
                }
            }
            guard !Task.isCancelled, let self else { return }
            let checks = self.crawlerChecks
            let site = Self.site(for: records)
            let root = await Task.detached { Self.projectRoot(for: records) }.value
            var entries: [ReportEntry] = []
            for link in records {
                var problems = WebCrawlerReport.problems(for: link, urlTexts: urlTexts)
                let check = checks[link.url]
                if let check, check.state != .ok { problems.insert(check.state == .broken ? "roto · \(check.note)" : "sin confirmar · \(check.note)", at: 0) }
                entries.append(ReportEntry(link: link, problems: problems, check: check, hints: []))
            }
            if let root {
                self.status = "claudwler · buscando en el código…"
                let targets = entries.filter { !$0.problems.isEmpty }.prefix(30).map { ($0.key, Self.searchTerms(for: $0)) }
                let found = await Task.detached { () -> [String: [String]] in
                    var out: [String: [String]] = [:]
                    for (key, terms) in targets {
                        for term in terms {
                            let hits = SourceLocator.hints(for: term, in: root)
                            if !hits.isEmpty { out[key] = hits; break }
                        }
                    }
                    return out
                }.value
                entries = entries.map { ReportEntry(link: $0.link, problems: $0.problems, check: $0.check, hints: found[$0.key] ?? []) }
            }
            guard !Task.isCancelled else { return }
            let snapshot = CrawlSnapshot(date: .now, entries: entries.map {
                CrawlSnapshot.Entry(key: $0.key, text: $0.link.text, url: $0.link.url, problems: $0.problems)
            })
            let diff = CrawlHistory.load(site: site).map { CrawlHistory.diff(previous: $0, current: snapshot) }
            CrawlHistory.save(snapshot, site: site)
            let report = WebCrawlerReport.build(entries, pages: max(pages, 1), site: site, diff: diff, verified: verified)
            self.lastReport = report.markdown
            self.hasReport = true
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report.markdown, forType: .string)
            try? FileManager.default.createDirectory(at: CrawlHistory.directory, withIntermediateDirectories: true)
            let file = CrawlHistory.directory.appendingPathComponent("informe-\(CrawlHistory.slug(site)).html")
            if (try? report.html.write(to: file, atomically: true, encoding: .utf8)) != nil {
                self.lastReportURL = file
                if openWhenDone { NSWorkspace.shared.open(file) }
            }
            var summary = "claudwler · \(records.count) enlaces · \(report.flagged) con problemas · \(report.broken) rotos"
            if let diff, !diff.isEmpty { summary += " · +\(diff.newLinks.count) nuevos, \(diff.fixed.count) arreglados" }
            self.status = summary + " · informe copiado"
        }
    }

    private nonisolated static func site(for records: [CrawledLink]) -> String {
        let hosts = records.compactMap { link -> String? in
            guard let url = URL(string: link.url), let host = url.host else { return nil }
            return url.port.map { "\(host):\($0)" } ?? host
        }
        return Dictionary(grouping: hosts, by: { $0 }).max { $0.value.count < $1.value.count }?.key ?? "página"
    }

    private nonisolated static func projectRoot(for records: [CrawledLink]) -> URL? {
        let local = records.compactMap { URL(string: $0.url) }.first { WebCrawlerReport.isLocal($0.absoluteString) && $0.port != nil }
        guard let port = local?.port else { return nil }
        return SourceLocator.projectRoot(port: port)
    }

    private nonisolated static func searchTerms(for entry: ReportEntry) -> [String] {
        var terms: [String] = []
        let text = entry.link.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var path: String?
        if let url = URL(string: entry.link.url), WebCrawlerReport.isLocal(entry.link.url), url.path.count > 1 { path = url.path }
        else if !entry.link.url.isEmpty, !WebCrawlerReport.isLocal(entry.link.url) { path = entry.link.url }
        if entry.broken, let path { terms.append(path) }
        if text.count >= 3 { terms.append(text) }
        if !entry.broken, let path { terms.append(path) }
        return terms
    }

    func stopCrawler() {
        let hadRecords = !crawlerRecords.isEmpty
        let pages = crawlerPage
        crawlerTask?.cancel()
        crawlerTask = nil
        crawlerLinks = []
        crawlerVisited = []
        crawlerIndex = 0
        crawlerPage = 0
        isCrawling = false
        clearOverlayOnly()
        if hadRecords { finishCrawl(pages: pages, openWhenDone: false) } else { status = "claudwler detenido" }
    }

    func nextFinding() { navigate(1) }
    func previousFinding() { navigate(-1) }

    func clear() {
        resetCurrentMode()
        status = "marcas eliminadas"
        clearOverlayOnly()
    }

    private func resetCurrentMode() {
        trackingTask?.cancel()
        trackingTask = nil
        crawlerTask?.cancel()
        crawlerTask = nil
        findings = []
        selectedElement = nil
        selectedRange = nil
        crawlerLinks = []
        crawlerVisited = []
        crawlerIndex = 0
        crawlerPage = 0
        issueCount = 0
        issueIndex = 0
        isCrawling = false
    }

    private func navigate(_ offset: Int) {
        guard findings.count > 1 else { return }
        issueIndex = (issueIndex + offset + findings.count) % findings.count
        status = "\(findings.count) problemas; mostrando \(issueIndex + 1)"
        refreshAudit()
    }

    private func ensureAccess() -> Bool {
        guard Self.isTrusted(prompt: false) else {
            requestAccess()
            return false
        }
        return true
    }

    private var targetPID: pid_t? {
        let current = NSWorkspace.shared.frontmostApplication
        if current?.bundleIdentifier != Bundle.main.bundleIdentifier { return current?.processIdentifier }
        return lastExternalPID
    }

    private func remember(_ application: NSRunningApplication?) {
        guard let application, application.bundleIdentifier != Bundle.main.bundleIdentifier,
              application.activationPolicy == .regular else { return }
        lastExternalPID = application.processIdentifier
    }

    private static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    private func startTracking() {
        trackingTask?.cancel()
        trackingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                if self.selectedElement != nil { self.refreshSelection() }
                else if !self.findings.isEmpty { self.refreshAudit() }
            }
        }
    }

    private func startCrawlerLoop() {
        crawlerTask?.cancel()
        crawlerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let wait: Duration = self.reduceMotion ? .milliseconds(950) : .milliseconds(720)
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled, self.isCrawling else { return }
                self.crawlerVisited.insert(self.crawlerIndex)
                if self.crawlerIndex + 1 < self.crawlerLinks.count {
                    self.crawlerIndex += 1
                    self.crawlerVisited.insert(self.crawlerIndex)
                    self.refreshCrawler()
                    continue
                }
                guard self.crawlerPage < 12, WebScoutAX.scrollDown(applicationPID: self.targetPID) else {
                    self.finishCrawl(pages: self.crawlerPage, openWhenDone: true)
                    return
                }
                self.crawlerPage += 1
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                let links = self.track(WebScoutAX.visibleLinks(applicationPID: self.targetPID))
                guard !links.isEmpty else {
                    self.finishCrawl(pages: self.crawlerPage - 1, openWhenDone: true)
                    return
                }
                self.crawlerLinks = links
                self.crawlerIndex = 0
                self.crawlerVisited = [0]
                self.status = "claudwler · página \(self.crawlerPage)"
                self.refreshCrawler()
            }
        }
    }

    private func refreshSelection() {
        guard let selectedElement, let selectedRange,
              let frame = WebScoutAX.bounds(element: selectedElement, range: selectedRange),
              let display = WebScoutDisplay.locate(frame) else { return }
        show(scene: ScoutScene(agent: agent,
                               marks: [ScoutMark(id: 0, rect: display.localRect, tone: .info, active: true)],
                               label: "evidencia seleccionada"), on: display.screen)
    }

    private func refreshAudit() {
        guard findings.indices.contains(issueIndex),
              let activeFrame = WebScoutAX.frame(findings[issueIndex].element),
              let display = WebScoutDisplay.locate(activeFrame) else { return }
        var marks: [ScoutMark] = []
        for (index, tracked) in findings.enumerated() {
            guard let frame = WebScoutAX.frame(tracked.element),
                  let located = WebScoutDisplay.locate(frame), located.screen == display.screen else { continue }
            marks.append(ScoutMark(id: index, rect: located.localRect, tone: tracked.finding.tone, active: index == issueIndex))
        }
        let current = findings[issueIndex].finding
        show(scene: ScoutScene(agent: agent, marks: marks,
                               label: "\(issueIndex + 1)/\(findings.count) · \(current.label)"), on: display.screen)
    }

    private func refreshCrawler() {
        guard crawlerLinks.indices.contains(crawlerIndex),
              let currentFrame = WebScoutAX.frame(crawlerLinks[crawlerIndex].element),
              let display = WebScoutDisplay.locate(currentFrame) else { return }
        visitedRecords.insert(crawlerLinks[crawlerIndex].record)
        var targets: [WebCrawlerTarget] = []
        var points: [CGPoint] = []
        for (index, link) in crawlerLinks.enumerated() {
            guard let frame = WebScoutAX.frame(link.element), let located = WebScoutDisplay.locate(frame),
                  located.screen == display.screen else { continue }
            let visited = crawlerVisited.contains(index)
            let verdict = visited ? tone(for: link.record) : (CrawlerTone.pending, nil)
            targets.append(WebCrawlerTarget(id: index, rect: located.localRect, visited: visited,
                                            current: index == crawlerIndex, tone: verdict.0, badge: verdict.1))
            points.append(CGPoint(x: located.localRect.midX, y: located.localRect.midY))
        }
        guard let current = targets.first(where: { $0.id == crawlerIndex }) else { return }
        let tally = visitedRecords.reduce(into: (ok: 0, warn: 0, broken: 0)) { acc, link in
            switch tone(for: link).0 {
            case .ok: acc.ok += 1
            case .warn: acc.warn += 1
            case .broken: acc.broken += 1
            case .pending: break
            }
        }
        let nextID = min(crawlerIndex + 1, crawlerLinks.count - 1)
        let next = targets.first(where: { $0.id == nextID }) ?? current
        let origin = CGPoint(x: current.rect.midX, y: current.rect.midY)
        let destination = CGPoint(x: next.rect.midX, y: next.rect.midY)
        let contacts = points.sorted { distance($0, origin) < distance($1, origin) }.prefix(8)
        let scene = WebCrawlerScene(agent: agent, targets: targets, from: origin, to: destination,
                                    contacts: Array(contacts), step: crawlerIndex + 1, total: crawlerLinks.count,
                                    startedAt: .now, duration: reduceMotion ? 1 : 0.7, reduceMotion: reduceMotion,
                                    ok: tally.ok, warn: tally.warn, broken: tally.broken, verifying: verifyLinks && pendingChecks.count > crawlerChecks.count)
        showCrawler(scene: scene, on: display.screen)
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || !PetStore.shared.animationsEnabled
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func showMessage(_ message: String) {
        guard let screen = NSScreen.main else { return }
        let mark = ScoutMark(id: 0, rect: CGRect(x: screen.frame.width - 84, y: screen.frame.height - 84, width: 1, height: 1), tone: .info, active: true)
        show(scene: ScoutScene(agent: agent, marks: [mark], label: message), on: screen)
    }

    private func show(scene: ScoutScene, on screen: NSScreen) {
        let panel = panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: NativeWebScoutOverlay(scene: scene))
        if panel.frame != screen.frame { panel.setFrame(screen.frame, display: false) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func showCrawler(scene: WebCrawlerScene, on screen: NSScreen) {
        let panel = panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: WebCrawlerOverlay(scene: scene))
        if panel.frame != screen.frame { panel.setFrame(screen.frame, display: false) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        self.panel = panel
        return panel
    }

    private func clearOverlayOnly() {
        panel?.orderOut(nil)
    }
}

private enum WebScoutAX {
    struct Selection {
        let element: AXUIElement
        let range: AXValue
    }

    static func selection(applicationPID: pid_t?) -> Selection? {
        let system = AXUIElementCreateSystemWide()
        var candidates: [AXUIElement] = []
        if let focused = copyElement(kAXFocusedUIElementAttribute as String, from: system) { candidates.append(focused) }
        if let applicationPID {
            let application = AXUIElementCreateApplication(applicationPID)
            if let focused = copyElement(kAXFocusedUIElementAttribute as String, from: application) { candidates.append(focused) }
        }
        for candidate in candidates {
            var element = candidate
            for _ in 0..<10 {
                if let text = copyString(kAXSelectedTextAttribute as String, from: element), !text.isEmpty,
                   let range = copyAXValue(kAXSelectedTextRangeAttribute as String, from: element) {
                    return Selection(element: element, range: range)
                }
                guard let parent = copyElement(kAXParentAttribute as String, from: element) else { break }
                element = parent
            }
        }
        return nil
    }

    static func visibleFindings(applicationPID: pid_t?) -> [TrackedFinding] {
        guard let application = focusedApplication(fallbackPID: applicationPID),
              let window = copyElement(kAXFocusedWindowAttribute as String, from: application) else { return [] }
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var index = 0
        var output: [TrackedFinding] = []
        while index < queue.count, index < 1600, output.count < 48 {
            let (element, depth) = queue[index]
            index += 1
            if let frame = frame(element), WebScoutDisplay.locate(frame) != nil {
                let input = WebScoutAuditInput(role: copyString(kAXRoleAttribute as String, from: element) ?? "",
                                               title: copyString(kAXTitleAttribute as String, from: element) ?? "",
                                               description: copyString(kAXDescriptionAttribute as String, from: element) ?? "",
                                               help: copyString(kAXHelpAttribute as String, from: element) ?? "",
                                               frame: frame)
                if let finding = WebScoutAudit.finding(for: input) { output.append(TrackedFinding(element: element, finding: finding)) }
            }
            if depth < 14, let children = copyValue(kAXChildrenAttribute as String, from: element) as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(300).map { ($0, depth + 1) })
            }
        }
        return output.sorted { lhs, rhs in
            if lhs.finding.tone == rhs.finding.tone { return false }
            return lhs.finding.tone == .error
        }
    }

    static func crawledLink(_ element: AXUIElement) -> CrawledLink {
        var text = copyString(kAXTitleAttribute as String, from: element) ?? ""
        if text.isEmpty { text = copyString(kAXDescriptionAttribute as String, from: element) ?? "" }
        if text.isEmpty, let children = copyValue(kAXChildrenAttribute as String, from: element) as? [AXUIElement] {
            text = children.prefix(8).compactMap { copyString(kAXValueAttribute as String, from: $0) }.joined(separator: " ")
        }
        let url = (copyValue("AXURL", from: element) as? URL)?.absoluteString ?? ""
        return CrawledLink(text: text.trimmingCharacters(in: .whitespacesAndNewlines), url: url)
    }

    static func visibleLinks(applicationPID: pid_t?) -> [AXUIElement] {
        guard let application = focusedApplication(fallbackPID: applicationPID),
              let window = copyElement(kAXFocusedWindowAttribute as String, from: application) else { return [] }
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var index = 0
        var links: [(AXUIElement, CGRect)] = []
        var frames = Set<String>()
        while index < queue.count, index < 2200, links.count < 80 {
            let (element, depth) = queue[index]
            index += 1
            if copyString(kAXRoleAttribute as String, from: element) == "AXLink",
               let frame = frame(element), WebScoutDisplay.locate(frame) != nil {
                let key = "\(Int(frame.minX)):\(Int(frame.minY)):\(Int(frame.width)):\(Int(frame.height))"
                if frames.insert(key).inserted { links.append((element, frame)) }
            }
            if depth < 16, let children = copyValue(kAXChildrenAttribute as String, from: element) as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(400).map { ($0, depth + 1) })
            }
        }
        return links.sorted {
            abs($0.1.minY - $1.1.minY) < 8 ? $0.1.minX < $1.1.minX : $0.1.minY < $1.1.minY
        }.map(\.0)
    }

    static func scrollDown(applicationPID: pid_t?) -> Bool {
        guard let application = focusedApplication(fallbackPID: applicationPID),
              let window = copyElement(kAXFocusedWindowAttribute as String, from: application) else { return false }
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var index = 0
        var candidates: [(AXUIElement, Double, Double)] = []
        while index < queue.count, index < 1800 {
            let (element, depth) = queue[index]
            index += 1
            if copyString(kAXRoleAttribute as String, from: element) == kAXScrollBarRole as String,
               copyString(kAXOrientationAttribute as String, from: element) == "AXVerticalOrientation",
               let value = copyValue(kAXValueAttribute as String, from: element) as? NSNumber,
               let frame = frame(element), frame.height > 180 {
                candidates.append((element, value.doubleValue, frame.height))
            }
            if depth < 14, let children = copyValue(kAXChildrenAttribute as String, from: element) as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(350).map { ($0, depth + 1) })
            }
        }
        guard let candidate = candidates.filter({ $0.1 < 0.995 }).max(by: { $0.2 < $1.2 }) else { return false }
        let next = min(1, candidate.1 + 0.12)
        return AXUIElementSetAttributeValue(candidate.0, kAXValueAttribute as CFString, NSNumber(value: next)) == .success
    }

    static func bounds(element: AXUIElement, range: AXValue) -> CGRect? {
        var raw: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = unsafeBitCast(raw, to: AXValue.self)
        var rect = CGRect.zero
        return AXValueGetValue(value, .cgRect, &rect) ? rect : nil
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = copyAXValue(kAXPositionAttribute as String, from: element),
              let size = copyAXValue(kAXSizeAttribute as String, from: element) else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions),
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private static func focusedApplication(fallbackPID: pid_t?) -> AXUIElement? {
        if let fallbackPID { return AXUIElementCreateApplication(fallbackPID) }
        let system = AXUIElementCreateSystemWide()
        if let app = copyElement(kAXFocusedApplicationAttribute as String, from: system),
           copyString(kAXRoleAttribute as String, from: app) == kAXApplicationRole as String { return app }
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        return AXUIElementCreateApplication(pid)
    }

    private static func copyValue(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private static func copyString(_ attribute: String, from element: AXUIElement) -> String? {
        copyValue(attribute, from: element) as? String
    }

    private static func copyElement(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        guard let value = copyValue(attribute, from: element), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func copyAXValue(_ attribute: String, from element: AXUIElement) -> AXValue? {
        guard let value = copyValue(attribute, from: element), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXValue.self)
    }
}

private enum WebScoutDisplay {
    struct Location {
        let screen: NSScreen
        let localRect: CGRect
    }

    static func locate(_ accessibilityRect: CGRect) -> Location? {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let display = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            guard display.intersects(accessibilityRect) else { continue }
            return Location(screen: screen,
                            localRect: CGRect(x: accessibilityRect.minX - display.minX,
                                              y: accessibilityRect.minY - display.minY,
                                              width: accessibilityRect.width,
                                              height: accessibilityRect.height))
        }
        return nil
    }
}

private struct NativeWebScoutOverlay: View {
    let scene: ScoutScene

    var body: some View {
        GeometryReader { geometry in
            let active = scene.marks.first(where: \.active)
            let pet = CGPoint(x: geometry.size.width - 48, y: geometry.size.height - 46)
            ZStack(alignment: .topLeading) {
                if let active {
                    Canvas { context, _ in
                        var line = Path()
                        line.move(to: pet)
                        line.addLine(to: CGPoint(x: active.rect.midX, y: active.rect.midY))
                        context.stroke(line, with: .color(scene.agent == .codex ? Color(hex: 0x96EBFF) : Color(hex: 0x7DB4FF)),
                                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                }
                ForEach(scene.marks) { mark in ScoutOutline(mark: mark, agent: scene.agent) }
                if let active {
                    Text(scene.label)
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(Pal.cream)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .frame(maxWidth: 260)
                        .background(Pal.charcoal, in: .rect(cornerRadius: 5))
                        .overlay { RoundedRectangle(cornerRadius: 5).stroke(tint(active.tone).opacity(0.8)) }
                        .position(labelPosition(for: active.rect, in: geometry.size))
                }
                ScoutPet(agent: scene.agent)
                    .frame(width: 64, height: 64)
                    .position(pet)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func tint(_ tone: WebScoutTone) -> Color {
        switch tone {
        case .info: scene.agent == .codex ? Color(hex: 0x96EBFF) : Color(hex: 0x7DB4FF)
        case .warning: Color(hex: 0xE7B45B)
        case .error: Color(hex: 0xFF7B70)
        }
    }

    private func labelPosition(for rect: CGRect, in size: CGSize) -> CGPoint {
        let width = min(270.0, size.width - 16)
        let x = min(max(rect.midX, width / 2 + 8), size.width - width / 2 - 8)
        let below = rect.maxY + 24
        return CGPoint(x: x, y: below < size.height - 80 ? below : max(24, rect.minY - 24))
    }
}

private struct ScoutOutline: View {
    let mark: ScoutMark
    let agent: WebScoutAgent

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(tint.opacity(mark.active ? 0.1 : 0.02))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(tint.opacity(mark.active ? 1 : 0.38),
                            style: StrokeStyle(lineWidth: mark.active ? 2 : 1, dash: mark.active ? [] : [4, 4]))
            }
            .frame(width: mark.rect.width + 6, height: mark.rect.height + 6)
            .position(x: mark.rect.midX, y: mark.rect.midY)
    }

    private var tint: Color {
        switch mark.tone {
        case .info: agent == .codex ? Color(hex: 0x96EBFF) : Color(hex: 0x7DB4FF)
        case .warning: Color(hex: 0xE7B45B)
        case .error: Color(hex: 0xFF7B70)
        }
    }
}

private struct ScoutPet: View {
    let agent: WebScoutAgent

    var body: some View {
        Canvas { context, size in
            if agent == .claude {
                let unit = size.width / 16
                for pixel in Sprite.pixels(.idle, tick: 0) {
                    context.fill(Path(CGRect(x: Double(pixel.x) * unit, y: Double(pixel.y) * unit, width: unit, height: unit)), with: .color(pixel.c))
                }
            } else {
                let unit = min(size.width / Double(CodexAvatar.width), size.height / Double(CodexAvatar.height))
                let x = (size.width - Double(CodexAvatar.width) * unit) / 2
                for cell in CodexAvatar.cells(legs: .stand, face: .prompt(cursor: true)) {
                    context.fill(Path(CGRect(x: x + Double(cell.x) * unit, y: Double(cell.y) * unit, width: unit, height: unit)), with: .color(cell.c))
                }
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }
}
