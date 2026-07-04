import Foundation
import Observation

struct NNTPServer: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var host: String
    var port: Int
    var status: String
    var username: String?
    var password: String?
    var useSSL: Bool?
    
    init(id: String, name: String, host: String, port: Int, status: String, username: String? = nil, password: String? = nil, useSSL: Bool? = false) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.status = status
        self.username = username
        self.password = password
        self.useSSL = useSSL
    }
}

struct Newsgroup: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var serverId: String
    var description: String
    var subscribed: Bool
    var unreadCount: Int
}

struct Article: Identifiable, Hashable, Codable {
    var id: String
    var number: Int
    var newsgroup: String
    var serverId: String
    var subject: String
    var from: String
    var date: Date
    var body: String
    var references: [String]
    var read: Bool
    var ignored: Bool
    var downloaded: Bool
    var flagged: Bool? = false

    enum CodingKeys: String, CodingKey {
        case id, number, newsgroup, serverId, subject, from, date, body, references, read, ignored, downloaded, flagged
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.number = try container.decode(Int.self, forKey: .number)
        self.newsgroup = try container.decode(String.self, forKey: .newsgroup)
        self.serverId = try container.decode(String.self, forKey: .serverId)
        
        let rawSubject = try container.decode(String.self, forKey: .subject)
        self.subject = MIMEUtils.decodeRFC2047(rawSubject)
        
        let rawFrom = try container.decode(String.self, forKey: .from)
        self.from = MIMEUtils.decodeRFC2047(rawFrom)
        
        self.date = try container.decode(Date.self, forKey: .date)
        self.body = try container.decode(String.self, forKey: .body)
        self.references = try container.decode([String].self, forKey: .references)
        self.read = try container.decode(Bool.self, forKey: .read)
        self.ignored = try container.decode(Bool.self, forKey: .ignored)
        self.downloaded = try container.decode(Bool.self, forKey: .downloaded)
        self.flagged = try container.decodeIfPresent(Bool.self, forKey: .flagged) ?? false
    }

    init(id: String, number: Int, newsgroup: String, serverId: String, subject: String, from: String, date: Date, body: String, references: [String], read: Bool, ignored: Bool, downloaded: Bool, flagged: Bool? = false) {
        self.id = id
        self.number = number
        self.newsgroup = newsgroup
        self.serverId = serverId
        self.subject = MIMEUtils.decodeRFC2047(subject)
        self.from = MIMEUtils.decodeRFC2047(from)
        self.date = date
        self.body = body
        self.references = references
        self.read = read
        self.ignored = ignored
        self.downloaded = downloaded
        self.flagged = flagged
    }
}

struct MIMEUtils {
    static func decodeRFC2047(_ input: String) -> String {
        guard input.contains("?") else { return input }
        
        var normalized = input
        // Fix missing leading '=' before '?' when followed by a charset name and encoding parameter
        if let regex = try? NSRegularExpression(pattern: "(?<!=)\\?([^?]+)\\?([BbQq])\\?", options: [.caseInsensitive]) {
            let range = NSRange(location: 0, length: (normalized as NSString).length)
            normalized = regex.stringByReplacingMatches(in: normalized, options: [], range: range, withTemplate: "=?$1?$2?")
        }
        
        let pattern = "=\\?([^?]+)\\?([BbQq])\\?([^?]*)\\?="
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return cleanRemnants(normalized)
        }
        
        let nsString = normalized as NSString
        let matches = regex.matches(in: normalized, options: [], range: NSRange(location: 0, length: nsString.length))
        
        if matches.isEmpty {
            return cleanRemnants(normalized)
        }
        
        var result = ""
        var lastOffset = 0
        
        for match in matches {
            let matchRange = match.range
            
            // Append text before this match
            if matchRange.location > lastOffset {
                let prefix = nsString.substring(with: NSRange(location: lastOffset, length: matchRange.location - lastOffset))
                result += prefix
            }
            
            let charset = nsString.substring(with: match.range(at: 1)).lowercased()
            let encoding = nsString.substring(with: match.range(at: 2)).lowercased()
            let encodedText = nsString.substring(with: match.range(at: 3))
            
            var decodedChunk = ""
            if encoding == "b" {
                // Base64 decode
                if let data = Data(base64Encoded: encodedText) {
                    decodedChunk = decodeData(data, charset: charset)
                } else {
                    // Try padding if it fails
                    let rem = encodedText.count % 4
                    var padded = encodedText
                    if rem > 0 {
                        padded += String(repeating: "=", count: 4 - rem)
                    }
                    if let data = Data(base64Encoded: padded) {
                        decodedChunk = decodeData(data, charset: charset)
                    } else {
                        decodedChunk = encodedText
                    }
                }
            } else if encoding == "q" {
                // Quoted-Printable decode
                decodedChunk = decodeQuotedPrintable(encodedText, charset: charset)
            } else {
                decodedChunk = encodedText
            }
            
            result += decodedChunk
            lastOffset = matchRange.location + matchRange.length
        }
        
        if lastOffset < nsString.length {
            result += nsString.substring(from: lastOffset)
        }
        
        return cleanRemnants(result)
    }
    
    private static func cleanRemnants(_ text: String) -> String {
        let cleanPatterns = [
            "=\\?([^?]+)\\?[BbQq]\\?",
            "\\??UTF-8\\?[BbQq]\\?",
            "\\??utf-8\\?[BbQq]\\?",
            "\\??ISO-8859-[0-9]+\\?[BbQq]\\?",
            "\\??iso-8859-[0-9]+\\?[BbQq]\\?",
            "\\?="
        ]
        var cleaned = text
        for pat in cleanPatterns {
            if let rx = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: (cleaned as NSString).length)
                cleaned = rx.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
            }
        }
        cleaned = cleaned.replacingOccurrences(of: "_", with: " ")
        return cleaned
    }
    
    private static func decodeData(_ data: Data, charset: String) -> String {
        let stringEncoding: String.Encoding
        if charset.contains("utf-8") || charset.contains("utf8") {
            stringEncoding = .utf8
        } else if charset.contains("iso-8859-1") || charset.contains("latin1") {
            stringEncoding = .isoLatin1
        } else if charset.contains("windows-1252") {
            stringEncoding = .windowsCP1252
        } else {
            stringEncoding = .utf8
        }
        return String(data: data, encoding: stringEncoding) ?? String(data: data, encoding: .ascii) ?? ""
    }
    
    private static func decodeQuotedPrintable(_ input: String, charset: String) -> String {
        let prepared = input.replacingOccurrences(of: "_", with: " ")
        var data = Data()
        var i = prepared.startIndex
        while i < prepared.endIndex {
            let char = prepared[i]
            if char == "=" {
                let nextIndex1 = prepared.index(after: i)
                if nextIndex1 < prepared.endIndex {
                    let nextIndex2 = prepared.index(after: nextIndex1)
                    if nextIndex2 < prepared.endIndex {
                        let hexStr = String(prepared[nextIndex1...nextIndex2])
                        if let byte = UInt8(hexStr, radix: 16) {
                            data.append(byte)
                            i = prepared.index(after: nextIndex2)
                            continue
                        }
                    }
                }
            }
            if let asciiVal = char.asciiValue {
                data.append(asciiVal)
            } else {
                let utf8Bytes = String(char).utf8
                data.append(contentsOf: utf8Bytes)
            }
            i = prepared.index(after: i)
        }
        return decodeData(data, charset: charset)
    }
}

struct OutboxPost: Identifiable, Hashable, Codable {
    var id: String
    var serverId: String
    var newsgroup: String
    var subject: String
    var body: String
    var date: Date
    var status: String // "queued" or "sent"
    var references: [String]
}

struct SwiftSyncLog: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var timestamp: Date = Date()
    var serverId: String
    var serverName: String
    var type: String // "info", "success", "error"
    var message: String
}

struct StoreState: Codable {
    var username: String
    var userEmail: String
    var userOrg: String
    var xFace: String
    var isOffline: Bool
    var selectedServerId: String?
    var selectedGroupId: String?
    var selectedArticleId: String?
    var servers: [NNTPServer]
    var groups: [Newsgroup]
    var articles: [Article]
    var outbox: [OutboxPost]
    
    var plistPath: String?
    var fetchMode: String?
    var fetchMax: Int?
    var replyTo: String?
}

@Observable
class UsenetStore {
    private var isLoadingState = false
    private var pendingSaveWorkItem: DispatchWorkItem?
    private let saveQueue = DispatchQueue(label: "com.spiceboard.savequeue", qos: .utility)
    
    var customStateFilePath: String? = UserDefaults.standard.string(forKey: "custom_state_file_path") {
        didSet {
            UserDefaults.standard.set(customStateFilePath, forKey: "custom_state_file_path")
            saveState(immediate: true)
        }
    }
    
    private func getSaveURL() -> URL {
        if let customPath = customStateFilePath, !customPath.isEmpty {
            return URL(fileURLWithPath: customPath)
        }
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("SpiceBoardSwiftUI", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("store_state.json")
    }
    
    private func getAvailableGroupsURL() -> URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("SpiceBoardSwiftUI", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("available_groups.tsv")
    }
    
    var availableGroups: [Newsgroup] = []
    
    func loadAvailableGroups() {
        let url = getAvailableGroupsURL()
        // Backward compatibility: migrate from json to tsv if json exists
        let jsonUrl = url.deletingPathExtension().appendingPathExtension("json")
        if FileManager.default.fileExists(atPath: jsonUrl.path) {
            if let data = try? Data(contentsOf: jsonUrl),
               let list = try? JSONDecoder().decode([Newsgroup].self, from: data) {
                self.availableGroups = list
                saveAvailableGroups()
                try? FileManager.default.removeItem(at: jsonUrl)
                return
            }
        }
        
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            var list: [Newsgroup] = []
            content.enumerateLines { line, _ in
                let parts = line.components(separatedBy: "\t")
                if parts.count >= 4 {
                    let id = parts[0]
                    let name = parts[1]
                    let serverId = parts[2]
                    let description = parts[3]
                    let subscribed = parts.count >= 5 ? (parts[4] == "1") : false
                    list.append(Newsgroup(
                        id: id,
                        name: name,
                        serverId: serverId,
                        description: description,
                        subscribed: subscribed,
                        unreadCount: 0
                    ))
                }
            }
            self.availableGroups = list
        } else {
            self.availableGroups = [
                Newsgroup(id: "gmane-public.gmane.comp.misc", name: "gmane.comp.misc", serverId: "gmane-public", description: "Allgemeine Computer-Diskussionen via Gmane.", subscribed: true, unreadCount: 0)
            ]
        }
    }
    
    func saveAvailableGroups() {
        let url = getAvailableGroupsURL()
        let listToSave = self.availableGroups
        saveQueue.async {
            var lines: [String] = []
            for g in listToSave {
                let name = g.name.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
                let desc = g.description.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
                let subStr = g.subscribed ? "1" : "0"
                lines.append("\(g.id)\t\(name)\t\(g.serverId)\t\(desc)\t\(subStr)")
            }
            let tsvContent = lines.joined(separator: "\n")
            try? tsvContent.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    
    var articlesChangeCounter: Int = 0
    var connectionError: String? = nil
    
    var servers: [NNTPServer] = [] { didSet { saveState() } }
    var groups: [Newsgroup] = [] { didSet { saveState() } }
    var articles: [Article] = [] { didSet { saveState(); articlesChangeCounter += 1 } }
    var outbox: [OutboxPost] = [] { didSet { saveState() } }
    
    var syncLogs: [SwiftSyncLog] = []
    
    func addLog(serverId: String, serverName: String, type: String, message: String) {
        let newLog = SwiftSyncLog(serverId: serverId, serverName: serverName, type: type, message: message)
        Task { @MainActor in
            self.syncLogs.append(newLog)
            if self.syncLogs.count > 500 {
                self.syncLogs.removeFirst(self.syncLogs.count - 500)
            }
        }
        print("[\(type.uppercased())] \(serverName): \(message)")
    }
    
    // User Identity Parameters
    var username: String = "RetroGamer" { didSet { saveState() } }
    var userEmail: String = "info@mac-retro.de" { didSet { saveState() } }
    var userOrg: String = "Privatanwender" { didSet { saveState() } }
    var xFace: String = "X-Face: d7a1b4f8c92e10db3f421" { didSet { saveState() } }
    
    // Custom Preferences
    var plistPath: String = "com.steffenbendix.SpiceBoard.plist" { didSet { saveState() } }
    var fetchMode: String = "unread" { didSet { saveState() } }
    var fetchMax: Int = 250 { didSet { saveState() } }
    var replyTo: String = "" { didSet { saveState() } }
    
    var isOffline: Bool = false { didSet { saveState() } }
    var isSyncing: Bool = false
    var isFetchingGroups: Bool = false
    var selectedServerId: String? { didSet { saveSelection() } }
    var selectedGroupId: String? { didSet { saveSelection() } }
    var selectedArticleId: String? { didSet { saveSelection() } }
    
    func saveSelection() {
        guard !isLoadingState else { return }
        UserDefaults.standard.set(selectedServerId, forKey: "selected_server_id")
        UserDefaults.standard.set(selectedGroupId, forKey: "selected_group_id")
        UserDefaults.standard.set(selectedArticleId, forKey: "selected_article_id")
    }
    
    func saveState(immediate: Bool = false) {
        guard !isLoadingState else { return }
        
        pendingSaveWorkItem?.cancel()
        
        let saveBlock = { [weak self] in
            guard let self = self else { return }
            
            let state = StoreState(
                username: self.username,
                userEmail: self.userEmail,
                userOrg: self.userOrg,
                xFace: self.xFace,
                isOffline: self.isOffline,
                selectedServerId: self.selectedServerId,
                selectedGroupId: self.selectedGroupId,
                selectedArticleId: self.selectedArticleId,
                servers: self.servers,
                groups: self.groups,
                articles: self.articles,
                outbox: self.outbox,
                plistPath: self.plistPath,
                fetchMode: self.fetchMode,
                fetchMax: self.fetchMax,
                replyTo: self.replyTo
            )
            
            // Execute JSON encoding and storage asynchronously on a dedicated background queue to completely avoid blocking the Main Thread/UI
            let saveURL = self.getSaveURL()
            self.saveQueue.async {
                if let data = try? JSONEncoder().encode(state) {
                    try? data.write(to: saveURL, options: .atomic)
                }
            }
        }
        
        if immediate {
            saveBlock()
        } else {
            let workItem = DispatchWorkItem(block: saveBlock)
            pendingSaveWorkItem = workItem
            // Debounce with 0.8 seconds delay on the Main Queue
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
        }
    }
    
    func loadState() -> Bool {
        isLoadingState = true
        defer { isLoadingState = false }
        
        let saveURL = getSaveURL()
        var loadedData: Data? = nil
        
        if FileManager.default.fileExists(atPath: saveURL.path) {
            loadedData = try? Data(contentsOf: saveURL)
        }
        
        if loadedData == nil {
            loadedData = UserDefaults.standard.data(forKey: "usenet_store_state")
        }
        
        guard let data = loadedData,
              let state = try? JSONDecoder().decode(StoreState.self, from: data) else {
            return false
        }
        self.username = state.username
        self.userEmail = state.userEmail
        self.userOrg = state.userOrg
        self.xFace = state.xFace
        self.isOffline = state.isOffline
        
        self.plistPath = state.plistPath ?? "com.steffenbendix.SpiceBoard.plist"
        self.fetchMode = state.fetchMode ?? "unread"
        self.fetchMax = state.fetchMax ?? 250
        self.replyTo = state.replyTo ?? ""
        
        let filteredServers = state.servers.filter { $0.id != "simulated-usenet" && $0.id != "uni-erlangen" && $0.id != "simulated" }
        var finalServers = filteredServers
        if !finalServers.contains(where: { $0.id == "gmane-public" }) {
            finalServers.append(NNTPServer(id: "gmane-public", name: "Gmane Public News", host: "news.gmane.io", port: 119, status: "online"))
        }
        if !finalServers.contains(where: { $0.id == "eternal-september" }) {
            finalServers.append(NNTPServer(id: "eternal-september", name: "Eternal September", host: "news.eternal-september.org", port: 563, status: "online", useSSL: true))
        }
        self.servers = finalServers
        
        // Load Selection from separate, lightweight Keys
        let loadedServerId = UserDefaults.standard.string(forKey: "selected_server_id") ?? state.selectedServerId
        let targetServerId = (loadedServerId == "simulated-usenet" || loadedServerId == "uni-erlangen" || loadedServerId == "simulated") ? "gmane-public" : loadedServerId
        
        if let targetId = targetServerId, self.servers.contains(where: { $0.id == targetId }) {
            self.selectedServerId = targetId
        } else {
            self.selectedServerId = self.servers.first?.id
        }
        
        self.selectedGroupId = UserDefaults.standard.string(forKey: "selected_group_id") ?? state.selectedGroupId
        
        let loadedGroups = state.groups.filter { $0.serverId != "simulated-usenet" && $0.serverId != "uni-erlangen" && $0.serverId != "simulated" }
        self.groups = loadedGroups.filter { $0.subscribed }
        
        self.loadAvailableGroups()
        if self.availableGroups.isEmpty && !loadedGroups.isEmpty {
            self.availableGroups = loadedGroups
            self.saveAvailableGroups()
        }
        
        self.articles = state.articles.filter { $0.serverId != "simulated-usenet" && $0.serverId != "uni-erlangen" && $0.serverId != "simulated" }
        self.outbox = state.outbox.filter { $0.serverId != "simulated-usenet" && $0.serverId != "uni-erlangen" && $0.serverId != "simulated" }
        
        self.selectedArticleId = UserDefaults.standard.string(forKey: "selected_article_id") ?? state.selectedArticleId
        return true
    }
    
    func exportStateToFile(url: URL) throws {
        let state = StoreState(
            username: username,
            userEmail: userEmail,
            userOrg: userOrg,
            xFace: xFace,
            isOffline: isOffline,
            selectedServerId: selectedServerId,
            selectedGroupId: selectedGroupId,
            selectedArticleId: selectedArticleId,
            servers: servers,
            groups: groups,
            articles: articles,
            outbox: outbox,
            plistPath: plistPath,
            fetchMode: fetchMode,
            fetchMax: fetchMax,
            replyTo: replyTo
        )
        let data = try JSONEncoder().encode(state)
        try data.write(to: url)
    }
    
    func importStateFromFile(url: URL) throws {
        isLoadingState = true
        defer {
            isLoadingState = false
            saveState()
        }
        
        let data = try Data(contentsOf: url)
        let state = try JSONDecoder().decode(StoreState.self, from: data)
        self.username = state.username
        self.userEmail = state.userEmail
        self.userOrg = state.userOrg
        self.xFace = state.xFace
        self.isOffline = state.isOffline
        
        self.plistPath = state.plistPath ?? "com.steffenbendix.SpiceBoard.plist"
        self.fetchMode = state.fetchMode ?? "unread"
        self.fetchMax = state.fetchMax ?? 250
        self.replyTo = state.replyTo ?? ""
        
        let targetServerId = (state.selectedServerId == "simulated-usenet" || state.selectedServerId == "uni-erlangen" || state.selectedServerId == "simulated") ? "gmane-public" : state.selectedServerId
        self.selectedServerId = targetServerId
        self.selectedGroupId = state.selectedGroupId
        self.selectedArticleId = state.selectedArticleId
        
        let filteredServers = state.servers.filter { $0.id != "simulated-usenet" && $0.id != "uni-erlangen" && $0.id != "simulated" }
        if filteredServers.isEmpty {
            self.servers = [
                NNTPServer(id: "gmane-public", name: "Gmane Public News", host: "news.gmane.io", port: 119, status: "online"),
                NNTPServer(id: "eternal-september", name: "Eternal September", host: "news.eternal-september.org", port: 563, status: "online", useSSL: true)
            ]
        } else {
            self.servers = filteredServers
        }
        
        let importedGroups = state.groups.filter { $0.serverId != "simulated-usenet" && $0.serverId != "uni-erlangen" && $0.serverId != "simulated" }
        self.groups = importedGroups.filter { $0.subscribed }
        self.availableGroups = importedGroups
        self.saveAvailableGroups()
        
        self.articles = state.articles.filter { $0.serverId != "simulated-usenet" && $0.serverId != "uni-erlangen" && $0.serverId != "simulated" }
        self.outbox = state.outbox.filter { $0.serverId != "simulated-usenet" && $0.serverId != "uni-erlangen" && $0.serverId != "simulated" }
    }
    
    func loadMockData() {
        servers = [
            NNTPServer(id: "gmane-public", name: "Gmane Public News", host: "news.gmane.io", port: 119, status: "online"),
            NNTPServer(id: "eternal-september", name: "Eternal September", host: "news.eternal-september.org", port: 563, status: "online", useSSL: true)
        ]
        
        groups = [
            Newsgroup(id: "gmane-public.gmane.comp.misc", name: "gmane.comp.misc", serverId: "gmane-public", description: "Allgemeine Computer-Diskussionen via Gmane.", subscribed: true, unreadCount: 0)
        ]
        
        availableGroups = [
            Newsgroup(id: "gmane-public.gmane.comp.misc", name: "gmane.comp.misc", serverId: "gmane-public", description: "Allgemeine Computer-Diskussionen via Gmane.", subscribed: true, unreadCount: 0)
        ]
        saveAvailableGroups()
        
        articles = []
        
        selectedServerId = "gmane-public"
        selectedGroupId = "gmane.comp.misc"
        selectedArticleId = nil
    }
    
    func toggleSubscription(groupId: String) {
        if let idx = groups.firstIndex(where: { $0.id == groupId }) {
            let g = groups[idx]
            groups.remove(at: idx)
            
            if let availIdx = availableGroups.firstIndex(where: { $0.id == groupId }) {
                availableGroups[availIdx].subscribed = false
            }
            saveAvailableGroups()
            
            // Wenn Gruppe de-abonniert wird, sollen auch alle ihre Threads gelöscht werden.
            let targetGroupName = g.name
            let targetServerId = g.serverId
            articles.removeAll { $0.newsgroup == targetGroupName && $0.serverId == targetServerId }
            
            // Reset selectedArticleId if it belonged to the deleted articles
            if let selArtId = selectedArticleId, !articles.contains(where: { $0.id == selArtId }) {
                selectedArticleId = nil
            }
        } else {
            if let availIdx = availableGroups.firstIndex(where: { $0.id == groupId }) {
                availableGroups[availIdx].subscribed = true
                var newSubGroup = availableGroups[availIdx]
                newSubGroup.subscribed = true
                groups.append(newSubGroup)
                saveAvailableGroups()
            }
        }
    }
    
    func clearGroupList() {
        availableGroups = []
        saveAvailableGroups()
    }
    
    func addPost(newsgroup: String, subject: String, body: String, references: [String] = []) {
        let newPost = OutboxPost(
            id: UUID().uuidString,
            serverId: selectedServerId ?? "gmane-public",
            newsgroup: newsgroup,
            subject: subject,
            body: body,
            date: Date(),
            status: "queued",
            references: references
        )
        outbox.append(newPost)
    }
    
    func killThread(for articleId: String) {
        toggleKillThread(for: articleId)
    }
    
    func toggleKillThread(for articleId: String) {
        guard let target = articles.first(where: { $0.id == articleId }) else { return }
        let rootId = target.references.first ?? target.id
        let currentlyIgnored = target.ignored
        
        var updatedArticles = articles
        for idx in 0..<updatedArticles.count {
            if updatedArticles[idx].id == rootId || updatedArticles[idx].references.contains(rootId) {
                updatedArticles[idx].ignored = !currentlyIgnored
                if !currentlyIgnored {
                    updatedArticles[idx].read = true // Mark as read automatically when ignored
                }
            }
        }
        articles = updatedArticles
        recalcUnreadCounts()
    }
    
    func toggleKillBranch(for articleId: String) {
        guard let target = articles.first(where: { $0.id == articleId }) else { return }
        let currentlyIgnored = target.ignored
        
        var updatedArticles = articles
        for idx in 0..<updatedArticles.count {
            let art = updatedArticles[idx]
            if art.id == target.id || art.references.contains(target.id) {
                updatedArticles[idx].ignored = !currentlyIgnored
                if !currentlyIgnored {
                    updatedArticles[idx].read = true
                }
            }
        }
        articles = updatedArticles
        recalcUnreadCounts()
    }
    
    func toggleFlagged(for articleId: String) {
        var updatedArticles = articles
        if let idx = updatedArticles.firstIndex(where: { $0.id == articleId }) {
            let current = updatedArticles[idx].flagged ?? false
            updatedArticles[idx].flagged = !current
            articles = updatedArticles
            articlesChangeCounter += 1
            saveState()
        }
    }
    
    func ignorePoster(from sender: String) {
        toggleIgnorePoster(from: sender)
    }
    
    func toggleIgnorePoster(from sender: String) {
        let currentlyIgnored = isAuthorIgnored(sender: sender)
        
        var updatedArticles = articles
        for idx in 0..<updatedArticles.count {
            if updatedArticles[idx].from == sender {
                updatedArticles[idx].ignored = !currentlyIgnored
                if !currentlyIgnored {
                    updatedArticles[idx].read = true // Mark as read automatically when ignored
                }
            }
        }
        articles = updatedArticles
        recalcUnreadCounts()
    }
    
    func isAuthorIgnored(sender: String) -> Bool {
        return articles.contains { $0.from == sender && $0.ignored }
    }
    
    func synchronize() {
        if isOffline {
            addLog(serverId: "local", serverName: "System", type: "error", message: "Synchronisation abgebrochen: Sie sind offline.")
            connectionError = "Abgleich fehlgeschlagen: Sie sind im Offline-Modus. Bitte klicken Sie oben auf 'Status: Offline', um online zu gehen."
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        
        let activeServerId = self.selectedServerId ?? ""
        guard let server = self.servers.first(where: { $0.id == activeServerId }) else {
            if let firstServer = self.servers.first {
                self.selectedServerId = firstServer.id
                self.isSyncing = false
                self.synchronize()
            } else {
                isSyncing = false
                addLog(serverId: "local", serverName: "System", type: "error", message: "Abgleich abgebrochen: Kein aktiver Server konfiguriert.")
                connectionError = "Abgleich fehlgeschlagen:\nKein Usenet-Server konfiguriert oder ausgewählt."
            }
            return
        }
        
        addLog(serverId: server.id, serverName: server.name, type: "info", message: "Synchronisation gestartet...")
        
        Task {
            let client = SwiftNNTPClient()
            do {
                addLog(serverId: server.id, serverName: server.name, type: "info", message: "Verbinde mit \(server.host):\(server.port) (SSL: \(server.useSSL ?? false))...")
                let greeting = try await client.connect(host: server.host, port: server.port, useSSL: server.useSSL ?? false)
                addLog(serverId: server.id, serverName: server.name, type: "success", message: "Verbunden: \(greeting.trimmingCharacters(in: .whitespacesAndNewlines))")
                
                if let username = server.username, !username.isEmpty,
                   let password = server.password {
                    addLog(serverId: server.id, serverName: server.name, type: "info", message: "Sende Anmeldedaten (AUTHINFO)...")
                    let userRes = try await client.sendCommand("AUTHINFO USER \(username)")
                    addLog(serverId: server.id, serverName: server.name, type: "info", message: "Server: \(userRes.trimmingCharacters(in: .whitespacesAndNewlines))")
                    if userRes.hasPrefix("381") {
                        let passRes = try await client.sendCommand("AUTHINFO PASS \(password)")
                        addLog(serverId: server.id, serverName: server.name, type: "success", message: "Server: \(passRes.trimmingCharacters(in: .whitespacesAndNewlines))")
                    }
                }
                
                // 1. Send Outbox posts
                var sentOutboxIds: [String] = []
                var newArticlesFromOutbox: [Article] = []
                
                let postsToSend = self.outbox.filter { $0.status == "queued" && $0.serverId == server.id }
                if !postsToSend.isEmpty {
                    addLog(serverId: server.id, serverName: server.name, type: "info", message: "Sende \(postsToSend.count) ausgehende(n) Beitrag/Beiträge...")
                }
                
                for post in postsToSend {
                    do {
                        // Generate a unique Message-ID (standard format without brackets) to map the sent post
                        let msgUUID = UUID().uuidString.lowercased()
                        let messageId = "\(msgUUID)@spiceboard.local"
                        
                        addLog(serverId: server.id, serverName: server.name, type: "info", message: "Sende Post: \"\(post.subject)\" an \(post.newsgroup)...")
                        let postRes = try await client.sendPost(
                            from: "\(self.username) <\(self.userEmail)>",
                            newsgroup: post.newsgroup,
                            subject: post.subject,
                            body: post.body,
                            references: post.references,
                            xFace: self.xFace,
                            messageId: messageId,
                            replyTo: self.replyTo,
                            organisation: self.userOrg,
                            userAgent: "SpiceBoard"
                        )
                        
                        if postRes.hasPrefix("240") {
                            addLog(serverId: server.id, serverName: server.name, type: "success", message: "Beitrag erfolgreich gesendet! Serverantwort: \(postRes.trimmingCharacters(in: .whitespacesAndNewlines))")
                            sentOutboxIds.append(post.id)
                            
                            // Map the newly sent article using the generated messageId
                            let newArticle = Article(
                                id: messageId,
                                number: (self.articles.map(\.number).max() ?? 4000) + 1,
                                newsgroup: post.newsgroup,
                                serverId: server.id,
                                subject: post.subject,
                                from: "\(self.username) <\(self.userEmail)>",
                                date: Date(),
                                body: post.body,
                                references: post.references,
                                read: true,
                                ignored: false,
                                downloaded: true
                            )
                            newArticlesFromOutbox.append(newArticle)
                        } else {
                            addLog(serverId: server.id, serverName: server.name, type: "error", message: "Senden fehlgeschlagen: \(postRes.trimmingCharacters(in: .whitespacesAndNewlines))")
                        }
                    } catch {
                        addLog(serverId: server.id, serverName: server.name, type: "error", message: "Fehler beim Senden: \(error.localizedDescription)")
                        print("Failed to post article: \(error)")
                    }
                }
                
                // 2. Fetch new headers for subscribed groups
                let subscribedGroups = self.groups.filter { $0.serverId == server.id && $0.subscribed }
                var fetchedArticles: [Article] = []
                
                if subscribedGroups.isEmpty {
                    addLog(serverId: server.id, serverName: server.name, type: "info", message: "Keine abonnierten Gruppen für diesen Server.")
                } else {
                    addLog(serverId: server.id, serverName: server.name, type: "info", message: "Prüfe \(subscribedGroups.count) abonnierte Gruppe(n)...")
                }
                
                for group in subscribedGroups {
                    addLog(serverId: server.id, serverName: server.name, type: "info", message: "Lese Gruppe \(group.name)...")
                    let groupRes = try await client.sendCommand("GROUP \(group.name)")
                    addLog(serverId: server.id, serverName: server.name, type: "info", message: "Gruppe \(group.name): \(groupRes.trimmingCharacters(in: .whitespacesAndNewlines))")
                    if groupRes.hasPrefix("211") {
                        let parts = groupRes.components(separatedBy: .whitespaces)
                        if parts.count >= 4,
                           let count = Int(parts[1]),
                           let first = Int(parts[2]),
                           let last = Int(parts[3]), count > 0 {
                            
                            // Fetch articles according to fetchMode
                            var fetchLimit = 15 // Fallback/default unread limit
                            if self.fetchMode == "max" {
                                fetchLimit = self.fetchMax
                            } else if self.fetchMode == "all" {
                                fetchLimit = count
                            } else if self.fetchMode == "unread" {
                                fetchLimit = 150
                            } else if self.fetchMode == "headers" {
                                fetchLimit = 50
                            }
                            
                            let startRange = max(first, last - fetchLimit)
                            addLog(serverId: server.id, serverName: server.name, type: "info", message: "Lade Header für \(group.name) (\(startRange) bis \(last), Modus: \(self.fetchMode))...")
                            let xoverRes = try await client.sendCommand("XOVER \(startRange)-\(last)", isMultiline: true)
                            let xoverLines = xoverRes.components(separatedBy: "\r\n")
                            
                            var groupHeaderCount = 0
                            for line in xoverLines {
                                if line == "." || line.isEmpty || line.hasPrefix("224") { continue }
                                let fields = line.components(separatedBy: "\t")
                                if fields.count >= 5 {
                                    let number = Int(fields[0]) ?? 0
                                    let subject = fields[1]
                                    let from = fields[2]
                                    let dateStr = fields[3]
                                    let rawId = fields[4]
                                    let messageId = rawId.replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
                                    let referencesStr = fields.count > 5 ? fields[5] : ""
                                    let references = referencesStr.components(separatedBy: .whitespaces)
                                        .filter { !$0.isEmpty }
                                        .map { $0.replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "") }
                                    
                                    // Parse date cleanly
                                    let date: Date
                                    let formatter = DateFormatter()
                                    formatter.locale = Locale(identifier: "en_US_POSIX")
                                    formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
                                    if let parsed = formatter.date(from: dateStr) {
                                        date = parsed
                                    } else {
                                        formatter.dateFormat = "d MMM yyyy HH:mm:ss Z"
                                        if let parsed = formatter.date(from: dateStr) {
                                            date = parsed
                                        } else {
                                            date = Date()
                                        }
                                    }
                                    
                                    let isDuplicate = self.articles.contains(where: { $0.id == messageId }) || newArticlesFromOutbox.contains(where: { $0.id == messageId })
                                    if !isDuplicate {
                                        var body = ""
                                        var downloaded = false
                                        
                                        if self.fetchMode != "headers" {
                                            do {
                                                let bodyRes = try await client.sendCommand("BODY <\(messageId)>", isMultiline: true)
                                                let lines = bodyRes.components(separatedBy: "\r\n")
                                                var bodyLines: [String] = []
                                                let startIdx = lines.first?.hasPrefix("222") == true ? 1 : 0
                                                for i in startIdx..<lines.count {
                                                    let line = lines[i]
                                                    if line == "." { break }
                                                    bodyLines.append(line)
                                                }
                                                body = bodyLines.joined(separator: "\n")
                                                downloaded = true
                                            } catch {
                                                print("Error downloading body during sync: \(error)")
                                            }
                                        }
                                        
                                        fetchedArticles.append(Article(
                                            id: messageId,
                                            number: number,
                                            newsgroup: group.name,
                                            serverId: server.id,
                                            subject: subject,
                                            from: from,
                                            date: date,
                                            body: body,
                                            references: references,
                                            read: false,
                                            ignored: false,
                                            downloaded: downloaded
                                        ))
                                        groupHeaderCount += 1
                                    }
                                }
                            }
                            if groupHeaderCount > 0 {
                                addLog(serverId: server.id, serverName: server.name, type: "success", message: "\(groupHeaderCount) neue(r) Header für \(group.name) geladen.")
                            } else {
                                addLog(serverId: server.id, serverName: server.name, type: "info", message: "Keine neuen Header in \(group.name).")
                            }
                        }
                    }
                }
                
                addLog(serverId: server.id, serverName: server.name, type: "success", message: "Synchronisation erfolgreich beendet!")
                
                await MainActor.run {
                    var updatedOutbox = self.outbox
                    for id in sentOutboxIds {
                        if let idx = updatedOutbox.firstIndex(where: { $0.id == id }) {
                            updatedOutbox[idx].status = "sent"
                        }
                    }
                    self.outbox = updatedOutbox
                    
                    var updatedArticles = self.articles
                    for art in newArticlesFromOutbox {
                        if !updatedArticles.contains(where: { $0.id == art.id }) {
                            updatedArticles.append(art)
                        }
                    }
                    for art in fetchedArticles {
                        if !updatedArticles.contains(where: { $0.id == art.id }) {
                            updatedArticles.append(art)
                        }
                    }
                    self.articles = updatedArticles
                    
                    // Automatically download bodies of all articles in subscribed threads!
                    let flaggedRootIds = Set(updatedArticles.filter { $0.flagged == true }.map { $0.references.first ?? $0.id })
                    let articlesToAutoDownload = updatedArticles.filter { art in
                        guard art.serverId == server.id else { return false }
                        let rootId = art.references.first ?? art.id
                        return flaggedRootIds.contains(rootId) && (!art.downloaded || art.body.isEmpty)
                    }
                    
                    if !articlesToAutoDownload.isEmpty {
                        self.addLog(serverId: server.id, serverName: "System", type: "info", message: "Abonnierte Threads: Starte automatischen Download von \(articlesToAutoDownload.count) neuen Beiträgen...")
                        for art in articlesToAutoDownload {
                            self.downloadArticleBody(articleId: art.id)
                        }
                    }
                    
                    self.isSyncing = false
                    self.recalcUnreadCounts()
                    self.saveState()
                }
                
            } catch {
                addLog(serverId: server.id, serverName: server.name, type: "error", message: "Synchronisation fehlgeschlagen: \(error.localizedDescription)")
                print("Sync failed: \(error)")
                await MainActor.run {
                    self.isSyncing = false
                    self.connectionError = "Synchronisation mit dem Server fehlgeschlagen:\n\(error.localizedDescription)"
                }
            }
            client.close()
        }
    }
    
    func fetchGroupsFromServer() {
        if isOffline {
            addLog(serverId: "local", serverName: "System", type: "error", message: "Gruppenliste abrufen abgebrochen: Sie sind offline.")
            connectionError = "Abrufen der Gruppenliste fehlgeschlagen: Sie sind im Offline-Modus. Bitte klicken Sie oben auf 'Status: Offline', um online zu gehen."
            return
        }
        guard !isFetchingGroups else { return }
        isFetchingGroups = true
        
        let activeServerId = self.selectedServerId ?? ""
        guard let server = self.servers.first(where: { $0.id == activeServerId }) else {
            if let firstServer = self.servers.first {
                self.selectedServerId = firstServer.id
                self.isFetchingGroups = false
                self.fetchGroupsFromServer()
            } else {
                isFetchingGroups = false
                addLog(serverId: "local", serverName: "System", type: "error", message: "Abrufen abgebrochen: Kein aktiver Server konfiguriert.")
                connectionError = "Abrufen der Gruppenliste fehlgeschlagen:\nKein Usenet-Server konfiguriert oder ausgewählt."
            }
            return
        }
        
        addLog(serverId: server.id, serverName: server.name, type: "info", message: "Abrufen der Gruppenliste gestartet...")
        
        Task {
            let client = SwiftNNTPClient()
            do {
                addLog(serverId: server.id, serverName: server.name, type: "info", message: "Verbinde mit \(server.host):\(server.port)...")
                let greeting = try await client.connect(host: server.host, port: server.port, useSSL: server.useSSL ?? false)
                addLog(serverId: server.id, serverName: server.name, type: "success", message: "Verbunden: \(greeting.trimmingCharacters(in: .whitespacesAndNewlines))")
                
                if let username = server.username, !username.isEmpty,
                   let password = server.password {
                    addLog(serverId: server.id, serverName: server.name, type: "info", message: "Sende Anmeldedaten (AUTHINFO)...")
                    let userRes = try await client.sendCommand("AUTHINFO USER \(username)")
                    if userRes.hasPrefix("381") {
                        _ = try await client.sendCommand("AUTHINFO PASS \(password)")
                    }
                }
                
                addLog(serverId: server.id, serverName: server.name, type: "info", message: "Fordere Liste der aktiven Newsgroups an (LIST ACTIVE)...")
                let groupsRes = try await client.sendCommand("LIST ACTIVE", isMultiline: true)
                let lines = groupsRes.components(separatedBy: "\r\n")
                
                var fetchedGroups: [Newsgroup] = []
                for line in lines {
                    if line == "." || line.isEmpty || line.hasPrefix("215") { continue }
                    let parts = line.components(separatedBy: .whitespaces)
                    if let name = parts.first, !name.isEmpty {
                        let id = "\(server.id).\(name)"
                        let isSubscribed = self.groups.contains(where: { $0.id == id && $0.subscribed })
                        fetchedGroups.append(Newsgroup(
                            id: id,
                            name: name,
                            serverId: server.id,
                            description: "Aktiv auf \(server.name)",
                            subscribed: isSubscribed,
                            unreadCount: 0
                        ))
                    }
                    if fetchedGroups.count >= 15000 { break }
                }
                
                addLog(serverId: server.id, serverName: server.name, type: "success", message: "\(fetchedGroups.count) Gruppen erfolgreich vom Server geladen.")
                
                await MainActor.run {
                    var updatedAvailable = self.availableGroups
                    for newG in fetchedGroups {
                        if let existingIdx = updatedAvailable.firstIndex(where: { $0.id == newG.id }) {
                            updatedAvailable[existingIdx].description = newG.description
                            updatedAvailable[existingIdx].subscribed = newG.subscribed
                        } else {
                            updatedAvailable.append(newG)
                        }
                    }
                    self.availableGroups = updatedAvailable
                    self.isFetchingGroups = false
                    self.saveAvailableGroups()
                }
            } catch {
                addLog(serverId: server.id, serverName: server.name, type: "error", message: "Fehler beim Abrufen der Gruppenliste: \(error.localizedDescription)")
                print("Error fetching groups from server: \(error)")
                await MainActor.run {
                    self.connectionError = "Abrufen der Gruppenliste fehlgeschlagen:\n\(error.localizedDescription)"
                    let cleanPrefix = server.name.lowercased()
                        .replacingOccurrences(of: " ", with: ".")
                        .replacingOccurrences(of: "(", with: "")
                        .replacingOccurrences(of: ")", with: "")
                        .filter { $0.isLetter || $0 == "." || $0.isNumber }
                    
                    let fallbackGroups = [
                        Newsgroup(id: "\(server.id).\(cleanPrefix).general", name: "\(cleanPrefix).general", serverId: server.id, description: "Allgemeine Diskussionen auf diesem Usenet-Server.", subscribed: false, unreadCount: 0),
                        Newsgroup(id: "\(server.id).\(cleanPrefix).news", name: "\(cleanPrefix).news", serverId: server.id, description: "Ankündigungen und Neuigkeiten des Betreibers.", subscribed: false, unreadCount: 0),
                        Newsgroup(id: "\(server.id).\(cleanPrefix).tech", name: "\(cleanPrefix).tech", serverId: server.id, description: "Technische Fragen, Hard- und Software Support.", subscribed: false, unreadCount: 0),
                        Newsgroup(id: "\(server.id).\(cleanPrefix).vintage", name: "\(cleanPrefix).vintage", serverId: server.id, description: "Nostalgie, historische Computer und Retro-Themen.", subscribed: false, unreadCount: 0)
                    ]
                    var updatedAvailable = self.availableGroups
                    for newG in fallbackGroups {
                        if !updatedAvailable.contains(where: { $0.id == newG.id }) {
                            updatedAvailable.append(newG)
                        }
                    }
                    self.availableGroups = updatedAvailable
                    self.isFetchingGroups = false
                    self.saveAvailableGroups()
                }
            }
            client.close()
        }
    }
    
    func downloadArticleBody(articleId: String) {
        guard let artIdx = articles.firstIndex(where: { $0.id == articleId }) else { return }
        let article = articles[artIdx]
        if article.downloaded && !article.body.isEmpty { return }
        
        guard let server = servers.first(where: { $0.id == article.serverId }) else { return }
        
        addLog(serverId: server.id, serverName: server.name, type: "info", message: "Lade Textkörper für Beitrag \"\(article.subject)\"...")
        
        Task {
            let client = SwiftNNTPClient()
            do {
                _ = try await client.connect(host: server.host, port: server.port, useSSL: server.useSSL ?? false)
                
                if let username = server.username, !username.isEmpty,
                   let password = server.password {
                    let userRes = try await client.sendCommand("AUTHINFO USER \(username)")
                    if userRes.hasPrefix("381") {
                        _ = try await client.sendCommand("AUTHINFO PASS \(password)")
                    }
                }
                
                _ = try await client.sendCommand("GROUP \(article.newsgroup)")
                
                let bodyRes = try await client.sendCommand("BODY <\(article.id)>", isMultiline: true)
                let lines = bodyRes.components(separatedBy: "\r\n")
                
                var bodyLines: [String] = []
                let startIdx = lines.first?.hasPrefix("222") == true ? 1 : 0
                for i in startIdx..<lines.count {
                    let line = lines[i]
                    if line == "." { break }
                    bodyLines.append(line)
                }
                
                let bodyContent = bodyLines.joined(separator: "\n")
                
                addLog(serverId: server.id, serverName: server.name, type: "success", message: "Textkörper für Beitrag erfolgreich geladen (\(bodyLines.count) Zeilen).")
                
                await MainActor.run {
                    if let idx = self.articles.firstIndex(where: { $0.id == articleId }) {
                        self.articles[idx].body = bodyContent
                        self.articles[idx].downloaded = true
                        self.saveState()
                    }
                }
            } catch {
                addLog(serverId: server.id, serverName: server.name, type: "error", message: "Fehler beim Download des Beitrags: \(error.localizedDescription)")
                print("Failed to download body: \(error)")
                await MainActor.run {
                    if let idx = self.articles.firstIndex(where: { $0.id == articleId }) {
                        self.articles[idx].body = "--- FEHLER BEIM DOWNLOAD ---\n\nServer: \(server.host)\nFehler: \(error.localizedDescription)\n\nBitte prüfen Sie Ihre Zugangsdaten in den Einstellungen."
                        self.articles[idx].downloaded = true
                        self.saveState()
                    }
                }
            }
            client.close()
        }
    }
    
    func downloadEntireThread(forArticleId articleId: String) {
        guard let selectedArt = articles.first(where: { $0.id == articleId }) else { return }
        
        let threadRootId: String = selectedArt.references.first ?? selectedArt.id
        
        let threadArticles = articles.filter { $0.id == threadRootId || $0.references.contains(threadRootId) }
        
        let toDownload = threadArticles.filter { !$0.downloaded || $0.body.isEmpty }
        
        guard !toDownload.isEmpty else { return }
        
        addLog(serverId: selectedArt.serverId, serverName: "System", type: "info", message: "Starte Download für \(toDownload.count) Beiträge im Thread...")
        
        for art in toDownload {
            downloadArticleBody(articleId: art.id)
        }
    }
    
    func recalcUnreadCounts() {
        // Precalculated dictionary mapping serverId|newsgroup to count of unread articles to optimize performance to O(A + G)
        var unreadCounts: [String: Int] = [:]
        for art in articles {
            if !art.read {
                let key = "\(art.serverId)|\(art.newsgroup)"
                unreadCounts[key, default: 0] += 1
            }
        }
        
        for idx in 0..<groups.count {
            let key = "\(groups[idx].serverId)|\(groups[idx].name)"
            groups[idx].unreadCount = unreadCounts[key] ?? 0
        }
    }
}

// MARK: - Native Swift NNTP TCP Client using Network Framework
import Network

class SwiftNNTPClient {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.spiceboard.nntp")
    private var buffer = Data()
    
    init() {}
    
    func connect(host: String, port: Int, useSSL: Bool = false) async throws -> String {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)))
        
        let parameters: NWParameters
        if useSSL || port == 563 {
            parameters = NWParameters(tls: NWProtocolTLS.Options())
        } else {
            parameters = NWParameters.tcp
        }
        
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection
        
        return try await withCheckedThrowingContinuation { continuation in
            var isFinished = false
            
            // Timeout Task after 8 seconds
            let timeoutWorkItem = DispatchWorkItem {
                guard !isFinished else { return }
                isFinished = true
                connection.cancel()
                continuation.resume(throwing: NSError(domain: "NNTP", code: -3, userInfo: [NSLocalizedDescriptionKey: "Verbindung fehlgeschlagen: Zeitüberschreitung (Timeout 8s)"]))
            }
            self.queue.asyncAfter(deadline: .now() + 8.0, execute: timeoutWorkItem)
            
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !isFinished else { return }
                    isFinished = true
                    timeoutWorkItem.cancel()
                    Task {
                        do {
                            let greeting = try await self.readResponse(isMultiline: false)
                            continuation.resume(returning: greeting)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                case .failed(let error):
                    guard !isFinished else { return }
                    isFinished = true
                    timeoutWorkItem.cancel()
                    continuation.resume(throwing: error)
                case .cancelled:
                    guard !isFinished else { return }
                    isFinished = true
                    timeoutWorkItem.cancel()
                    continuation.resume(throwing: NSError(domain: "NNTP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Verbindung abgebrochen"]))
                default:
                    break
                }
            }
            connection.start(queue: self.queue)
        }
    }
    
    func sendCommand(_ command: String, isMultiline: Bool = false) async throws -> String {
        guard let connection = connection else {
            throw NSError(domain: "NNTP", code: -2, userInfo: [NSLocalizedDescriptionKey: "Nicht verbunden"])
        }
        
        let data = (command + "\r\n").data(using: .utf8) ?? Data()
        
        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                Task {
                    do {
                        let response = try await self.readResponse(isMultiline: isMultiline)
                        continuation.resume(returning: response)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            })
        }
    }
    
    func sendPost(from: String, newsgroup: String, subject: String, body: String, references: [String], xFace: String?, messageId: String? = nil, replyTo: String? = nil, organisation: String? = nil, userAgent: String? = nil) async throws -> String {
        guard let connection = connection else {
            throw NSError(domain: "NNTP", code: -2, userInfo: [NSLocalizedDescriptionKey: "Nicht verbunden"])
        }
        
        let postReadyRes = try await sendCommand("POST", isMultiline: false)
        guard postReadyRes.hasPrefix("340") else {
            throw NSError(domain: "NNTP", code: -3, userInfo: [NSLocalizedDescriptionKey: "Posting nicht erlaubt: \(postReadyRes)"])
        }
        
        var postData = ""
        postData += "From: \(from)\r\n"
        postData += "Newsgroups: \(newsgroup)\r\n"
        postData += "Subject: \(subject)\r\n"
        postData += "MIME-Version: 1.0\r\n"
        postData += "Content-Type: text/plain; charset=UTF-8\r\n"
        postData += "Content-Transfer-Encoding: 8bit\r\n"
        if let repTo = replyTo, !repTo.isEmpty {
            postData += "Reply-To: \(repTo)\r\n"
        }
        if let org = organisation, !org.isEmpty {
            postData += "Organization: \(org)\r\n"
        }
        if let agent = userAgent, !agent.isEmpty {
            postData += "User-Agent: \(agent)\r\n"
        } else {
            postData += "User-Agent: SpiceBoard\r\n"
        }
        if let msgId = messageId {
            postData += "Message-ID: <\(msgId)>\r\n"
        }
        if !references.isEmpty {
            postData += "References: \(references.map { "<\($0)>" }.joined(separator: " "))\r\n"
        }
        if let xFace = xFace, !xFace.isEmpty {
            postData += "\(xFace)\r\n"
        }
        postData += "\r\n"
        postData += body
        postData += "\r\n.\r\n"
        
        let rawData = postData.data(using: .utf8) ?? Data()
        
        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: rawData, completion: .contentProcessed { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                Task {
                    do {
                        let response = try await self.readResponse(isMultiline: false)
                        continuation.resume(returning: response)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            })
        }
    }
    
    private func readResponse(isMultiline: Bool) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            var accumulated = Data()
            
            func readMore() {
                connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, context, isComplete, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if let data = data, !data.isEmpty {
                        accumulated.append(data)
                        
                        var finished = false
                        if isMultiline {
                            // Check if it is an error response (like 4xx or 5xx), which are single-line
                            if accumulated.count >= 3 {
                                let firstChar = accumulated[0]
                                // '4' is 52, '5' is 53
                                if firstChar == 52 || firstChar == 53 {
                                    if accumulated.count >= 2 && accumulated.suffix(2) == Data([13, 10]) {
                                        finished = true
                                    }
                                }
                            }
                            
                            if !finished {
                                // Check for standard NNTP multiline end markers
                                if accumulated.count >= 5 && accumulated.suffix(5) == Data([13, 10, 46, 13, 10]) {
                                    finished = true
                                } else if accumulated.count >= 3 && accumulated.suffix(3) == Data([10, 46, 10]) {
                                    finished = true
                                } else if accumulated.count >= 4 && (accumulated.suffix(4) == Data([10, 46, 13, 10]) || accumulated.suffix(4) == Data([13, 10, 46, 10])) {
                                    finished = true
                                }
                            }
                        } else {
                            // Single-line responses end with CRLF or LF
                            if accumulated.count >= 2 && accumulated.suffix(2) == Data([13, 10]) {
                                finished = true
                            } else if accumulated.count >= 1 && accumulated.suffix(1) == Data([10]) {
                                finished = true
                            }
                        }
                        
                        if finished {
                            let responseString = self.decodeSmart(accumulated)
                            continuation.resume(returning: responseString)
                            return
                        }
                    }
                    if isComplete {
                        if !accumulated.isEmpty {
                            let responseString = self.decodeSmart(accumulated)
                            continuation.resume(returning: responseString)
                        } else {
                            continuation.resume(throwing: NSError(domain: "NNTP", code: -4, userInfo: [NSLocalizedDescriptionKey: "Verbindung geschlossen"]))
                        }
                        return
                    }
                    readMore()
                }
            }
            readMore()
        }
    }
    
    private func decodeSmart(_ data: Data) -> String {
        if let utf8Str = String(data: data, encoding: .utf8) {
            return utf8Str
        }
        if let cp1252Str = String(data: data, encoding: .windowsCP1252) {
            return cp1252Str
        }
        if let latin1Str = String(data: data, encoding: .isoLatin1) {
            return latin1Str
        }
        return String(decoding: data, as: UTF8.self)
    }
    
    func close() {
        if let conn = connection {
            let data = "QUIT\r\n".data(using: .utf8) ?? Data()
            conn.send(content: data, completion: .contentProcessed { _ in })
            conn.cancel()
            self.connection = nil
        }
    }
}

import AppKit
import SwiftUI

extension Color {
    static var sysBackground: Color {
        return Color(nsColor: .windowBackgroundColor)
    }
    
    static var sysSecondaryBackground: Color {
        return Color(nsColor: .controlBackgroundColor)
    }
    
    static var sysSeparator: Color {
        return Color(nsColor: .separatorColor)
    }
    
    static var sysLabel: Color {
        return Color(nsColor: .labelColor)
    }
    
    static var sysGray4: Color {
        return Color(nsColor: .controlColor)
    }
}

