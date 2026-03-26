import SwiftUI

// MARK: - Search Result
struct SearchResult: Identifiable {
    let id = UUID()
    let elementId: UUID
    let elementType: CanvasElement.ElementType
    let title: String
    let subtitle: String?
    let matchedText: String
    let position: CGPoint
    let icon: String
}

// MARK: - Search Overlay View
struct SearchOverlayView: View {
    @ObservedObject var canvasManager: CanvasManager
    @Binding var isPresented: Bool
    let onNavigate: (UUID, CGPoint) -> Void
    
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
            
            // Results list
            if !searchText.isEmpty {
                resultsList
            }
        }
        .frame(width: 500)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(canvasManager.theme == .dark ? Color(white: 0.15) : Color.white)
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(canvasManager.theme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: searchText) { newValue in
            performSearch(query: newValue)
            selectedIndex = 0
        }
        .onExitCommand {
            // ESC key - close search
            isPresented = false
        }
    }
    
    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            
            TextField("Search elements...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isSearchFocused)
                .onSubmit {
                    if !searchResults.isEmpty {
                        navigateToResult(searchResults[selectedIndex])
                    }
                }
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Close button
            Button(action: { isPresented = false }) {
                Text("ESC")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(canvasManager.theme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(canvasManager.theme == .dark ? Color.clear : Color.clear)
    }
    
    // MARK: - Results List
    private var resultsList: some View {
        VStack(spacing: 0) {
            Divider()
            
            if searchResults.isEmpty && !searchText.isEmpty {
                // No results
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No results found")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 30)
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, result in
                                searchResultRow(result: result, isSelected: index == selectedIndex)
                                    .id(index)
                                    .onTapGesture {
                                        navigateToResult(result)
                                    }
                            }
                        }
                    }
                    .frame(maxHeight: 350)
                    .onChange(of: selectedIndex) { newIndex in
                        withAnimation {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
            
            // Footer with keyboard hints
            if !searchResults.isEmpty {
                Divider()
                keyboardHints
            }
        }
    }
    
    // MARK: - Search Result Row
    private func searchResultRow(result: SearchResult, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: result.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(iconColor(for: result.elementType))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(iconColor(for: result.elementType).opacity(0.15))
                )
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // Matched text highlight
                if !result.matchedText.isEmpty && result.matchedText != result.title {
                    Text("\"...\(result.matchedText)...\"")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Type badge
            Text(typeName(for: result.elementType))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(canvasManager.theme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            isSelected
                ? (canvasManager.theme == .dark ? Color.blue.opacity(0.3) : Color.blue.opacity(0.1))
                : Color.clear
        )
        .contentShape(Rectangle())
    }
    
    // MARK: - Keyboard Hints
    private var keyboardHints: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                keyboardKey("↑↓")
                Text("Navigate")
            }
            
            HStack(spacing: 4) {
                keyboardKey("⏎")
                Text("Go to")
            }
            
            HStack(spacing: 4) {
                keyboardKey("ESC")
                Text("Close")
            }
            
            Spacer()
            
            Text("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s")")
                .foregroundColor(.secondary)
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    private func keyboardKey(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(canvasManager.theme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
            )
    }
    
    // MARK: - Search Logic
    private func performSearch(query: String) {
        guard !query.isEmpty, let elements = canvasManager.currentCanvas?.elements else {
            searchResults = []
            return
        }
        
        let lowercaseQuery = query.lowercased()
        var results: [SearchResult] = []
        
        for element in elements {
            var title = ""
            var subtitle: String? = nil
            var matchedText = ""
            var matched = false
            
            switch element.type {
            case .webview:
                // Parse web content for title/URL
                // Content is the URL string directly
                let url = element.content.isEmpty ? "https://www.google.com" : element.content
                title = extractDomainName(from: url)
                subtitle = url
                
                // Search in both domain name and full URL
                if title.lowercased().contains(lowercaseQuery) {
                    matchedText = findMatchContext(in: title, query: lowercaseQuery)
                    matched = true
                } else if url.lowercased().contains(lowercaseQuery) {
                    matchedText = findMatchContext(in: url, query: lowercaseQuery)
                    matched = true
                }
                
            case .pdf:
                // Parse PDF content for filename
                title = parsePDFName(element.content)
                subtitle = "PDF Document"
                
                if title.lowercased().contains(lowercaseQuery) {
                    matchedText = findMatchContext(in: title, query: lowercaseQuery)
                    matched = true
                }
                
            case .text:
                // Search through text content
                title = "Text Note"
                let textContent = element.content
                
                if textContent.lowercased().contains(lowercaseQuery) {
                    // Extract preview of matched content
                    matchedText = findMatchContext(in: textContent, query: lowercaseQuery)
                    title = String(textContent.prefix(50)).replacingOccurrences(of: "\n", with: " ")
                    if textContent.count > 50 { title += "..." }
                    matched = true
                }
                
            case .frame:
                // Search frame titles
                title = element.content.isEmpty ? "Untitled Section" : element.content
                subtitle = "Section"
                
                if title.lowercased().contains(lowercaseQuery) {
                    matchedText = findMatchContext(in: title, query: lowercaseQuery)
                    matched = true
                }
                
            case .drawing:
                // Drawings don't have searchable content
                continue
            }
            
            if matched {
                results.append(SearchResult(
                    elementId: element.id,
                    elementType: element.type,
                    title: title,
                    subtitle: subtitle,
                    matchedText: matchedText,
                    position: element.position,
                    icon: iconName(for: element.type)
                ))
            }
        }
        
        // Sort by relevance (title matches first, then content matches)
        results.sort { result1, result2 in
            let title1MatchesStart = result1.title.lowercased().hasPrefix(lowercaseQuery)
            let title2MatchesStart = result2.title.lowercased().hasPrefix(lowercaseQuery)
            
            if title1MatchesStart && !title2MatchesStart { return true }
            if !title1MatchesStart && title2MatchesStart { return false }
            
            return result1.title.count < result2.title.count
        }
        
        searchResults = results
    }
    
    // MARK: - Content Parsing Helpers
    private struct WebInfo {
        let title: String
        let url: String
    }
    
    private func extractDomainName(from urlString: String) -> String {
        // Try to extract a readable domain name from URL
        guard let url = URL(string: urlString) else {
            return urlString.isEmpty ? "Web Page" : urlString
        }
        
        if let host = url.host {
            // Remove www. prefix if present
            var domain = host
            if domain.hasPrefix("www.") {
                domain = String(domain.dropFirst(4))
            }
            // Capitalize first letter of each part
            return domain.split(separator: ".").first.map { String($0).capitalized } ?? domain
        }
        
        return "Web Page"
    }
    
    private func parseWebContent(_ content: String) -> WebInfo? {
        // Try to parse JSON content
        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let title = json["title"] as? String ?? ""
            let url = json["url"] as? String ?? content
            return WebInfo(title: title, url: url)
        }
        
        // Fallback: treat content as URL
        return WebInfo(title: "", url: content)
    }
    
    private func parsePDFName(_ content: String) -> String {
        // Try to extract filename from path or URL
        if content.contains("/") {
            return (content as NSString).lastPathComponent
        }
        return content.isEmpty ? "PDF Document" : content
    }
    
    private func findMatchContext(in text: String, query: String, contextLength: Int = 30) -> String {
        guard let range = text.lowercased().range(of: query) else { return "" }
        
        let startIndex = text.index(range.lowerBound, offsetBy: -contextLength, limitedBy: text.startIndex) ?? text.startIndex
        let endIndex = text.index(range.upperBound, offsetBy: contextLength, limitedBy: text.endIndex) ?? text.endIndex
        
        var result = String(text[startIndex..<endIndex])
        result = result.replacingOccurrences(of: "\n", with: " ")
        
        return result
    }
    
    private func highlightedText(_ text: String, query: String) -> Text {
        // Simple implementation - returns the text as-is
        // Could be enhanced to actually highlight matching portions
        Text(text)
            .foregroundColor(.primary)
    }
    
    // MARK: - Navigation
    private func navigateToResult(_ result: SearchResult) {
        isPresented = false
        onNavigate(result.elementId, result.position)
    }
    
    // Move to previous result
    func selectPrevious() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }
    
    // Move to next result
    func selectNext() {
        if selectedIndex < searchResults.count - 1 {
            selectedIndex += 1
        }
    }
    
    // MARK: - Appearance Helpers
    private func iconName(for type: CanvasElement.ElementType) -> String {
        switch type {
        case .webview: return "globe"
        case .pdf: return "doc.richtext"
        case .text: return "text.quote"
        case .drawing: return "pencil.tip"
        case .frame: return "rectangle.dashed"
        }
    }
    
    private func iconColor(for type: CanvasElement.ElementType) -> Color {
        switch type {
        case .webview: return .blue
        case .pdf: return .red
        case .text: return .green
        case .drawing: return .orange
        case .frame: return .purple
        }
    }
    
    private func typeName(for type: CanvasElement.ElementType) -> String {
        switch type {
        case .webview: return "Web"
        case .pdf: return "PDF"
        case .text: return "Text"
        case .drawing: return "Drawing"
        case .frame: return "Section"
        }
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.gray.opacity(0.3)
        
        SearchOverlayView(
            canvasManager: CanvasManager(),
            isPresented: .constant(true),
            onNavigate: { _, _ in }
        )
    }
    .frame(width: 600, height: 500)
}
