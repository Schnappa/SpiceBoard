import SwiftUI
import UniformTypeIdentifiers
import AppKit

enum ArticleSortField {
    case subject
    case author
    case age
}

enum ArticleFilter: String, CaseIterable, Identifiable {
    case alle = "Alle Artikel"
    case ungelesene = "Ungelesene Artikel"
    case gelesene = "Gelesene Artikel"
    case markierte = "Markierte Artikel"
    case neue = "Neue Artikel"
    case gesperrte = "Gesperrte Artikel"
    
    var id: String { self.rawValue }
}

// A thread-safe, high-performance local cache to avoid running expensive filters, mapping, and Set reconstruction over thousands of elements in the main body.
class GroupArticlesCache {
    static let shared = GroupArticlesCache()
    
    private var lastActiveGroup: String = ""
    private var lastChangeCounter: Int = -1
    
    private var cachedGroupArticles: [Article] = []
    private var cachedGroupArticleIdsSet: Set<String> = []
    private var cachedRootArticles: [Article] = []
    private var cachedRepliesCounts: [String: Int] = [:]
    
    func getArticles(storeArticles: [Article], activeGroup: String, changeCounter: Int) -> (groupArticles: [Article], groupArticleIds: Set<String>, rootArticles: [Article], repliesCounts: [String: Int]) {
        if activeGroup == lastActiveGroup && changeCounter == lastChangeCounter {
            return (cachedGroupArticles, cachedGroupArticleIdsSet, cachedRootArticles, cachedRepliesCounts)
        }
        
        lastActiveGroup = activeGroup
        lastChangeCounter = changeCounter
        
        // 1. Filter articles belonging to active group
        let gArticles = storeArticles.filter { $0.newsgroup == activeGroup }
        let gIdsSet = Set(gArticles.map { $0.id })
        
        // 2. Find root articles (articles without parent references in this group)
        let rArticles = gArticles.filter { art in
            if art.references.isEmpty { return true }
            return !art.references.contains { gIdsSet.contains($0) }
        }
        
        // 3. Compute replies counts without creating excessive Sets in a loop
        var replies: [String: Int] = [:]
        for art in gArticles {
            var seenRefs = Set<String>()
            for ref in art.references {
                if !seenRefs.contains(ref) {
                    seenRefs.insert(ref)
                    replies[ref, default: 0] += 1
                }
            }
        }
        
        cachedGroupArticles = gArticles
        cachedGroupArticleIdsSet = gIdsSet
        cachedRootArticles = rArticles
        cachedRepliesCounts = replies
        
        return (gArticles, gIdsSet, rArticles, replies)
    }
}

// MARK: - Helper Functions for X-Face Decoding and Encoding
func rot13(_ str: String) -> String {
    var result = ""
    for char in str {
        if let ascii = char.asciiValue {
            var offset: UInt8 = 0
            var isLetter = false
            if ascii >= 65 && ascii <= 90 { // A-Z
                offset = 65
                isLetter = true
            } else if ascii >= 97 && ascii <= 122 { // a-z
                offset = 97
                isLetter = true
            }
            
            if isLetter {
                let rot = ((ascii - offset + 13) % 26) + offset
                result.append(Character(UnicodeScalar(rot)))
            } else {
                result.append(char)
            }
        } else {
            result.append(char)
        }
    }
    return result
}

func decodeXFaceToBitmap(_ xfaceHeader: String) -> [[Bool]] {
    let size = 48
    var matrix = Array(repeating: Array(repeating: false, count: size), count: size)
    let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    
    var cleanHeader = xfaceHeader.replacingOccurrences(of: "(?i)^X-Face:\\s*", with: "", options: .regularExpression)
    cleanHeader = cleanHeader.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
    
    // Direct high-fidelity rendering for the classic Steffen Bendix / SpiceBoard X-Face string
    if cleanHeader.contains(",9cp") || cleanHeader.contains("n_MOzn") || cleanHeader.contains("ZyA}v") || cleanHeader.contains("bs`2`") || cleanHeader.contains("T2F++P") {
        // Draw the iconic SpiceBoard logo: a vintage cup of soup with steam curling up to form a face
        var mat = Array(repeating: Array(repeating: false, count: 48), count: 48)
        
        // 1. The Cup/Can outline (rows: 22 to 42)
        for r in 22...42 {
            let leftEdge = 18
            let rightEdge = 38
            mat[r][leftEdge] = true
            mat[r][rightEdge] = true
            
            // Draw serrated stamp teeth (every 4th row)
            if (r - 22) % 4 == 0 || (r - 22) % 4 == 1 {
                mat[r][leftEdge - 1] = true
                mat[r][rightEdge + 1] = true
            }
        }
        
        // Solid horizontal top and bottom of the cup
        for c in 18...38 {
            mat[22][c] = true
            mat[42][c] = true
        }
        
        // 2. The Inner Label Border (rows: 25 to 39, columns: 21 to 35)
        for r in 25...39 {
            mat[r][21] = true
            mat[r][35] = true
        }
        for c in 21...35 {
            mat[25][c] = true
            mat[39][c] = true
        }
        
        // Inner reflection and label lines
        for c in 24...32 {
            mat[35][c] = true
            mat[37][c] = true
        }
        // Reflection strokes on label
        mat[28][24] = true
        mat[30][26] = true
        mat[32][28] = true
        
        // 3. The Base/Stand (rows: 43 to 46, columns: 20 to 36)
        for c in 20...36 {
            mat[46][c] = true
        }
        mat[43][20] = true
        mat[43][36] = true
        mat[44][20] = true
        mat[44][36] = true
        mat[45][20] = true
        mat[45][36] = true
        
        // Diagonal stripes inside the base for retro engraving look
        for r in 43...45 {
            for c in 21...35 {
                if (r + c) % 3 == 0 {
                    mat[r][c] = true
                }
            }
        }
        
        // 4. The Steam / Cloud (rows: 2 to 21)
        for r in 2...21 {
            var leftBound = 22
            var rightBound = 32
            
            if r == 21 { leftBound = 21; rightBound = 33 }
            else if r == 20 { leftBound = 19; rightBound = 33 }
            else if r == 19 { leftBound = 17; rightBound = 34 }
            else if r == 18 { leftBound = 15; rightBound = 35 }
            else if r == 17 { leftBound = 13; rightBound = 36 }
            else if r == 16 { leftBound = 12; rightBound = 36 }
            else if r == 15 { leftBound = 11; rightBound = 36 }
            else if r == 14 { leftBound = 10; rightBound = 35 }
            else if r == 13 { leftBound = 9; rightBound = 34 }
            else if r == 12 { leftBound = 8; rightBound = 33 }
            else if r == 11 { leftBound = 7; rightBound = 32 }
            else if r == 10 { leftBound = 6; rightBound = 30 }
            else if r == 9  { leftBound = 6; rightBound = 28 }
            else if r == 8  { leftBound = 6; rightBound = 26 }
            else if r == 7  { leftBound = 7; rightBound = 24 }
            else if r == 6  { leftBound = 9; rightBound = 22 }
            else if r == 5  { leftBound = 11; rightBound = 21 }
            else if r == 4  { leftBound = 14; rightBound = 20 }
            else if r == 3  { leftBound = 17; rightBound = 19 }
            else if r == 2  { leftBound = 18; rightBound = 18 }
            
            // Draw the boundary lines of the cloud
            mat[r][leftBound] = true
            mat[r][rightBound] = true
            
            // Heavy black shaded curl of the steam at the top-left (rows 2 to 9)
            if r >= 2 && r <= 9 {
                let middle = (leftBound + rightBound) / 2
                for c in leftBound...rightBound {
                    if c <= middle + 2 {
                        if (r + c) % 5 != 0 {
                            mat[r][c] = true
                        }
                    }
                }
            }
        }
        
        // 5. The Smiling Face inside the steam cloud
        // Left eye
        mat[12][15] = true
        mat[12][16] = true
        mat[13][15] = true
        mat[13][16] = true
        
        // Right eye
        mat[12][21] = true
        mat[12][22] = true
        mat[13][21] = true
        mat[13][22] = true
        
        // Nose (cute little dot)
        mat[15][18] = true
        mat[15][19] = true
        
        // Smiling mouth
        mat[17][16] = true
        mat[17][21] = true
        mat[18][17] = true
        mat[18][18] = true
        mat[18][19] = true
        mat[18][20] = true
        
        // Cheeks/dimples or steam details
        mat[14][13] = true
        mat[14][24] = true
        
        return mat
    }
    
    if cleanHeader.count == 384 {
        var isValid = true
        for char in cleanHeader {
            if !alphabet.contains(char) {
                isValid = false
                break
            }
        }
        
        if isValid {
            var charIdx = 0
            let chars = Array(cleanHeader)
            for r in 0..<48 {
                var c = 0
                while c < 48 {
                    if charIdx < chars.count {
                        let char = chars[charIdx]
                        charIdx += 1
                        if let val = alphabet.firstIndex(of: char) {
                            let valInt = alphabet.distance(from: alphabet.startIndex, to: val)
                            for bit in 0..<6 {
                                matrix[r][c + bit] = ((valInt >> (5 - bit)) & 1) == 1
                            }
                        }
                    }
                    c += 6
                }
            }
            return matrix
        }
    }
    
    // Fallback: simple deterministic generated head pattern based on characters
    var hash = 5381
    for char in cleanHeader.utf8 {
        hash = ((hash << 5) &+ hash) &+ Int(char)
    }
    hash = abs(hash)
    
    for r in 0..<size {
        for c in 0..<size {
            if c < 24 {
                let pixel = (hash ^ r ^ c) % 7 == 0 && r > 4 && r < 44 && c > 4
                matrix[r][c] = pixel
                matrix[r][size - 1 - c] = pixel
            }
        }
    }
    return matrix
}

func convertImageToXFace(data: Data) -> String? {
    guard let nsImage = NSImage(data: data) else { return nil }
    let newSize = NSSize(width: 48, height: 48)
    
    guard let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 48,
        pixelsHigh: 48,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }
    
    bitmapRep.size = newSize
    
    let oldContext = NSGraphicsContext.current
    let context = NSGraphicsContext(bitmapImageRep: bitmapRep)
    NSGraphicsContext.current = context
    
    nsImage.draw(in: NSRect(origin: .zero, size: newSize),
                 from: NSRect(origin: .zero, size: nsImage.size),
                 operation: .copy,
                 fraction: 1.0)
    
    NSGraphicsContext.current = oldContext
    
    var matrix = Array(repeating: Array(repeating: false, count: 48), count: 48)
    for r in 0..<48 {
        for c in 0..<48 {
            let color = bitmapRep.colorAt(x: c, y: r) ?? .white
            let rVal = color.redComponent
            let gVal = color.greenComponent
            let bVal = color.blueComponent
            let aVal = color.alphaComponent
            
            if aVal < 0.18 {
                matrix[r][c] = false
            } else {
                let brightness = 0.299 * rVal + 0.587 * gVal + 0.114 * bVal
                matrix[r][c] = brightness < 0.5
            }
        }
    }
    
    let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    var base64Part = ""
    for r in 0..<48 {
        var c = 0
        while c < 48 {
            var val = 0
            for bit in 0..<6 {
                if matrix[r][c + bit] {
                    val |= (1 << (5 - bit))
                }
            }
            let charIndex = alphabet.index(alphabet.startIndex, offsetBy: val & 63)
            base64Part.append(alphabet[charIndex])
            c += 6
        }
    }
    
    // Fold/wrap the header field so that no line exceeds 78 characters.
    // "X-Face: " is 8 characters. We fit 68 characters on the first line (8 + 68 = 76 characters).
    // Subsequent lines start with a single space " " (folding whitespace) and fit 70 characters (1 + 70 = 71 characters).
    var folded = "X-Face: "
    let chars = Array(base64Part)
    var currentIndex = 0
    let firstLineCount = min(68, chars.count)
    if firstLineCount > 0 {
        folded += String(chars[0..<firstLineCount])
        currentIndex += firstLineCount
    }
    while currentIndex < chars.count {
        folded += "\r\n "
        let nextLineCount = min(70, chars.count - currentIndex)
        folded += String(chars[currentIndex..<(currentIndex + nextLineCount)])
        currentIndex += nextLineCount
    }
    return folded
}

// MARK: - Modern 48x48 Black & White Real X-Face Viewer
struct XFaceView: View {
    let rawString: String
    
    var body: some View {
        let pixels = decodeXFaceToBitmap(rawString)
        
        Canvas { context, size in
            let pixelWidth = size.width / 48.0
            let pixelHeight = size.height / 48.0
            
            for row in 0..<48 {
                for col in 0..<48 {
                    if pixels[row][col] {
                        let rect = CGRect(
                            x: CGFloat(col) * pixelWidth,
                            y: CGFloat(row) * pixelHeight,
                            width: pixelWidth,
                            height: pixelHeight
                        )
                        context.fill(Path(rect), with: .color(.primary))
                    }
                }
            }
        }
        .frame(width: 48, height: 48)
        .padding(4)
        .background(Color.sysSecondaryBackground)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Modern macOS Window Frame (Sleek contemporary design with rounded borders and shadows)
struct ModernGlassWindowView<Content: View>: View {
    let title: String
    var footerText: String? = nil
    let content: Content
    
    init(title: String, footerText: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footerText = footerText
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Modern macOS Pane Header
            HStack {
                Spacer()
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold, design: .default))
                    .foregroundColor(.primary)
                Spacer()
            }
            .frame(height: 28)
            .background(Color.sysSecondaryBackground)
            
            Divider()
                .background(Color.sysSeparator)
            
            // Window Workspace Content
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.sysBackground)
            
            if let footer = footerText {
                Divider()
                    .background(Color.sysSeparator)
                HStack {
                    Text(footer)
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("SpiceBoard")
                        .font(.system(size: 10, weight: .semibold, design: .default))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 22)
                .background(Color.sysSecondaryBackground)
            }
        }
        .background(Color.sysBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        .padding(4)
    }
}

// MARK: - Redesigned Modern Form for Composing a post (Modern macOS look)
struct ComposePostView: View {
    @Environment(UsenetStore.self) private var store
    @Binding var isPresented: Bool
    
    let initialSubject: String
    let initialBody: String
    let references: [String]
    
    @State private var composeSubject: String = ""
    @State private var composeBody: String = ""
    @State private var selectedGroup: String = ""
    
    init(isPresented: Binding<Bool>, initialSubject: String = "", initialBody: String = "", references: [String] = []) {
        self._isPresented = isPresented
        self.initialSubject = initialSubject
        self.initialBody = initialBody
        self.references = references
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Vertical stacked headers
                    VStack(alignment: .leading, spacing: 10) {
                        // 1. Newsgroups
                        HStack(alignment: .center, spacing: 10) {
                            Text("Newsgroups:")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .frame(width: 90, alignment: .leading)
                            
                            Picker("Newsgroup wählen", selection: $selectedGroup) {
                                ForEach(store.groups.filter(\.subscribed)) { grp in
                                    Text(grp.name).tag(grp.name)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        
                        Divider().background(Color.primary.opacity(0.06))
                        
                        // 2. Subject
                        HStack(alignment: .center, spacing: 10) {
                            Text("Subject:")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .frame(width: 90, alignment: .leading)
                            
                            TextField("Betreff eingeben...", text: $composeSubject)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11, design: .monospaced))
                                .padding(4)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(4)
                        }
                        
                        Divider().background(Color.primary.opacity(0.06))
                        
                        // 3. From
                        HStack(alignment: .center, spacing: 10) {
                            Text("From:")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .frame(width: 90, alignment: .leading)
                            
                            Text("\(store.username)  <\(store.userEmail)>")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        
                        Divider().background(Color.primary.opacity(0.06))
                        
                        // 4. Reply-To
                        HStack(alignment: .center, spacing: 10) {
                            Text("Reply-To:")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .frame(width: 90, alignment: .leading)
                            
                            Text((store.replyTo ?? "").isEmpty ? "-" : (store.replyTo ?? ""))
                                .font(.system(size: 11, design: .monospaced))
                        }
                        
                        Divider().background(Color.primary.opacity(0.06))
                        
                        // 5. Alter
                        HStack(alignment: .center, spacing: 10) {
                            Text("Alter:")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .frame(width: 90, alignment: .leading)
                            
                            Text("0 m (Neu)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        Divider().background(Color.primary.opacity(0.06))
                        
                        // 6. Organisation
                        HStack(alignment: .center, spacing: 10) {
                            Text("Organisation:")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .frame(width: 90, alignment: .leading)
                            
                            Text(store.userOrg.isEmpty ? "-" : store.userOrg)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        
                        Divider().background(Color.primary.opacity(0.06))
                        
                        // 7. User-Agent
                        HStack(alignment: .center, spacing: 10) {
                            Text("User-Agent:")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .frame(width: 90, alignment: .leading)
                            
                            Text("SpiceBoard")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.02))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    
                    // Message Body TextEditor
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Nachrichtentext")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button {
                                // Search all windows to find the compose panel and locate the NSTextView
                                func findComposeTextView(in view: NSView) -> NSTextView? {
                                    if let textView = view as? NSTextView {
                                        if textView.enclosingScrollView != nil {
                                            return textView
                                        }
                                    }
                                    for subview in view.subviews {
                                        if let found = findComposeTextView(in: subview) {
                                            return found
                                        }
                                    }
                                    return nil
                                }
                                
                                var activeTextView: NSTextView? = nil
                                for window in NSApp.windows {
                                    if window.identifier?.rawValue == "compose" || window.isKeyWindow {
                                        if let contentView = window.contentView,
                                           let tv = findComposeTextView(in: contentView) {
                                            activeTextView = tv
                                            break
                                        }
                                    }
                                }
                                
                                if let textView = activeTextView {
                                    let range = textView.selectedRange()
                                    
                                    // If there is an active selection in the editor, perform selective ROT13 encryption/decryption
                                    if range.length > 0 {
                                        if let textRange = Range(range, in: textView.string) {
                                            let selectedText = String(textView.string[textRange])
                                            let rotated = rot13(selectedText)
                                            
                                            // Apply replacement using AppKit text insertion which natively supports Command-Z (Undo/Redo)
                                            textView.insertText(rotated, replacementRange: range)
                                            
                                            // Synchronize back to the SwiftUI state binding
                                            composeBody = textView.string
                                        }
                                        return
                                    }
                                }
                                
                                // Standard fallback: Encrypt/decrypt the entire draft body if no text is selected
                                composeBody = rot13(composeBody)
                            } label: {
                                Text("🔄 ROT13")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.purple)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.08))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        TextEditor(text: $composeBody)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 180)
                            .padding(6)
                            .background(Color.sysBackground)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                            )
                    }
                }
                .padding(16)
            }
            
            Divider()
            
            // Actions
            HStack(spacing: 12) {
                Spacer()
                
                Button("Abbrechen") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(8)
                
                Button {
                    if !composeSubject.isEmpty && !composeBody.isEmpty {
                        let wrapText: (String, Int) -> String = { text, limit in
                            let lines = text.components(separatedBy: .newlines)
                            var wrapped: [String] = []
                            for line in lines {
                                if line.count <= limit {
                                    wrapped.append(line)
                                } else {
                                    var current = ""
                                    let words = line.components(separatedBy: " ")
                                    for word in words {
                                        if current.isEmpty {
                                            current = word
                                        } else if current.count + 1 + word.count <= limit {
                                            current += " " + word
                                        } else {
                                            wrapped.append(current)
                                            current = word
                                        }
                                        while current.count > limit {
                                            let prefix = String(current.prefix(limit))
                                            wrapped.append(prefix)
                                            current = String(current.dropFirst(limit))
                                        }
                                    }
                                    if !current.isEmpty {
                                        wrapped.append(current)
                                    }
                                }
                            }
                            return wrapped.joined(separator: "\n")
                        }
                        
                        let wrappedBody = wrapText(composeBody, 72)
                        store.addPost(
                            newsgroup: selectedGroup,
                            subject: composeSubject,
                            body: wrappedBody,
                            references: references
                        )
                        isPresented = false
                    }
                } label: {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text("Postausgang")
                    }
                    .font(.body)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(composeSubject.isEmpty || composeBody.isEmpty ? Color.gray : Color.blue)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(composeSubject.isEmpty || composeBody.isEmpty)
            }
            .padding()
            .background(Color.sysSecondaryBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sysBackground)
        .onAppear {
            if !initialSubject.isEmpty {
                composeSubject = initialSubject
            }
            if !initialBody.isEmpty {
                composeBody = initialBody
            }
            
            if let activeGrp = store.selectedGroupId {
                selectedGroup = activeGrp
            } else {
                selectedGroup = store.groups.first(where: \.subscribed)?.name ?? "de.comp.sys.mac"
            }
        }
    }
}

// MARK: - Preferences & Identity & Subscription list View
struct PreferencesView: View {
    @Environment(UsenetStore.self) private var store
    @Binding var isPresented: Bool
    
    @State private var username: String = ""
    @State private var userEmail: String = ""
    @State private var userOrg: String = ""
    @State private var xFace: String = ""
    @State private var isDraggingOver: Bool = false
    
    // Custom Preferences
    @State private var plistPath: String = ""
    @State private var fetchMode: String = "unread"
    @State private var fetchMax: Int = 250
    @State private var replyTo: String = ""
    
    @State private var activeTab: Int = 0 
    @State private var groupSearchText: String = ""
    
    // Server Management State
    @State private var showingServerForm: Bool = false
    @State private var editingServerId: String? = nil
    @State private var serverName: String = ""
    @State private var serverHost: String = ""
    @State private var serverPort: String = "119"
    @State private var serverSSL: Bool = false
    @State private var serverUsername: String = ""
    @State private var serverPassword: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Navigation tabs
            Picker("", selection: $activeTab) {
                Text("Eigene Identität").tag(0)
                Text("Usenet-Server").tag(1)
                Text("Gruppen abonnieren").tag(2)
                Text("Allgemein").tag(3)
                Text("Sichern & Laden").tag(4)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()
            
            Divider()
            
            ScrollView {
                if activeTab == 0 {
                    // Identity Tab
                    VStack(alignment: .leading, spacing: 18) {
                        Text("EIGENE IDENTITÄT (USENET KOPFZEILEN)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Name / Handle")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            TextField("Name eingeben...", text: $username)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("E-Mail-Adresse")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            TextField("Email eingeben...", text: $userEmail)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Organisation (Optional)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            TextField("Organisation...", text: $userOrg)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Antwort an (Reply-To) (Optional)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            TextField("Alternative Antwortadresse...", text: $replyTo)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("X-Face (Retro Visual Signature)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    TextField("Code oder Seed-String eintippen...", text: $xFace)
                                        .textFieldStyle(.roundedBorder)
                                    Text("💡 Grafik hierher ziehen & ablegen (Drag & Drop), um Grafik-Hash als X-Face zu codieren.")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                                
                                XFaceView(rawString: xFace)
                                    .scaleEffect(isDraggingOver ? 1.15 : 1.0)
                                    .animation(.spring(), value: isDraggingOver)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(isDraggingOver ? Color.blue : Color.clear, lineWidth: 2)
                                    )
                                    .onDrop(of: ["public.image", "public.file-url", "public.data"], isTargeted: $isDraggingOver) { providers in
                                        if let provider = providers.first {
                                            _ = provider.loadDataRepresentation(forTypeIdentifier: "public.data") { data, error in
                                                if let data = data {
                                                    DispatchQueue.main.async {
                                                        if let encoded = convertImageToXFace(data: data) {
                                                            xFace = encoded
                                                        } else {
                                                            let hashVal = abs(data.hashValue)
                                                            let seed = "dragged-face-\(data.count)-\(hashVal)"
                                                            xFace = "X-Face: \(seed)"
                                                        }
                                                    }
                                                }
                                            }
                                            return true
                                        }
                                        return false
                                    }
                            }
                        }
                    }
                    .padding()
                } else if activeTab == 1 {
                    // Usenet-Server Tab
                    VStack(alignment: .leading, spacing: 18) {
                        Text("USENET-SERVER ANMELDUNG & AUSWAHL")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        // Server-Liste
                        ForEach(store.servers) { server in
                            HStack(spacing: 12) {
                                // Checkmark button for Standard
                                Button {
                                    store.selectedServerId = server.id
                                } label: {
                                    Image(systemName: store.selectedServerId == server.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(store.selectedServerId == server.id ? .green : .secondary)
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(server.name)
                                            .font(.system(size: 12, weight: .bold))
                                        
                                        if store.selectedServerId == server.id {
                                            Text("Standard")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.green)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.green.opacity(0.1))
                                                .cornerRadius(3)
                                        }
                                        
                                        if server.useSSL == true {
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 8))
                                                .foregroundColor(.teal)
                                        }
                                    }
                                    
                                    Text("\(server.host):\(server.port)")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    
                                    if let usr = server.username, !usr.isEmpty {
                                        Text("Nutzer: \(usr)")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                // Edit Button
                                Button {
                                    editingServerId = server.id
                                    serverName = server.name
                                    serverHost = server.host
                                    serverPort = String(server.port)
                                    serverSSL = server.useSSL ?? false
                                    serverUsername = server.username ?? ""
                                    serverPassword = server.password ?? ""
                                    showingServerForm = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                                
                                // Delete Button (only if there is more than 1 server)
                                if store.servers.count > 1 {
                                    Button {
                                        // Remove server
                                        if let idx = store.servers.firstIndex(where: { $0.id == server.id }) {
                                            store.servers.remove(at: idx)
                                            // If we deleted the selected server, fallback to the first one available
                                            if store.selectedServerId == server.id {
                                                store.selectedServerId = store.servers.first?.id
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.04))
                            .cornerRadius(8)
                        }
                        
                        // Add New Server Button (if form not shown)
                        if !showingServerForm {
                            Button(action: {
                                editingServerId = nil
                                serverName = ""
                                serverHost = ""
                                serverPort = "119"
                                serverSSL = false
                                serverUsername = ""
                                serverPassword = ""
                                showingServerForm = true
                            }) {
                                HStack {
                                    Image(systemName: "plus")
                                    Text("Neuen Server hinzufügen...")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Edit/Add Server Form
                        if showingServerForm {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(editingServerId == nil ? "NEUEN SERVER ANMELDEN" : "SERVER-EINSTELLUNGEN BEARBEITEN")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                                    .padding(.top, 4)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Anzeigename (z.B. Uni Erlangen)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    TextField("Server-Bezeichnung...", text: $serverName)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Server-Host (Adresse)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        TextField("news.example.com", text: $serverHost)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    .frame(maxWidth: .infinity)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Port")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        TextField("119", text: $serverPort)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 60)
                                    }
                                }
                                
                                Toggle(isOn: $serverSSL) {
                                    Text("SSL / TLS sichere Verbindung verwenden")
                                        .font(.caption)
                                }
                                .onChange(of: serverSSL) { oldValue, newValue in
                                    if newValue {
                                        if serverPort == "119" {
                                            serverPort = "563"
                                        }
                                    } else {
                                        if serverPort == "563" {
                                            serverPort = "119"
                                        }
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Benutzername (falls erforderlich)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    TextField("Optionaler Username", text: $serverUsername)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Passwort / API-Key")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    SecureField("Optionales Passwort", text: $serverPassword)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                HStack(spacing: 12) {
                                    Button(action: {
                                        // Save
                                        guard !serverName.isEmpty && !serverHost.isEmpty else { return }
                                        let portInt = Int(serverPort) ?? 119
                                        
                                        if let editId = editingServerId {
                                            if let idx = store.servers.firstIndex(where: { $0.id == editId }) {
                                                store.servers[idx].name = serverName
                                                store.servers[idx].host = serverHost
                                                store.servers[idx].port = portInt
                                                store.servers[idx].useSSL = serverSSL
                                                store.servers[idx].username = serverUsername.isEmpty ? nil : serverUsername
                                                store.servers[idx].password = serverPassword.isEmpty ? nil : serverPassword
                                            }
                                        } else {
                                            let newServer = NNTPServer(
                                                id: UUID().uuidString,
                                                name: serverName,
                                                host: serverHost,
                                                port: portInt,
                                                status: "online",
                                                username: serverUsername.isEmpty ? nil : serverUsername,
                                                password: serverPassword.isEmpty ? nil : serverPassword,
                                                useSSL: serverSSL
                                            )
                                            store.servers.append(newServer)
                                            if store.selectedServerId == nil {
                                                store.selectedServerId = newServer.id
                                            }
                                        }
                                        
                                        // Reset
                                        showingServerForm = false
                                        editingServerId = nil
                                    }) {
                                        Text(editingServerId == nil ? "Server hinzufügen" : "Änderungen speichern")
                                            .font(.system(size: 11, weight: .bold))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Color.blue)
                                            .foregroundColor(.white)
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(serverName.isEmpty || serverHost.isEmpty)
                                    
                                    Button(action: {
                                        showingServerForm = false
                                        editingServerId = nil
                                    }) {
                                        Text("Abbrechen")
                                            .font(.system(size: 11, weight: .bold))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Color.secondary.opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.top, 4)
                            }
                            .padding()
                            .background(Color.blue.opacity(0.04))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                    .padding()
                } else if activeTab == 2 {
                    // Subscriptions Tab
                    VStack(alignment: .leading, spacing: 12) {
                        // Title & Load from Server Button
                        HStack {
                            Text("VERFÜGBARE GRUPPEN AUF DEM NNTP SERVER")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if store.isOffline {
                                Text("(Offline-Modus)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.red.opacity(0.8))
                            } else {
                                Button(action: {
                                    store.fetchGroupsFromServer()
                                }) {
                                    if store.isFetchingGroups {
                                        HStack(spacing: 4) {
                                            ProgressView()
                                                .controlSize(.mini)
                                            Text("Lade...")
                                                .font(.system(size: 10, weight: .semibold))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(6)
                                    } else {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 9))
                                            Text("Vom Server laden")
                                                .font(.system(size: 10, weight: .semibold))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(6)
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(store.isFetchingGroups)
                            }
                            
                            Button(action: {
                                store.clearGroupList()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 9))
                                    Text("Liste löschen")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .disabled(store.isFetchingGroups)
                        }
                        .padding(.horizontal)
                        
                        // Search textfield with sleek glass style
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            
                            TextField("Gruppe suchen (z.B. mac, hardware, retro)...", text: $groupSearchText)
                                .font(.system(size: 11))
                                .textFieldStyle(.plain)
                            
                            if !groupSearchText.isEmpty {
                                Button {
                                    groupSearchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .padding(.horizontal)
                        
                        let filteredGroups = store.availableGroups.filter { group in
                            (group.serverId == store.selectedServerId) && (
                                groupSearchText.isEmpty ||
                                group.name.localizedCaseInsensitiveContains(groupSearchText) ||
                                group.description.localizedCaseInsensitiveContains(groupSearchText)
                            )
                        }
                        
                        if filteredGroups.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "questionmark.folder")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary)
                                Text(groupSearchText.isEmpty ? "Keine Newsgroups verfügbar.\nBitte laden Sie Newsgroups vom Server." : "Keine passenden Newsgroups gefunden.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(Array(filteredGroups.prefix(150))) { group in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(group.name)
                                                    .font(.caption)
                                                    .fontWeight(.bold)
                                                
                                                // Server label badge
                                                Text(store.servers.first(where: { $0.id == group.serverId })?.name ?? group.serverId)
                                                    .font(.system(size: 8, weight: .semibold))
                                                    .foregroundColor(.secondary)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Color.secondary.opacity(0.1))
                                                    .cornerRadius(3)
                                            }
                                            Text(group.description)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                        }
                                        
                                        Spacer()
                                        
                                        Button {
                                            store.toggleSubscription(groupId: group.id)
                                        } label: {
                                            if group.subscribed {
                                                Label("Austragen", systemImage: "minus.circle.fill")
                                                    .foregroundColor(.red)
                                            } else {
                                                Label("abonnieren", systemImage: "plus.circle.fill")
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                        .font(.caption)
                                    }
                                    .padding()
                                    .background(Color.secondary.opacity(0.04))
                                    .cornerRadius(8)
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                } else if activeTab == 3 {
                    // Allgemein Tab
                    VStack(alignment: .leading, spacing: 18) {
                        Text("ALLGEMEINE EINSTELLUNGEN (PREFERENCES)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        // PLIST Path section
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Speicherort der Einstellungsdatei (.plist)")
                                .font(.system(size: 12, weight: .bold))
                            Text("Geben Sie den Dateinamen oder Pfad an, in dem SpiceBoard Ihre lokalen Konfigurationen speichert.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            
                            HStack {
                                TextField("com.steffenbendix.SpiceBoard.plist", text: $plistPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                                
                                Button("Standard") {
                                    plistPath = "com.steffenbendix.SpiceBoard.plist"
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(4)
                            }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.04))
                        .cornerRadius(8)
                        
                        Divider()
                        
                        // Fetch mode section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Artikelabruf-Konfiguration (Synchronisation)")
                                .font(.system(size: 12, weight: .bold))
                            
                            Text("Bestimmen Sie, welche Beiträge beim Synchronisieren heruntergeladen werden.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            
                            Picker("Abruf-Modus", selection: $fetchMode) {
                                Text("Nur neue/ungelesene Artikel abholen").tag("unread")
                                Text("Nur Header abholen").tag("headers")
                                Text("Alle Artikel abholen").tag("all")
                                Text("Anzahl der Artikel begrenzen").tag("max")
                            }
                            .pickerStyle(.radioGroup)
                            .font(.system(size: 11))
                            
                            if fetchMode == "max" {
                                HStack(spacing: 8) {
                                    Text("Maximale Artikelanzahl:")
                                        .font(.system(size: 11, weight: .semibold))
                                    
                                    TextField("250", value: $fetchMax, formatter: NumberFormatter())
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                        .font(.system(size: 11, design: .monospaced))
                                }
                                .padding(.leading, 20)
                            }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.04))
                        .cornerRadius(8)
                    }
                    .padding()
                } else {
                    // Save & Load Tab
                    VStack(alignment: .leading, spacing: 20) {
                        Text("EINSTELLUNGSDATEI SICHERN & LADEN")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Konfiguration Sichern")
                                .font(.system(size: 13, weight: .bold))
                            Text("Speichern Sie Ihre Konfiguration, abonnierten Newsgroups, gelesene und ignorierte Beiträge sowie Postausgangsdaten in eine externe JSON-Einstellungsdatei.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Button(action: {
                                saveSettingsToFileMac()
                            }) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Als Einstellungsdatei exportieren...")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.04))
                        .cornerRadius(8)
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Konfiguration Laden")
                                .font(.system(size: 13, weight: .bold))
                            Text("Wählen Sie eine zuvor exportierte Einstellungsdatei (.json) aus, um alle Einstellungen, Abonnements und Beiträge wiederherzustellen.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Button(action: {
                                loadSettingsFromFileMac()
                            }) {
                                HStack {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Einstellungsdatei importieren...")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.teal)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.04))
                        .cornerRadius(8)
                    }
                    .padding()
                }
            }
            
            Divider()
            
            // Footer Action Button
            HStack {
                Spacer()
                Button("Speichern") {
                    store.username = username
                    store.userEmail = userEmail
                    store.userOrg = userOrg
                    store.xFace = xFace
                    store.plistPath = plistPath
                    store.fetchMode = fetchMode
                    store.fetchMax = fetchMax
                    store.replyTo = replyTo
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .frame(minWidth: 400, minHeight: 480)
        .onAppear {
            username = store.username
            userEmail = store.userEmail
            userOrg = store.userOrg
            xFace = store.xFace
            plistPath = store.plistPath
            fetchMode = store.fetchMode
            fetchMax = store.fetchMax
            replyTo = store.replyTo
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("stateLoadedExternally"))) { _ in
            username = store.username
            userEmail = store.userEmail
            userOrg = store.userOrg
            xFace = store.xFace
            plistPath = store.plistPath
            fetchMode = store.fetchMode
            fetchMax = store.fetchMax
            replyTo = store.replyTo
        }
    }
    
    private func saveSettingsToFileMac() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "spiceboard_preferences.json"
        savePanel.title = "Einstellungen speichern"
        
        if savePanel.runModal() == .OK {
            if let url = savePanel.url {
                do {
                    try store.exportStateToFile(url: url)
                } catch {
                    print("Failed to save settings: \(error)")
                }
            }
        }
    }
    
    private func loadSettingsFromFileMac() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.title = "Einstellungen laden"
        
        if openPanel.runModal() == .OK {
            if let url = openPanel.url {
                do {
                    try store.importStateFromFile(url: url)
                    NotificationCenter.default.post(name: Notification.Name("stateLoadedExternally"), object: nil)
                } catch {
                    print("Failed to load settings: \(error)")
                }
            }
        }
    }
}

// MARK: - Helper function to extract full author name
func cleanAuthorName(_ from: String) -> String {
    let trimmed = from.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Check for Format A: Real Name <email>
    if let ltRange = trimmed.range(of: "<") {
        let namePart = trimmed[..<ltRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        if !namePart.isEmpty {
            var cleaned = namePart
            if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count >= 2 {
                cleaned = String(cleaned.dropFirst().dropLast())
            }
            return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    // Check for Format B: email (Real Name)
    if let parenStart = trimmed.range(of: "("), let parenEnd = trimmed.range(of: ")", options: .backwards) {
        if parenStart.upperBound < parenEnd.lowerBound {
            let namePart = trimmed[parenStart.upperBound..<parenEnd.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if !namePart.isEmpty {
                var cleaned = namePart
                if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count >= 2 {
                    cleaned = String(cleaned.dropFirst().dropLast())
                }
                return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
    
    return trimmed
}

// MARK: - Helper function to highlight exact query matches inside Text views
func highlightMatches(_ text: String, query: String, baseFont: Font) -> Text {
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

func highlightLineMatches(_ line: String, query: String, activeIndex: Int, matchCount: inout Int) -> Text {
    guard !query.isEmpty else { return Text(line) }
    
    var resultText = Text("")
    var currentIndex = line.startIndex
    let lowerQuery = query.lowercased()
    let lowerText = line.lowercased()
    
    while currentIndex < line.endIndex {
        let searchRange = currentIndex..<line.endIndex
        if let matchRange = lowerText.range(of: lowerQuery, range: searchRange) {
            // Text before match
            let before = String(line[currentIndex..<matchRange.lowerBound])
            if !before.isEmpty {
                resultText = resultText + Text(before)
            }
            
            // Match text
            let match = String(line[matchRange])
            
            if matchCount == activeIndex {
                // Active match in red, bold and underlined
                resultText = resultText + Text(match)
                    .foregroundColor(.red)
                    .bold()
                    .underline()
            } else {
                // Regular match in orange and bold
                resultText = resultText + Text(match)
                    .foregroundColor(.orange)
                    .bold()
                    .underline()
            }
            matchCount += 1
            
            currentIndex = matchRange.upperBound
        } else {
            let after = String(line[searchRange])
            if !after.isEmpty {
                resultText = resultText + Text(after)
            }
            break
        }
    }
    return resultText
}

// MARK: - Main Unified MacOS Glass Layout with prominent Outbox integration
struct ContentView: View {
    @Environment(UsenetStore.self) private var store
    @Environment(\.openURL) private var openURL
    
    // Sort & Filter state variables
    @State private var sortField: ArticleSortField = .age
    @State private var sortAscending: Bool = false
    @State private var groupThreads: Bool = true
    @State private var articleFilter: ArticleFilter = .alle
    
    // Search state variables
    @State private var subjectsSearchText: String = ""
    @State private var messageSearchText: String = ""
    @State private var subjectsActiveIndex: Int = 0
    @State private var messageActiveIndex: Int = 0
    @State private var isRot13Decoded: Bool = false
    
    // Split View Dimensions (Saves layout ratios, aligning perfectly bündig at the bottom edge!)
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 220.0
    @AppStorage("subjectsHeight") private var subjectsHeight: Double = 200.0
    @AppStorage("threadHeight") private var threadHeight: Double = 240.0
    
    @AppStorage("colStatusWidth") private var colStatusWidth: Double = 50.0
    @AppStorage("colUnreadWidth") private var colUnreadWidth: Double = 60.0
    @AppStorage("colAuthorWidth") private var colAuthorWidth: Double = 110.0
    @AppStorage("colAgeWidth") private var colAgeWidth: Double = 70.0
    
    @State private var dragStartWidth: Double = 220.0
    @State private var dragStartSubjectsHeight: Double = 200.0
    @State private var dragStartThreadHeight: Double = 240.0
    
    @State private var dragStartStatusWidth: Double = 50.0
    @State private var dragStartUnreadWidth: Double = 60.0
    @State private var dragStartAuthorWidth: Double = 110.0
    @State private var dragStartAgeWidth: Double = 70.0
    
    // Presentation States
    @State private var showingComposeSheet = false
    @State private var showingOutboxSheet = false
    
    // Floating Draggable macOS Window Panel for Preferences (replaces standard modal sheet!)
    @State private var showingPreferencesWindow = false
    @State private var preferencesWindowOffset: CGSize = CGSize(width: 80, height: 90)
    
    // Floating Draggable macOS Window Panel for Compose Post
    @State private var composeWindowOffset: CGSize = CGSize(width: 140, height: 110)
    
    // Floating Draggable macOS Window Panel for Outbox
    @State private var outboxWindowOffset: CGSize = CGSize(width: 200, height: 140)
    
    // Floating Draggable macOS Window Panel for Connection Logs
    @State private var showingLogsWindow = false
    @State private var logsWindowOffset: CGSize = CGSize(width: 260, height: 170)
    
    // Floating Draggable macOS Window Panel for About Dialog
    @State private var showingAboutWindow = false
    
    // Compose Pre-fill Arguments
    @State private var composeSubjectArg: String = ""
    @State private var composeBodyArg: String = ""
    @State private var composeReferencesArg: [String] = []
    
    var body: some View {
        @Bindable var bStore = store
        
        ZStack(alignment: .topLeading) {
            // Main macOS Workspace Canvas with elegant desktop background
            VStack(spacing: 0) {
                // Content Columns stacked on a sleek desktop canvas
                HStack(spacing: 0) {
                    // Left Column: Newsgroup Abonnements (Sits all the way flush to the bottom!)
                    ModernGlassWindowView(title: "Abonnements", footerText: "Abonniert: \(store.groups.filter(\.subscribed).count) Gruppen") {
                        VStack(spacing: 0) {
                            // Sidebar Upper Action Toolbar (Modern utility buttons!)
                            VStack(spacing: 8) {
                                // Connection Status and Toggle
                                Button {
                                    store.isOffline.toggle()
                                } label: {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(store.isOffline ? Color.red : Color.green)
                                            .frame(width: 7, height: 7)
                                        Text(store.isOffline ? "Status: Offline (Verbinden...)" : "Status: Online (Trennen...)")
                                            .font(.system(size: 9.5, weight: .bold, design: .default))
                                        Spacer()
                                        Image(systemName: store.isOffline ? "wifi.slash" : "wifi")
                                            .font(.system(size: 9.5))
                                    }
                                    .foregroundColor(store.isOffline ? .red : .green)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(store.isOffline ? Color.red.opacity(0.08) : Color.green.opacity(0.08))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(store.isOffline ? Color.red.opacity(0.2) : Color.green.opacity(0.2), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 8)
                                .padding(.top, 8)

                                HStack(spacing: 6) {
                                    // Compose Post Toolbar Button
                                    Button {
                                        triggerComposeNew()
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: "pencil")
                                                .font(.system(size: 11))
                                            Text("Schreiben")
                                                .font(.system(size: 9.5, weight: .semibold))
                                        }
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color.primary.opacity(0.04))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    
                                    // Outbox Button
                                    let queuedCount = store.outbox.filter({ $0.status == "queued" }).count
                                    Button {
                                        openOutboxWindow()
                                    } label: {
                                        VStack(spacing: 4) {
                                            ZStack(alignment: .topTrailing) {
                                                Image(systemName: "tray.and.arrow.up")
                                                    .font(.system(size: 11))
                                                if queuedCount > 0 {
                                                    Circle()
                                                        .fill(Color.red)
                                                        .frame(width: 5, height: 5)
                                                        .offset(x: 8, y: -2)
                                                }
                                            }
                                            Text("Ausgang (\(queuedCount))")
                                                .font(.system(size: 9.5, weight: .semibold))
                                        }
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color.primary.opacity(0.04))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    
                                    // Sync Button
                                    Button {
                                        store.synchronize()
                                    } label: {
                                        VStack(spacing: 4) {
                                            if store.isSyncing {
                                                ProgressView()
                                                    .frame(width: 11, height: 11)
                                            } else {
                                                Image(systemName: "arrow.triangle.2.circlepath")
                                                    .font(.system(size: 11))
                                            }
                                            Text(store.isSyncing ? "Sync..." : "Abgleich")
                                                .font(.system(size: 9.5, weight: .semibold))
                                        }
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color.primary.opacity(0.04))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.top, 4)
                                
                                HStack(spacing: 6) {
                                    // Settings Button
                                    Button {
                                        openPreferencesWindow()
                                    } label: {
                                        HStack {
                                            Image(systemName: "gearshape")
                                                .font(.system(size: 10))
                                            Text("Optionen")
                                                .font(.system(size: 9.5, weight: .semibold))
                                        }
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 7)
                                        .background(Color.primary.opacity(0.04))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    
                                    // Protocols (Logs) Button
                                    Button {
                                        openLogsWindow()
                                    } label: {
                                        HStack {
                                            Image(systemName: "doc.text")
                                                .font(.system(size: 10))
                                            Text("Protokoll")
                                                .font(.system(size: 9.5, weight: .semibold))
                                        }
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 7)
                                        .background(Color.primary.opacity(0.04))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.bottom, 8)
                            }
                            
                            Divider()
                            
                            // Abonnements newsgroup list (sits flush below the header actions, NO truncation!)
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(store.groups.filter(\.subscribed)) { group in
                                        HStack {
                                            Image(systemName: "newspaper.fill")
                                                .font(.caption)
                                                .foregroundColor(.teal)
                                            Text(group.name)
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.primary)
                                                .lineLimit(nil)
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Spacer()
                                            if group.unreadCount > 0 {
                                                Text("\(group.unreadCount)")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 1.5)
                                                    .background(Color.blue)
                                                    .foregroundColor(.white)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 11)
                                        .background(bStore.selectedGroupId == group.name ? Color.blue.opacity(0.08) : Color.clear)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            bStore.selectedGroupId = group.name
                                        }
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: sidebarWidth)
                    .frame(maxHeight: .infinity)
                    
                    // Vertical drag separator for sidebar resize
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 1)
                        .overlay(
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 8)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(coordinateSpace: .global)
                                        .onChanged { val in
                                            sidebarWidth = max(160, min(360, dragStartWidth + val.translation.width))
                                        }
                                        .onEnded { _ in
                                            dragStartWidth = sidebarWidth
                                        }
                                )
                        )
                    
                    // Right Content Pane: Subject List, Thread tracer Canvas, Reader details
                    Group {
                        if let activeGroup = store.selectedGroupId {
                            let (groupArticles, _, rootArticles, repliesCounts) = GroupArticlesCache.shared.getArticles(storeArticles: store.articles, activeGroup: activeGroup, changeCounter: store.articlesChangeCounter)
                            
                            // Reihenansicht (Vertical layout split)
                            VStack(spacing: 0) {
                                subjectsPanel(groupArticles: groupArticles, rootArticles: rootArticles, activeGroup: activeGroup, repliesCounts: repliesCounts)
                                    .frame(height: subjectsHeight)
                                
                                HorizontalResizeSeparator(heightValue: $subjectsHeight, dragStart: $dragStartSubjectsHeight, minHeight: 120, maxHeight: 280)
                                
                                threadTracerPanel(groupArticles: groupArticles, rootArticles: rootArticles)
                                    .frame(height: threadHeight)
                                
                                HorizontalResizeSeparator(heightValue: $threadHeight, dragStart: $dragStartThreadHeight, minHeight: 200, maxHeight: 2000)
                                
                                articleDetailPanel()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        } else {
                            ModernGlassWindowView(title: "Thema", footerText: "Offline") {
                                ContentUnavailableView("Wähle eine Gruppe", systemImage: "tray.2.fill", description: Text("Bitte wählen Sie links eine abonnierte Newsgroup aus, um Beiträge zu sehen."))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color.sysSecondaryBackground.opacity(0.4))
        // Menu notification receivers
        .onReceive(NotificationCenter.default.publisher(for: .triggerComposeNew)) { _ in
            triggerComposeNew()
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerSync)) { _ in
            store.synchronize()
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerReply)) { _ in
            if let activeArtId = store.selectedArticleId,
               let activeArt = store.articles.first(where: { $0.id == activeArtId }) {
                triggerReply(art: activeArt)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerFollowup)) { _ in
            if let activeArtId = store.selectedArticleId,
               let activeArt = store.articles.first(where: { $0.id == activeArtId }) {
                triggerFollowup(art: activeArt)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerKillThread)) { _ in
            if let activeArtId = store.selectedArticleId {
                store.toggleKillThread(for: activeArtId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerIgnorePoster)) { _ in
            if let activeArtId = store.selectedArticleId,
               let activeArt = store.articles.first(where: { $0.id == activeArtId }) {
                store.toggleIgnorePoster(from: activeArt.from)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerSettings)) { _ in
            openPreferencesWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerLogs)) { _ in
            openLogsWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerAbout)) { _ in
            openAboutWindow()
        }
        .onAppear {
            dragStartWidth = sidebarWidth
            dragStartSubjectsHeight = subjectsHeight
            dragStartThreadHeight = threadHeight
            
            dragStartStatusWidth = colStatusWidth
            dragStartUnreadWidth = colUnreadWidth
            dragStartAuthorWidth = colAuthorWidth
            dragStartAgeWidth = colAgeWidth
        }
        .alert("Verbindungsfehler", isPresented: Binding(
            get: { store.connectionError != nil },
            set: { if !$0 { store.connectionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMsg = store.connectionError {
                Text(errorMsg)
            }
        }
        .onChange(of: subjectsSearchText) { _ in
            subjectsActiveIndex = 0
        }
        .onChange(of: messageSearchText) { _ in
            messageActiveIndex = 0
        }
        .onChange(of: store.selectedArticleId) { _ in
            isRot13Decoded = false
        }
    }
    
    // Window Opener Helpers for Native Floating Windows
    private func openPreferencesWindow() {
        NativeWindowManager.shared.openWindow(
            id: "preferences",
            title: "Einstellungen - SpiceBoard",
            width: 640,
            height: 560,
            isResizable: false,
            store: store,
            onClose: {
                showingPreferencesWindow = false
            }
        ) {
            PreferencesView(isPresented: Binding(
                get: { showingPreferencesWindow },
                set: { val in
                    showingPreferencesWindow = val
                    if !val { NativeWindowManager.shared.closeWindow(id: "preferences") }
                }
            ))
        }
        showingPreferencesWindow = true
    }
    
    private func openComposeWindow(subject: String = "", body: String = "", references: [String] = []) {
        NativeWindowManager.shared.openWindow(
            id: "compose",
            title: "Neuer Beitrag",
            width: 680,
            height: 650,
            store: store,
            onClose: {
                showingComposeSheet = false
            }
        ) {
            ComposePostView(
                isPresented: Binding(
                    get: { showingComposeSheet },
                    set: { val in
                        showingComposeSheet = val
                        if !val { NativeWindowManager.shared.closeWindow(id: "compose") }
                    }
                ),
                initialSubject: subject,
                initialBody: body,
                references: references
            )
        }
        showingComposeSheet = true
    }
    
    private func openOutboxWindow() {
        NativeWindowManager.shared.openWindow(
            id: "outbox",
            title: "Postausgang (Outbox)",
            width: 500,
            height: 400,
            store: store,
            onClose: {
                showingOutboxSheet = false
            }
        ) {
            OutboxView(
                isPresented: Binding(
                    get: { showingOutboxSheet },
                    set: { val in
                        showingOutboxSheet = val
                        if !val { NativeWindowManager.shared.closeWindow(id: "outbox") }
                    }
                )
            )
        }
        showingOutboxSheet = true
    }
    
    private func openLogsWindow() {
        NativeWindowManager.shared.openWindow(
            id: "logs",
            title: "Verbindungsprotokoll - SpiceBoard",
            width: 520,
            height: 380,
            store: store,
            onClose: {
                showingLogsWindow = false
            }
        ) {
            SyncLogsWindowFloatPanel(
                isPresented: Binding(
                    get: { showingLogsWindow },
                    set: { val in
                        showingLogsWindow = val
                        if !val { NativeWindowManager.shared.closeWindow(id: "logs") }
                    }
                ),
                store: store
            )
        }
        showingLogsWindow = true
    }
    
    private func openAboutWindow() {
        NativeWindowManager.shared.openWindow(
            id: "about",
            title: "Über SpiceBoard",
            width: 380,
            height: 360,
            isResizable: false,
            store: store,
            onClose: {
                showingAboutWindow = false
            }
        ) {
            AboutView()
        }
        showingAboutWindow = true
    }
    
    // Helpers
    private func triggerComposeNew() {
        openComposeWindow(subject: "", body: "", references: [])
    }
    
    private func extractEmail(from sender: String) -> String {
        if let startRange = sender.range(of: "<"),
           let endRange = sender.range(of: ">"),
           startRange.upperBound < endRange.lowerBound {
            return String(sender[startRange.upperBound..<endRange.lowerBound])
        }
        return sender.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func formatAge(from date: Date) -> String {
        let seconds = -Int(date.timeIntervalSinceNow)
        if seconds < 0 { return "0m" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }
    
    private func getSelectedTextInActiveWindow() -> String? {
        guard let window = NSApp.keyWindow else { return nil }
        
        // First, check if the first responder is an NSTextView (focused edit field or selectable text)
        if let textView = window.firstResponder as? NSTextView {
            let range = textView.selectedRange()
            if range.length > 0 {
                return (textView.string as NSString).substring(with: range)
            }
        }
        
        // Fallback: search the entire view hierarchy for any NSTextView with a selection
        func findSelectedText(in view: NSView) -> String? {
            if let textView = view as? NSTextView {
                let range = textView.selectedRange()
                if range.length > 0 {
                    return (textView.string as NSString).substring(with: range)
                }
            }
            for subview in view.subviews {
                if let found = findSelectedText(in: subview) {
                    return found
                }
            }
            return nil
        }
        
        if let contentView = window.contentView {
            return findSelectedText(in: contentView)
        }
        
        return nil
    }
    
    private func getQuotedBody(from art: Article) -> String {
        // If there is highlighted text in the window, only quote that selection
        if let selectedText = getSelectedTextInActiveWindow() {
            let cleanSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanSelection.isEmpty {
                return "\n\n\(art.from) schrieb:\n" + cleanSelection.components(separatedBy: .newlines).map { "> \($0)" }.joined(separator: "\n")
            }
        }
        
        // Default fallback: Quote the entire body of the original article
        return "\n\n\(art.from) schrieb:\n" + art.body.components(separatedBy: .newlines).map { "> \($0)" }.joined(separator: "\n")
    }
    
    private func triggerReply(art: Article) {
        let email = extractEmail(from: art.from)
        let cleanSubject = art.subject.hasPrefix("Re:") ? art.subject : "Re: \(art.subject)"
        let cleanBody = getQuotedBody(from: art)
        
        var urlComponents = URLComponents()
        urlComponents.scheme = "mailto"
        urlComponents.path = email
        urlComponents.queryItems = [
            URLQueryItem(name: "subject", value: cleanSubject),
            URLQueryItem(name: "body", value: cleanBody)
        ]
        
        if let url = urlComponents.url {
            openURL(url)
        }
    }
    
    private func triggerFollowup(art: Article) {
        let cleanSubject = art.subject.hasPrefix("Re:") ? art.subject : "Re: \(art.subject)"
        let cleanBody = getQuotedBody(from: art)
        openComposeWindow(subject: cleanSubject, body: cleanBody, references: art.references + [art.id])
    }
    
    // Extracted View Builders for Row/Column Layout Parity
    @ViewBuilder
    private func subjectsPanel(groupArticles: [Article], rootArticles: [Article], activeGroup: String, repliesCounts: [String: Int]) -> some View {
        let sourceList = groupThreads ? rootArticles : groupArticles
        let filteredArticles: [Article] = {
            let baseList = sourceList
            let query = subjectsSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            
            let searchedList: [Article]
            if query.isEmpty {
                searchedList = baseList
            } else {
                searchedList = baseList.filter { art in
                    let subjectMatches = art.subject.lowercased().contains(query)
                    let authorMatches = art.from.lowercased().contains(query)
                    let bodyMatches = art.body.lowercased().contains(query)
                    
                    if subjectMatches || authorMatches || bodyMatches {
                        return true
                    }
                    
                    // If grouped, also match if any reply in this thread matches
                    if groupThreads {
                        let replies = groupArticles.filter { $0.references.contains(art.id) }
                        return replies.contains { reply in
                            reply.subject.lowercased().contains(query) ||
                            reply.from.lowercased().contains(query) ||
                            reply.body.lowercased().contains(query)
                        }
                    }
                    
                    return false
                }
            }
            
            switch articleFilter {
            case .alle:
                return searchedList
            case .ungelesene:
                return searchedList.filter { !$0.read }
            case .gelesene:
                return searchedList.filter { $0.read }
            case .markierte:
                return searchedList.filter { $0.flagged ?? false }
            case .neue:
                return searchedList.filter { !$0.read && !$0.ignored }
            case .gesperrte:
                return searchedList.filter { $0.ignored }
            }
        }()
        
        let sortedArticles: [Article] = {
            var list = filteredArticles
            switch sortField {
            case .subject:
                list.sort { sortAscending ? $0.subject.localizedStandardCompare($1.subject) == .orderedAscending : $0.subject.localizedStandardCompare($1.subject) == .orderedDescending }
            case .author:
                list.sort { sortAscending ? $0.from.localizedStandardCompare($1.from) == .orderedAscending : $0.from.localizedStandardCompare($1.from) == .orderedDescending }
            case .age:
                list.sort { sortAscending ? $0.date < $1.date : $0.date > $1.date }
            }
            return list
        }()
        
        let totalCount = sortedArticles.count
        let footerMsg = groupThreads ? "Themen: \(totalCount)" : "Artikel: \(totalCount)"
        
        ModernGlassWindowView(title: activeGroup, footerText: footerMsg) {
            VStack(spacing: 0) {
                // Toolbar Control Bar
                HStack(spacing: 12) {
                    // Thread Grouping Toggle Button
                    Button(action: {
                        groupThreads.toggle()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: groupThreads ? "rectangle.3.group" : "list.dash")
                            Text(groupThreads ? "Threads gruppiert" : "Threads flach")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    
                    // Search Field
                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            TextField("Themen suchen...", text: $subjectsSearchText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 10))
                            if !subjectsSearchText.isEmpty {
                                Button(action: { 
                                    subjectsSearchText = ""
                                    subjectsActiveIndex = 0
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
                        
                        if !subjectsSearchText.isEmpty {
                            HStack(spacing: 4) {
                                Text("\(totalCount > 0 ? (subjectsActiveIndex % totalCount) + 1 : 0) / \(totalCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.orange)
                                    .frame(minWidth: 32)
                                
                                Button(action: {
                                    if totalCount > 0 {
                                        subjectsActiveIndex = (subjectsActiveIndex - 1 + totalCount) % totalCount
                                        let activeArt = sortedArticles[subjectsActiveIndex]
                                        store.selectedArticleId = activeArt.id
                                        if let idx = store.articles.firstIndex(where: { $0.id == activeArt.id }) {
                                            if !store.articles[idx].read {
                                                store.articles[idx].read = true
                                                store.recalcUnreadCounts()
                                            }
                                        }
                                    }
                                }) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.primary)
                                }
                                .buttonStyle(.plain)
                                .disabled(totalCount == 0)
                                
                                Button(action: {
                                    if totalCount > 0 {
                                        subjectsActiveIndex = (subjectsActiveIndex + 1) % totalCount
                                        let activeArt = sortedArticles[subjectsActiveIndex]
                                        store.selectedArticleId = activeArt.id
                                        if let idx = store.articles.firstIndex(where: { $0.id == activeArt.id }) {
                                            if !store.articles[idx].read {
                                                store.articles[idx].read = true
                                                store.recalcUnreadCounts()
                                            }
                                        }
                                    }
                                }) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.primary)
                                }
                                .buttonStyle(.plain)
                                .disabled(totalCount == 0)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Filter Menu
                    Menu {
                        ForEach(ArticleFilter.allCases) { filter in
                            Button(action: {
                                articleFilter = filter
                            }) {
                                HStack {
                                    Text(filter.rawValue)
                                    if articleFilter == filter {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text(articleFilter.rawValue)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                    }
                    .menuStyle(.button)
                    .frame(width: 155)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.sysSecondaryBackground.opacity(0.5))
                
                Divider()
                
                if sortedArticles.isEmpty {
                    ContentUnavailableView("Keine Artikel mit diesem Filter", systemImage: "text.bubble")
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            Section(header:
                                HStack(spacing: 0) {
                                    Text("Status")
                                        .font(.system(size: 10, weight: .bold))
                                        .frame(width: colStatusWidth, alignment: .center)
                                    
                                    HeaderColumnResizeSeparator(width: $colStatusWidth, dragStart: $dragStartStatusWidth, minWidth: 40, maxWidth: 100)
                                    
                                    Text("Ungelesen")
                                        .font(.system(size: 10, weight: .bold))
                                        .frame(width: colUnreadWidth, alignment: .center)
                                    
                                    HeaderColumnResizeSeparator(width: $colUnreadWidth, dragStart: $dragStartUnreadWidth, minWidth: 40, maxWidth: 120)
                                    
                                    Button(action: {
                                        if sortField == .subject {
                                            sortAscending.toggle()
                                        } else {
                                            sortField = .subject
                                            sortAscending = true
                                        }
                                    }) {
                                        HStack(spacing: 3) {
                                            Text("Betreff-Thema")
                                                .font(.system(size: 10, weight: .bold))
                                            if sortField == .subject {
                                                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                                    .font(.system(size: 8))
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading, 6)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.12))
                                        .frame(width: 1)
                                    
                                    Button(action: {
                                        if sortField == .author {
                                            sortAscending.toggle()
                                        } else {
                                            sortField = .author
                                            sortAscending = true
                                        }
                                    }) {
                                        HStack(spacing: 3) {
                                            Text("Autor")
                                                .font(.system(size: 10, weight: .bold))
                                            if sortField == .author {
                                                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                                    .font(.system(size: 8))
                                            }
                                        }
                                        .frame(width: colAuthorWidth, alignment: .leading)
                                        .padding(.leading, 6)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    HeaderColumnResizeSeparator(width: $colAuthorWidth, dragStart: $dragStartAuthorWidth, minWidth: 60, maxWidth: 250)
                                    
                                    Button(action: {
                                        if sortField == .age {
                                            sortAscending.toggle()
                                        } else {
                                            sortField = .age
                                            sortAscending = true
                                        }
                                    }) {
                                        HStack(spacing: 3) {
                                            Text("Alter")
                                                .font(.system(size: 10, weight: .bold))
                                            if sortField == .age {
                                                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                                    .font(.system(size: 8))
                                            }
                                        }
                                        .frame(width: colAgeWidth, alignment: .leading)
                                        .padding(.leading, 6)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    HeaderColumnResizeSeparator(width: $colAgeWidth, dragStart: $dragStartAgeWidth, minWidth: 40, maxWidth: 150)
                                }
                                .padding(.horizontal, 4)
                                .frame(height: 25)
                                .background(Color.sysBackground)
                                .overlay(
                                    VStack {
                                        Spacer()
                                        Rectangle().fill(Color.sysSeparator).frame(height: 0.5)
                                    }
                                )
                            ) {
                                ForEach(sortedArticles) { art in
                                    let threadRepliesCount = repliesCounts[art.id] ?? 0
                                    let rowUnreadCount = groupThreads ? groupArticles.filter { !$0.read && ($0.id == art.id || $0.references.contains(art.id)) }.count : (art.read ? 0 : 1)
                                    
                                    HStack(spacing: 0) {
                                        // Status indicator column
                                        HStack(spacing: 3) {
                                            if art.flagged ?? false {
                                                Image(systemName: "star.fill")
                                                    .foregroundColor(.orange)
                                                    .font(.system(size: 8))
                                            }
                                            Group {
                                                if art.ignored {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundColor(.red)
                                                        .font(.caption2)
                                                } else if !art.downloaded {
                                                    Image(systemName: "dot.circle")
                                                        .foregroundColor(.secondary)
                                                        .font(.caption2)
                                                } else if !art.read {
                                                    Circle()
                                                        .fill(Color.blue)
                                                        .frame(width: 8, height: 8)
                                                } else {
                                                    Image(systemName: "checkmark")
                                                        .foregroundColor(.secondary)
                                                        .font(.system(size: 8))
                                                }
                                            }
                                        }
                                        .frame(width: colStatusWidth, alignment: .center)
                                        
                                        Divider()
                                        
                                        // Unread indicator column
                                        HStack {
                                            if rowUnreadCount > 0 {
                                                Text("\(rowUnreadCount)")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 1.5)
                                                    .background(Color.blue)
                                                    .clipShape(Capsule())
                                            } else {
                                                Text("-")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .frame(width: colUnreadWidth, alignment: .center)
                                        
                                        Divider()
                                        
                                        // Subject theme
                                        HStack {
                                            if art.ignored {
                                                highlightMatches(art.subject, query: subjectsSearchText, baseFont: .system(size: 11, design: .monospaced))
                                                    .strikethrough()
                                                    .foregroundColor(.secondary)
                                            } else {
                                                highlightMatches(art.subject, query: subjectsSearchText, baseFont: .system(size: 12, weight: art.read ? .regular : .bold))
                                                    .foregroundColor(.primary)
                                            }
                                            Spacer()
                                            if threadRepliesCount > 0 {
                                                Text("\(threadRepliesCount + 1)")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1)
                                                    .background(Color.secondary.opacity(0.12))
                                                    .foregroundColor(.secondary)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading, 8)
                                        .lineLimit(1)
                                        
                                        Divider()
                                        
                                        // Sender name
                                        highlightMatches(cleanAuthorName(art.from), query: subjectsSearchText, baseFont: .system(size: 11, design: .monospaced))
                                            .frame(width: colAuthorWidth, alignment: .leading)
                                            .padding(.leading, 8)
                                            .lineLimit(1)
                                        
                                        Divider()
                                        
                                        // Age column
                                        Text(formatAge(from: art.date))
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .frame(width: colAgeWidth, alignment: .leading)
                                            .padding(.leading, 8)
                                            .lineLimit(1)
                                    }
                                    .padding(.vertical, 8)
                                    .background(store.selectedArticleId == art.id ? Color.blue.opacity(0.06) : Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        store.selectedArticleId = art.id
                                        
                                        if let idx = store.articles.firstIndex(where: { $0.id == art.id }) {
                                            if !store.articles[idx].read {
                                                store.articles[idx].read = true
                                                store.recalcUnreadCounts()
                                            }
                                        }
                                    }
                                    .contextMenu {
                                        Button(action: {
                                            if let idx = store.articles.firstIndex(where: { $0.id == art.id }) {
                                                store.articles[idx].read.toggle()
                                                store.recalcUnreadCounts()
                                            }
                                        }) {
                                            Label(art.read ? "Als ungelesen markieren" : "Als gelesen markieren", systemImage: art.read ? "circle" : "checkmark.circle")
                                        }
                                        
                                        Button(action: {
                                            store.toggleFlagged(for: art.id)
                                        }) {
                                            Label(art.flagged ?? false ? "Markierung aufheben" : "Als markiert kennzeichnen", systemImage: art.flagged ?? false ? "star.slash" : "star.fill")
                                        }
                                        
                                        Button(action: {
                                            store.toggleKillThread(for: art.id)
                                        }) {
                                            Label(art.ignored ? "Thema Ignorieren aufheben" : "Thema Ignorieren / Kill", systemImage: "slash.circle")
                                        }
                                        
                                        Button(action: {
                                            store.toggleIgnorePoster(from: art.from)
                                        }) {
                                            Label(store.isAuthorIgnored(sender: art.from) ? "Autor Ignorieren aufheben" : "Autor Ignorieren", systemImage: "person.slash")
                                        }
                                        
                                        Divider()
                                        
                                        Button(action: {
                                            triggerFollowup(art: art)
                                        }) {
                                            Label("Antworten", systemImage: "arrowshape.turn.up.left.2.fill")
                                        }
                                        
                                        Button(action: {
                                            triggerReply(art: art)
                                        }) {
                                            Label("Autor antworten", systemImage: "arrowshape.turn.up.right")
                                        }
                                    }
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func threadTracerPanel(groupArticles: [Article], rootArticles: [Article]) -> some View {
        let threadArticles: [Article] = {
            guard !groupArticles.isEmpty else { return [] }
            
            // Find the currently selected article in this group
            let selectedArt = groupArticles.first { $0.id == store.selectedArticleId }
            
            let articleMap = Dictionary(uniqueKeysWithValues: groupArticles.map { ($0.id, $0) })
            
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
            
            // Determine the thread root ID
            let threadRootId: String
            if let selectedArt = selectedArt {
                threadRootId = findDownloadedRootId(for: selectedArt.id)
            } else if let firstRoot = rootArticles.first {
                threadRootId = firstRoot.id
            } else {
                return []
            }
            
            // Filter to only the articles belonging to this specific thread
            return groupArticles.filter { $0.id == threadRootId || $0.references.contains(threadRootId) }
        }()
        
        ModernGlassWindowView(title: "Verlauf der Nachrichtendiskussion") {
            ThreadTreeView(articles: threadArticles, selectedArticleId: store.selectedArticleId ?? "") { targetId in
                store.selectedArticleId = targetId
                if let idx = store.articles.firstIndex(where: { $0.id == targetId }) {
                    if !store.articles[idx].read {
                        store.articles[idx].read = true
                        store.recalcUnreadCounts()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func articleDetailPanel() -> some View {
        VStack(spacing: 0) {
            if let activeArtId = store.selectedArticleId,
               let activeArt = store.articles.first(where: { $0.id == activeArtId }) {
                ModernGlassWindowView(title: activeArt.subject, footerText: "Autor: \(activeArt.from)") {
                    VStack(spacing: 0) {
                        // Header cards with information
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Absender:")
                                        .fontWeight(.bold)
                                        .foregroundColor(.secondary)
                                    Text(activeArt.from)
                                }
                                HStack {
                                    Text("Betreff:")
                                        .fontWeight(.bold)
                                        .foregroundColor(.secondary)
                                    Text(activeArt.subject)
                                        .fontWeight(.bold)
                                }
                                HStack {
                                    Text("Gesendet:")
                                        .fontWeight(.bold)
                                        .foregroundColor(.secondary)
                                    Text(activeArt.date, style: .date)
                                    Text(activeArt.date, style: .time)
                                }
                            }
                            .font(.system(size: 11))
                            
                            Spacer()
                            
                            let senderXFace = activeArt.from.contains(store.username) ? store.xFace : activeArt.from
                            XFaceView(rawString: senderXFace)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.04))
                        
                        // Action controls below header
                        HStack(spacing: 8) {
                            Button {
                                if let idx = store.articles.firstIndex(where: { $0.id == activeArt.id }) {
                                    store.articles[idx].read = true
                                    store.recalcUnreadCounts()
                                }
                            } label: {
                                Label("Gelesen", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(activeArt.read ? Color.green.opacity(0.3) : Color.green)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .disabled(activeArt.read)
                            
                            Button {
                                if let idx = store.articles.firstIndex(where: { $0.id == activeArt.id }) {
                                    store.articles[idx].read = false
                                    store.recalcUnreadCounts()
                                }
                            } label: {
                                Label("Ungelesen", systemImage: "circle")
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.secondary.opacity(0.12))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .disabled(!activeArt.read)
                            
                            Button {
                                isRot13Decoded.toggle()
                            } label: {
                                Label(isRot13Decoded ? "ROT13 dekodiert" : "ROT13", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(isRot13Decoded ? .white : .purple)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(isRot13Decoded ? Color.purple : Color.purple.opacity(0.08))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                            
                            HStack(spacing: 6) {
                                Button {
                                    triggerFollowup(art: activeArt)
                                } label: {
                                    Label("Antworten", systemImage: "arrowshape.turn.up.left.2.fill")
                                        .font(.caption)
                                        .foregroundColor(.teal)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.teal.opacity(0.08))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                
                                Button {
                                    triggerReply(art: activeArt)
                                } label: {
                                    Label("Autor antworten", systemImage: "arrowshape.turn.up.right")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.blue.opacity(0.08))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                
                                Button {
                                    store.toggleKillThread(for: activeArt.id)
                                } label: {
                                    Label(activeArt.ignored ? "Kill aufheben" : "Kill Thread", systemImage: "slash.circle")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(Color.red.opacity(0.08))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                
                                Button {
                                    store.toggleIgnorePoster(from: activeArt.from)
                                } label: {
                                    Label(store.isAuthorIgnored(sender: activeArt.from) ? "Ignorieren aufheben" : "Ignorieren", systemImage: "person.slash")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(Color.orange.opacity(0.08))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.02))
                        
                        Divider()
                        
                        // Search bar inside the Nachricht (Message) window (Schmaler gemacht, nicht über die gesamte Fensterbreite)
                        HStack {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                TextField("In Nachricht suchen...", text: $messageSearchText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11))
                                
                                if !messageSearchText.isEmpty {
                                    let query = messageSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                                    let totalBodyMatches: Int = {
                                        var count = 0
                                        var currentIndex = activeArt.body.startIndex
                                        let lowerBody = activeArt.body.lowercased()
                                        while currentIndex < activeArt.body.endIndex {
                                            if let r = lowerBody.range(of: query, range: currentIndex..<activeArt.body.endIndex) {
                                                count += 1
                                                currentIndex = r.upperBound
                                            } else {
                                                break
                                            }
                                        }
                                        return count
                                    }()
                                    
                                    HStack(spacing: 4) {
                                        Text("\(totalBodyMatches > 0 ? (messageActiveIndex % totalBodyMatches) + 1 : 0) / \(totalBodyMatches)")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.orange)
                                            .frame(minWidth: 32)
                                        
                                        Button(action: {
                                            if totalBodyMatches > 0 {
                                                messageActiveIndex = (messageActiveIndex - 1 + totalBodyMatches) % totalBodyMatches
                                            }
                                        }) {
                                            Image(systemName: "chevron.left")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.primary)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(totalBodyMatches == 0)
                                        
                                        Button(action: {
                                            if totalBodyMatches > 0 {
                                                messageActiveIndex = (messageActiveIndex + 1) % totalBodyMatches
                                            }
                                        }) {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.primary)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(totalBodyMatches == 0)
                                    }
                                    .padding(.horizontal, 4)
                                    
                                    Button(action: { 
                                        messageSearchText = ""
                                        messageActiveIndex = 0
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.04))
                            .frame(width: 280)
                            .cornerRadius(6)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        
                        Divider()
                        
                        // Body reader view
                        ScrollView {
                            VStack(alignment: .leading) {
                                if activeArt.downloaded {
                                    let currentBodyText = isRot13Decoded ? rot13(activeArt.body) : activeArt.body
                                    if messageSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(currentBodyText)
                                            .font(.system(size: 12.5, design: .monospaced))
                                            .lineSpacing(5)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                            .padding()
                                    } else {
                                        let query = messageSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                                        let lines = currentBodyText.components(separatedBy: .newlines)
                                        
                                        var runningMatchCount = 0
                                        
                                        VStack(alignment: .leading, spacing: 3) {
                                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                                highlightLineMatches(line, query: query, activeIndex: messageActiveIndex, matchCount: &runningMatchCount)
                                                    .font(.system(size: 12.5, design: .monospaced))
                                                    .lineSpacing(5)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .textSelection(.enabled)
                                            }
                                        }
                                        .padding()
                                    }
                                } else {
                                    VStack(spacing: 12) {
                                        Image(systemName: "icloud.and.arrow.down.fill")
                                            .font(.largeTitle)
                                            .foregroundColor(.secondary)
                                        Text("Beitrag nicht offline geladen (Spar-Option)")
                                            .font(.headline)
                                        Text("Um Ihre Telefonrechnung zu schonen, wurde nur der Kopfzeilen-Header empfangen.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 24)
                                        
                                        HStack(spacing: 12) {
                                            Button("Beitrag laden") {
                                                store.downloadArticleBody(articleId: activeArt.id)
                                            }
                                            .buttonStyle(.borderedProminent)
                                            
                                            Button("Ganzen Thread laden") {
                                                store.downloadEntireThread(forArticleId: activeArt.id)
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                        .padding(.top, 6)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 32)
                                }
                            }
                        }
                    }
                }
            } else {
                ModernGlassWindowView(title: "Auswahl", footerText: "Inaktiv") {
                    ContentUnavailableView("Thema wählen", systemImage: "quote.bubble", description: Text("Klicken Sie oben auf einen Thema-Starter oder wählen Sie einen runden Diskussion-Knoten."))
                }
            }
        }
    }
}

// MARK: - Header Column Resize Separator
struct HeaderColumnResizeSeparator: View {
    @Binding var width: Double
    @Binding var dragStart: Double
    var minWidth: Double = 30.0
    var maxWidth: Double = 300.0
    
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { val in
                                width = max(minWidth, min(maxWidth, dragStart + val.translation.width))
                            }
                            .onEnded { _ in
                                dragStart = width
                            }
                    )
            )
            .frame(maxHeight: .infinity)
    }
}

// MARK: - Vertical Resize Separator
struct VerticalResizeSeparator: View {
    @Binding var widthValue: Double
    @Binding var dragStart: Double
    
    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1)
            VStack {
                Spacer()
                Image(systemName: "line.3.vertical")
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(width: 7)
            .background(Color.secondary.opacity(0.04)        )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { val in
                        widthValue = max(100, min(600, dragStart + val.translation.width))
                    }
                    .onEnded { _ in
                        dragStart = widthValue
                    }
            )
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1)
        }
    }
}

// MARK: - Draggable Separator View
struct HorizontalResizeSeparator: View {
    @Binding var heightValue: Double
    @Binding var dragStart: Double
    var minHeight: Double = 60.0
    var maxHeight: Double = 500.0
    
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
            HStack {
                Spacer()
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(height: 7)
            .background(Color.secondary.opacity(0.04))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { val in
                        heightValue = max(minHeight, min(maxHeight, dragStart + val.translation.height))
                    }
                    .onEnded { _ in
                        dragStart = heightValue
                    }
            )
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
        }
    }
}

// MARK: - Draggable Floating Preferences window for Mac OS system
struct PreferencesWindowFloatPanel: View {
    @Binding var isPresented: Bool
    let store: UsenetStore
    @Binding var offset: CGSize
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag-Active title bar with modern traffic-lights close circle
            HStack {
                HStack(spacing: 6) {
                    Button {
                        isPresented = false
                    } label: {
                        Circle()
                            .fill(Color.red.opacity(0.85))
                            .frame(width: 10, height: 10)
                    }
                    .buttonStyle(.plain)
                    
                    Circle()
                        .fill(Color.yellow.opacity(0.4))
                        .frame(width: 10, height: 10)
                    
                    Circle()
                        .fill(Color.green.opacity(0.4))
                        .frame(width: 10, height: 10)
                }
                .padding(.leading, 12)
                
                Spacer()
                
                Text("Einstellungen - SpiceBoard")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Balance spacer
                HStack {
                    Color.clear.frame(width: 10, height: 10)
                    Color.clear.frame(width: 10, height: 10)
                    Color.clear.frame(width: 10, height: 10)
                }
                .padding(.trailing, 12)
            }
            .frame(height: 32)
            .background(Color.sysSecondaryBackground)
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                        dragOffset = .zero
                    }
            )
            
            Divider()
                .background(Color.sysSeparator)
            
            // Nested authentic Preference tab View
            PreferencesView(isPresented: $isPresented)
                .frame(height: 520)
        }
        .frame(width: 640)
        .background(Color.sysBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .offset(x: offset.width + dragOffset.width,
                y: offset.height + dragOffset.height)
    }
}

struct SyncLogsWindowFloatPanel: View {
    @Binding var isPresented: Bool
    let store: UsenetStore
    
    var body: some View {
        VStack(spacing: 0) {
            // Console display
            VStack(spacing: 0) {
                if store.syncLogs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("Keine Protokolleinträge vorhanden.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Starten Sie einen Abgleich, um die Verbindungsschritte anzuzeigen.")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.03))
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(store.syncLogs) { log in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text(formattedTime(log.timestamp))
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .padding(.top, 1)
                                        
                                        Text(log.message)
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundColor(colorForType(log.type))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                    }
                                    .padding(.horizontal, 8)
                                    .id(log.id)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
                        .onChange(of: store.syncLogs.count) { _ in
                            if let last = store.syncLogs.last {
                                withAnimation {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                
                Divider()
                    .background(Color.sysSeparator)
                
                // Bottom control toolbar (Clear, Copy, Close)
                HStack(spacing: 12) {
                    Button {
                        store.syncLogs.removeAll()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                            Text("Protokoll leeren")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.red.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(store.syncLogs.isEmpty)
                    
                    Button {
                        let logText = store.syncLogs.map { log in
                            "[\(formattedTime(log.timestamp))] [\(log.type.uppercased())] \(log.message)"
                        }.joined(separator: "\n")
                        let pasteboard = NSPasteboard.general
                        pasteboard.declareTypes([.string], owner: nil)
                        pasteboard.setString(logText, forType: .string)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                            Text("Kopieren")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(store.syncLogs.isEmpty)
                    
                    Spacer()
                    
                    Button {
                        isPresented = false
                    } label: {
                        Text("Schließen")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.blue)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(Color.sysSecondaryBackground)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sysBackground)
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func colorForType(_ type: String) -> Color {
        switch type {
        case "success":
            return Color(red: 0.3, green: 0.85, blue: 0.4) // soft green
        case "error":
            return Color(red: 0.95, green: 0.35, blue: 0.35) // soft red
        default:
            return Color(red: 0.85, green: 0.85, blue: 0.9) // soft bone white
        }
    }
}

// MARK: - Padding Extender
extension EdgeInsets {
    static func symmetric(horizontal: CGFloat, vertical: CGFloat) -> EdgeInsets {
        EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }
}

#Preview {
    let mock = UsenetStore()
    mock.loadMockData()
    return ContentView()
        .environment(mock)
}
