// ConsoleLog — 伪装成系统日志查看器的本地 txt 阅读器
// 常规应用（Dock + ⌘Tab）；Esc 老板键整屏切换为持续滚动的假日志；
// 章节目录侧边栏（⌘\）可筛选（⌘F）、点击跳转，伪装时自动隐藏。

import AppKit

// MARK: - 常量

private let appDisplayName = "StealthReader"
private let coverWindowTitle = "StealthReader — system.log"
private let sidebarWidth: CGFloat = 244
private let emptyStateText = """
    将日志文件拖入本窗口，或按 ⌘O 打开。

    ␣ / → / ↓　翻下一页
    ⇞ / ← / ↑　翻上一页
    ⌘\\　　　　　目录侧边栏
    ⌘F　　　　　筛选章节
    Esc　　　　一键暂停刷新（老板键）
    """

// MARK: - 文本加载与编码检测

enum TextLoadError: Error, LocalizedError {
    case unreadable(String)
    case undecodable

    var errorDescription: String? {
        switch self {
        case .unreadable(let msg): return "无法读取文件：\(msg)"
        case .undecodable: return "无法识别的日志格式"
        }
    }
}

// MARK: - 章节识别

struct Chapter: Equatable {
    let line: Int
    let title: String
}

enum ChapterParser {
    private static let terminators: Set<Character> = ["章", "节", "卷", "部", "集", "回", "篇", "幕"]
    private static let numerals: Set<Character> = [
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "零", "一", "二", "两", "三", "四", "五", "六", "七", "八", "九",
        "十", "百", "千", "万", "亿", "〇",
    ]
    // 第X章 后面必须紧跟这些字符（或行尾），排除"第三章的内容…"这类叙述段
    private static let afterTerminators: Set<Character> = [
        " ", "\t", "　", "：", ":", "、", "，", ",", "．", ".", "－", "—", "-", "·",
        "（", "(", "【", "[", "《", "「", "《",
    ]
    private static let specialPrefixes = ["序章", "序言", "序幕", "楔子", "引子", "前言", "尾声", "终章", "后记", "后序", "番外"]

    static func parse(_ lines: [Substring]) -> [Chapter] {
        var out: [Chapter] = []
        for (i, line) in lines.enumerated() {
            if let t = titleIfChapter(line) {
                out.append(Chapter(line: i, title: t))
            }
        }
        return out.count >= 3 ? out : fallbackChunks(lines.count)
    }

    // 识别不到章节时按固定行数分块，保证目录仍可跳转
    static func fallbackChunks(_ lineCount: Int, chunk: Int = 500) -> [Chapter] {
        guard lineCount > chunk else { return [] }
        var out: [Chapter] = []
        var start = 0
        while start < lineCount {
            let end = min(start + chunk, lineCount)
            out.append(Chapter(line: start, title: "行 \(start + 1)–\(end)"))
            start = end
        }
        return out
    }

    private static func titleIfChapter(_ raw: Substring) -> String? {
        var s = raw
        while let f = s.first, f == " " || f == "\t" || f == "　" { s = s.dropFirst() }
        while let l = s.last, l == " " || l == "\t" || l == "　" { s = s.dropLast() }
        guard s.count >= 2, s.count <= 45 else { return nil }

        if s.hasPrefix("第") {
            let after = s.dropFirst()
            var idx = after.startIndex
            var digits = 0
            while idx < after.endIndex, digits < 16 {
                let ch = after[idx]
                if numerals.contains(ch) {
                    idx = after.index(after: idx)
                    digits += 1
                    continue
                }
                guard digits >= 1, terminators.contains(ch) else { return nil }
                let next = after.index(after: idx)
                if next == after.endIndex { break }
                guard afterTerminators.contains(after[next]) else { return nil }
                break
            }
            return String(s)
        }

        if s.hasPrefix("Chapter") || s.hasPrefix("chapter") {
            var idx = s.index(after: s.startIndex)
            // C h a p t e r 共 7 个字符
            for _ in 0..<7 { idx = s.index(after: idx) }
            guard idx < s.endIndex else { return nil }
            var sawDigit = false
            while idx < s.endIndex {
                let ch = s[idx]
                if ch.isNumber { sawDigit = true; idx = s.index(after: idx); continue }
                if ch == " " && sawDigit { break }
                return nil
            }
            return String(s)
        }

        if specialPrefixes.contains(where: { s.hasPrefix($0) }), s.count <= 30 {
            return String(s)
        }
        return nil
    }
}

final class NovelDocument {
    let url: URL
    let fileSize: Int
    let modifiedAt: Date
    let encodingName: String
    let lines: [Substring]
    let chapters: [Chapter]
    private let storage: String

    var lineCount: Int { lines.count }

    static func load(url: URL) throws -> NovelDocument {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw TextLoadError.unreadable(error.localizedDescription)
        }
        let (text, enc) = decode(data)
        guard let text else { throw TextLoadError.undecodable }
        return NovelDocument(url: url, data: data, text: text, encodingName: enc)
    }

    // 依序尝试：UTF-8 BOM / UTF-16 BOM / UTF-8 / GB18030（覆盖绝大多数中文 txt）
    private static func decode(_ data: Data) -> (String?, String) {
        let start = data.startIndex
        if data.count >= 3,
           data[start] == 0xEF, data[start + 1] == 0xBB, data[start + 2] == 0xBF,
           let s = String(data: data.dropFirst(3), encoding: .utf8) {
            return (s, "UTF-8")
        }
        if data.count >= 2, data[start] == 0xFF, data[start + 1] == 0xFE,
           let s = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) {
            return (s, "UTF-16 LE")
        }
        if data.count >= 2, data[start] == 0xFE, data[start + 1] == 0xFF,
           let s = String(data: data.dropFirst(2), encoding: .utf16BigEndian) {
            return (s, "UTF-16 BE")
        }
        if let s = String(data: data, encoding: .utf8) { return (s, "UTF-8") }
        let gbNS = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        let gb = String.Encoding(rawValue: gbNS)
        if let s = String(data: data, encoding: gb) { return (s, "GB18030") }
        return (nil, "unknown")
    }

    private init(url: URL, data: Data, text: String, encodingName: String) {
        self.url = url
        self.fileSize = data.count
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        self.modifiedAt = (attrs?[.modificationDate] as? Date) ?? Date()
        self.encodingName = encodingName
        self.storage = text
        self.lines = Self.splitLines(text)
        self.chapters = ChapterParser.parse(self.lines)
    }

    // 按 UTF-8 字节扫描拆行（兼容 LF / CR / CRLF；\r\n 在 Swift 中是单个字素簇，
    // 基于字符的 firstIndex(of: "\n") 永远匹配不到 CRLF 文本的换行）
    private static func splitLines(_ text: String) -> [Substring] {
        var result: [Substring] = []
        let view = text.utf8
        result.reserveCapacity(view.count / 28 + 16)
        var lineStart = view.startIndex
        var i = view.startIndex
        while i < view.endIndex {
            let b = view[i]
            if b == 0x0A || b == 0x0D {
                result.append(text[lineStart..<i])
                let next = view.index(after: i)
                if next < view.endIndex {
                    let nb = view[next]
                    if (b == 0x0D && nb == 0x0A) || (b == 0x0A && nb == 0x0D) {
                        i = next   // 成对换行符只算一行
                    }
                }
                i = view.index(after: i)
                lineStart = i
            } else {
                i = view.index(after: i)
            }
        }
        result.append(text[lineStart...])
        return result
    }
}

// MARK: - 进度与最近文件（存在本机偏好里）

final class ProgressStore {
    static let shared = ProgressStore()
    private let defaults = UserDefaults.standard
    private let recentsKey = "recent_paths"
    private let progressPrefix = "progress."

    func savedLine(for doc: NovelDocument) -> Int? {
        guard let v = defaults.dictionary(forKey: progressPrefix + doc.url.path) else { return nil }
        guard let size = v["size"] as? Int, size == doc.fileSize,
              let mt = v["mtime"] as? Double, abs(mt - doc.modifiedAt.timeIntervalSince1970) < 1.5,
              let line = v["line"] as? Int else { return nil }
        return line
    }

    func saveLine(_ line: Int, for doc: NovelDocument) {
        defaults.set(["size": doc.fileSize,
                      "mtime": doc.modifiedAt.timeIntervalSince1970,
                      "line": line],
                     forKey: progressPrefix + doc.url.path)
    }

    func recentPaths() -> [String] {
        defaults.stringArray(forKey: recentsKey) ?? []
    }

    func noteRecent(_ path: String) {
        var list = recentPaths().filter { $0 != path }
        list.insert(path, at: 0)
        if list.count > 10 { list = Array(list.prefix(10)) }
        defaults.set(list, forKey: recentsKey)
    }

    func clearRecents() {
        defaults.removeObject(forKey: recentsKey)
    }
}

// MARK: - 伪装日志生成器

enum FakeLog {
    private static let host = Host.current().localizedName ?? "MacBook-Pro"

    private static let processes = [
        "kernel", "launchd", "WindowServer", "networkd", "mds", "mds_stores", "cloudd",
        "Finder", "Dock", "symptomsd", "configd", "hidd", "bluetoothd", "coreaudiod",
        "powerd", "loginwindow", "fontd", "securityd", "airportd", "mDNSResponder",
    ]

    private static let domains = [
        "time.euro.apple.com", "gateway.icloud.com", "ocsp.apple.com", "xp.apple.com",
        "init.ess.apple.com", "api-p.itunes.apple.com", "updates.cdn-apple.com",
        "stats.push.apple.com", "dg.inbox.apple.com",
        "cdn.jsdelivr.net", "registry.npmjs.org", "api.github.com", "s.gravatar.com",
    ]

    private static func randIP() -> String {
        "\(UInt8([17, 192, 203, 31, 104, 140].randomElement()!)).\(UInt8.random(in: 0...255)).\(UInt8.random(in: 0...255)).\(UInt8.random(in: 1...254))"
    }

    private static func randPort() -> Int { [443, 80, 5223, 993, 123, 53].randomElement()! }

    private static func randMsg() -> String {
        switch Int.random(in: 0...14) {
        case 0: return "TCP connection to \(randIP()):\(randPort()) established (en0)"
        case 1: return "TCP connection to \(randIP()):\(randPort()) closed after \(Int.random(in: 1...120))s"
        case 2: return "Sending DNS query for \(domains.randomElement()!) to resolver 192.168.1.1"
        case 3: return "DNS resolution of \(domains.randomElement()!) completed in \(String(format: "%.1f", Double.random(in: 1...80)))ms"
        case 4: return "push keep-alive: channel \(Int.random(in: 1000...9999)) renewed, next in \(Int.random(in: 3...60))min"
        case 5: return "metadata index update: \(Int.random(in: 2...400)) items, \(String(format: "%.2f", Double.random(in: 0.1...5)))s"
        case 6: return "reclaimed \(Int.random(in: 1...512)) MB from purgeable space"
        case 7: return "flushed \(Int.random(in: 4...128)) journal blocks to disk"
        case 8: return "certificate status for \(domains.randomElement()!) is valid"
        case 9: return "network configuration changed: interface en0, score \(Int.random(in: 40...100))"
        case 10: return "scanner: ignoring path /System/Volumes/Data (exclude list)"
        case 11: return "power assertion created: \(processes.randomElement()!) (\(Int.random(in: 100...999)))"
        case 12: return "background task \(Int.random(in: 100...999)) finished with status 0"
        case 13: return "cache cleanup: removed \(Int.random(in: 1...64)) stale entries"
        default: return "keepalive ping to \(randIP()) latency \(String(format: "%.1f", Double.random(in: 2...120)))ms"
        }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static var lastDate = Date().addingTimeInterval(-120)

    static func line() -> String {
        lastDate = lastDate.addingTimeInterval(Double.random(in: 0.2...3.0))
        if lastDate > Date() { lastDate = Date() }
        let proc = processes.randomElement()!
        let pid = Int.random(in: 100...60_000)
        return "\(formatter.string(from: lastDate)) \(host) \(proc)[\(pid)]: \(randMsg())"
    }

    static func initialPage(count: Int) -> String {
        (0..<count).map { _ in line() }.joined(separator: "\n")
    }

    static func lineSeq(count: Int) -> [String] {
        (0..<count).map { _ in line() }
    }
}

// MARK: - 自定义视图：拖拽 + 拦截滚轮/按键

final class DropView: NSView {
    var draggingHandler: ((NSDraggingInfo) -> NSDragOperation)?
    var performDropHandler: ((NSDraggingInfo) -> Bool)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingHandler?(sender) ?? []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        performDropHandler?(sender) ?? false
    }
}

final class PageTextView: NSTextView {
    var onScroll: (NSEvent) -> Void = { _ in }

    override func scrollWheel(with event: NSEvent) {
        onScroll(event)
    }
}

// 窗口级按键拦截：无论焦点在正文、目录表格还是搜索框，老板键都可靠生效
final class ReaderWindow: NSWindow {
    var handleKeyEvent: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let h = handleKeyEvent, h(event) { return }
        super.sendEvent(event)
    }
}

// MARK: - 主控制器

final class NovelController: NSObject, NSWindowDelegate, NSTextViewDelegate,
                             NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let window: NSWindow
    private let containerView: DropView
    private let sidebarRoot: NSView
    private let searchField: NSSearchField
    private let chapterTable: NSTableView
    private let sidebarScroll: NSScrollView
    private var sidebarWidthConstraint: NSLayoutConstraint!
    private let scrollView: NSScrollView
    private let textView: PageTextView

    private var document: NovelDocument?
    private var firstLine = 0
    private var linesPerPage = 40
    private var isLoading = false

    private var inCoverMode = false
    private var coverTimer: Timer?
    private var coverBuffer: [String] = []
    private var coverCapacity = 40
    private var sidebarWasVisibleBeforeCover = false
    private var sidebarVisible = false
    private var filteredChapters: [Chapter] = []
    private var suppressSelectionSync = false
    private var scrollAccum: CGFloat = 0

    private let fontSizeKey = "font_size"
    private let autoCoverKey = "auto_cover"
    // 启动后短时间内忽略失焦自动伪装，避免激活抖动导致一打开就是日志画面
    private var autoCoverArmedAt = Date().addingTimeInterval(1.5)

    private var fontSize: CGFloat {
        get { CGFloat(UserDefaults.standard.object(forKey: fontSizeKey) as? Double ?? 14) }
        set { UserDefaults.standard.set(Double(newValue), forKey: fontSizeKey) }
    }

    var autoCoverEnabled: Bool {
        get { UserDefaults.standard.object(forKey: autoCoverKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoCoverKey) }
    }

    var isShowingDocument: Bool { document != nil }
    var isInCoverMode: Bool { inCoverMode }

    private static let textColor = NSColor(calibratedWhite: 0.82, alpha: 1)
    private static let backgroundColor = NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.12, alpha: 1)
    private static let sidebarColor = NSColor(calibratedRed: 0.07, green: 0.075, blue: 0.08, alpha: 1)

    override init() {
        window = ReaderWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = appDisplayName
        window.minSize = NSSize(width: 640, height: 360)

        containerView = DropView()

        // 侧边栏（目录）：搜索框 + 章节表格 + 右侧 1px 分隔线
        sidebarRoot = NSView()
        sidebarRoot.wantsLayer = true
        sidebarRoot.layer?.backgroundColor = Self.sidebarColor.cgColor

        searchField = NSSearchField()
        searchField.placeholderString = "筛选"
        searchField.appearance = NSAppearance(named: .vibrantDark)
        searchField.font = NSFont(name: "Menlo", size: 12)
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true

        chapterTable = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        chapterTable.addTableColumn(column)
        chapterTable.headerView = nil
        chapterTable.usesAlternatingRowBackgroundColors = false
        chapterTable.selectionHighlightStyle = .sourceList
        chapterTable.backgroundColor = .clear
        chapterTable.rowHeight = 24
        chapterTable.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        chapterTable.sizeLastColumnToFit()

        sidebarScroll = NSScrollView()
        sidebarScroll.documentView = chapterTable
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.hasHorizontalScroller = false
        sidebarScroll.drawsBackground = true
        sidebarScroll.backgroundColor = Self.sidebarColor

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 1).cgColor

        sidebarRoot.addSubview(searchField)
        sidebarRoot.addSubview(sidebarScroll)
        sidebarRoot.addSubview(divider)

        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Self.backgroundColor

        textView = PageTextView()
        textView.isEditable = false
        textView.isRichText = false
        textView.allowsUndo = false
        textView.drawsBackground = true
        textView.backgroundColor = Self.backgroundColor
        textView.textContainerInset = NSSize(width: 14, height: 10)
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false

        scrollView.documentView = textView

        containerView.addSubview(sidebarRoot)
        containerView.addSubview(scrollView)
        window.contentView = containerView

        sidebarRoot.translatesAutoresizingMaskIntoConstraints = false
        searchField.translatesAutoresizingMaskIntoConstraints = false
        sidebarScroll.translatesAutoresizingMaskIntoConstraints = false
        divider.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        sidebarWidthConstraint = sidebarRoot.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            sidebarRoot.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            sidebarRoot.topAnchor.constraint(equalTo: containerView.topAnchor),
            sidebarRoot.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            sidebarWidthConstraint,
            divider.trailingAnchor.constraint(equalTo: sidebarRoot.trailingAnchor),
            divider.topAnchor.constraint(equalTo: sidebarRoot.topAnchor),
            divider.bottomAnchor.constraint(equalTo: sidebarRoot.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            searchField.topAnchor.constraint(equalTo: sidebarRoot.topAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: sidebarRoot.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: divider.leadingAnchor, constant: -10),
            searchField.heightAnchor.constraint(equalToConstant: 24),
            sidebarScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            sidebarScroll.leadingAnchor.constraint(equalTo: sidebarRoot.leadingAnchor, constant: 4),
            sidebarScroll.trailingAnchor.constraint(equalTo: divider.leadingAnchor),
            sidebarScroll.bottomAnchor.constraint(equalTo: sidebarRoot.bottomAnchor, constant: -4),
            scrollView.leadingAnchor.constraint(equalTo: sidebarRoot.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
        sidebarRoot.isHidden = true
        window.center()

        super.init()

        window.delegate = self
        textView.delegate = self
        chapterTable.dataSource = self
        chapterTable.delegate = self
        searchField.delegate = self
        textView.onScroll = { [weak self] in self?.handleScroll($0) }
        if let readerWindow = window as? ReaderWindow {
            readerWindow.handleKeyEvent = { [weak self] in (self?.windowKeyDown($0)) ?? false }
        }

        containerView.registerForDraggedTypes([.fileURL])
        containerView.draggingHandler = { info in
            info.draggingPasteboard.canReadObject(forClasses: [NSURL.self],
                                                  options: [.urlReadingFileURLsOnly: true]) ? .copy : []
        }
        containerView.performDropHandler = { [weak self] info in
            guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                                 options: [.urlReadingFileURLsOnly: true]) as? [URL],
                  let url = urls.first else { return false }
            self?.openURL(url)
            return true
        }

        applyFontAttributes()
        showEmptyState()
    }

    func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(textView)
        window.contentView?.layoutSubtreeIfNeeded()
        relayoutAndRender()
    }

    // MARK: 字体与渲染

    private var textAttributes: [NSAttributedString.Key: Any] {
        let font = NSFont(name: "Menlo", size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let para = NSMutableParagraphStyle()
        let lh = round(fontSize * 1.45)
        para.minimumLineHeight = lh
        para.maximumLineHeight = lh
        return [.font: font, .foregroundColor: Self.textColor, .paragraphStyle: para]
    }

    private func applyFontAttributes() {
        textView.typingAttributes = textAttributes
        textView.defaultParagraphStyle = textAttributes[.paragraphStyle] as? NSParagraphStyle
        textView.insertionPointColor = Self.textColor
    }

    private var lineHeight: CGFloat { round(fontSize * 1.45) }

    private func computeLinesPerPage() -> Int {
        window.contentView?.layoutSubtreeIfNeeded()
        textView.frame = scrollView.contentView.bounds
        let avail = scrollView.contentView.bounds.height - textView.textContainerInset.height * 2
        return max(8, Int(avail / lineHeight))
    }

    private func relayoutAndRender() {
        linesPerPage = computeLinesPerPage()
        renderPage()
    }

    private func renderPage() {
        guard let doc = document else {
            showEmptyState()
            return
        }
        let maxFirst = max(0, doc.lineCount - linesPerPage)
        firstLine = min(max(0, firstLine), maxFirst)
        let end = min(firstLine + linesPerPage, doc.lineCount)
        let text = doc.lines[firstLine..<end].joined(separator: "\n")
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: text, attributes: textAttributes))
        updateTitle()
        ProgressStore.shared.saveLine(firstLine, for: doc)
        if sidebarVisible { syncCurrentChapterSelection() }
    }

    private func updateTitle() {
        guard let doc = document else {
            window.title = appDisplayName
            return
        }
        let pct = doc.lineCount > 1
            ? Int((Double(firstLine) / Double(max(doc.lineCount - 1, 1))) * 100)
            : 100
        window.title = "\(appDisplayName) — \(pct)%"
    }

    private func showEmptyState() {
        var attrs = textAttributes
        attrs[.foregroundColor] = NSColor(calibratedWhite: 0.48, alpha: 1)
        if let para = attrs[.paragraphStyle] as? NSMutableParagraphStyle {
            para.lineSpacing = 6
        }
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: emptyStateText, attributes: attrs))
        window.title = appDisplayName
    }

    // MARK: 打开文档

    func openURL(_ url: URL) {
        // 不做 fileExists 预检：TCC（下载/桌面/文稿文件夹隐私保护）会让 stat 静默失败，
        // 而真正的读取才会触发系统权限弹窗
        guard url.isFileURL else { return }
        // 同一文件不重复加载（启动参数与文件关联事件可能先后到达）
        if let doc = document, doc.url.standardizedFileURL.path == url.standardizedFileURL.path { return }
        guard !isLoading else { return }
        isLoading = true
        showLoadingState()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let t0 = Date()
            let doc = try? NovelDocument.load(url: url)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                if let doc {
                    let ms = Date().timeIntervalSince(t0) * 1000
                    FileHandle.standardError.write(Data(
                        "loaded \(doc.lineCount) lines, \(doc.chapters.count) chapters in \(Int(ms))ms (\(doc.encodingName))\n".utf8))
                    self.document = doc
                    self.firstLine = ProgressStore.shared.savedLine(for: doc) ?? 0
                    self.searchField.stringValue = ""
                    self.updateFilter("")
                    if self.inCoverMode { self.exitCover() } else { self.relayoutAndRender() }
                    ProgressStore.shared.noteRecent(url.path)
                } else {
                    var attrs = self.textAttributes
                    attrs[.foregroundColor] = NSColor(calibratedWhite: 0.55, alpha: 1)
                    let msg = "无法读取该文件：\n\n若该文件位于「下载」「桌面」或「文稿」文件夹，\n请在系统弹出的权限询问中点击「允许」后重试。"
                    self.textView.textStorage?.setAttributedString(
                        NSAttributedString(string: msg, attributes: attrs))
                }
            }
        }
    }

    private func showLoadingState() {
        var attrs = textAttributes
        attrs[.foregroundColor] = NSColor(calibratedWhite: 0.48, alpha: 1)
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: "正在解析日志…", attributes: attrs))
    }

    // MARK: 翻页与输入

    private func goTo(_ line: Int) {
        guard document != nil, !inCoverMode else { return }
        firstLine = max(0, line)
        renderPage()
    }

    func nextPage() { goTo(firstLine + linesPerPage) }
    func prevPage() { goTo(firstLine - linesPerPage) }
    func goHome() { goTo(0) }
    func goEnd() {
        guard let doc = document else { return }
        goTo(max(0, doc.lineCount - linesPerPage))
    }

    func changeFontSize(delta: CGFloat) {
        fontSize = min(28, max(9, fontSize + delta))
        applyFontAttributes()
        relayoutAndRender()
    }

    private func handleScroll(_ event: NSEvent) {
        guard document != nil, !inCoverMode else { return }
        if event.momentumPhase == .began || event.momentumPhase == .changed { return }
        scrollAccum += event.scrollingDeltaY
        if scrollAccum > 30 {
            scrollAccum = 0
            nextPage()
        } else if scrollAccum < -30 {
            scrollAccum = 0
            prevPage()
        }
        if event.momentumPhase == .ended { scrollAccum = 0 }
    }

    // 窗口级按键处理：伪装模式只放行 Esc 与 ⌘ 快捷键；阅读模式搜索框获得焦点时
    // 放行普通字符（正在筛选章节），其余按键统一接管为翻页/老板键
    private func windowKeyDown(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) { return false }
        if inCoverMode {
            if event.keyCode == 53 { exitCover() }
            return true
        }
        if event.keyCode == 53 {
            enterCover()
            return true
        }
        let searchFocused: Bool
        if let editor = searchField.currentEditor() {
            searchFocused = window.firstResponder === editor
        } else {
            searchFocused = false
        }
        guard !searchFocused, document != nil else { return false }
        switch event.keyCode {
        case 49, 121, 124, 125: nextPage()            // 空格 / PageDown / → / ↓
        case 116, 123, 126: prevPage()                // PageUp / ← / ↑
        case 115: goHome()                            // Home
        case 119: goEnd()                             // End
        default: return false
        }
        return true
    }

    // MARK: 侧边栏（目录）

    func toggleSidebar() {
        guard document != nil else { return }
        setSidebarVisible(!sidebarVisible)
        if sidebarVisible { syncCurrentChapterSelection() }
    }

    func focusChapterFilter() {
        guard document != nil else { return }
        if !sidebarVisible { setSidebarVisible(true) }
        window.makeFirstResponder(searchField)
    }

    private func setSidebarVisible(_ visible: Bool) {
        sidebarVisible = visible
        sidebarRoot.isHidden = !visible
        sidebarWidthConstraint.constant = visible ? sidebarWidth : 0
        containerView.layoutSubtreeIfNeeded()
        if document != nil && !inCoverMode { relayoutAndRender() }
    }

    private func updateFilter(_ text: String) {
        guard let doc = document else {
            filteredChapters = []
            chapterTable.reloadData()
            return
        }
        let q = text.trimmingCharacters(in: .whitespaces)
        filteredChapters = q.isEmpty ? doc.chapters
            : doc.chapters.filter { $0.title.localizedCaseInsensitiveContains(q) }
        chapterTable.reloadData()
    }

    // 把表格选中行同步到当前阅读位置所在的章节
    private func syncCurrentChapterSelection() {
        guard let doc = document, !doc.chapters.isEmpty else { return }
        let current = doc.chapters.lastIndex(where: { $0.line <= firstLine }) ?? 0
        guard let row = filteredChapters.firstIndex(where: { $0 == doc.chapters[current] }) else { return }
        suppressSelectionSync = true
        chapterTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        chapterTable.scrollRowToVisible(row)
        suppressSelectionSync = false
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredChapters.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("ChapterCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? {
            let v = NSTableCellView()
            v.identifier = id
            let tf = NSTextField(labelWithString: "")
            tf.identifier = NSUserInterfaceItemIdentifier("title")
            tf.font = NSFont(name: "Menlo", size: 12) ?? NSFont.systemFont(ofSize: 12)
            tf.textColor = NSColor(calibratedWhite: 0.74, alpha: 1)
            tf.lineBreakMode = .byTruncatingTail
            tf.maximumNumberOfLines = 1
            tf.cell?.truncatesLastVisibleLine = true
            v.textField = tf
            v.addSubview(tf)
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 6).isActive = true
            tf.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor, constant: -6).isActive = true
            tf.centerYAnchor.constraint(equalTo: v.centerYAnchor).isActive = true
            return v
        }()
        cell.textField?.stringValue = filteredChapters[row].title
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelectionSync,
              let tv = notification.object as? NSTableView, tv === chapterTable else { return }
        let row = tv.selectedRow
        guard row >= 0, row < filteredChapters.count else { return }
        goTo(filteredChapters[row].line)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField, field === searchField else { return }
        updateFilter(field.stringValue)
    }

    // MARK: 老板键伪装

    func toggleCover() {
        inCoverMode ? exitCover() : enterCover()
    }

    func enterCover(startTimer: Bool = true) {
        guard document != nil, !inCoverMode else { return }
        inCoverMode = true
        scrollAccum = 0
        window.title = coverWindowTitle
        // 伪装时隐藏目录侧边栏，防止章节名穿帮
        sidebarWasVisibleBeforeCover = sidebarVisible
        if sidebarVisible { setSidebarVisible(false) }
        coverCapacity = max(linesPerPage, 12)
        coverBuffer = FakeLog.lineSeq(count: coverCapacity)
        renderCover()
        coverTimer?.invalidate()
        if startTimer {
            coverTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
                self?.coverTick()
            }
        }
    }

    func exitCover() {
        guard inCoverMode else { return }
        inCoverMode = false
        coverTimer?.invalidate()
        coverTimer = nil
        if sidebarWasVisibleBeforeCover {
            sidebarWasVisibleBeforeCover = false
            setSidebarVisible(true)
        }
        renderPage()
        window.makeFirstResponder(textView)
    }

    private func renderCover() {
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: coverBuffer.joined(separator: "\n"), attributes: textAttributes))
    }

    private func coverTick() {
        // 环形缓冲：每次推进 1–3 行并整屏重绘，视觉上等价于日志持续滚动
        let add = [1, 1, 1, 1, 1, 2, 2, 3].randomElement()!
        for _ in 0..<add { coverBuffer.append(FakeLog.line()) }
        if coverBuffer.count > coverCapacity {
            coverBuffer.removeFirst(coverBuffer.count - coverCapacity)
        }
        renderCover()
    }

    // MARK: NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        guard document != nil else { return }
        if inCoverMode {
            coverCapacity = max(linesPerPage, 12)
            if coverBuffer.count > coverCapacity {
                coverBuffer.removeFirst(coverBuffer.count - coverCapacity)
            }
            renderCover()
            return
        }
        let saved = firstLine
        linesPerPage = computeLinesPerPage()
        firstLine = saved
        renderPage()
    }

    func windowWillClose(_ notification: Notification) {
        if let doc = document { ProgressStore.shared.saveLine(firstLine, for: doc) }
        // 关窗即静默进入伪装，下次从 Dock 打开看到的是日志画面
        if autoCoverEnabled && document != nil && !inCoverMode {
            enterCover(startTimer: false)
        }
        coverTimer?.invalidate()
        coverTimer = nil
    }

    // 切走应用时自动伪装（启动后 1.5 秒才武装，避免激活抖动误触发）
    func handleAppResignActive() {
        guard autoCoverEnabled, isShowingDocument,
              Date() >= autoCoverArmedAt else { return }
        enterCover()
    }
}

// MARK: - 菜单与应用委托

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = NovelController()
    private var recentMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenus()
        controller.showWindow()
        if let arg = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) {
            controller.openURL(URL(fileURLWithPath: arg))
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.controller.handleAppResignActive()
        }
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        if let first = filenames.first {
            controller.openURL(URL(fileURLWithPath: first))
        }
    }

    // 有 Dock 图标后，关窗保留应用（点 Dock 图标重新打开）
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { controller.showWindow() }
        return true
    }

    private func buildMenus() {
        let main = NSMenu()

        // App 菜单
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu(title: appDisplayName)
        appMenu.addItem(NSMenuItem(title: "关于 \(appDisplayName)", action: nil, keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出 \(appDisplayName)",
                                   action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu

        // 文件菜单
        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let fileMenu = NSMenu(title: "文件")
        fileItem.submenu = fileMenu
        let openItem = NSMenuItem(title: "打开日志…", action: #selector(openFile(_:)), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)

        let recentItem = NSMenuItem(title: "打开最近", action: nil, keyEquivalent: "")
        recentMenu = NSMenu(title: "打开最近")
        recentItem.submenu = recentMenu
        fileMenu.addItem(recentItem)
        rebuildRecentMenu()

        let clearRecent = NSMenuItem(title: "清空最近记录", action: #selector(clearRecents(_:)), keyEquivalent: "")
        clearRecent.target = self
        fileMenu.addItem(clearRecent)
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "关闭窗口",
                                    action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        // 编辑菜单
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        editMenu.addItem(NSMenuItem(title: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        // 显示菜单
        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: "显示")
        viewItem.submenu = viewMenu
        let sidebar = NSMenuItem(title: "显示边栏", action: #selector(toggleSidebarMenu(_:)), keyEquivalent: "\\")
        sidebar.target = self
        viewMenu.addItem(sidebar)
        let findItem = NSMenuItem(title: "筛选条目", action: #selector(findMenu(_:)), keyEquivalent: "f")
        findItem.target = self
        viewMenu.addItem(findItem)
        viewMenu.addItem(.separator())
        let coverItem = NSMenuItem(title: "暂停刷新", action: #selector(toggleCover(_:)), keyEquivalent: "")
        coverItem.target = self
        viewMenu.addItem(coverItem)
        let autoCover = NSMenuItem(title: "切走时自动暂停", action: #selector(toggleAutoCover(_:)), keyEquivalent: "")
        autoCover.target = self
        autoCover.state = controller.autoCoverEnabled ? .on : .off
        viewMenu.addItem(autoCover)
        viewMenu.addItem(.separator())
        let zoomIn = NSMenuItem(title: "放大字号", action: #selector(zoomIn(_:)), keyEquivalent: "+")
        zoomIn.target = self
        viewMenu.addItem(zoomIn)
        let zoomOut = NSMenuItem(title: "缩小字号", action: #selector(zoomOut(_:)), keyEquivalent: "-")
        zoomOut.target = self
        viewMenu.addItem(zoomOut)

        NSApp.mainMenu = main
    }

    private func rebuildRecentMenu() {
        recentMenu?.removeAllItems()
        for path in ProgressStore.shared.recentPaths() {
            let item = NSMenuItem(title: (path as NSString).lastPathComponent,
                                  action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = path
            item.toolTip = path
            recentMenu?.addItem(item)
        }
        if recentMenu?.numberOfItems == 0 {
            let empty = NSMenuItem(title: "无记录", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu?.addItem(empty)
        }
    }

    @objc private func openFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "选择日志文件"
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            controller.openURL(url)
            rebuildRecentMenu()
        }
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        controller.openURL(URL(fileURLWithPath: path))
    }

    @objc private func clearRecents(_ sender: NSMenuItem) {
        ProgressStore.shared.clearRecents()
        rebuildRecentMenu()
    }

    @objc private func toggleSidebarMenu(_ sender: NSMenuItem) { controller.toggleSidebar() }
    @objc private func findMenu(_ sender: NSMenuItem) { controller.focusChapterFilter() }
    @objc private func toggleCover(_ sender: NSMenuItem) { controller.toggleCover() }

    @objc private func toggleAutoCover(_ sender: NSMenuItem) {
        controller.autoCoverEnabled.toggle()
        sender.state = controller.autoCoverEnabled ? .on : .off
    }

    @objc private func zoomIn(_ sender: NSMenuItem) { controller.changeFontSize(delta: 1) }
    @objc private func zoomOut(_ sender: NSMenuItem) { controller.changeFontSize(delta: -1) }
}

// MARK: - 入口

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
