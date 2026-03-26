import SwiftUI
import AppKit

// Environment key for zoom level
struct ZoomLevelKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var zoomLevel: CGFloat {
        get { self[ZoomLevelKey.self] }
        set { self[ZoomLevelKey.self] = newValue }
    }
}

// MARK: - Simple Scroll View (No Magnification)
struct SimpleScrollView<Content: View>: NSViewRepresentable {
    let content: Content
    let contentSize: CGSize
    @Binding var scrollOffset: CGPoint
    
    init(contentSize: CGSize, scrollOffset: Binding<CGPoint>, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.contentSize = contentSize
        self._scrollOffset = scrollOffset
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: SimpleScrollView
        var isUpdating = false
        
        init(_ parent: SimpleScrollView) {
            self.parent = parent
        }
        
        // No longer tracking scroll - NSScrollView handles it natively for smooth performance
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = OptimizedScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        
        // NO magnification - we handle zoom in SwiftUI
        scrollView.allowsMagnification = false
        
        // Smooth scrolling optimizations
        scrollView.usesPredominantAxisScrolling = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .allowed
        
        // Enable scroll deceleration for momentum scrolling
        scrollView.scrollerKnobStyle = .default
        
        // High-performance layer backing
        scrollView.wantsLayer = true
        scrollView.layer?.drawsAsynchronously = true
        scrollView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        
        // Replace default clip view with our zoom-stable version
        let clipView = ZoomStableClipView()
        clipView.wantsLayer = true
        clipView.layer?.drawsAsynchronously = true
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        
        let hostingView = NSHostingView(rootView: content)
        hostingView.wantsLayer = true
        hostingView.layer?.drawsAsynchronously = true
        hostingView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        scrollView.documentView = hostingView
        
        // Store reference for zoom operations
        ScrollViewHelper.shared.scrollView = scrollView
        
        // No scroll observer needed - NSScrollView handles scrolling natively
        // This eliminates SwiftUI state updates during scroll for maximum smoothness
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.isUpdating = true
        defer { context.coordinator.isUpdating = false }
        
        if let hostingView = nsView.documentView as? NSHostingView<Content> {
            // Update content
            hostingView.rootView = content
            
            // Update content size - only resize, let scroll view handle position naturally
            let currentSize = hostingView.frame.size
            if currentSize != contentSize {
                hostingView.frame.size = contentSize
                // No scroll position adjustment - let the zoom preserve apparent position
            }
        }
    }
    
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }
}

// Optimized scroll view subclass for better performance
class OptimizedScrollView: NSScrollView {
    override class var isCompatibleWithResponsiveScrolling: Bool { true }
    
    override func scrollWheel(with event: NSEvent) {
        // Pass through to default implementation for smooth scrolling
        super.scrollWheel(with: event)
    }
}

// Custom clip view that can lock scroll position during zoom
class ZoomStableClipView: NSClipView {
    var lockedBoundsOrigin: CGPoint?
    
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        
        // If we have a locked position during zoom, use it
        if let locked = lockedBoundsOrigin {
            bounds.origin = locked
        }
        
        return bounds
    }
    
    override func scroll(to newOrigin: NSPoint) {
        // If locked during zoom, ignore automatic scroll adjustments
        if lockedBoundsOrigin != nil {
            return
        }
        super.scroll(to: newOrigin)
    }
}

// Helper to access NSScrollView
class ScrollViewHelper: ObservableObject {
    static var shared = ScrollViewHelper()
    weak var scrollView: NSScrollView?
    var isZooming = false // Flag to suppress scroll notifications during zoom
    var targetZoomOffset: CGPoint? // Target offset to maintain during zoom
    
    /// Lock scroll position during zoom operation
    func lockScrollPosition(_ offset: CGPoint) {
        if let clipView = scrollView?.contentView as? ZoomStableClipView {
            clipView.lockedBoundsOrigin = offset
        }
        targetZoomOffset = offset
    }
    
    /// Unlock and apply final scroll position
    func unlockScrollPosition() {
        if let clipView = scrollView?.contentView as? ZoomStableClipView {
            let target = clipView.lockedBoundsOrigin ?? clipView.bounds.origin
            clipView.lockedBoundsOrigin = nil
            clipView.setBoundsOrigin(target)
        }
        targetZoomOffset = nil
    }
    
    func scrollTo(_ point: CGPoint, animated: Bool = true) {
        guard let scrollView = scrollView else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                scrollView.contentView.animator().setBoundsOrigin(point)
            }
        } else {
            scrollView.contentView.scroll(to: point)
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

// MARK: - Content View
struct ContentView: View {
    @EnvironmentObject var canvasManager: CanvasManager
    @Binding var selectedElementId: UUID?
    @Binding var zoomLevel: CGFloat
    @Binding var lastMagnification: CGFloat
    
    @State private var selectedTool: Tool = .none
    @State private var scrollOffset: CGPoint = .zero
    @State private var placementMode = false
    @State private var pendingElement: (type: CanvasElement.ElementType, content: String)?
    @State private var previewPosition: CGPoint?
    @State private var keyMonitor: Any?
    @State private var scrollMonitor: Any?
    @State private var magnifyMonitor: Any?
    @State private var gestureZoomAnchor: CGPoint = .zero
    
    // Local dragging state for alignment guides (to avoid lag)
    @State private var isDraggingForAlignment = false
    @State private var draggingElementPosition: CGPoint = .zero
    @State private var draggingElementId: UUID?
    @State private var draggingElementSize: CGSize = .zero
    
    // Previous zoom level for section drawing restore
    @State private var previousZoomLevel: CGFloat = 1.0
    
    // Search overlay state
    @State private var isSearchVisible = false
    
    // Mini map visibility
    @State private var showMiniMap = true
    
    // Minimum canvas size and padding for infinite canvas feel
    private let minimumCanvasSize = CGSize(width: 3000, height: 3000)
    private let canvasPadding: CGFloat = 2000 // Extra space around content
    
    /// Calculates dynamic canvas size based on elements (unscaled) - always square
    private var baseCanvasSize: CGSize {
        guard let elements = canvasManager.currentCanvas?.elements, !elements.isEmpty else {
            return minimumCanvasSize
        }
        
        // Find the bounding box of all elements
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        
        for element in elements {
            let elementRight = element.position.x + element.size.width / 2
            let elementBottom = element.position.y + element.size.height / 2
            maxX = max(maxX, elementRight)
            maxY = max(maxY, elementBottom)
        }
        
        // Add padding so user can scroll beyond content
        let contentWidth = maxX + canvasPadding
        let contentHeight = maxY + canvasPadding
        
        // Calculate required size (at least minimum)
        let requiredWidth = max(minimumCanvasSize.width, contentWidth)
        let requiredHeight = max(minimumCanvasSize.height, contentHeight)
        
        // Always return a square canvas (use the larger dimension)
        let squareSize = max(requiredWidth, requiredHeight)
        return CGSize(width: squareSize, height: squareSize)
    }
    
    /// Scaled canvas size for scroll view content - uses zoomLevel directly
    private var scaledCanvasSize: CGSize {
        let base = baseCanvasSize
        return CGSize(
            width: base.width * zoomLevel,
            height: base.height * zoomLevel
        )
    }
    
    var body: some View {
        GeometryReader { geometry in
            let currentBaseSize = baseCanvasSize
            let currentScaledSize = scaledCanvasSize
            
            ZStack {
                // Scrollable infinite canvas
                SimpleScrollView(
                    contentSize: currentScaledSize,
                    scrollOffset: $scrollOffset
                ) {
                    canvasContentView(canvasSize: currentBaseSize)
                        .frame(width: currentBaseSize.width, height: currentBaseSize.height)
                        .scaleEffect(zoomLevel, anchor: .topLeading)
                        .frame(
                            width: currentScaledSize.width,
                            height: currentScaledSize.height,
                            alignment: .topLeading
                        )
                        // Note: Can't use drawingGroup() because canvas contains native AppKit views
                        // (text editors, web views, PDFs) that can't be flattened to Metal textures
                }
                .background(canvasManager.theme == .dark ? Color.black : Color.white)
                
                // Placement mode overlay
                if placementMode {
                    placementOverlay
                }
                
                // Section drawing overlay
                if canvasManager.isDrawingSectionMode {
                    SectionDrawingOverlay(
                        canvasManager: canvasManager,
                        zoomLevel: $zoomLevel,
                        previousZoomLevel: $previousZoomLevel,
                        canvasSize: currentScaledSize
                    )
                    .transition(.opacity)
                }
                
                // Mini Map overlay (bottom right)
                if showMiniMap && !canvasManager.isDrawingSectionMode {
                    MiniMapView(
                        canvasManager: canvasManager,
                        canvasSize: currentBaseSize,
                        zoomLevel: zoomLevel,
                        onNavigate: { point in
                            navigateToCanvasPoint(point)
                        }
                    )
                }
                
                // Search overlay (centered, modal)
                if isSearchVisible {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            isSearchVisible = false
                        }
                    
                    VStack {
                        Spacer()
                            .frame(height: 100)
                        
                        SearchOverlayView(
                            canvasManager: canvasManager,
                            isPresented: $isSearchVisible,
                            onNavigate: { elementId, position in
                                navigateToElement(elementId: elementId, position: position)
                            }
                        )
                        
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSearchVisible)
        .onChange(of: canvasManager.isDrawingSectionMode) { isDrawingMode in
            if isDrawingMode {
                // Zoom out when entering section drawing mode
                previousZoomLevel = zoomLevel
                performZoomAtCenter(to: 0.1)
            } else {
                // Zoom back in when exiting
                performZoomAtCenter(to: previousZoomLevel)
            }
        }
        .onAppear {
            setupKeyboardShortcuts()
            setupScrollWheelZoom()
            setupMagnifyGesture()
        }
        .onDisappear {
            cleanupMonitors()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EnterPlacementMode"))) { notification in
            if let userInfo = notification.userInfo,
               let type = userInfo["type"] as? CanvasElement.ElementType,
               let content = userInfo["content"] as? String {
                pendingElement = (type, content)
                placementMode = true
            }
        }
    }
    
    // MARK: - Canvas Content
    private func canvasContentView(canvasSize: CGSize) -> some View {
        ZStack {
            // Background - simplified for performance
            canvasBackground
            
            // Grid overlay
            GridOverlay(
                canvasSize: canvasSize,
                gridSize: canvasManager.gridSize,
                showGrid: canvasManager.showGrid
            )
            
            // Connections between elements (drawn below elements)
            if let currentCanvas = canvasManager.currentCanvas {
                ConnectionsView(
                    connections: currentCanvas.connections,
                    elements: currentCanvas.elements,
                    canvasManager: canvasManager,
                    zoomLevel: zoomLevel
                )
            }
            
            // Elements with optimized rendering
            if let currentCanvas = canvasManager.currentCanvas {
                // Frames go first (lower z-index)
                ForEach(currentCanvas.elements.filter { $0.type == .frame }.sorted { $0.zIndex < $1.zIndex }, id: \.id) { element in
                    FrameElementView(
                        element: element,
                        canvasManager: canvasManager,
                        isSelected: selectedElementId == element.id || canvasManager.selectedElementIds.contains(element.id),
                        onSelect: { handleElementSelect(element.id) }
                    )
                    .environment(\.zoomLevel, zoomLevel)
                }
                
                // Other elements on top
                ForEach(currentCanvas.elements.filter { $0.type != .frame }.sorted { $0.zIndex < $1.zIndex }, id: \.id) { element in
                    CanvasElementView(
                        element: element,
                        canvasManager: canvasManager,
                        isSelected: selectedElementId == element.id || canvasManager.selectedElementIds.contains(element.id),
                        onSelect: { handleElementSelect(element.id) },
                        onDrag: nil,
                        onDragEnd: {
                            isDraggingForAlignment = false
                            draggingElementId = nil
                        },
                        onDragStart: { id, size in
                            isDraggingForAlignment = true
                            draggingElementId = id
                            draggingElementSize = size
                            draggingElementPosition = element.position
                        },
                        onDragPositionUpdate: { pos in
                            draggingElementPosition = pos
                        }
                    )
                    .environment(\.zoomLevel, zoomLevel)
                }
                
                // Alignment guides (shown during drag)
                if isDraggingForAlignment, let dragId = draggingElementId {
                    AlignmentGuidesView(
                        guides: computeAlignmentGuides(
                            forPosition: draggingElementPosition,
                            size: draggingElementSize,
                            excluding: dragId,
                            in: currentCanvas.elements
                        ),
                        canvasSize: canvasSize
                    )
                }
                
                // Placement preview
                if placementMode, let pending = pendingElement, let position = previewPosition {
                    placementPreview(for: pending.type, at: position)
                }
            }
            
            // Connection mode overlay
            ConnectionModeOverlay(
                canvasManager: canvasManager,
                elements: canvasManager.currentCanvas?.elements ?? []
            )
        }
    }
    
    // Handle element selection with multi-select support
    private func handleElementSelect(_ elementId: UUID) {
        // Handle connection mode
        if canvasManager.isConnectionMode {
            if let startId = canvasManager.connectionStartElement {
                if startId != elementId {
                    // Create connection
                    canvasManager.addConnection(from: startId, to: elementId)
                }
                canvasManager.connectionStartElement = nil
                canvasManager.isConnectionMode = false
            } else {
                canvasManager.connectionStartElement = elementId
            }
            return
        }
        
        // Normal selection
        if NSEvent.modifierFlags.contains(.shift) {
            // Multi-select with Shift
            if canvasManager.selectedElementIds.contains(elementId) {
                canvasManager.selectedElementIds.remove(elementId)
            } else {
                canvasManager.selectedElementIds.insert(elementId)
            }
        } else if NSEvent.modifierFlags.contains(.command) {
            // Toggle selection with Command
            if canvasManager.selectedElementIds.contains(elementId) {
                canvasManager.selectedElementIds.remove(elementId)
            } else {
                canvasManager.selectedElementIds.insert(elementId)
            }
        } else {
            // Single select
            canvasManager.selectedElementIds.removeAll()
            selectedElementId = elementId
        }
    }
    
    // Separate background view for better performance
    private var canvasBackground: some View {
        Rectangle()
            .fill(canvasManager.theme == .dark ? Color.black : Color.white)
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleCanvasTap(at: location)
            }
            .onContinuousHover { phase in
                if case .active(let location) = phase, placementMode, let pending = pendingElement {
                    let size = canvasManager.sizeForElementType(pending.type)
                    previewPosition = magneticSnap(location: location, size: size)
                }
            }
    }
    
    // MARK: - Placement Preview
    private func placementPreview(for type: CanvasElement.ElementType, at position: CGPoint) -> some View {
        let size = canvasManager.sizeForElementType(type)
        return RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.blue, lineWidth: 3)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.15))
            )
            .frame(width: size.width, height: size.height)
            .position(position)
            .overlay(
                VStack {
                    Image(systemName: iconForType(type))
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.blue.opacity(0.6))
                    Text(labelForType(type))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue.opacity(0.8))
                }
                .position(position)
            )
            .allowsHitTesting(false)
    }
    
    // MARK: - Placement Overlay
    private var placementOverlay: some View {
        VStack {
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 16))
                    Text("Click on empty space to place")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white)
                
                Spacer()
                
                Button(action: cancelPlacement) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                        Text("Cancel")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color.blue.opacity(0.95))
            
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.3), value: placementMode)
    }
    
    // MARK: - Actions
    private func handleCanvasTap(at location: CGPoint) {
        if placementMode, let pending = pendingElement {
            let size = canvasManager.sizeForElementType(pending.type)
            let snappedLocation = canvasManager.snapPositionToGrid(location)
            let placementRect = CGRect(
                x: snappedLocation.x - size.width / 2,
                y: snappedLocation.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            
            let overlapsExisting = canvasManager.currentCanvas?.elements.contains { element in
                let elementRect = CGRect(
                    x: element.position.x - element.size.width / 2,
                    y: element.position.y - element.size.height / 2,
                    width: element.size.width,
                    height: element.size.height
                )
                return placementRect.intersects(elementRect)
            } ?? false
            
            if !overlapsExisting {
                canvasManager.addElementAtPosition(type: pending.type, content: pending.content, position: snappedLocation)
                cancelPlacement()
            }
        } else if selectedTool == .text {
            let snappedLocation = canvasManager.snapPositionToGrid(location)
            canvasManager.addElementAtPosition(type: .text, content: "", position: snappedLocation)
            selectedTool = .none
        } else {
            // Clear selection
            selectedElementId = nil
            canvasManager.selectedElementIds.removeAll()
            
            // Cancel connection mode if clicking empty area
            if canvasManager.isConnectionMode {
                canvasManager.isConnectionMode = false
                canvasManager.connectionStartElement = nil
            }
        }
    }
    
    private func cancelPlacement() {
        placementMode = false
        pendingElement = nil
        previewPosition = nil
    }
    
    // MARK: - Alignment Guides Computation
    private func computeAlignmentGuides(forPosition position: CGPoint, size: CGSize, excluding: UUID, in elements: [CanvasElement]) -> [AlignmentGuide] {
        guard canvasManager.showAlignmentGuides else { return [] }
        
        var guides: [AlignmentGuide] = []
        let threshold: CGFloat = 10
        
        let elementLeft = position.x - size.width/2
        let elementRight = position.x + size.width/2
        let elementTop = position.y - size.height/2
        let elementBottom = position.y + size.height/2
        let elementCenterX = position.x
        let elementCenterY = position.y
        
        for other in elements where other.id != excluding {
            let otherLeft = other.position.x - other.size.width/2
            let otherRight = other.position.x + other.size.width/2
            let otherTop = other.position.y - other.size.height/2
            let otherBottom = other.position.y + other.size.height/2
            let otherCenterX = other.position.x
            let otherCenterY = other.position.y
            
            // Vertical guides (for X alignment)
            if abs(elementLeft - otherLeft) < threshold {
                guides.append(AlignmentGuide(type: .vertical, position: otherLeft))
            }
            if abs(elementRight - otherRight) < threshold {
                guides.append(AlignmentGuide(type: .vertical, position: otherRight))
            }
            if abs(elementCenterX - otherCenterX) < threshold {
                guides.append(AlignmentGuide(type: .vertical, position: otherCenterX))
            }
            if abs(elementLeft - otherRight) < threshold {
                guides.append(AlignmentGuide(type: .vertical, position: otherRight))
            }
            if abs(elementRight - otherLeft) < threshold {
                guides.append(AlignmentGuide(type: .vertical, position: otherLeft))
            }
            
            // Horizontal guides (for Y alignment)
            if abs(elementTop - otherTop) < threshold {
                guides.append(AlignmentGuide(type: .horizontal, position: otherTop))
            }
            if abs(elementBottom - otherBottom) < threshold {
                guides.append(AlignmentGuide(type: .horizontal, position: otherBottom))
            }
            if abs(elementCenterY - otherCenterY) < threshold {
                guides.append(AlignmentGuide(type: .horizontal, position: otherCenterY))
            }
            if abs(elementTop - otherBottom) < threshold {
                guides.append(AlignmentGuide(type: .horizontal, position: otherBottom))
            }
            if abs(elementBottom - otherTop) < threshold {
                guides.append(AlignmentGuide(type: .horizontal, position: otherTop))
            }
        }
        
        return guides
    }
    
    // MARK: - Zoom Functions
    private func zoomIn() {
        let newZoom = min(zoomLevel + 0.1, 3.0)
        performZoomAtCursor(to: newZoom)
    }
    
    private func zoomOut() {
        let newZoom = max(zoomLevel - 0.1, 0.1)
        performZoomAtCursor(to: newZoom)
    }
    
    private func resetZoom() {
        performZoomAtCenter(to: 1.0)
    }
    
    /// Zoom following the cursor position
    private func performZoomAtCursor(to target: CGFloat) {
        guard let scrollView = ScrollViewHelper.shared.scrollView,
              let window = scrollView.window else {
            zoomLevel = target
            lastMagnification = target
            return
        }
        
        let oldZoom = zoomLevel
        
        // Get current scroll position and visible size BEFORE any changes
        let currentOffset = scrollView.contentView.bounds.origin
        let visibleSize = scrollView.contentView.bounds.size
        
        // Get mouse position relative to the clip view (visible area)
        let mouseInWindow = window.mouseLocationOutsideOfEventStream
        let mouseInClipView = scrollView.contentView.convert(mouseInWindow, from: nil)
        
        // Clamp mouse position to visible area
        let clampedMouseX = max(0, min(mouseInClipView.x, visibleSize.width))
        let clampedMouseY = max(0, min(mouseInClipView.y, visibleSize.height))
        
        // Calculate the canvas point under the cursor (in unscaled canvas coordinates)
        let canvasX = (currentOffset.x + clampedMouseX) / oldZoom
        let canvasY = (currentOffset.y + clampedMouseY) / oldZoom
        
        // Calculate new scroll offset to keep that canvas point under the cursor
        let newOffsetX = canvasX * target - clampedMouseX
        let newOffsetY = canvasY * target - clampedMouseY
        
        // Calculate bounds for the new zoom level
        let newContentWidth = baseCanvasSize.width * target
        let newContentHeight = baseCanvasSize.height * target
        let maxX = max(0, newContentWidth - visibleSize.width)
        let maxY = max(0, newContentHeight - visibleSize.height)
        
        // Clamp to valid scroll bounds
        let targetOffset = CGPoint(
            x: max(0, min(newOffsetX, maxX)),
            y: max(0, min(newOffsetY, maxY))
        )
        
        // Lock scroll position to prevent shifting during content size update
        ScrollViewHelper.shared.lockScrollPosition(targetOffset)
        
        // Update zoom level (triggers SwiftUI content size update)
        zoomLevel = target
        lastMagnification = target
        
        // Unlock after SwiftUI has finished updating
        DispatchQueue.main.async {
            ScrollViewHelper.shared.unlockScrollPosition()
        }
    }
    
    /// Zoom keeping center of view fixed (for reset zoom)
    private func performZoomAtCenter(to target: CGFloat) {
        guard let scrollView = ScrollViewHelper.shared.scrollView else {
            zoomLevel = target
            lastMagnification = target
            return
        }
        
        let oldZoom = zoomLevel
        let currentOffset = scrollView.contentView.bounds.origin
        let visibleSize = scrollView.contentView.bounds.size
        
        // Calculate the center point in canvas coordinates (unscaled)
        let centerCanvasX = (currentOffset.x + visibleSize.width / 2) / oldZoom
        let centerCanvasY = (currentOffset.y + visibleSize.height / 2) / oldZoom
        
        // Calculate new offset to keep center point centered
        let newOffsetX = centerCanvasX * target - visibleSize.width / 2
        let newOffsetY = centerCanvasY * target - visibleSize.height / 2
        
        // Calculate bounds for the new zoom level
        let newContentWidth = baseCanvasSize.width * target
        let newContentHeight = baseCanvasSize.height * target
        let maxX = max(0, newContentWidth - visibleSize.width)
        let maxY = max(0, newContentHeight - visibleSize.height)
        
        let targetOffset = CGPoint(
            x: max(0, min(newOffsetX, maxX)),
            y: max(0, min(newOffsetY, maxY))
        )
        
        // Lock scroll position
        ScrollViewHelper.shared.lockScrollPosition(targetOffset)
        
        // Update zoom
        zoomLevel = target
        lastMagnification = target
        
        // Unlock after SwiftUI update
        DispatchQueue.main.async {
            ScrollViewHelper.shared.unlockScrollPosition()
        }
    }
    
    // MARK: - Navigation Functions
    
    /// Navigate to a specific point on the canvas (used by mini map)
    private func navigateToCanvasPoint(_ point: CGPoint) {
        guard let scrollView = ScrollViewHelper.shared.scrollView else { return }
        
        let visibleSize = scrollView.contentView.bounds.size
        
        // Calculate scroll offset to center the point
        let targetX = point.x * zoomLevel - visibleSize.width / 2
        let targetY = point.y * zoomLevel - visibleSize.height / 2
        
        // Clamp to valid bounds
        let maxX = max(0, baseCanvasSize.width * zoomLevel - visibleSize.width)
        let maxY = max(0, baseCanvasSize.height * zoomLevel - visibleSize.height)
        
        let clampedOffset = CGPoint(
            x: max(0, min(targetX, maxX)),
            y: max(0, min(targetY, maxY))
        )
        
        // Animate scroll
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            scrollView.contentView.animator().setBoundsOrigin(clampedOffset)
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
    
    /// Navigate to a specific element (used by search)
    private func navigateToElement(elementId: UUID, position: CGPoint) {
        // Select the element
        selectedElementId = elementId
        canvasManager.selectedElementIds.removeAll()
        
        // Navigate to center the element
        navigateToCanvasPoint(position)
    }
    
    // MARK: - Event Monitors
    private func setupKeyboardShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // ESC key
            if event.keyCode == 53 {
                if isSearchVisible {
                    isSearchVisible = false
                    return nil
                } else if canvasManager.isDrawingSectionMode {
                    // Cancel section drawing and restore zoom
                    performZoomAtCenter(to: previousZoomLevel)
                    canvasManager.isDrawingSectionMode = false
                    return nil
                } else if placementMode {
                    cancelPlacement()
                } else {
                    selectedElementId = nil
                    selectedTool = .none
                }
                return nil
            }
            // Cmd + F - Search
            if event.keyCode == 3 && event.modifierFlags.contains(.command) {
                isSearchVisible.toggle()
                return nil
            }
            // Cmd + M - Toggle Mini Map
            if event.keyCode == 46 && event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.shift) {
                showMiniMap.toggle()
                return nil
            }
            // Cmd + Plus
            if event.keyCode == 24 && event.modifierFlags.contains(.command) {
                zoomIn()
                return nil
            }
            // Cmd + Minus
            if event.keyCode == 27 && event.modifierFlags.contains(.command) {
                zoomOut()
                return nil
            }
            // Cmd + 0
            if event.keyCode == 29 && event.modifierFlags.contains(.command) {
                resetZoom()
                return nil
            }
            // Cmd + Delete - Delete selected element
            if event.keyCode == 51 && event.modifierFlags.contains(.command) {
                if let selectedId = selectedElementId,
                   let element = canvasManager.currentCanvas?.elements.first(where: { $0.id == selectedId }) {
                    canvasManager.removeElement(element)
                    selectedElementId = nil
                }
                return nil
            }
            return event
        }
    }
    
    // Throttle zoom updates to reduce CPU
    @State private var lastZoomUpdate: Date = Date()
    private let zoomThrottleInterval: TimeInterval = 1.0 / 60.0 // 60fps max
    
    private func setupScrollWheelZoom() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // When Command is held, treat ALL scroll as zoom (block horizontal panning)
            if event.modifierFlags.contains(.command) {
                // Throttle zoom updates to reduce CPU
                let now = Date()
                guard now.timeIntervalSince(lastZoomUpdate) >= zoomThrottleInterval else {
                    return nil // Consume but don't process
                }
                
                let delta = event.scrollingDeltaY
                
                // Only zoom if there's meaningful vertical movement
                if abs(delta) > 0.5 {
                    lastZoomUpdate = now
                    
                    // Smooth zoom factor
                    let zoomFactor: CGFloat = 0.01
                    let zoomDelta = zoomFactor * delta
                    let newZoom = max(0.1, min(3.0, zoomLevel + zoomDelta))
                    
                    // Only update if change is meaningful
                    if abs(newZoom - zoomLevel) >= 0.005 {
                        ScrollViewHelper.shared.isZooming = true
                        
                        if let scrollView = ScrollViewHelper.shared.scrollView {
                            let oldZoom = zoomLevel
                            let currentOffset = scrollView.contentView.bounds.origin
                            let visibleSize = scrollView.contentView.bounds.size
                            
                            // Get mouse position in clip view coordinates
                            let mouseInWindow = event.locationInWindow
                            let mouseInClipView = scrollView.contentView.convert(mouseInWindow, from: nil)
                            
                            // Clamp mouse to visible area
                            let clampedMouseX = max(0, min(mouseInClipView.x, visibleSize.width))
                            let clampedMouseY = max(0, min(mouseInClipView.y, visibleSize.height))
                            
                            // Calculate canvas point under cursor (unscaled)
                            let canvasX = (currentOffset.x + clampedMouseX) / oldZoom
                            let canvasY = (currentOffset.y + clampedMouseY) / oldZoom
                            
                            // Calculate new offset to keep canvas point under cursor
                            let newOffsetX = canvasX * newZoom - clampedMouseX
                            let newOffsetY = canvasY * newZoom - clampedMouseY
                            
                            // Calculate bounds
                            let newContentWidth = baseCanvasSize.width * newZoom
                            let newContentHeight = baseCanvasSize.height * newZoom
                            let maxX = max(0, newContentWidth - visibleSize.width)
                            let maxY = max(0, newContentHeight - visibleSize.height)
                            
                            let targetOffset = CGPoint(
                                x: max(0, min(newOffsetX, maxX)),
                                y: max(0, min(newOffsetY, maxY))
                            )
                            
                            // Lock scroll position during zoom
                            ScrollViewHelper.shared.lockScrollPosition(targetOffset)
                            
                            // Update zoom
                            zoomLevel = newZoom
                            
                            // Unlock after SwiftUI update
                            DispatchQueue.main.async {
                                ScrollViewHelper.shared.unlockScrollPosition()
                            }
                        } else {
                            zoomLevel = newZoom
                        }
                        
                        // Reset zooming flag after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            ScrollViewHelper.shared.isZooming = false
                        }
                    }
                }
                // ALWAYS consume the event when Command is held to block horizontal scroll
                return nil
            }
            
            // Block scroll events during pinch-to-zoom to prevent jitter
            if ScrollViewHelper.shared.isZooming {
                return nil
            }
            
            return event
        }
    }
    
    private func setupMagnifyGesture() {
        // Native trackpad pinch-to-zoom via NSEvent
        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { event in
            // Set zooming flag for entire event to block scroll events
            ScrollViewHelper.shared.isZooming = true
            
            // Throttle zoom updates
            let now = Date()
            guard now.timeIntervalSince(lastZoomUpdate) >= zoomThrottleInterval else {
                return nil
            }
            lastZoomUpdate = now
            
            // Use a small delay to reset the flag after gesture ends
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                ScrollViewHelper.shared.isZooming = false
            }
            
            let delta = event.magnification
            
            // Require meaningful delta
            guard abs(delta) > 0.01 else { return nil }
            
            // Responsive pinch factor
            let smoothDelta = delta * 0.6
            let newZoom = max(0.1, min(3.0, zoomLevel * (1.0 + smoothDelta)))
            
            // Only update if change is meaningful
            if abs(newZoom - zoomLevel) >= 0.005 {
                if let scrollView = ScrollViewHelper.shared.scrollView {
                    let oldZoom = zoomLevel
                    let currentOffset = scrollView.contentView.bounds.origin
                    let visibleSize = scrollView.contentView.bounds.size
                    
                    // Get mouse/pinch position in clip view coordinates
                    let mouseInWindow = event.locationInWindow
                    let mouseInClipView = scrollView.contentView.convert(mouseInWindow, from: nil)
                    
                    // Clamp to visible area
                    let clampedMouseX = max(0, min(mouseInClipView.x, visibleSize.width))
                    let clampedMouseY = max(0, min(mouseInClipView.y, visibleSize.height))
                    
                    // Calculate canvas point under cursor (unscaled)
                    let canvasX = (currentOffset.x + clampedMouseX) / oldZoom
                    let canvasY = (currentOffset.y + clampedMouseY) / oldZoom
                    
                    // Calculate new offset
                    let newOffsetX = canvasX * newZoom - clampedMouseX
                    let newOffsetY = canvasY * newZoom - clampedMouseY
                    
                    // Calculate bounds
                    let newContentWidth = baseCanvasSize.width * newZoom
                    let newContentHeight = baseCanvasSize.height * newZoom
                    let maxX = max(0, newContentWidth - visibleSize.width)
                    let maxY = max(0, newContentHeight - visibleSize.height)
                    
                    let targetOffset = CGPoint(
                        x: max(0, min(newOffsetX, maxX)),
                        y: max(0, min(newOffsetY, maxY))
                    )
                    
                    // Lock scroll position during zoom
                    ScrollViewHelper.shared.lockScrollPosition(targetOffset)
                    
                    zoomLevel = newZoom
                    
                    // Unlock after SwiftUI update
                    DispatchQueue.main.async {
                        ScrollViewHelper.shared.unlockScrollPosition()
                    }
                } else {
                    zoomLevel = newZoom
                }
            }
            return nil
        }
    }
    
    private func cleanupMonitors() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
        if let monitor = magnifyMonitor {
            NSEvent.removeMonitor(monitor)
            magnifyMonitor = nil
        }
    }
    
    // MARK: - Helpers
    private func magneticSnap(location: CGPoint, size: CGSize) -> CGPoint {
        guard let elements = canvasManager.currentCanvas?.elements else {
            return location
        }
        
        let snapThreshold: CGFloat = 30
        let padding: CGFloat = 20
        let maxVicinityDistance: CGFloat = 150
        
        var bestSnapPosition: CGPoint?
        var minEdgeDistance: CGFloat = .infinity
        
        for element in elements {
            let elementCenterDistance = hypot(
                location.x - element.position.x,
                location.y - element.position.y
            )
            
            let maxReach = max(element.size.width, element.size.height) / 2 + maxVicinityDistance
            if elementCenterDistance > maxReach { continue }
            
            let elementLeft = element.position.x - element.size.width / 2
            let elementRight = element.position.x + element.size.width / 2
            let elementTop = element.position.y - element.size.height / 2
            let elementBottom = element.position.y + element.size.height / 2
            
            // Right edge
            if location.x > elementRight && location.x < elementRight + snapThreshold + size.width / 2 + padding {
                let snapX = elementRight + size.width / 2 + padding
                let distanceToEdge = abs(location.x - snapX)
                if distanceToEdge < minEdgeDistance {
                    minEdgeDistance = distanceToEdge
                    bestSnapPosition = CGPoint(x: snapX, y: location.y)
                }
            }
            
            // Left edge
            if location.x < elementLeft && location.x > elementLeft - snapThreshold - size.width / 2 - padding {
                let snapX = elementLeft - size.width / 2 - padding
                let distanceToEdge = abs(location.x - snapX)
                if distanceToEdge < minEdgeDistance {
                    minEdgeDistance = distanceToEdge
                    bestSnapPosition = CGPoint(x: snapX, y: location.y)
                }
            }
            
            // Bottom edge
            if location.y > elementBottom && location.y < elementBottom + snapThreshold + size.height / 2 + padding {
                let snapY = elementBottom + size.height / 2 + padding
                let distanceToEdge = abs(location.y - snapY)
                if distanceToEdge < minEdgeDistance {
                    minEdgeDistance = distanceToEdge
                    bestSnapPosition = CGPoint(x: location.x, y: snapY)
                }
            }
            
            // Top edge
            if location.y < elementTop && location.y > elementTop - snapThreshold - size.height / 2 - padding {
                let snapY = elementTop - size.height / 2 - padding
                let distanceToEdge = abs(location.y - snapY)
                if distanceToEdge < minEdgeDistance {
                    minEdgeDistance = distanceToEdge
                    bestSnapPosition = CGPoint(x: location.x, y: snapY)
                }
            }
        }
        
        return bestSnapPosition ?? location
    }
    
    private func iconForType(_ type: CanvasElement.ElementType) -> String {
        switch type {
        case .webview: return "globe"
        case .pdf: return "doc.richtext"
        case .text: return "text.quote"
        case .drawing: return "pencil.tip"
        case .frame: return "rectangle.dashed"
        }
    }
    
    private func labelForType(_ type: CanvasElement.ElementType) -> String {
        switch type {
        case .webview: return "Webpage"
        case .pdf: return "PDF Document"
        case .text: return "Text"
        case .drawing: return "Drawing"
        case .frame: return "Section"
        }
    }
    
    enum Tool {
        case none, drawing, text, webview, pdf
    }
}

// MARK: - Color Extension
extension Color {
    var hexString: String {
        let nsColor = NSColor(self)
        guard let rgbColor = nsColor.usingColorSpace(.deviceRGB) else { return "#000000" }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

#Preview {
    ContentView(selectedElementId: .constant(nil), zoomLevel: .constant(1.0), lastMagnification: .constant(1.0))
        .environmentObject(CanvasManager())
}
