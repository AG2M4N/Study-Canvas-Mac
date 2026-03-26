import SwiftUI

// MARK: - Grid Overlay
struct GridOverlay: View {
    let canvasSize: CGSize
    let gridSize: CGFloat
    let showGrid: Bool
    
    var body: some View {
        if showGrid {
            GeometryReader { _ in
                Path { path in
                    // Draw vertical lines
                    var x: CGFloat = 0
                    while x <= canvasSize.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                        x += gridSize
                    }
                    
                    // Draw horizontal lines
                    var y: CGFloat = 0
                    while y <= canvasSize.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                        y += gridSize
                    }
                }
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Alignment Guides View
struct AlignmentGuidesView: View {
    let guides: [AlignmentGuide]
    let canvasSize: CGSize
    
    var body: some View {
        ForEach(guides) { guide in
            switch guide.type {
            case .vertical:
                Rectangle()
                    .fill(Color.pink.opacity(0.8))
                    .frame(width: 1, height: canvasSize.height)
                    .position(x: guide.position, y: canvasSize.height / 2)
            case .horizontal:
                Rectangle()
                    .fill(Color.pink.opacity(0.8))
                    .frame(width: canvasSize.width, height: 1)
                    .position(x: canvasSize.width / 2, y: guide.position)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Organization Toolbar
struct OrganizationToolbar: View {
    @ObservedObject var canvasManager: CanvasManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Grid toggle
            Toggle(isOn: $canvasManager.showGrid) {
                Label("Grid", systemImage: "grid")
            }
            .toggleStyle(.button)
            .help("Show Grid")
            
            Divider()
                .frame(height: 20)
            
            // Draw Section mode
            Toggle(isOn: $canvasManager.isDrawingSectionMode) {
                Label("Section", systemImage: "rectangle.dashed")
            }
            .toggleStyle(.button)
            .help("Draw Section - Click and drag to create")
            .onChange(of: canvasManager.isDrawingSectionMode) { newValue in
                if newValue {
                    // Turn off connection mode when entering section mode
                    canvasManager.isConnectionMode = false
                }
            }
            
            // Section color picker (only shown when in draw mode)
            if canvasManager.isDrawingSectionMode {
                Menu {
                    ForEach(FrameColors.presets, id: \.hex) { preset in
                        Button(action: {
                            canvasManager.sectionDrawingColor = preset.hex
                        }) {
                            HStack {
                                Circle()
                                    .fill(Color(hex: preset.hex))
                                    .frame(width: 12, height: 12)
                                Text(preset.name)
                                if canvasManager.sectionDrawingColor == preset.hex {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Circle()
                        .fill(Color(hex: canvasManager.sectionDrawingColor))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
            
            Divider()
                .frame(height: 20)
            
            // Connection mode
            Toggle(isOn: $canvasManager.isConnectionMode) {
                Label("Connect", systemImage: "arrow.right.arrow.left")
            }
            .toggleStyle(.button)
            .help("Draw Connections")
            .onChange(of: canvasManager.isConnectionMode) { newValue in
                if newValue {
                    canvasManager.isDrawingSectionMode = false
                }
                if !newValue {
                    canvasManager.connectionStartElement = nil
                }
            }
            
            // Alignment guides toggle
            Toggle(isOn: $canvasManager.showAlignmentGuides) {
                Label("Guides", systemImage: "ruler")
            }
            .toggleStyle(.button)
            .help("Show Alignment Guides")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Section Drawing Overlay
struct SectionDrawingOverlay: View {
    @ObservedObject var canvasManager: CanvasManager
    @Binding var zoomLevel: CGFloat
    @Binding var previousZoomLevel: CGFloat
    let canvasSize: CGSize
    
    @State private var drawStart: CGPoint?
    @State private var drawEnd: CGPoint?
    @State private var isReady = false
    @State private var showNamingPopup = false
    @State private var sectionName = ""
    @State private var selectedColor: String
    @State private var pendingRect: CGRect?
    
    init(canvasManager: CanvasManager, zoomLevel: Binding<CGFloat>, previousZoomLevel: Binding<CGFloat>, canvasSize: CGSize) {
        self.canvasManager = canvasManager
        self._zoomLevel = zoomLevel
        self._previousZoomLevel = previousZoomLevel
        self.canvasSize = canvasSize
        self._selectedColor = State(initialValue: canvasManager.sectionDrawingColor)
    }
    
    // Preview rect in screen coordinates (what user sees)
    private var drawingRect: CGRect? {
        guard let start = drawStart, let end = drawEnd else { return nil }
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)
        // Clamp to reasonable values to prevent geometry errors
        guard width < 10000, height < 10000, minX > -10000, minY > -10000 else { return nil }
        return CGRect(x: minX, y: minY, width: width, height: height)
    }
    
    // Canvas rect - converted from screen to canvas coordinates
    private var canvasRect: CGRect? {
        guard let rect = drawingRect, zoomLevel > 0.01 else { return nil }
        // Convert screen coordinates to canvas coordinates by dividing by zoom
        let converted = CGRect(
            x: max(0, rect.origin.x / zoomLevel),
            y: max(0, rect.origin.y / zoomLevel),
            width: min(rect.width / zoomLevel, 5000),
            height: min(rect.height / zoomLevel, 5000)
        )
        return converted
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Semi-transparent overlay
                Color.black.opacity(0.3)
                    .allowsHitTesting(!showNamingPopup)
                
                // Drawing rectangle preview
                if let rect = drawingRect, !showNamingPopup {
                    Rectangle()
                        .fill(Color(hex: selectedColor).opacity(0.4))
                        .frame(width: rect.width, height: rect.height)
                        .overlay(
                            Rectangle()
                                .strokeBorder(Color(hex: selectedColor), style: StrokeStyle(lineWidth: 3, dash: [10, 5]))
                        )
                        .position(x: rect.midX, y: rect.midY)
                }
                
                // Instructions (when not showing naming popup)
                if !showNamingPopup {
                    VStack {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(hex: selectedColor))
                                        .frame(width: 20, height: 20)
                                    Text("Draw Section")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                }
                                Text("Click and drag to create a section area")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.9))
                                Text("Press ESC to cancel")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .padding(16)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(12)
                            .padding(20)
                            Spacer()
                        }
                        Spacer()
                    }
                    .opacity(isReady ? 1 : 0)
                }
                
                // Naming popup
                if showNamingPopup {
                    sectionNamingPopup
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showNamingPopup)
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .local)
                    .onChanged { value in
                        guard isReady && !showNamingPopup else { return }
                        if drawStart == nil {
                            drawStart = value.startLocation
                        }
                        drawEnd = value.location
                    }
                    .onEnded { value in
                        guard isReady && !showNamingPopup else { return }
                        if let rect = canvasRect, rect.width > 100, rect.height > 80 {
                            // Store the rect and show naming popup
                            pendingRect = rect
                            showNamingPopup = true
                        } else {
                            // Too small, reset
                            drawStart = nil
                            drawEnd = nil
                        }
                    }
            )
            .onAppear {
                selectedColor = canvasManager.sectionDrawingColor
                // Allow drawing immediately - zoom handled by ContentView
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeIn(duration: 0.15)) {
                        isReady = true
                    }
                }
            }
        }
    }
    
    // MARK: - Section Naming Popup
    private var sectionNamingPopup: some View {
        VStack(spacing: 16) {
            // Header
            Text("Name Your Section")
                .font(.system(size: 16, weight: .semibold))
            
            // Name input
            TextField("Section name", text: $sectionName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            
            // Color picker
            VStack(spacing: 10) {
                Text("Color")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                
                // Two rows of colors
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        ForEach(Array(FrameColors.presets.prefix(5)), id: \.hex) { preset in
                            colorButton(for: preset)
                        }
                    }
                    HStack(spacing: 10) {
                        ForEach(Array(FrameColors.presets.suffix(5)), id: \.hex) { preset in
                            colorButton(for: preset)
                        }
                    }
                }
            }
            
            // Buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    cancelSection()
                }
                .keyboardShortcut(.escape)
                
                Button("Create Section") {
                    createSection()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        )
    }
    
    private func colorButton(for preset: (name: String, hex: String)) -> some View {
        Button(action: { selectedColor = preset.hex }) {
            Circle()
                .fill(Color(hex: preset.hex))
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white, lineWidth: selectedColor == preset.hex ? 3 : 0)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: selectedColor == preset.hex ? 2 : 0)
                        .scaleEffect(1.15)
                )
        }
        .buttonStyle(.plain)
        .help(preset.name)
    }
    
    private func createSection() {
        guard let rect = pendingRect else { return }
        
        canvasManager.addFrame(
            title: sectionName.isEmpty ? "Section" : sectionName,
            color: selectedColor,
            rect: rect
        )
        
        // Reset and exit
        resetState()
        canvasManager.isDrawingSectionMode = false
    }
    
    private func cancelSection() {
        resetState()
        canvasManager.isDrawingSectionMode = false
    }
    
    private func resetState() {
        drawStart = nil
        drawEnd = nil
        pendingRect = nil
        showNamingPopup = false
        sectionName = ""
    }
}

// MARK: - Connection Style Picker
struct ConnectionStylePicker: View {
    @Binding var style: Connection.ConnectionStyle
    @Binding var color: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Style picker
            HStack(spacing: 8) {
                ForEach([Connection.ConnectionStyle.line, .arrow, .dashed, .curved], id: \.self) { s in
                    Button(action: { style = s }) {
                        Image(systemName: iconForStyle(s))
                            .font(.system(size: 14))
                            .frame(width: 32, height: 32)
                            .background(style == s ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Color picker
            HStack(spacing: 4) {
                ForEach(["#007AFF", "#34C759", "#FF9500", "#FF3B30", "#AF52DE", "#5856D6"], id: \.self) { hex in
                    Button(action: { color = hex }) {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .strokeBorder(color == hex ? Color.white : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private func iconForStyle(_ style: Connection.ConnectionStyle) -> String {
        switch style {
        case .line: return "line.diagonal"
        case .arrow: return "arrow.right"
        case .dashed: return "line.horizontal.3"
        case .curved: return "scribble"
        }
    }
}
