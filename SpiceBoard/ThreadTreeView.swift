import SwiftUI

// Internal child structures for final positions and connection lines at the top level
struct ThreadPosition: Identifiable {
    let id: String
    let article: Article
    let x: CGFloat
    let y: CGFloat
    let depth: Int
}

struct ThreadLine: Identifiable {
    let id: String
    let start: CGPoint
    let end: CGPoint
}

// Thread-safe and UI-thread bound calculation cache to prevent redundant layout calculations
class ThreadTreeCache {
    static let shared = ThreadTreeCache()
    
    private var lastArticles: [Article] = []
    
    private var cachedPositions: [ThreadPosition] = []
    private var cachedLines: [ThreadLine] = []
    
    func getPositionsAndLines(
        articles: [Article],
        calculatePositions: () -> [ThreadPosition],
        calculateLines: ([ThreadPosition]) -> [ThreadLine]
    ) -> ([ThreadPosition], [ThreadLine]) {
        if articles == lastArticles {
            return (cachedPositions, cachedLines)
        }
        
        lastArticles = articles
        let pos = calculatePositions()
        let lns = calculateLines(pos)
        cachedPositions = pos
        cachedLines = lns
        return (pos, lns)
    }
}

struct ThreadTreeView: View {
    let articles: [Article]
    let selectedArticleId: String
    let onSelect: (String) -> Void
    
    // Helper node class for organizing the logical tree hierarchy recursively
    private class ThreadNode {
        let id: String
        let article: Article
        var children: [ThreadNode] = []
        var depth: Int = 0
        
        init(id: String, article: Article) {
            self.id = id
            self.article = article
        }
    }
    
    @Environment(UsenetStore.self) private var store
    @State private var hoveredAuthor: String? = nil
    @State private var searchText: String = ""
    @State private var searchActiveIndex: Int = 0
    
    var body: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matchedArticles = articles.filter { art in
            if query.isEmpty { return false }
            return art.subject.lowercased().contains(query) ||
                   art.from.lowercased().contains(query) ||
                   art.body.lowercased().contains(query)
        }.sorted { $0.date < $1.date }
        let matchCount = matchedArticles.count

        VStack(alignment: .leading, spacing: 0) {
            // Read/Unread and Usenet actions toolbar for the active thread
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Button {
                        markThreadRead(true)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Thread gelesen")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        markThreadRead(false)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "circle")
                                .foregroundColor(.blue)
                            Text("Thread ungelesen")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            TextField("Suchen...", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 10))
                            if !searchText.isEmpty {
                                Button(action: { 
                                    searchText = ""
                                    searchActiveIndex = 0
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)
                        .frame(width: 130)
                        
                        if !searchText.isEmpty {
                            HStack(spacing: 4) {
                                Text("\(matchCount > 0 ? (searchActiveIndex % matchCount) + 1 : 0) / \(matchCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.orange)
                                    .frame(minWidth: 32)
                                
                                Button(action: {
                                    if matchCount > 0 {
                                        searchActiveIndex = (searchActiveIndex - 1 + matchCount) % matchCount
                                        onSelect(matchedArticles[searchActiveIndex].id)
                                    }
                                }) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.primary)
                                }
                                .buttonStyle(.plain)
                                .disabled(matchCount == 0)
                                
                                Button(action: {
                                    if matchCount > 0 {
                                        searchActiveIndex = (searchActiveIndex + 1) % matchCount
                                        onSelect(matchedArticles[searchActiveIndex].id)
                                    }
                                }) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.primary)
                                }
                                .buttonStyle(.plain)
                                .disabled(matchCount == 0)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    if let author = hoveredAuthor {
                        (Text("Autor: ") + highlightMatches(author, query: searchText, baseFont: .system(size: 10, weight: .bold)))
                            .foregroundColor(.blue)
                    } else {
                        Text("")
                            .font(.system(size: 9, design: .default))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Graphical Usenet Command Shortcuts for selected node
                if let selectedId = store.selectedArticleId,
                   let activeArt = store.articles.first(where: { $0.id == selectedId }) {
                    Divider()
                        .background(Color.sysSeparator)
                        .padding(.vertical, 2)
                    
                    HStack(spacing: 10) {
                        (Text("Auswahl: \"") + highlightMatches(activeArt.subject, query: searchText, baseFont: .system(size: 9.5, weight: .semibold)) + Text("\""))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        // Followup to Newsgroup (Antworten)
                        Button {
                            NotificationCenter.default.post(name: .triggerFollowup, object: nil)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrowshape.turn.up.left.2.fill")
                                Text("Antworten")
                                    .font(.system(size: 9.5, weight: .bold))
                            }
                            .foregroundColor(.teal)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.teal.opacity(0.08))
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        
                        // Reply to Author (Autor antworten)
                        Button {
                            NotificationCenter.default.post(name: .triggerReply, object: nil)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrowshape.turn.up.right")
                                Text("Autor antworten")
                                    .font(.system(size: 9.5, weight: .bold))
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.08))
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        
                        // Kill Thread
                        Button {
                            NotificationCenter.default.post(name: .triggerKillThread, object: nil)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "slash.circle")
                                Text(activeArt.ignored ? "Kill aufheben" : "Kill Thread")
                                    .font(.system(size: 9.5, weight: .bold))
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        
                        // Kill Branch
                        Button {
                            store.toggleKillBranch(for: activeArt.id)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.branch")
                                Text(activeArt.ignored ? "Zweig-Kill aufheben" : "Zweig killen")
                                    .font(.system(size: 9.5, weight: .bold))
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        
                        // Ignore Poster (Ignorieren)
                        Button {
                            NotificationCenter.default.post(name: .triggerIgnorePoster, object: nil)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "person.slash")
                                Text(store.isAuthorIgnored(sender: activeArt.from) ? "Freigeben" : "Ignorieren")
                                    .font(.system(size: 9.5, weight: .bold))
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.08))
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.sysSecondaryBackground)
            .overlay(Rectangle().fill(Color.sysSeparator).frame(height: 1), alignment: .bottom)
            
            // Layout Calculations and Rendering canvas (using a high-performance cache to prevent redundant UI layout cycles)
            let (positions, lines) = ThreadTreeCache.shared.getPositionsAndLines(
                articles: articles,
                calculatePositions: { self.calculatePositions() },
                calculateLines: { self.calculateLines(positions: $0) }
            )
            
            let contentWidth = positions.map(\.x).max() ?? 300
            let contentHeight = positions.map(\.y).max() ?? 100
            
            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    // Lines between nodes (Arbeitsweise SpiceBoard: ein Stück horizontal, dann vertikal, dann horizontal)
                    ForEach(lines) { line in
                        Path { path in
                            path.move(to: line.start)
                            if line.start.y == line.end.y {
                                path.addLine(to: line.end)
                            } else {
                                // Classic SpiceBoard style: Horizontal segment out (18px), vertical drop, horizontal in, BUT WITH ROUNDED CORNERS!
                                let r: CGFloat = 6.0
                                let startY = line.start.y
                                let endY = line.end.y
                                let startX = line.start.x
                                let cornerX = startX + 18
                                
                                // Step 1: Horizontal line from start towards the bend
                                path.addLine(to: CGPoint(x: cornerX - r, y: startY))
                                
                                // Step 2: Curve at the first bend
                                let goingDown = endY > startY
                                let bend1Control = CGPoint(x: cornerX, y: startY)
                                let bend1End = CGPoint(x: cornerX, y: goingDown ? startY + r : startY - r)
                                path.addQuadCurve(to: bend1End, control: bend1Control)
                                
                                // Step 3: Vertical line towards the second bend
                                path.addLine(to: CGPoint(x: cornerX, y: goingDown ? endY - r : endY + r))
                                
                                // Step 4: Curve at the second bend
                                let bend2Control = CGPoint(x: cornerX, y: endY)
                                let bend2End = CGPoint(x: cornerX + r, y: endY)
                                path.addQuadCurve(to: bend2End, control: bend2Control)
                                
                                // Step 5: Horizontal line to the end
                                path.addLine(to: line.end)
                            }
                        }
                        .stroke(Color.primary.opacity(searchText.isEmpty ? 0.7 : 0.2), lineWidth: 2.0)
                    }
                    
                    // Clickable nodes
                    ForEach(positions) { pos in
                        let isSelected = pos.id == selectedArticleId
                        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        let isMatch = query.isEmpty || 
                                      pos.article.subject.lowercased().contains(query) || 
                                      pos.article.from.lowercased().contains(query) || 
                                      pos.article.body.lowercased().contains(query)
                        
                        ZStack {
                            // Invisible oversized tap target helper (reliable click hitbox)
                            Color.clear
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                            
                            if pos.article.ignored {
                                // Killed/Ignored: Black circle with red cross
                                Circle()
                                    .fill(Color.primary)
                                    .frame(width: 14, height: 14)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: 2)
                                    )
                                
                                // Red Cross
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.red)
                            } else if !pos.article.downloaded {
                                // News headers only: Grey circle with grey border
                                Circle()
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(width: 14, height: 14)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.secondary.opacity(0.5), lineWidth: 1.5)
                                    )
                            } else if pos.article.read {
                                // Read: Hollow circle with dark boarder
                                Circle()
                                    .fill(Color.sysBackground)
                                    .frame(width: 14, height: 14)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary.opacity(0.7), lineWidth: 2)
                                    )
                            } else {
                                // Unread: Circle with outline and cross inside
                                Circle()
                                    .fill(Color.sysBackground)
                                    .frame(width: 14, height: 14)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: 2)
                                    )
                                
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(Color.primary)
                            }
                            
                            // Glowing Selection Ring (classic halo)
                            if isSelected {
                                Circle()
                                    .stroke(Color.blue, lineWidth: 2.5)
                                    .frame(width: 24, height: 24)
                            }
                            
                            // Glowing Search Highlight Ring
                            if !query.isEmpty && isMatch {
                                let isCurrentActiveMatch = searchActiveIndex < matchedArticles.count && matchedArticles[searchActiveIndex].id == pos.id
                                Circle()
                                    .stroke(isCurrentActiveMatch ? Color.red : Color.orange, lineWidth: isCurrentActiveMatch ? 3.0 : 2.0)
                                    .frame(width: isCurrentActiveMatch ? 22 : 20, height: isCurrentActiveMatch ? 22 : 20)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .opacity(isMatch ? 1.0 : 0.35)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect(pos.id)
                        }
                        .contextMenu {
                            Button(action: {
                                if let idx = store.articles.firstIndex(where: { $0.id == pos.id }) {
                                    store.articles[idx].read.toggle()
                                    store.recalcUnreadCounts()
                                }
                            }) {
                                Label(pos.article.read ? "Als ungelesen markieren" : "Als gelesen markieren", systemImage: pos.article.read ? "circle" : "checkmark.circle")
                            }
                            
                            Button(action: {
                                store.toggleKillThread(for: pos.id)
                            }) {
                                Label(pos.article.ignored ? "Thema Ignorieren aufheben" : "Thema Ignorieren / Kill", systemImage: "slash.circle")
                            }
                            
                            Button(action: {
                                store.toggleKillBranch(for: pos.id)
                            }) {
                                Label(pos.article.ignored ? "Zweig Ignorieren aufheben" : "Zweig Ignorieren / Kill", systemImage: "arrow.branch")
                            }
                            
                            Button(action: {
                                store.toggleIgnorePoster(from: pos.article.from)
                            }) {
                                Label(store.isAuthorIgnored(sender: pos.article.from) ? "Autor Ignorieren aufheben" : "Autor Ignorieren", systemImage: "person.slash")
                            }
                        }
                        .help("\(pos.article.subject) - \(pos.article.from)")
                        .onHover { isHovering in
                            if isHovering {
                                hoveredAuthor = pos.article.from
                            } else {
                                if hoveredAuthor == pos.article.from {
                                    hoveredAuthor = nil
                                }
                            }
                        }
                        .position(x: pos.x, y: pos.y)
                    }
                }
                .frame(width: contentWidth + 40, height: contentHeight + 40)
            }
            .background(Color.sysBackground)
        }
        .onChange(of: searchText) { _ in
            searchActiveIndex = 0
        }
    }
    
    private func highlightMatches(_ text: String, query: String, baseFont: Font) -> Text {
        guard !query.isEmpty else { return Text(text).font(baseFont) }
        
        var resultText = Text("")
        var currentIndex = text.startIndex
        let lowerQuery = query.lowercased()
        let lowerText = text.lowercased()
        
        while currentIndex < text.endIndex {
            let searchRange = currentIndex..<text.endIndex
            if let matchRange = lowerText.range(of: lowerQuery, range: searchRange) {
                // Text before match
                let before = String(text[currentIndex..<matchRange.lowerBound])
                if !before.isEmpty {
                    resultText = resultText + Text(before).font(baseFont)
                }
                
                // Match text
                let match = String(text[matchRange])
                resultText = resultText + Text(match)
                    .font(baseFont)
                    .foregroundColor(.orange)
                    .bold()
                    .underline()
                
                currentIndex = matchRange.upperBound
            } else {
                let after = String(text[searchRange])
                if !after.isEmpty {
                    resultText = resultText + Text(after).font(baseFont)
                }
                break
            }
        }
        return resultText
    }
    
    private func markThreadRead(_ isRead: Bool) {
        guard let activeArt = articles.first(where: { $0.id == selectedArticleId }) else { return }
        let rootId = activeArt.references.first ?? activeArt.id
        
        var updatedArticles = store.articles
        var modified = false
        for idx in updatedArticles.indices {
            let art = updatedArticles[idx]
            if art.id == rootId || art.references.contains(rootId) {
                updatedArticles[idx].read = isRead
                modified = true
            }
        }
        if modified {
            store.articles = updatedArticles
            store.recalcUnreadCounts()
        }
    }
    
    private func calculatePositions() -> [ThreadPosition] {
        guard !articles.isEmpty else { return [] }
        
        // Ensure only unique articles are processed to avoid Dictionary unique key crashes
        var seenIds = Set<String>()
        var uniqueArticles: [Article] = []
        for art in articles {
            if !seenIds.contains(art.id) {
                uniqueArticles.append(art)
                seenIds.insert(art.id)
            }
        }
        
        let articleMap = Dictionary(uniqueKeysWithValues: uniqueArticles.map { ($0.id, $0) })
        
        // 1. Reconstruct Node Tree Mapping
        var treeNodes: [String: ThreadNode] = [:]
        for art in uniqueArticles {
            treeNodes[art.id] = ThreadNode(id: art.id, article: art)
        }
        
        var roots: [ThreadNode] = []
        for art in uniqueArticles {
            guard let node = treeNodes[art.id] else { continue }
            var parentId: String? = nil
            
            if !art.references.isEmpty {
                for refId in art.references.reversed() {
                    if articleMap[refId] != nil {
                        parentId = refId
                        break
                    }
                }
            }
            
            if let pId = parentId, let parentNode = treeNodes[pId] {
                parentNode.children.append(node)
            } else {
                roots.append(node)
            }
        }
        
        // Sort roots by date
        roots.sort { $0.article.date < $1.article.date }
        
        // Find the root node of the thread for the selected article by tracing up in downloaded articles
        func findDownloadedRootId(for articleId: String) -> String {
            var currentId = articleId
            var visited = Set<String>()
            while let art = articleMap[currentId] {
                if visited.contains(currentId) { break }
                visited.insert(currentId)
                var parentId: String? = nil
                if !art.references.isEmpty {
                    for refId in art.references.reversed() {
                        if articleMap[refId] != nil {
                            parentId = refId
                            break
                        }
                    }
                }
                if let pId = parentId {
                    currentId = pId
                } else {
                    return currentId
                }
            }
            return currentId
        }

        let activeThreadId: String?
        if articleMap[selectedArticleId] != nil {
            activeThreadId = findDownloadedRootId(for: selectedArticleId)
        } else {
            activeThreadId = roots.first?.id
        }
        
        let filteredRoots = roots.filter { $0.id == activeThreadId }
        
        var subtreeRows: [String: Int] = [:]
        
        func calculateSubtreeRows(n: ThreadNode, depth: Int) -> Int {
            n.depth = depth
            if n.children.isEmpty {
                subtreeRows[n.id] = 1
                return 1
            }
            
            // Sort children by date order
            n.children.sort { $0.article.date < $1.article.date }
            
            var sum = 0
            for child in n.children {
                sum += calculateSubtreeRows(n: child, depth: depth + 1)
            }
            let total = max(1, sum)
            subtreeRows[n.id] = total
            return total
        }
        
        for root in filteredRoots {
            _ = calculateSubtreeRows(n: root, depth: 0)
        }
        
        var positionedNodes: [ThreadPosition] = []
        let paddingX: CGFloat = 30
        let paddingY: CGFloat = 24
        let colWidth: CGFloat = 54
        let rowHeight: CGFloat = 32
        
        func assignCoords(n: ThreadNode, x: CGFloat, startY: CGFloat) {
            let px = paddingX + (x - 1) * colWidth
            let py = paddingY + (startY - 1) * rowHeight
            
            positionedNodes.append(ThreadPosition(
                id: n.id,
                article: n.article,
                x: px,
                y: py,
                depth: n.depth
            ))
            
            var childY = startY
            for child in n.children {
                let rowsNeeded = CGFloat(subtreeRows[child.id] ?? 1)
                assignCoords(n: child, x: x + 1, startY: childY)
                childY += rowsNeeded
            }
        }
        
        var rootY: CGFloat = 1
        for root in filteredRoots {
            let rows = CGFloat(subtreeRows[root.id] ?? 1)
            assignCoords(n: root, x: 1, startY: rootY)
            rootY += rows
        }
        
        return positionedNodes
    }
    
    private func calculateLines(positions: [ThreadPosition]) -> [ThreadLine] {
        var lines: [ThreadLine] = []
        let posMap = Dictionary(uniqueKeysWithValues: positions.map { ($0.id, $0) })
        
        for pos in positions {
            // Find parent
            var parentId: String? = nil
            if !pos.article.references.isEmpty {
                // Find closest ancestor in positions using posMap for O(1) lookup
                for refId in pos.article.references.reversed() {
                    if posMap[refId] != nil {
                        parentId = refId
                        break
                    }
                }
            }
            
            guard let pId = parentId else { continue }
            guard let parentPos = posMap[pId] else { continue }
            
            lines.append(ThreadLine(
                id: "\(parentPos.id)-\(pos.id)",
                start: CGPoint(x: parentPos.x, y: parentPos.y),
                end: CGPoint(x: pos.x, y: pos.y)
            ))
        }
        
        return lines
    }
}
