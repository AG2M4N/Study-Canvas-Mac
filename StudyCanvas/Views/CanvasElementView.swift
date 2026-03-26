import SwiftUI
import WebKit
import PDFKit
import Combine

struct CanvasElementView: View {
    let element: CanvasElement
    let canvasManager: CanvasManager
    let isSelected: Bool
    let onSelect: () -> Void
    let onDrag: ((CGPoint) -> Void)?
    let onDragEnd: (() -> Void)?
    let onDragStart: ((UUID, CGSize) -> Void)?
    let onDragPositionUpdate: ((CGPoint) -> Void)?
    @State private var size: CGSize
    @State private var position: CGPoint
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var isResizing = false
    @State private var resizeStartSize: CGSize = .zero
    @State private var autoScrollAccumulator: CGSize = .zero
    @Environment(\.zoomLevel) private var zoomLevel
    
    init(element: CanvasElement, canvasManager: CanvasManager, isSelected: Bool, onSelect: @escaping () -> Void, onDrag: ((CGPoint) -> Void)? = nil, onDragEnd: (() -> Void)? = nil, onDragStart: ((UUID, CGSize) -> Void)? = nil, onDragPositionUpdate: ((CGPoint) -> Void)? = nil) {
        self.element = element
        self.canvasManager = canvasManager
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onDrag = onDrag
        self.onDragEnd = onDragEnd
        self.onDragStart = onDragStart
        self.onDragPositionUpdate = onDragPositionUpdate
        _size = State(initialValue: element.size)
        _position = State(initialValue: element.position)
    }
    
    private func shouldRenderLive() -> Bool {
        // Always render all types live (no thumbnailing based on zoom or count)
        return true
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Title Bar - simplified to reduce complexity
            titleBar
            
            // Content
            contentView
        }
        .frame(width: max(50, size.width), height: max(50, size.height))
        .background(backgroundView)
        .overlay(overlayView)
        .rotationEffect(.degrees(element.rotation))
        .position(x: safePosition.x, y: safePosition.y)
        .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
        .transaction { transaction in
            // Disable all animations during drag/resize for performance
            if isDragging || isResizing {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .onChange(of: element.position) { newPosition in
            // Sync position when element is moved externally (e.g., by section drag)
            if !isDragging {
                position = newPosition
            }
        }
    }
    
    // Safe position that validates coordinates
    private var safePosition: CGPoint {
        let rawX = position.x + dragOffset.width
        let rawY = position.y + dragOffset.height
        
        // Ensure values are finite and within reasonable bounds
        let safeX = rawX.isFinite ? max(-50000, min(50000, rawX)) : position.x
        let safeY = rawY.isFinite ? max(-50000, min(50000, rawY)) : position.y
        
        return CGPoint(x: safeX, y: safeY)
    }
    
    // MARK: - Computed Views (broken out to reduce body complexity)
    
    private var titleBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Text(titleForElement(element.type))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
                
                if isSelected {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isResizing ? .accentColor.opacity(0.7) : .accentColor)
                        .help("Drag to resize")
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if resizeStartSize == .zero {
                                        resizeStartSize = size
                                    }
                                    isResizing = true
                                    let newWidth = max(150, resizeStartSize.width + value.translation.width)
                                    let newHeight = max(100, resizeStartSize.height + value.translation.height)
                                    size = CGSize(width: newWidth, height: newHeight)
                                }
                                .onEnded { _ in
                                    isResizing = false
                                    resizeStartSize = .zero
                                    var updatedElement = element
                                    updatedElement.size = size
                                    canvasManager.updateElement(updatedElement)
                                    canvasManager.saveCanvases()
                                }
                        )
                        .onHover { hovering in
                            if hovering {
                                NSCursor.resizeUpDown.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                }
                
                Button(action: {
                    canvasManager.removeElement(element)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
            )
            .gesture(optimizedDragGesture)
    }
    
    // MARK: - Optimized Drag Gesture
    private var optimizedDragGesture: some Gesture {
        // Use .global coordinate space to prevent jitter from the element moving under the cursor
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    autoScrollAccumulator = .zero
                    // Notify drag start with element size
                    onDragStart?(element.id, size)
                }
                
                // Validate translation values to prevent invalid geometry
                let translation = value.translation
                guard translation.width.isFinite && translation.height.isFinite else {
                    return
                }
                
                // Adjust translation for zoom level so element follows cursor exactly
                // Global translation is in screen pixels, but canvas is scaled by zoomLevel
                let adjustedWidth = translation.width / zoomLevel
                let adjustedHeight = translation.height / zoomLevel
                
                // Round to whole pixels to prevent sub-pixel jitter
                let clampedWidth = round(max(-10000, min(10000, adjustedWidth)))
                let clampedHeight = round(max(-10000, min(10000, adjustedHeight)))
                
                dragOffset = CGSize(width: clampedWidth, height: clampedHeight)
                
                // Update real-time position for alignment guides via callback
                let currentPos = CGPoint(
                    x: position.x + clampedWidth,
                    y: position.y + clampedHeight
                )
                onDragPositionUpdate?(currentPos)
                
                onDrag?(value.location)
            }
            .onEnded { value in
                let translation = value.translation
                
                // Validate before applying final position
                guard translation.width.isFinite && translation.height.isFinite else {
                    dragOffset = .zero
                    isDragging = false
                    onDragEnd?()
                    return
                }
                
                // Adjust for zoom level
                let adjustedWidth = translation.width / zoomLevel
                let adjustedHeight = translation.height / zoomLevel
                
                // Round final position to whole pixels
                let clampedWidth = round(max(-10000, min(10000, adjustedWidth)))
                let clampedHeight = round(max(-10000, min(10000, adjustedHeight)))
                
                position = CGPoint(
                    x: round(position.x + clampedWidth),
                    y: round(position.y + clampedHeight)
                )
                
                dragOffset = .zero
                autoScrollAccumulator = .zero
                isDragging = false
                
                var updatedElement = element
                updatedElement.position = position
                canvasManager.updateElement(updatedElement)
                
                // Report drag end
                onDragEnd?()
            }
    }
    
    // MARK: - Computed Properties for Performance
    
    private var contentView: some View {
        Group {
            switch element.type {
            case .drawing:
                DrawingElementView(element: element)
            case .text:
                TextElementView(element: element, canvasManager: canvasManager, isSelected: isSelected, onSelect: onSelect)
            case .webview:
                WebViewElementView(element: element, isSelected: isSelected)
                    .allowsHitTesting(true)
            case .pdf:
                PDFElementView(element: element, isSelected: isSelected)
                    .allowsHitTesting(true)
            case .frame:
                // Frames are rendered separately by FrameElementView
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: element.type == .text ? 0 : 12, style: .continuous)
            .fill(element.type == .text ? Color.clear : Color(NSColor.controlBackgroundColor))
    }
    
    private var overlayView: some View {
        Group {
            if isDragging || isSelected {
                RoundedRectangle(cornerRadius: element.type == .text ? 0 : 12, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            } else if element.type != .text {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .allowsHitTesting(!isSelected)
    }
    
    // Optimize shadow - use constant values for better performance
    private var shadowColor: Color {
        .black.opacity(0.1)
    }
    
    private var shadowRadius: CGFloat {
        6
    }
    
    private var shadowY: CGFloat {
        2
    }
    
    func titleForElement(_ type: CanvasElement.ElementType) -> String {
        switch type {
        case .drawing: return "Drawing"
        case .text: return "Text"
        case .webview: return "Webpage"
        case .pdf: return "PDF"
        case .frame: return "Frame"
        }
    }
}

struct ThumbnailView: View {
    let element: CanvasElement
    let type: String
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.1))
            
            VStack(spacing: 12) {
                Image(systemName: element.type == .webview ? "globe" : "doc.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                
                Text(type)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text("Tap to activate")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding()
        }
    }
}

struct ResizeHandle: View {
    @Binding var size: CGSize
    let onResizeEnd: () -> Void
    @State private var isResizing = false
    @State private var initialSize: CGSize = .zero
    
    enum HandlePosition {
        case bottomRight, bottomLeft, topRight, topLeft
        case right, left, top, bottom
    }
    
    var body: some View {
        ZStack {
            // Edge handles (behind corners)
            ResizeEdge(position: .right, size: $size, isResizing: $isResizing, initialSize: $initialSize, onResizeEnd: onResizeEnd)
            ResizeEdge(position: .left, size: $size, isResizing: $isResizing, initialSize: $initialSize, onResizeEnd: onResizeEnd)
            ResizeEdge(position: .top, size: $size, isResizing: $isResizing, initialSize: $initialSize, onResizeEnd: onResizeEnd)
            ResizeEdge(position: .bottom, size: $size, isResizing: $isResizing, initialSize: $initialSize, onResizeEnd: onResizeEnd)
            
            // Corner handles (on top for priority)
            ResizeCorner(position: .bottomRight, size: $size, isResizing: $isResizing, initialSize: $initialSize, onResizeEnd: onResizeEnd)
            ResizeCorner(position: .bottomLeft, size: $size, isResizing: $isResizing, initialSize: $initialSize, onResizeEnd: onResizeEnd)
            ResizeCorner(position: .topRight, size: $size, isResizing: $isResizing, initialSize: $initialSize, onResizeEnd: onResizeEnd)
            ResizeCorner(position: .topLeft, size: $size, isResizing: $isResizing, initialSize: $initialSize, onResizeEnd: onResizeEnd)
        }
        .allowsHitTesting(true)
    }
}

struct ResizeCorner: View {
    let position: ResizeHandle.HandlePosition
    @Binding var size: CGSize
    @Binding var isResizing: Bool
    @Binding var initialSize: CGSize
    let onResizeEnd: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        GeometryReader { geometry in
            Circle()
                .fill(Color.accentColor)
                .frame(width: isHovering || isResizing ? 14 : 12, height: isHovering || isResizing ? 14 : 12)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.3), radius: 4)
                .position(cornerPosition(in: geometry.size))
                .onHover { hovering in
                    isHovering = hovering
                }
                .cursor(cursorForPosition())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if initialSize == .zero {
                                initialSize = size
                            }
                            isResizing = true
                            updateSize(with: value.translation)
                        }
                        .onEnded { _ in
                            isResizing = false
                            initialSize = .zero
                            onResizeEnd()
                        }
                )
        }
        .allowsHitTesting(true)
    }
    
    func cornerPosition(in size: CGSize) -> CGPoint {
        switch position {
        case .bottomRight: return CGPoint(x: size.width - 5, y: size.height - 5)
        case .bottomLeft: return CGPoint(x: 5, y: size.height - 5)
        case .topRight: return CGPoint(x: size.width - 5, y: 5)
        case .topLeft: return CGPoint(x: 5, y: 5)
        default: return .zero
        }
    }
    
    func updateSize(with translation: CGSize) {
        let minSize: CGFloat = 100
        switch position {
        case .bottomRight:
            size.width = max(minSize, initialSize.width + translation.width)
            size.height = max(minSize, initialSize.height + translation.height)
        case .bottomLeft:
            size.width = max(minSize, initialSize.width - translation.width)
            size.height = max(minSize, initialSize.height + translation.height)
        case .topRight:
            size.width = max(minSize, initialSize.width + translation.width)
            size.height = max(minSize, initialSize.height - translation.height)
        case .topLeft:
            size.width = max(minSize, initialSize.width - translation.width)
            size.height = max(minSize, initialSize.height - translation.height)
        default: break
        }
    }
    
    func cursorForPosition() -> NSCursor {
        switch position {
        case .bottomRight, .topLeft:
            // Use system cursor for diagonal resize (NW-SE)
            if let cursor = NSCursor.perform(NSSelectorFromString("_windowResizeNorthWestSouthEastCursor"))?.takeUnretainedValue() as? NSCursor {
                return cursor
            }
            return .arrow
        case .bottomLeft, .topRight:
            // Use system cursor for diagonal resize (NE-SW)
            if let cursor = NSCursor.perform(NSSelectorFromString("_windowResizeNorthEastSouthWestCursor"))?.takeUnretainedValue() as? NSCursor {
                return cursor
            }
            return .arrow
        default: return .arrow
        }
    }
}

struct ResizeEdge: View {
    let position: ResizeHandle.HandlePosition
    @Binding var size: CGSize
    @Binding var isResizing: Bool
    @Binding var initialSize: CGSize
    let onResizeEnd: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(isHovering || isResizing ? Color.accentColor.opacity(0.4) : Color.clear)
                .frame(width: edgeFrame(in: geometry.size).width, height: edgeFrame(in: geometry.size).height)
                .position(edgePosition(in: geometry.size))
                .onHover { hovering in
                    isHovering = hovering
                }
                .cursor(cursorForPosition())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if initialSize == .zero {
                                initialSize = size
                            }
                            isResizing = true
                            updateSize(with: value.translation)
                        }
                        .onEnded { _ in
                            isResizing = false
                            initialSize = .zero
                            onResizeEnd()
                        }
                )
        }
        .allowsHitTesting(true)
    }
    
    func edgeFrame(in size: CGSize) -> CGSize {
        switch position {
        case .right, .left: return CGSize(width: 12, height: size.height - 30)
        case .top, .bottom: return CGSize(width: size.width - 30, height: 12)
        default: return .zero
        }
    }
    
    func edgePosition(in size: CGSize) -> CGPoint {
        switch position {
        case .right: return CGPoint(x: size.width - 6, y: size.height / 2)
        case .left: return CGPoint(x: 6, y: size.height / 2)
        case .top: return CGPoint(x: size.width / 2, y: 6)
        case .bottom: return CGPoint(x: size.width / 2, y: size.height - 6)
        default: return .zero
        }
    }
    
    func updateSize(with translation: CGSize) {
        let minSize: CGFloat = 100
        switch position {
        case .right:
            size.width = max(minSize, initialSize.width + translation.width)
        case .left:
            size.width = max(minSize, initialSize.width - translation.width)
        case .bottom:
            size.height = max(minSize, initialSize.height + translation.height)
        case .top:
            size.height = max(minSize, initialSize.height - translation.height)
        default: break
        }
    }
    
    func cursorForPosition() -> NSCursor {
        switch position {
        case .right, .left: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        default: return .arrow
        }
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onContinuousHover { phase in
            switch phase {
            case .active:
                cursor.push()
            case .ended:
                NSCursor.pop()
            }
        }
    }
}

struct DrawingElementView: View {
    let element: CanvasElement
    
    var body: some View {
        Color.white
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray.opacity(0.3))
            )
    }
}

struct TextElementView: View {
    let element: CanvasElement
    let canvasManager: CanvasManager
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var text: String
    @State private var textSize: CGFloat = 16
    @State private var textColor: Color = .black
    @FocusState private var isFocused: Bool
    
    init(element: CanvasElement, canvasManager: CanvasManager, isSelected: Bool, onSelect: @escaping () -> Void) {
        self.element = element
        self.canvasManager = canvasManager
        self.isSelected = isSelected
        self.onSelect = onSelect
        
        // Try to parse JSON content for styling or PDF note
        if let data = element.content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            _textSize = State(initialValue: json["size"] as? CGFloat ?? 16)
            if let colorHex = json["color"] as? String {
                _textColor = State(initialValue: Color(hex: colorHex))
            }
            _text = State(initialValue: json["text"] as? String ?? "")
        } else {
            _text = State(initialValue: element.content)
        }
    }
    
    private var isPDFNote: Bool {
        guard let data = element.content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return json["pdfElementId"] != nil
    }
    
    private var pdfNoteInfo: (pdfId: UUID, page: Int, selectedText: String)? {
        guard let data = element.content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pdfIdString = json["pdfElementId"] as? String,
              let pdfId = UUID(uuidString: pdfIdString),
              let page = json["pageNumber"] as? Int,
              let selectedText = json["selectedText"] as? String else {
            return nil
        }
        return (pdfId, page, selectedText)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // PDF Reference header (if this is a PDF note)
            if let noteInfo = pdfNoteInfo {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text("Page \(noteInfo.page + 1)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                        Spacer()
                        Button(action: {
                            // Jump to PDF page
                            jumpToPDFPage(noteInfo.pdfId, page: noteInfo.page)
                        }) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Text("\"\(noteInfo.selectedText.prefix(60))...\"")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                
                Divider()
            }
            
            ZStack {
                if text.isEmpty && !isFocused {
                    Text(isPDFNote ? "Your notes here..." : "Type here...")
                        .font(.system(size: textSize))
                        .foregroundColor(.gray.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(8)
                        .onTapGesture {
                            isFocused = true
                            onSelect()
                        }
                }
                
                TextEditor(text: $text)
                .font(.system(size: textSize))
                .foregroundColor(textColor)
                .background(Color.clear)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .onChange(of: text) { newValue in
                    saveText()
                }
                .onChange(of: isFocused) { focused in
                    if focused {
                        onSelect()
                    } else {
                        saveText()
                    }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isSelected {
                onSelect()
            }
            isFocused = true
        }
        .onChange(of: element.content) { newContent in
            // Update when style changes from toolbar
            if let data = newContent.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                textSize = json["size"] as? CGFloat ?? textSize
                if let colorHex = json["color"] as? String {
                    textColor = Color(hex: colorHex)
                }
            }
        }
        .onChange(of: isSelected) { selected in
            // Remove focus when element is deselected
            if !selected {
                isFocused = false
            }
        }
        .onAppear {
            // Auto-focus new empty text elements (but not PDF notes)
            if text.isEmpty && !isPDFNote {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFocused = true
                    onSelect()
                }
            }
        }
        }
    }
    
    private func jumpToPDFPage(_ pdfId: UUID, page: Int) {
        // Get the selected text to highlight
        guard let noteInfo = pdfNoteInfo else { return }
        
        // Post notification to jump to page and highlight
        NotificationCenter.default.post(
            name: NSNotification.Name("JumpToPDFPage"),
            object: nil,
            userInfo: [
                "pdfElementId": pdfId.uuidString,
                "pageIndex": page,
                "selectedText": noteInfo.selectedText
            ]
        )
    }
    
    private func saveText() {
        var jsonData: [String: Any] = [
            "text": text,
            "size": textSize,
            "color": textColor.hexString
        ]
        
        // Preserve PDF note information if this is a PDF note
        if let noteInfo = pdfNoteInfo {
            jsonData["pdfElementId"] = noteInfo.pdfId.uuidString
            jsonData["pageNumber"] = noteInfo.page
            jsonData["selectedText"] = noteInfo.selectedText
        }
        
        if let json = try? JSONSerialization.data(withJSONObject: jsonData),
           let jsonString = String(data: json, encoding: .utf8) {
            var updatedElement = element
            updatedElement.content = jsonString
            canvasManager.updateElement(updatedElement)
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: 1
        )
    }
}

struct WebViewElementView: View {
    let element: CanvasElement
    let isSelected: Bool
    @EnvironmentObject var canvasManager: CanvasManager
    @Environment(\.zoomLevel) private var zoomLevel
    @State private var isLoaded = false
    @State private var urlString: String
    @State private var displayURL: String = ""
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var isLoading = false
    @State private var loadProgress: Double = 0
    @State private var showBookmarks = false
    @State private var restoredState: Data?
    @State private var saveTimer: Timer?
    @State private var currentWebView: WKWebView?
    @StateObject private var navigationDelegate = WebViewNavigationDelegate()
    
    init(element: CanvasElement, isSelected: Bool) {
        self.element = element
        self.isSelected = isSelected
        let initialURL = element.content.isEmpty ? "https://www.google.com" : element.content
        _urlString = State(initialValue: initialURL)
        _displayURL = State(initialValue: initialURL)
        
        // Restore navigation state if available
        if let stateString = element.state,
           let stateData = Data(base64Encoded: stateString) {
            _restoredState = State(initialValue: stateData)
        }
    }
    
    var body: some View {
        ZStack {
            // Keep loaded content in background (always rendered once loaded)
            if isLoaded {
                LoadedWebView(
                    element: element,
                    urlString: $urlString,
                    displayURL: $displayURL,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    isLoading: $isLoading,
                    loadProgress: $loadProgress,
                    restoredState: $restoredState,
                    navigationDelegate: navigationDelegate,
                    onSnapshotCaptured: { thumbnailData in
                        saveThumbnail(thumbnailData)
                    }
                )
                .environmentObject(canvasManager)
                .id(element.id)
            }
            
            // Show preview overlay only when not loaded
            if !isLoaded {
                WebViewPreview(
                    urlString: urlString,
                    thumbnail: element.thumbnail,
                    isLoaded: $isLoaded
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isLoaded = true
                    }
                }
                .allowsHitTesting(true)
                .onChange(of: isSelected) { selected in
                    if selected && !isLoaded {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isLoaded = true
                        }
                    }
                }
            }
        }
    }
    
    private func saveThumbnail(_ data: String) {
        var updatedElement = element
        updatedElement.thumbnail = data
        canvasManager.updateElement(updatedElement)
    }
}

struct WebViewPreview: View {
    let urlString: String
    let thumbnail: String?
    @Binding var isLoaded: Bool
    
    var thumbnailImage: NSImage? {
        guard let thumbnail = thumbnail,
              let data = Data(base64Encoded: thumbnail) else {
            return nil
        }
        return NSImage(data: data)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Show thumbnail if available, otherwise gradient
                if let image = thumbnailImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
                        .clipped()
                        .overlay(
                            LinearGradient(
                                colors: [Color.black.opacity(0.3), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                } else {
                    LinearGradient(
                        colors: [Color.blue.opacity(0.1), Color.blue.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                
                // Invisible tap target to ensure entire area is tappable
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle())
                
                VStack(spacing: 12) {
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        
                        Text(urlString)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.7))
                    .allowsHitTesting(false)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.3), radius: 4)
                }
                .padding(12)
            }
        }
    }
}

struct LoadedWebView: View {
    let element: CanvasElement
    @Binding var urlString: String
    @Binding var displayURL: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var loadProgress: Double
    @Binding var restoredState: Data?
    @ObservedObject var navigationDelegate: WebViewNavigationDelegate
    let onSnapshotCaptured: (String) -> Void
    @EnvironmentObject var canvasManager: CanvasManager
    @State private var saveTimer: Timer?
    @State private var currentWebView: WKWebView?
    @State private var snapshotTimer: Timer?
    
    var body: some View {
        VStack(spacing: 0) {
            // Navigation Bar
            VStack(spacing: 0) {
                // Top bar with navigation controls
                HStack(spacing: 8) {
                    // Back button
                    Button(action: {
                        navigationDelegate.goBack()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(canGoBack ? .primary : .secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoBack)
                    .onTapGesture { } // Prevent tap from bubbling up
                    
                    // Forward button
                    Button(action: {
                        navigationDelegate.goForward()
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(canGoForward ? .primary : .secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoForward)
                    .onTapGesture { } // Prevent tap from bubbling up
                    
                    // Reload button
                    Button(action: {
                        if isLoading {
                            navigationDelegate.stopLoading()
                        } else {
                            navigationDelegate.reload()
                        }
                    }) {
                        Image(systemName: isLoading ? "xmark" : "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .onTapGesture { } // Prevent tap from bubbling up
                    
                    // URL field
                    HStack(alignment: .center, spacing: 6) {
                        Image(systemName: urlString.hasPrefix("https://") ? "lock.fill" : "globe")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(width: 12)
                        
                        TextField("Search or enter website", text: $displayURL)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)
                            .onSubmit {
                                urlString = displayURL
                            }
                        
                        if !displayURL.isEmpty {
                            Button(action: {
                                displayURL = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .onTapGesture { } // Prevent tap from bubbling up
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    
                    // Share button
                    Button(action: {
                        if let url = URL(string: urlString) {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .onTapGesture { } // Prevent tap from bubbling up
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
                .contentShape(Rectangle())
                .onTapGesture { } // Prevent deselection when clicking in header area
                
                // Progress bar
                if isLoading && loadProgress < 1.0 {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * loadProgress, height: 2)
                    }
                    .frame(height: 2)
                }
                
                Divider()
            }
            
            // Web content
            SafariWebView(
                element: element,
                urlString: $urlString,
                displayURL: $displayURL,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                isLoading: $isLoading,
                loadProgress: $loadProgress,
                restoredState: restoredState,
                navigationDelegate: navigationDelegate,
                onStateChanged: { stateData in
                    saveWebState(stateData)
                }
            )
            .background(Color.white)
            .onReceive(canvasManager.$shouldSaveWebStates) { shouldSave in
                // When user goes back, force save current state immediately
                if shouldSave {
                    forceSaveCurrentState()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: CanvasManager.cleanupNotification)) { _ in
                // Clean up resources when switching canvases
                cleanupWebViewResources()
            }
            .onChange(of: isLoading) { loading in
                if !loading && loadProgress >= 1.0 {
                    // Page finished loading, capture snapshot after a short delay
                    snapshotTimer?.invalidate()
                    snapshotTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                        captureSnapshot()
                    }
                }
            }
        }
        .onAppear {
            // Capture initial snapshot if page is already loaded
            if !isLoading {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    captureSnapshot()
                }
            }
        }
        .onDisappear {
            // Save state immediately when view disappears (e.g., switching canvases)
            forceSaveCurrentState()
            cleanupWebViewResources()
            snapshotTimer?.invalidate()
        }
    }
    
    private func captureSnapshot() {
        guard let webView = navigationDelegate.webView else { return }
        
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: webView.bounds.size)
        
        webView.takeSnapshot(with: config) { image, error in
            guard let image = image, error == nil else { return }
            
            // Calculate aspect ratio to match element size
            let sourceSize = image.size
            
            // Validate image has non-zero dimensions
            guard sourceSize.width > 0 && sourceSize.height > 0 else {
                print("Skipping snapshot: image has zero size")
                return
            }
            
            let targetAspect = sourceSize.width / sourceSize.height
            
            // Maximum quality thumbnail (1600px width - retina quality)
            let thumbnailWidth: CGFloat = 1600
            let thumbnailHeight = thumbnailWidth / targetAspect
            let thumbnailSize = CGSize(width: thumbnailWidth, height: thumbnailHeight)
            
            // Validate thumbnail size is valid
            guard thumbnailSize.width > 0 && thumbnailSize.height > 0,
                  !thumbnailSize.width.isNaN && !thumbnailSize.height.isNaN,
                  !thumbnailSize.width.isInfinite && !thumbnailSize.height.isInfinite else {
                print("Skipping snapshot: calculated thumbnail size is invalid")
                return
            }
            
            // Create highest-quality thumbnail with proper interpolation
            let thumbnail = NSImage(size: thumbnailSize)
            
            // Verify NSImage was created with valid size before locking focus
            guard thumbnail.size.width > 0 && thumbnail.size.height > 0 else {
                print("Skipping snapshot: NSImage created with zero size")
                return
            }
            
            thumbnail.lockFocus()
            
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(in: CGRect(origin: .zero, size: thumbnailSize),
                      from: CGRect(origin: .zero, size: sourceSize),
                      operation: .copy,
                      fraction: 1.0)
            thumbnail.unlockFocus()
            
            // Convert to base64 with PNG for lossless quality (or JPEG at 95% for smaller size)
            if let tiffData = thumbnail.tiffRepresentation,
               let bitmapImage = NSBitmapImageRep(data: tiffData) {
                // Use JPEG at 95% quality - good balance between quality and size
                if let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) {
                    let base64 = jpegData.base64EncodedString()
                    onSnapshotCaptured(base64)
                }
            }
        }
    }
    
    private func cleanupWebViewResources() {
        // Save state first
        forceSaveCurrentState()
        
        // Stop loading and clear resources
        if let webView = navigationDelegate.webView {
            webView.stopLoading()
            // Note: WKProcessPool manipulation is deprecated in macOS 12.0+
            // The system manages process pools automatically
        }
        
        // Clear timers
        saveTimer?.invalidate()
        saveTimer = nil
        
        // Clear webView reference
        navigationDelegate.webView = nil
        currentWebView = nil
    }
    
    private func forceSaveCurrentState() {
        saveTimer?.invalidate()
        
        // Capture current state from webView via navigation delegate
        if let webView = navigationDelegate.webView,
           let stateData = webView.interactionState as? Data {
            let state = stateData.base64EncodedString()
            let content = displayURL.isEmpty ? urlString : displayURL
            canvasManager.updateElementWebState(elementId: element.id, state: state, content: content)
        }
    }
    
    private func saveWebState(_ stateData: Data?) {
        guard let stateData = stateData else { return }
        
        // Debounce saving to avoid excessive updates
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak canvasManager] _ in
            let state = stateData.base64EncodedString()
            let content = self.displayURL.isEmpty ? self.urlString : self.displayURL
            canvasManager?.updateElementWebState(elementId: self.element.id, state: state, content: content)
        }
    }
}

class WebViewNavigationDelegate: NSObject, ObservableObject, WKNavigationDelegate {
    weak var webView: WKWebView?
    var displayURLBinding: Binding<String>?
    var canGoBackBinding: Binding<Bool>?
    var canGoForwardBinding: Binding<Bool>?
    var isLoadingBinding: Binding<Bool>?
    var loadProgressBinding: Binding<Double>?
    var onStateChanged: ((Data?) -> Void)?
    
    func goBack() {
        webView?.goBack()
    }
    
    func goForward() {
        webView?.goForward()
    }
    
    func reload() {
        webView?.reload()
    }
    
    func stopLoading() {
        webView?.stopLoading()
    }
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.isLoadingBinding?.wrappedValue = true
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.isLoadingBinding?.wrappedValue = false
            self.loadProgressBinding?.wrappedValue = 1.0
            self.displayURLBinding?.wrappedValue = webView.url?.absoluteString ?? ""
            self.canGoBackBinding?.wrappedValue = webView.canGoBack
            self.canGoForwardBinding?.wrappedValue = webView.canGoForward
            
            // Save web state (history, scroll position, etc.) after page loads
            self.saveWebState(webView)
        }
    }
    
    // Helper method to save web state
    private func saveWebState(_ webView: WKWebView) {
        if let stateData = webView.interactionState as? Data {
            self.onStateChanged?(stateData)
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // Ignore cancellation errors (code -999)
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        DispatchQueue.main.async {
            self.isLoadingBinding?.wrappedValue = false
        }
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // Ignore cancellation errors (code -999)
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        DispatchQueue.main.async {
            self.isLoadingBinding?.wrappedValue = false
        }
    }
}

struct SafariWebView: NSViewRepresentable {
    let element: CanvasElement
    @Binding var urlString: String
    @Binding var displayURL: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var loadProgress: Double
    let restoredState: Data?
    @ObservedObject var navigationDelegate: WebViewNavigationDelegate
    let onStateChanged: (Data?) -> Void
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        // Use persistent data store to save cookies and login sessions
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        // Enable modern web features
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = navigationDelegate
        
        // Set user agent to match Safari to avoid Google blocking embedded browsers
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        
        // Allow popups for OAuth flows
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView.uiDelegate = context.coordinator
        
        navigationDelegate.webView = webView
        navigationDelegate.displayURLBinding = $displayURL
        navigationDelegate.canGoBackBinding = $canGoBack
        navigationDelegate.canGoForwardBinding = $canGoForward
        navigationDelegate.isLoadingBinding = $isLoading
        navigationDelegate.loadProgressBinding = $loadProgress
        navigationDelegate.onStateChanged = onStateChanged
        
        // Observe progress
        context.coordinator.loadProgressBinding = $loadProgress
        
        webView.publisher(for: \.estimatedProgress)
            .receive(on: DispatchQueue.main)
            .sink { progress in
                Task { @MainActor in
                    context.coordinator.updateProgress(progress)
                }
            }
            .store(in: &context.coordinator.cancellables)
        
        // Restore state if available
        if let restoredState = restoredState {
            webView.interactionState = restoredState
            
            // Verify restoration worked after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if webView.url == nil {
                    self.loadURL(in: webView, urlString: urlString)
                }
            }
        } else {
            loadURL(in: webView, urlString: urlString)
        }
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Update navigation state asynchronously
        DispatchQueue.main.async {
            self.canGoBack = nsView.canGoBack
            self.canGoForward = nsView.canGoForward
        }
        
        // Only load if URL changed and coordinator hasn't tracked this URL yet
        let newURL = prepareURLString(urlString)
        if context.coordinator.lastLoadedURL != newURL && !urlString.isEmpty {
            context.coordinator.lastLoadedURL = newURL
            DispatchQueue.main.async {
                self.loadURL(in: nsView, urlString: urlString)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKUIDelegate {
        var cancellables = Set<AnyCancellable>()
        var loadProgressBinding: Binding<Double>?
        var lastLoadedURL: String = ""
        
        func updateProgress(_ progress: Double) {
            loadProgressBinding?.wrappedValue = progress
        }
        
        // Handle popup windows for OAuth
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Load popup requests in the same webview instead of blocking them
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
    
    private func prepareURLString(_ string: String) -> String {
        var finalURLString = string.trimmingCharacters(in: .whitespaces)
        
        // Check if it's a search query or URL
        if !finalURLString.contains(".") && !finalURLString.hasPrefix("http") {
            // Treat as Google search
            finalURLString = "https://www.google.com/search?q=" + finalURLString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        } else if !finalURLString.hasPrefix("http://") && !finalURLString.hasPrefix("https://") {
            finalURLString = "https://" + finalURLString
        }
        
        return finalURLString
    }
    
    private func loadURL(in webView: WKWebView, urlString: String) {
        let finalURLString = prepareURLString(urlString)
        if let url = URL(string: finalURLString) {
            webView.load(URLRequest(url: url))
        }
    }
}

struct PDFElementView: View {
    let element: CanvasElement
    let isSelected: Bool
    @EnvironmentObject var canvasManager: CanvasManager
    @Environment(\.zoomLevel) private var zoomLevel
    @State private var isLoaded = false
    @State private var showNoteCreator = false
    @State private var selectedText = ""
    @State private var currentPage = 0
    @State private var notePosition = CGPoint.zero
    @State private var notesExpanded = true
    @State private var highlights: [PDFHighlight] = []
    @State private var pdfDocument: PDFDocument?
    @State private var pdfView: PDFView?
    @State private var collapsedView = false
    @State private var selectedHighlightColor: NSColor = .red
    @State private var showColorPicker = false
    @State private var contextLevel: Double = 2 // 1=aggressive, 2=balanced, 3=contextual
    @State private var currentHighlightIndex: Int = 0
    
    private var pdfNotes: [CanvasElement] {
        guard let canvas = canvasManager.currentCanvas else { return [] }
        return canvas.elements.filter { note in
            guard let data = note.content.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pdfIdString = json["pdfElementId"] as? String,
                  let pdfId = UUID(uuidString: pdfIdString) else {
                return false
            }
            return pdfId == element.id
        }
    }
    
    private var pdfFileName: String {
        if let url = URL(string: element.content) {
            return url.lastPathComponent
        }
        return "PDF Document"
    }
    
    var body: some View {
        ZStack {
            // Keep loaded content in background (always rendered once loaded)
            if isLoaded {
                LoadedPDFView(
                    element: element,
                    showNoteCreator: $showNoteCreator,
                    selectedText: $selectedText,
                    currentPage: $currentPage,
                    notePosition: $notePosition,
                    notesExpanded: $notesExpanded,
                    highlights: $highlights,
                    pdfDocument: $pdfDocument,
                    pdfView: $pdfView,
                    collapsedView: $collapsedView,
                    selectedHighlightColor: $selectedHighlightColor,
                    showColorPicker: $showColorPicker,
                    contextLevel: $contextLevel,
                    currentHighlightIndex: $currentHighlightIndex,
                    pdfNotes: pdfNotes,
                    onSnapshotCaptured: { thumbnailData in
                        saveThumbnail(thumbnailData)
                    }
                )
                .environmentObject(canvasManager)
                .id(element.id)
            }
            
            // Show preview overlay only when not loaded
            if !isLoaded {
                PDFPreview(
                    fileName: pdfFileName,
                    thumbnail: element.thumbnail,
                    isLoaded: $isLoaded
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isLoaded = true
                    }
                }
                .allowsHitTesting(true)
                .onChange(of: isSelected) { selected in
                    if selected && !isLoaded {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isLoaded = true
                        }
                    }
                }
            }
        }
    }
    
    private func saveThumbnail(_ data: String) {
        var updatedElement = element
        updatedElement.thumbnail = data
        canvasManager.updateElement(updatedElement)
    }
}

struct PDFPreview: View {
    let fileName: String
    let thumbnail: String?
    @Binding var isLoaded: Bool
    
    var thumbnailImage: NSImage? {
        guard let thumbnail = thumbnail,
              let data = Data(base64Encoded: thumbnail) else {
            return nil
        }
        return NSImage(data: data)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Show thumbnail if available, otherwise gradient
                if let image = thumbnailImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
                        .clipped()
                        .overlay(
                            LinearGradient(
                                colors: [Color.black.opacity(0.3), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                } else {
                    LinearGradient(
                        colors: [Color.red.opacity(0.1), Color.red.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                
                // Invisible tap target to ensure entire area is tappable
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle())
                
                VStack(spacing: 12) {
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        
                        Text(fileName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.3), radius: 4)
                    .allowsHitTesting(false)
                }
                .padding(12)
                .allowsHitTesting(false)
            }
        }
    }
}

struct LoadedPDFView: View {
    let element: CanvasElement
    @Binding var showNoteCreator: Bool
    @Binding var selectedText: String
    @Binding var currentPage: Int
    @Binding var notePosition: CGPoint
    @Binding var notesExpanded: Bool
    @Binding var highlights: [PDFHighlight]
    @Binding var pdfDocument: PDFDocument?
    @Binding var pdfView: PDFView?
    @Binding var collapsedView: Bool
    @Binding var selectedHighlightColor: NSColor
    @Binding var showColorPicker: Bool
    @Binding var contextLevel: Double
    @Binding var currentHighlightIndex: Int
    let pdfNotes: [CanvasElement]
    let onSnapshotCaptured: (String) -> Void
    @EnvironmentObject var canvasManager: CanvasManager
    @State private var hasCapturedSnapshot = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if collapsedView {
                // Collapsed view showing only highlighted excerpts
                VStack(spacing: 0) {
                    // Context level control
                    HStack(spacing: 12) {
                        // Navigation
                        HStack(spacing: 8) {
                            Button(action: {
                                if currentHighlightIndex > 0 {
                                    currentHighlightIndex -= 1
                                    scrollToHighlight(at: currentHighlightIndex)
                                }
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11))
                                    .foregroundColor(currentHighlightIndex > 0 ? .white : .gray)
                            }
                            .buttonStyle(.plain)
                            .disabled(currentHighlightIndex == 0)
                            
                            Text("\(currentHighlightIndex + 1) / \(highlights.count)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.gray)
                                .frame(width: 60)
                            
                            Button(action: {
                                if currentHighlightIndex < highlights.count - 1 {
                                    currentHighlightIndex += 1
                                    scrollToHighlight(at: currentHighlightIndex)
                                }
                            }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11))
                                    .foregroundColor(currentHighlightIndex < highlights.count - 1 ? .white : .gray)
                            }
                            .buttonStyle(.plain)
                            .disabled(currentHighlightIndex >= highlights.count - 1)
                        }
                        
                        Divider()
                            .frame(height: 20)
                            .background(Color.gray.opacity(0.3))
                        
                        Text("Context")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.gray)
                        
                        Slider(value: $contextLevel, in: 1...3, step: 1)
                            .frame(width: 100)
                        
                        Text(contextLevel == 1 ? "Min" : contextLevel == 2 ? "Bal" : "Full")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                            .frame(width: 35)
                        
                        Spacer()
                        
                        Button(action: {
                            collapsedView = false
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 10))
                                Text("Full PDF")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.8))
                    
                    Divider()
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
                        ForEach(highlights.sorted(by: { $0.pageNumber < $1.pageNumber })) { highlight in
                            VStack(alignment: .leading, spacing: 16) {
                                // Page number and jump button
                                HStack {
                                    Text("PAGE \(highlight.pageNumber + 1)")
                                        .font(.system(size: 9, weight: .bold))
                                        .tracking(1)
                                        .foregroundColor(.gray)
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        // Immediately expand if collapsed
                                        if collapsedView {
                                            collapsedView = false
                                            // Wait for view to fully expand
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                                jumpToPageWithHighlight(highlight.pageNumber, text: highlight.text, color: highlight.color)
                                            }
                                        } else {
                                            // Already expanded, navigate immediately
                                            jumpToPageWithHighlight(highlight.pageNumber, text: highlight.text, color: highlight.color)
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Text("View")
                                                .font(.system(size: 11, weight: .medium))
                                            Image(systemName: "arrow.right")
                                                .font(.system(size: 9, weight: .semibold))
                                        }
                                        .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .onTapGesture { } // Prevent tap from bubbling up
                                }
                                
                                // Content with context based on level
                                VStack(alignment: .leading, spacing: 10) {
                                    // Show context based on level: 1=none, 2=some, 3=full
                                    if contextLevel >= 2 && !highlight.contextBefore.isEmpty {
                                        Text(highlight.contextBefore)
                                            .font(.system(size: 14))
                                            .foregroundColor(.gray)
                                            .lineSpacing(4)
                                            .lineLimit(contextLevel == 2 ? 5 : nil)
                                    }
                                    
                                    // Highlighted text with left accent
                                    HStack(alignment: .top, spacing: 0) {
                                        Rectangle()
                                            .fill(Color(hex: highlight.color))
                                            .frame(width: 4)
                                        
                                        Text(highlight.text)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.white)
                                            .lineSpacing(5)
                                            .padding(.leading, 16)
                                    }
                                    
                                    if contextLevel >= 2 && !highlight.contextAfter.isEmpty {
                                        Text(highlight.contextAfter)
                                            .font(.system(size: 14))
                                            .foregroundColor(.gray)
                                            .lineSpacing(4)
                                            .lineLimit(contextLevel == 2 ? 5 : nil)
                                    }
                                }
                                
                                Divider()
                                    .background(Color.gray.opacity(0.3))
                            }
                        }
                    }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 24)
                    }
                }
                .background(Color.black)
                .transition(.opacity.animation(.easeInOut(duration: 0.35).delay(0.1)))
            } else {
                // Normal PDF view
                PDFKitView(
                    element: element,
                    url: URL(fileURLWithPath: element.content),
                    onPageChanged: { pageIndex in
                        currentPage = pageIndex
                        savePDFState(pageIndex: pageIndex)
                    },
                    onTextSelected: { text, pdfView in
                        DispatchQueue.main.async {
                            selectedText = text
                            // Calculate position for note next to PDF
                            notePosition = CGPoint(
                                x: element.position.x + element.size.width + 20,
                                y: element.position.y
                            )
                            showNoteCreator = true
                        }
                    },
                    onDocumentLoaded: { document, view in
                        DispatchQueue.main.async {
                            pdfDocument = document
                            pdfView = view
                            
                            // Capture thumbnail after page restoration completes
                            if !hasCapturedSnapshot {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    capturePDFSnapshot(from: view)
                                }
                            }
                        }
                    },
                    onHighlightDoubleTap: { point, pageIndex in
                        removeHighlightAt(point: point, pageIndex: pageIndex)
                    }
                )
                .background(Color.white)
                .transition(.opacity.animation(.easeInOut(duration: 0.35).delay(0.1)))
            }
            
            VStack {
                // Stack toggle button (appears when there are notes)
                if !pdfNotes.isEmpty {
                    Button(action: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            notesExpanded.toggle()
                            toggleNotesStack()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: notesExpanded ? "square.stack.3d.down.right" : "square.stack.3d.up")
                            Text(notesExpanded ? "Stack Notes" : "Expand Notes")
                            Text("(\(pdfNotes.count))")
                                .font(.system(size: 10))
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .cornerRadius(6)
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                
                // Highlight button (appears when text is selected)
                if !selectedText.isEmpty && showNoteCreator {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Button(action: {
                                addHighlight()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "highlighter")
                                    Text("Highlight")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(selectedHighlightColor))
                                .cornerRadius(8)
                                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                            }
                            .buttonStyle(.plain)
                            
                            // Color picker toggle
                            Button(action: {
                                showColorPicker.toggle()
                            }) {
                                Image(systemName: "paintpalette")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.gray)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        
                            Button(action: {
                                createNote()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "note.text.badge.plus")
                                    Text("Note")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .cornerRadius(8)
                                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Color palette
                        if showColorPicker {
                            HStack(spacing: 10) {
                                ForEach([
                                    NSColor.red,
                                    NSColor.systemYellow,
                                    NSColor.systemBlue,
                                    NSColor.systemGreen,
                                    NSColor.systemOrange,
                                    NSColor.systemPurple
                                ], id: \.self) { color in
                                    Button(action: {
                                        selectedHighlightColor = color
                                        showColorPicker = false
                                    }) {
                                        Circle()
                                            .fill(Color(color))
                                            .frame(width: 26, height: 26)
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(selectedHighlightColor == color ? Color.white : Color.clear, lineWidth: 3)
                                            )
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(selectedHighlightColor == color ? Color.black : Color.clear, lineWidth: 1.5)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(10)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(10)
                            .shadow(color: .black.opacity(0.3), radius: 8)
                            .transition(.scale.combined(with: .opacity).animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.05)))
                        }
                    }
                    .transition(.scale.combined(with: .opacity).animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.1)))
                }
                
                // Collapse/Expand highlights button
                if !highlights.isEmpty {
                    Button(action: {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.75).delay(0.08)) {
                            collapsedView.toggle()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: collapsedView ? "doc.text" : "list.bullet.rectangle")
                            Text(collapsedView ? "Full PDF" : "Show Highlights")
                            Text("(\(highlights.count))")
                                .font(.system(size: 10))
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.8))
                        .cornerRadius(6)
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .animation(.spring(response: 0.3), value: showNoteCreator)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: collapsedView)
        .onAppear {
            loadHighlights()
            // Reapply highlights after a short delay to ensure PDF is loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                reapplyHighlights()
            }
        }
        .onChange(of: collapsedView) { _ in
            // Ensure highlights are visible when returning to PDF view
            if !collapsedView {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    reapplyHighlights()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: CanvasManager.cleanupNotification)) { _ in
            // Clean up PDF resources when switching canvases
            cleanupPDFResources()
        }
        .onDisappear {
            // Save current state before cleanup
            saveCombinedState()
            canvasManager.saveCanvases()
            // Clean up when view disappears
            cleanupPDFResources()
        }
    }
    
    private func addHighlight() {
        guard !selectedText.isEmpty, let document = pdfDocument else { return }
        
        let pageIndex = currentPage
        
        // Extract context before and after
        let (contextBefore, contextAfter) = extractContext(for: selectedText, on: pageIndex)
        
        // Convert NSColor to hex
        let colorHex = selectedHighlightColor.toHex()
        
        // Capture bounds for multi-line support
        var boundsArray: [CGRect] = []
        if let page = document.page(at: pageIndex) {
            let selections = document.findString(selectedText, withOptions: .caseInsensitive)
            for selection in selections {
                let selectionsByLine = selection.selectionsByLine()
                for lineSelection in selectionsByLine {
                    guard let selPage = lineSelection.pages.first, selPage == page else { continue }
                    boundsArray.append(lineSelection.bounds(for: selPage))
                }
            }
        }
        
        let highlight = PDFHighlight(
            text: selectedText,
            pageNumber: pageIndex,
            contextBefore: contextBefore,
            contextAfter: contextAfter,
            color: colorHex,
            bounds: boundsArray
        )
        
        highlights.append(highlight)
        saveHighlights()
        
        // Also highlight in the PDF (permanently)
        highlightTextInPDF(selectedText, color: selectedHighlightColor)
        
        selectedText = ""
        showNoteCreator = false
        showColorPicker = false
    }
    
    // Scroll to specific highlight in collapsed view
    private func scrollToHighlight(at index: Int) {
        // This would require ScrollViewReader - placeholder for now
        // In _mplementation, wrap highlights in ScrollViewReader
        // and use scrollTo with the highlight ID
    }
    
    // Remove highlight at a specific point
    private func removeHighlightAt(point: CGPoint, pageIndex: Int) {
        guard let document = pdfDocument,
              let _ = document.page(at: pageIndex) else {
            return
        }
        
        // Find which highlight was tapped (with expanded hit area)
        var highlightToRemove: PDFHighlight?
        let tolerance: CGFloat = 10 // pixels of tolerance
        
        for highlight in highlights where highlight.pageNumber == pageIndex {
            // Check if point intersects with any of the highlight bounds
            for bounds in highlight.bounds {
                // Expand bounds slightly for easier hit detection
                let expandedBounds = bounds.insetBy(dx: -tolerance, dy: -tolerance)
                if expandedBounds.contains(point) {
                    highlightToRemove = highlight
                    break
                }
            }
            if highlightToRemove != nil { break }
        }
        
        // Remove from our array
        if let highlightToRemove = highlightToRemove {
            highlights.removeAll { $0.id == highlightToRemove.id }
            saveCombinedState()
            
            // Remove annotations from PDF
            reapplyHighlights()
        }
    }
    
    // Extract context before and after selected text
    private func extractContext(for text: String, on pageIndex: Int) -> (String, String) {
        guard let document = pdfDocument,
              let page = document.page(at: pageIndex),
              let pageContent = page.string else {
            return ("", "")
        }
        
        // Find the selected text in the page content
        guard let range = pageContent.range(of: text) else {
            return ("", "")
        }
        
        // More context for better comprehension (5 lines for balanced, 10 for full)
        let contextLines = 5
        
        // Get context before
        let beforeStartIndex = pageContent.startIndex
        let beforeEndIndex = range.lowerBound
        let beforeText = String(pageContent[beforeStartIndex..<beforeEndIndex])
        let beforeLines = beforeText.components(separatedBy: .newlines)
        let contextBefore = beforeLines.suffix(contextLines).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Get context after
        let afterStartIndex = range.upperBound
        let afterEndIndex = pageContent.endIndex
        let afterText = String(pageContent[afterStartIndex..<afterEndIndex])
        let afterLines = afterText.components(separatedBy: .newlines)
        let contextAfter = afterLines.prefix(contextLines).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        
        return (contextBefore, contextAfter)
    }
    
    // Capture PDF thumbnail
    private func capturePDFSnapshot(from pdfView: PDFView) {
        guard !hasCapturedSnapshot,
              let currentPage = pdfView.currentPage else { return }
        
        hasCapturedSnapshot = true
        
        // Get page bounds to maintain aspect ratio
        let pageBounds = currentPage.bounds(for: .mediaBox)
        
        // Validate page bounds are non-zero
        guard pageBounds.width > 0 && pageBounds.height > 0 else {
            print("Skipping PDF snapshot: page has zero size")
            hasCapturedSnapshot = false
            return
        }
        
        let pageAspect = pageBounds.width / pageBounds.height
        
        // Validate aspect ratio
        guard !pageAspect.isNaN && !pageAspect.isInfinite && pageAspect > 0 else {
            print("Skipping PDF snapshot: invalid page aspect ratio")
            hasCapturedSnapshot = false
            return
        }
        
        // Maximum quality thumbnail (1600px width - retina quality)
        let thumbnailWidth: CGFloat = 1600
        let thumbnailHeight = thumbnailWidth / pageAspect
        let thumbnailSize = CGSize(width: thumbnailWidth, height: thumbnailHeight)
        
        // Validate thumbnail size thoroughly
        guard thumbnailSize.width > 0 && thumbnailSize.height > 0,
              !thumbnailSize.width.isNaN && !thumbnailSize.height.isNaN,
              !thumbnailSize.width.isInfinite && !thumbnailSize.height.isInfinite else {
            print("Skipping PDF snapshot: calculated thumbnail size is invalid")
            hasCapturedSnapshot = false
            return
        }
        
        // Create highest-quality thumbnail
        let thumbnail = currentPage.thumbnail(of: thumbnailSize, for: .mediaBox)
        
        // Validate thumbnail has valid size
        guard thumbnail.size.width > 0 && thumbnail.size.height > 0 else {
            print("Skipping PDF snapshot: generated thumbnail has zero size")
            hasCapturedSnapshot = false
            return
        }
        
        // Convert to JPEG at 95% quality - excellent quality with reasonable size
        if let tiffData = thumbnail.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) {
            let base64 = jpegData.base64EncodedString()
            onSnapshotCaptured(base64)
        }
    }
    
    // Jump to a specific page
    private func jumpToPage(_ pageIndex: Int) {
        guard let document = pdfDocument,
              let page = document.page(at: pageIndex),
              let view = pdfView else {
            return
        }
        
        view.go(to: page)
    }
    
    // Jump to page and show lighting effect on highlighted text
    private func jumpToPageWithHighlight(_ pageIndex: Int, text: String, color: String) {
        guard let document = pdfDocument,
              let page = document.page(at: pageIndex),
              let view = pdfView else {
            return
        }
        
        // Ensure we're on the main thread and PDFView is ready
        DispatchQueue.main.async {
            // Update current page first
            self.currentPage = pageIndex
            
            // Then navigate
            view.go(to: page)
            
            // Scroll to ensure the page is visible
            if let scrollView = view.documentView?.enclosingScrollView {
                scrollView.flashScrollers()
            }
        }
        
        // Add temporary flash effect after navigation settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let selections = document.findString(text, withOptions: .caseInsensitive)
            
            for selection in selections {
                let selectionsByLine = selection.selectionsByLine()
                for lineSelection in selectionsByLine {
                    guard let selPage = lineSelection.pages.first,
                          selPage == page else { continue }
                    let bounds = lineSelection.bounds(for: selPage)
                    
                    // Create flash highlight
                    let flash = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                    flash.color = NSColor.white.withAlphaComponent(0.8)
                    page.addAnnotation(flash)
                    
                    // Fade out the flash
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        flash.color = NSColor.white.withAlphaComponent(0.4)
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        page.removeAnnotation(flash)
                    }
                }
            }
        }
    }
    
    // Highlight text in PDF (permanently) - only on current page
    private func highlightTextInPDF(_ text: String, color: NSColor) {
        guard let document = pdfDocument,
              let page = document.page(at: currentPage) else {
            return
        }
        
        // Only search on the current page, not entire document
        let selections = document.findString(text, withOptions: .caseInsensitive)
        
        for selection in selections {
            let selectionsByLine = selection.selectionsByLine()
            for lineSelection in selectionsByLine {
                // Only highlight if it's on the current page
                guard let selPage = lineSelection.pages.first,
                      selPage == page else { continue }
                let bounds = lineSelection.bounds(for: selPage)
                
                let highlight = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                highlight.color = color.withAlphaComponent(0.4)
                page.addAnnotation(highlight)
                // No removal - highlight stays permanently
            }
        }
    }
    
    // Re-apply all highlights when loading
    private func reapplyHighlights() {
        guard let document = pdfDocument else { return }
        
        // First, clear all existing highlight annotations to prevent duplicates
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let annotations = page.annotations.filter { $0.type == "Highlight" }
            for annotation in annotations {
                page.removeAnnotation(annotation)
            }
        }
        
        // Now add highlights from our stored data
        for highlight in highlights {
            guard let page = document.page(at: highlight.pageNumber) else { continue }
            let color = NSColor(hex: highlight.color) ?? .yellow
            
            let selections = document.findString(highlight.text, withOptions: .caseInsensitive)
            for selection in selections {
                let selectionsByLine = selection.selectionsByLine()
                for lineSelection in selectionsByLine {
                    guard let selPage = lineSelection.pages.first,
                          selPage == page else { continue }
                    let bounds = lineSelection.bounds(for: selPage)
                    
                    let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                    annotation.color = color.withAlphaComponent(0.4)
                    annotation.userName = "StudyCanvas_\(highlight.id.uuidString)" // Mark as ours
                    page.addAnnotation(annotation)
                }
            }
        }
    }
    
    // Save highlights to element state
    private func saveHighlights() {
        saveCombinedState()
    }
    
    // Clean up PDF resources to save memory
    private func cleanupPDFResources() {
        // Save current state first
        saveCombinedState()
        
        // Clear PDF document and view to release memory
        if let view = pdfView {
            view.document = nil
        }
        pdfDocument = nil
        pdfView = nil
        
        // Clear highlights array (they're already saved)
        // Keep a small footprint by not clearing if count is reasonable
        if highlights.count > 50 {
            highlights = []
        }
    }
    
    // Load highlights from element state
    private func loadHighlights() {
        guard let state = element.state,
              let data = state.data(using: .utf8) else {
            return
        }
        
        // Define the combined state structure
        struct PDFState: Codable {
            let pageIndex: Int
            let highlights: [PDFHighlight]
        }
        
        // Try new combined format first
        if let decoded = try? JSONDecoder().decode(PDFState.self, from: data) {
            highlights = decoded.highlights
            currentPage = decoded.pageIndex
        }
        // Fallback: try old format (just highlights array)
        else if let decoded = try? JSONDecoder().decode([PDFHighlight].self, from: data) {
            highlights = decoded
        }
        // Fallback: try old format (just page index)
        else if let decoded = try? JSONDecoder().decode([String: Int].self, from: data),
                let pageIndex = decoded["pageIndex"] {
            currentPage = pageIndex
        }
    }
    
    private func createNote() {
        let noteData = (element.id, currentPage, selectedText, notePosition)
        DispatchQueue.main.async {
            canvasManager.addPDFNote(
                pdfElementId: noteData.0,
                pageNumber: noteData.1,
                selectedText: noteData.2,
                position: noteData.3
            )
        }
        showNoteCreator = false
        selectedText = ""
    }
    
    private func toggleNotesStack() {
        guard let canvas = canvasManager.currentCanvas,
              let canvasIndex = canvasManager.canvases.firstIndex(where: { $0.id == canvas.id }) else {
            return
        }
        
        // Get all notes for this PDF
        let notes = pdfNotes
        
        // Base position for stacking
        let stackX = element.position.x + element.size.width + 20
        let stackY = element.position.y
        
        for (index, note) in notes.enumerated() {
            guard let noteIndex = canvasManager.canvases[canvasIndex].elements.firstIndex(where: { $0.id == note.id }) else {
                continue
            }
            
            var updatedNote = canvasManager.canvases[canvasIndex].elements[noteIndex]
            
            if notesExpanded {
                // Expanded: vertical cascade with offset
                let verticalSpacing: CGFloat = 160
                let horizontalOffset: CGFloat = CGFloat(index % 2) * 15
                updatedNote.position = CGPoint(
                    x: stackX + horizontalOffset,
                    y: stackY + (CGFloat(index) * verticalSpacing)
                )
            } else {
                // Collapsed: all stacked in one position with slight rotation
                updatedNote.position = CGPoint(x: stackX, y: stackY)
                updatedNote.rotation = Double(index) * 2.0 // Slight rotation for depth
            }
            
            canvasManager.canvases[canvasIndex].elements[noteIndex] = updatedNote
        }
        
        canvasManager.currentCanvas = canvasManager.canvases[canvasIndex]
        canvasManager.saveCanvases()
    }
    
    private func savePDFState(pageIndex: Int) {
        currentPage = pageIndex
        saveCombinedState()
        
        // Update thumbnail to show current page
        if let view = pdfView {
            // Reset flag to allow new snapshot
            hasCapturedSnapshot = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.capturePDFSnapshot(from: view)
            }
        }
    }
    
    // Save both highlights and page state together
    private func saveCombinedState() {
        struct PDFState: Codable {
            let pageIndex: Int
            let highlights: [PDFHighlight]
        }
        
        let state = PDFState(pageIndex: currentPage, highlights: highlights)
        
        guard let stateData = try? JSONEncoder().encode(state),
              let stateString = String(data: stateData, encoding: .utf8) else { return }
        
        var updatedElement = element
        updatedElement.state = stateString
        DispatchQueue.main.async {
            canvasManager.updateElement(updatedElement)
        }
    }
}

struct PDFHighlight: Identifiable, Codable {
    let id: UUID
    let text: String
    let pageNumber: Int
    let contextBefore: String
    let contextAfter: String
    let color: String // Hex color
    var bounds: [CGRect] // Support multi-line highlights
    
    init(id: UUID = UUID(), text: String, pageNumber: Int, contextBefore: String = "", contextAfter: String = "", color: String = "#FF0000", bounds: [CGRect] = []) {
        self.id = id
        self.text = text
        self.pageNumber = pageNumber
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.color = color
        self.bounds = bounds
    }
}

struct PDFKitView: NSViewRepresentable {
    let element: CanvasElement
    let url: URL
    let onPageChanged: (Int) -> Void
    let onTextSelected: (String, PDFView) -> Void
    let onDocumentLoaded: (PDFDocument, PDFView) -> Void
    let onHighlightDoubleTap: (CGPoint, Int) -> Void
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.displayDirection = .vertical
        
        // Disable page snapping for free scrolling
        if let scrollView = pdfView.documentView?.enclosingScrollView {
            scrollView.verticalPageScroll = 0
            scrollView.horizontalPageScroll = 0
        }
        
        context.coordinator.pdfView = pdfView
        context.coordinator.elementId = element.id
        context.coordinator.onHighlightDoubleTap = onHighlightDoubleTap
        
        // Add double-click gesture recognizer
        let doubleTapGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTapGesture.numberOfClicksRequired = 2
        doubleTapGesture.delaysPrimaryMouseButtonEvents = false
        pdfView.addGestureRecognizer(doubleTapGesture)
        
        if let document = PDFDocument(url: url) {
            pdfView.document = document
            onDocumentLoaded(document, pdfView)
            context.coordinator.document = document
            
            // Restore saved page if available
            if let stateString = element.state,
               let stateData = stateString.data(using: .utf8) {
                
                // Define combined state structure
                struct PDFState: Codable {
                    let pageIndex: Int
                    let highlights: [PDFHighlight]
                }
                
                // Try new combined format
                if let state = try? JSONDecoder().decode(PDFState.self, from: stateData),
                   state.pageIndex < document.pageCount,
                   let page = document.page(at: state.pageIndex) {
                    pdfView.go(to: page)
                    context.coordinator.lastPageIndex = state.pageIndex
                }
                // Fallback: try old format
                else if let state = try? JSONDecoder().decode([String: Int].self, from: stateData),
                        let pageIndex = state["pageIndex"],
                        pageIndex < document.pageCount,
                        let page = document.page(at: pageIndex) {
                    pdfView.go(to: page)
                    context.coordinator.lastPageIndex = pageIndex
                }
            }
        }
        
        // Observe page changes
        NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged,
            object: pdfView,
            queue: .main
        ) { _ in
            if let currentPage = pdfView.currentPage,
               let document = pdfView.document {
                let pageIndex = document.index(for: currentPage)
                onPageChanged(pageIndex)
            }
        }
        
        // Observe text selection
        NotificationCenter.default.addObserver(
            forName: .PDFViewSelectionChanged,
            object: pdfView,
            queue: .main
        ) { _ in
            if let selection = pdfView.currentSelection,
               let text = selection.string, !text.isEmpty {
                onTextSelected(text, pdfView)
            }
        }
        
        // Observe highlight and jump requests
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("JumpToPDFPage"),
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let pdfIdString = userInfo["pdfElementId"] as? String,
               let pageIndex = userInfo["pageIndex"] as? Int,
               let selectedText = userInfo["selectedText"] as? String,
               pdfIdString == context.coordinator.elementId?.uuidString,
               let document = pdfView.document,
               pageIndex < document.pageCount,
               let page = document.page(at: pageIndex) {
                
                // Jump to page
                pdfView.go(to: page)
                context.coordinator.lastPageIndex = pageIndex
                
                // Highlight text after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    context.coordinator.highlightText(selectedText, on: page)
                }
            }
        }
        
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        // Check if state changed and navigate to new page
        if let stateString = element.state,
           let stateData = stateString.data(using: .utf8),
           let document = nsView.document {
            
            // Define combined state structure
            struct PDFState: Codable {
                let pageIndex: Int
                let highlights: [PDFHighlight]
            }
            
            var pageIndex: Int?
            
            // Try new combined format
            if let state = try? JSONDecoder().decode(PDFState.self, from: stateData) {
                pageIndex = state.pageIndex
            }
            // Fallback: try old format
            else if let state = try? JSONDecoder().decode([String: Int].self, from: stateData) {
                pageIndex = state["pageIndex"]
            }
            
            if let pageIndex = pageIndex,
               pageIndex < document.pageCount,
               pageIndex != context.coordinator.lastPageIndex {
                if let page = document.page(at: pageIndex) {
                    nsView.go(to: page)
                    context.coordinator.lastPageIndex = pageIndex
                    
                    // Try to find and highlight the text on the page
                    if let selectedText = context.coordinator.selectedTextToHighlight {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            context.coordinator.highlightText(selectedText, on: page)
                        }
                        context.coordinator.selectedTextToHighlight = nil
                    }
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        weak var pdfView: PDFView?
        var document: PDFDocument?
        var highlightAnnotation: PDFAnnotation?
        var lastPageIndex: Int = -1
        var selectedTextToHighlight: String?
        var elementId: UUID?
        var onHighlightDoubleTap: ((CGPoint, Int) -> Void)?
        
        @objc func handleDoubleTap(_ gesture: NSClickGestureRecognizer) {
            guard gesture.state == .ended else { return }
            
            guard let pdfView = pdfView,
                  let document = document,
                  let currentPage = pdfView.currentPage else {
                return
            }
            
            let locationInView = gesture.location(in: pdfView)
            let locationInPage = pdfView.convert(locationInView, to: currentPage)
            let pageIndex = document.index(for: currentPage)
            
            // Ensure this runs on main thread
            DispatchQueue.main.async {
                self.onHighlightDoubleTap?(locationInPage, pageIndex)
            }
        }
        
        func highlightText(_ searchText: String, on page: PDFPage) {
            // Remove previous highlight
            if let previousHighlight = highlightAnnotation {
                previousHighlight.page?.removeAnnotation(previousHighlight)
                highlightAnnotation = nil
            }
            
            // Search for the text on the page using document search
            guard let document = self.document else { return }
            
            let selections = document.findString(searchText, withOptions: .caseInsensitive)
            
            // Find selection on this specific page
            guard let selection = selections.first(where: { $0.pages.contains(page) }) else {
                return
            }
            
            // Get bounds of the selected text
            let bounds = selection.bounds(for: page)
            
            // Create highlight annotation for the text
            let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            annotation.color = NSColor.yellow.withAlphaComponent(0.5)
            
            page.addAnnotation(annotation)
            highlightAnnotation = annotation
            
            // Remove highlight after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                page.removeAnnotation(annotation)
                self.highlightAnnotation = nil
            }
        }
    }
}

// MARK: - Color Extensions
extension NSColor {
    func toHex() -> String {
        guard let rgbColor = self.usingColorSpace(.deviceRGB) else {
            return "#FFFF00"
        }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
    
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

#Preview {
    CanvasElementView(
        element: CanvasElement(
            id: UUID(),
            type: .text,
            position: CGPoint(x: 100, y: 100),
            size: CGSize(width: 300, height: 200),
            rotation: 0,
            zIndex: 0,
            content: ""
        ),
        canvasManager: CanvasManager(),
        isSelected: false,
        onSelect: {}
    )
}
