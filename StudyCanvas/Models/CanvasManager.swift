import Foundation
import AppKit
import UniformTypeIdentifiers
import SwiftUI

enum AppTheme: String, Codable {
    case light
    case dark
}

class CanvasManager: ObservableObject {
    @Published var canvases: [Canvas] = []
    @Published var currentCanvas: Canvas?
    @Published var shouldSaveWebStates = false
    @Published var theme: AppTheme = .light
    
    // Grid & Alignment Settings
    @Published var snapToGrid: Bool = false
    @Published var showGrid: Bool = false
    @Published var gridSize: CGFloat = 20
    @Published var showAlignmentGuides: Bool = true  // Enabled by default
    
    // Dragging state for alignment guides (non-published to avoid lag)
    var isDraggingElement: Bool = false
    var draggingElementId: UUID?
    var draggingElementPosition: CGPoint = .zero
    
    // Selection for multi-element operations
    @Published var selectedElementIds: Set<UUID> = []
    
    // Connection mode
    @Published var isConnectionMode: Bool = false
    @Published var connectionStartElement: UUID?
    
    // Section/Frame dragging state (for child element visual offset)
    var draggingFrameId: UUID?
    var draggingFrameOffset: CGSize = .zero
    var draggingFrameChildIds: Set<UUID> = []
    
    // Section drawing mode
    @Published var isDrawingSectionMode: Bool = false
    @Published var sectionDrawingColor: String = FrameColors.presets[0].hex
    
    // Notification for cleaning up resources when switching canvases
    static let cleanupNotification = Notification.Name("CleanupCanvasResources")
    
    init() {
        loadCanvases()
        loadTheme()
        // Don't auto-select a canvas, let the user choose from landing page
        currentCanvas = nil
    }
    
    /// Clean up resources from the current canvas before switching
    func cleanupCurrentCanvas() {
        guard currentCanvas != nil else { return }
        
        // Save current state first
        saveAllStates()
        
        // Post notification to all views to clean up their resources
        NotificationCenter.default.post(name: CanvasManager.cleanupNotification, object: nil)
        
        // Give views a moment to respond to cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Additional cleanup can be added here if needed
        }
    }
    
    func toggleTheme() {
        theme = theme == .light ? .dark : .light
        saveTheme()
    }
    
    private func loadTheme() {
        if let savedTheme = UserDefaults.standard.string(forKey: "appTheme"),
           let theme = AppTheme(rawValue: savedTheme) {
            self.theme = theme
        }
    }
    
    private func saveTheme() {
        UserDefaults.standard.set(theme.rawValue, forKey: "appTheme")
    }
    
    func createNewCanvas(name: String) {
        let newCanvas = Canvas(name: name)
        canvases.append(newCanvas)
        currentCanvas = newCanvas
        saveCanvases()
    }
    
    func deleteCanvas(_ canvas: Canvas) {
        canvases.removeAll { $0.id == canvas.id }
        if currentCanvas?.id == canvas.id {
            currentCanvas = canvases.first
        }
        saveCanvases()
    }
    
    func renameCanvas(_ canvas: Canvas, newName: String) {
        if let index = canvases.firstIndex(where: { $0.id == canvas.id }) {
            canvases[index].name = newName
            saveCanvases()
        }
    }
    
    private func getCanvasesFileURL() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory.appendingPathComponent("StudyCanvas_Data.json")
    }
    
    func saveCanvases() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(canvases)
            let fileURL = getCanvasesFileURL()
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Silently handle errors
        }
    }
    
    func loadCanvases() {
        let fileURL = getCanvasesFileURL()
        
        // First try to load from file
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let decoded = try JSONDecoder().decode([Canvas].self, from: data)
                self.canvases = decoded
                return
            } catch {
                // Silently handle errors
            }
        }
        
        // Fallback: migrate from UserDefaults if exists
        if let data = UserDefaults.standard.data(forKey: "canvases"),
           let decoded = try? JSONDecoder().decode([Canvas].self, from: data) {
            self.canvases = decoded
            // Save to file and remove from UserDefaults
            saveCanvases()
            UserDefaults.standard.removeObject(forKey: "canvases")
        }
    }
    
    func saveAllStates() {
        // Immediately save current canvas to array
        if let current = currentCanvas,
           let index = canvases.firstIndex(where: { $0.id == current.id }) {
            canvases[index] = current
        }
        
        // Trigger all web views to save their current state
        shouldSaveWebStates = true
        
        // Save to disk immediately
        saveCanvases()
        
        // Reset trigger after web views have had time to respond
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.shouldSaveWebStates = false
            // Save again to capture any web state updates
            self.saveCanvases()
        }
    }
    
    func addElement(type: CanvasElement.ElementType, content: String) {
        guard let currentCanvas = currentCanvas,
              let index = canvases.firstIndex(where: { $0.id == currentCanvas.id }) else {
            return
        }
        
        // Calculate next available position
        let position = calculateNextPosition(for: type, in: canvases[index])
        let size = sizeForElementType(type)
        
        let newElement = CanvasElement(
            id: UUID(),
            type: type,
            position: position,
            size: size,
            rotation: 0,
            zIndex: canvases[index].elements.count,
            content: content
        )
        
        canvases[index].elements.append(newElement)
        self.currentCanvas = canvases[index]
        saveCanvases()
        
        // Post notification to scroll to new element
        NotificationCenter.default.post(
            name: NSNotification.Name("ScrollToElement"),
            object: nil,
            userInfo: ["position": position, "size": size]
        )
    }
    
    private func calculateNextPosition(for type: CanvasElement.ElementType, in canvas: Canvas) -> CGPoint {
        // Start position
        let startX: CGFloat = 150
        let startY: CGFloat = 150
        let spacing: CGFloat = 50
        let maxWidth: CGFloat = 9500 // Canvas width minus margin
        
        // Get the size for this element type
        let elementSize = sizeForElementType(type)
        
        // If no elements, return start position
        if canvas.elements.isEmpty {
            return CGPoint(x: startX, y: startY)
        }
        
        // Find the rightmost element to place new one to its right
        let lastElement = canvas.elements.max(by: { e1, e2 in
            (e1.position.x + e1.size.width) < (e2.position.x + e2.size.width)
        })
        
        if let last = lastElement {
            let nextX = last.position.x + last.size.width + spacing
            // Check if new element would fit within canvas bounds
            if nextX + elementSize.width > maxWidth {
                // Find bottom-most element and place below it
                if let bottomMost = canvas.elements.max(by: { $0.position.y < $1.position.y }) {
                    return CGPoint(x: startX, y: bottomMost.position.y + bottomMost.size.height + spacing)
                }
            }
            return CGPoint(x: nextX, y: last.position.y)
        }
        
        return CGPoint(x: startX, y: startY)
    }
    
    func updateElementAccessTime(_ elementId: UUID) {
        guard let currentCanvas = currentCanvas,
              let canvasIndex = canvases.firstIndex(where: { $0.id == currentCanvas.id }),
              let elementIndex = canvases[canvasIndex].elements.firstIndex(where: { $0.id == elementId }) else {
            return
        }
        
        canvases[canvasIndex].elements[elementIndex].lastAccessedTime = Date()
        self.currentCanvas = canvases[canvasIndex]
    }
    
    func sizeForElementType(_ type: CanvasElement.ElementType) -> CGSize {
        switch type {
        case .text:
            return CGSize(width: 400, height: 150)
        case .webview:
            return CGSize(width: 800, height: 600)
        case .pdf:
            return CGSize(width: 700, height: 900)
        case .drawing:
            return CGSize(width: 600, height: 400)
        case .frame:
            return CGSize(width: 600, height: 400)
        }
    }
    
    // MARK: - Grid & Snap Functions
    
    func snapPositionToGrid(_ position: CGPoint) -> CGPoint {
        guard snapToGrid else { return position }
        return CGPoint(
            x: round(position.x / gridSize) * gridSize,
            y: round(position.y / gridSize) * gridSize
        )
    }
    
    func snapSizeToGrid(_ size: CGSize) -> CGSize {
        guard snapToGrid else { return size }
        return CGSize(
            width: max(gridSize, round(size.width / gridSize) * gridSize),
            height: max(gridSize, round(size.height / gridSize) * gridSize)
        )
    }
    
    // MARK: - Frame Functions
    
    func addFrame(title: String, color: String, rect: CGRect) {
        guard let currentCanvas = currentCanvas,
              let index = canvases.firstIndex(where: { $0.id == currentCanvas.id }) else { return }
        
        // Ensure minimum size
        let minWidth: CGFloat = 150
        let minHeight: CGFloat = 100
        let frameSize = CGSize(
            width: max(minWidth, rect.width),
            height: max(minHeight, rect.height)
        )
        
        // Position is the center of the rect
        let finalPosition = CGPoint(
            x: rect.origin.x + frameSize.width / 2,
            y: rect.origin.y + frameSize.height / 2
        )
        
        let newFrame = CanvasElement(
            id: UUID(),
            type: .frame,
            position: finalPosition,
            size: frameSize,
            rotation: 0,
            zIndex: -1, // Frames go behind other elements
            content: title,
            frameColor: color,
            isCollapsed: false,
            childElements: []
        )
        
        canvases[index].elements.append(newFrame)
        self.currentCanvas = canvases[index]
        saveCanvases()
    }
    
    func toggleFrameCollapsed(_ frameId: UUID) {
        guard let currentCanvas = currentCanvas,
              let canvasIndex = canvases.firstIndex(where: { $0.id == currentCanvas.id }),
              let elementIndex = canvases[canvasIndex].elements.firstIndex(where: { $0.id == frameId }) else { return }
        
        canvases[canvasIndex].elements[elementIndex].isCollapsed?.toggle()
        self.currentCanvas = canvases[canvasIndex]
        saveCanvases()
    }
    
    func updateFrameColor(_ frameId: UUID, color: String) {
        guard let currentCanvas = currentCanvas,
              let canvasIndex = canvases.firstIndex(where: { $0.id == currentCanvas.id }),
              let elementIndex = canvases[canvasIndex].elements.firstIndex(where: { $0.id == frameId }) else { return }
        
        canvases[canvasIndex].elements[elementIndex].frameColor = color
        self.currentCanvas = canvases[canvasIndex]
        saveCanvases()
    }
    
    // MARK: - Section Child Element Functions
    
    /// Get all elements that are visually inside a section/frame
    func getElementsInsideFrame(_ frameId: UUID) -> [CanvasElement] {
        guard let currentCanvas = currentCanvas,
              let frame = currentCanvas.elements.first(where: { $0.id == frameId && $0.type == .frame }) else {
            return []
        }
        
        let frameRect = CGRect(
            x: frame.position.x - frame.size.width / 2,
            y: frame.position.y - frame.size.height / 2,
            width: frame.size.width,
            height: frame.size.height
        )
        
        return currentCanvas.elements.filter { element in
            // Skip the frame itself and other frames
            guard element.id != frameId && element.type != .frame else { return false }
            
            // Get element rect
            let elementRect = CGRect(
                x: element.position.x - element.size.width / 2,
                y: element.position.y - element.size.height / 2,
                width: element.size.width,
                height: element.size.height
            )
            
            // Check if element is mostly inside the frame (at least 50% overlap)
            let intersection = frameRect.intersection(elementRect)
            if intersection.isNull { return false }
            
            let elementArea = elementRect.width * elementRect.height
            let intersectionArea = intersection.width * intersection.height
            
            // Element is considered "inside" if more than 50% of it is within the frame
            return intersectionArea > (elementArea * 0.5)
        }
    }
    
    /// Get child elements inside a frame at a given position
    func getChildElementsInFrame(_ frameId: UUID, framePosition: CGPoint) -> [(id: UUID, offset: CGPoint)] {
        guard let currentCanvas = currentCanvas,
              let frame = currentCanvas.elements.first(where: { $0.id == frameId }) else { return [] }
        
        let frameRect = CGRect(
            x: framePosition.x - frame.size.width / 2,
            y: framePosition.y - frame.size.height / 2,
            width: frame.size.width,
            height: frame.size.height
        )
        
        var children: [(id: UUID, offset: CGPoint)] = []
        
        for element in currentCanvas.elements {
            // Skip the frame itself and other frames
            guard element.id != frameId && element.type != .frame else { continue }
            
            // Get element rect
            let elementRect = CGRect(
                x: element.position.x - element.size.width / 2,
                y: element.position.y - element.size.height / 2,
                width: element.size.width,
                height: element.size.height
            )
            
            // Check if element is mostly inside the frame (at least 50% overlap)
            let intersection = frameRect.intersection(elementRect)
            if intersection.isNull { continue }
            
            let elementArea = elementRect.width * elementRect.height
            let intersectionArea = intersection.width * intersection.height
            
            if intersectionArea > (elementArea * 0.5) {
                // Store the offset from frame position to element position
                let offset = CGPoint(
                    x: element.position.x - framePosition.x,
                    y: element.position.y - framePosition.y
                )
                children.append((id: element.id, offset: offset))
            }
        }
        
        return children
    }
    
    /// Start dragging a frame - capture child IDs for visual offset
    func startFrameDrag(_ frameId: UUID, framePosition: CGPoint) -> [(id: UUID, offset: CGPoint)] {
        let children = getChildElementsInFrame(frameId, framePosition: framePosition)
        draggingFrameId = frameId
        draggingFrameChildIds = Set(children.map { $0.id })
        draggingFrameOffset = .zero
        return children
    }
    
    /// Update frame drag offset (for visual display only, no model update)
    func updateFrameDragOffset(_ offset: CGSize) {
        draggingFrameOffset = offset
        // Don't trigger UI update - children will update at drag end for performance
    }
    
    /// End frame drag - clear dragging state
    func endFrameDrag() {
        draggingFrameId = nil
        draggingFrameChildIds = []
        draggingFrameOffset = .zero
    }
    
    /// Check if an element should apply visual drag offset
    func getDragOffsetForElement(_ elementId: UUID) -> CGSize {
        if draggingFrameChildIds.contains(elementId) {
            return draggingFrameOffset
        }
        return .zero
    }
    
    /// Move child elements to follow a frame (real-time during drag) - DEPRECATED, use visual offset instead
    func moveChildElements(_ children: [(id: UUID, offset: CGPoint)], toFollowFrameAt framePosition: CGPoint) {
        // No longer updates model during drag - uses visual offset instead
    }
    
    /// Finalize frame and children positions after drag (with save)
    func finalizeFrameWithChildren(_ frameId: UUID, to newPosition: CGPoint, children: [(id: UUID, offset: CGPoint)]) {
        guard let currentCanvas = currentCanvas,
              let canvasIndex = canvases.firstIndex(where: { $0.id == currentCanvas.id }),
              let frameIndex = canvases[canvasIndex].elements.firstIndex(where: { $0.id == frameId }) else { return }
        
        // Move the frame
        canvases[canvasIndex].elements[frameIndex].position = newPosition
        
        // Move all child elements
        for child in children {
            if let childIndex = canvases[canvasIndex].elements.firstIndex(where: { $0.id == child.id }) {
                canvases[canvasIndex].elements[childIndex].position = CGPoint(
                    x: newPosition.x + child.offset.x,
                    y: newPosition.y + child.offset.y
                )
            }
        }
        
        self.currentCanvas = canvases[canvasIndex]
        saveCanvases()
    }
    
    /// Move a section/frame along with all elements inside it (legacy - for single move)
    func moveFrameWithChildren(_ frameId: UUID, from oldPosition: CGPoint, to newPosition: CGPoint) {
        let children = getChildElementsInFrame(frameId, framePosition: oldPosition)
        finalizeFrameWithChildren(frameId, to: newPosition, children: children)
    }
    
    // MARK: - Connection Functions
    
    func addConnection(from: UUID, to: UUID, style: Connection.ConnectionStyle = .arrow, color: String = "#007AFF") {
        guard let currentCanvas = currentCanvas,
              let index = canvases.firstIndex(where: { $0.id == currentCanvas.id }) else { return }
        
        // Don't create duplicate connections
        let exists = canvases[index].connections.contains { 
            ($0.fromElementId == from && $0.toElementId == to) ||
            ($0.fromElementId == to && $0.toElementId == from)
        }
        guard !exists else { return }
        
        let connection = Connection(from: from, to: to, style: style, color: color)
        canvases[index].connections.append(connection)
        self.currentCanvas = canvases[index]
        saveCanvases()
    }
    
    func removeConnection(_ connectionId: UUID) {
        guard let currentCanvas = currentCanvas,
              let index = canvases.firstIndex(where: { $0.id == currentCanvas.id }) else { return }
        
        canvases[index].connections.removeAll { $0.id == connectionId }
        self.currentCanvas = canvases[index]
        saveCanvases()
    }
    
    func removeConnectionsForElement(_ elementId: UUID) {
        guard let currentCanvas = currentCanvas,
              let index = canvases.firstIndex(where: { $0.id == currentCanvas.id }) else { return }
        
        canvases[index].connections.removeAll { 
            $0.fromElementId == elementId || $0.toElementId == elementId 
        }
        self.currentCanvas = canvases[index]
        saveCanvases()
    }
    
    // MARK: - Quick Arrange Functions
    
    func arrangeSelectedAsGrid(columns: Int = 3, spacing: CGFloat = 30) {
        guard let currentCanvas = currentCanvas,
              let index = canvases.firstIndex(where: { $0.id == currentCanvas.id }),
              !selectedElementIds.isEmpty else { return }
        
        let selectedElements = canvases[index].elements.filter { selectedElementIds.contains($0.id) }
        guard !selectedElements.isEmpty else { return }
        
        // Find top-left corner of selection
        let minX = selectedElements.map { $0.position.x - $0.size.width/2 }.min() ?? 0
        let minY = selectedElements.map { $0.position.y - $0.size.height/2 }.min() ?? 0
        
        // Arrange in grid
        for (i, element) in selectedElements.enumerated() {
            let row = i / columns
            let col = i % columns
            
            // Calculate cumulative widths and heights for positioning
            var xOffset: CGFloat = 0
            var yOffset: CGFloat = 0
            
            for c in 0..<col {
                let colElements = selectedElements.enumerated().filter { $0.offset % columns == c }
                let maxWidth = colElements.map { $0.element.size.width }.max() ?? 0
                xOffset += maxWidth + spacing
            }
            
            for r in 0..<row {
                let rowElements = selectedElements.enumerated().filter { $0.offset / columns == r }
                let maxHeight = rowElements.map { $0.element.size.height }.max() ?? 0
                yOffset += maxHeight + spacing
            }
            
            let newPosition = CGPoint(
                x: minX + element.size.width/2 + xOffset,
                y: minY + element.size.height/2 + yOffset
            )
            
            if let elementIndex = canvases[index].elements.firstIndex(where: { $0.id == element.id }) {
                canvases[index].elements[elementIndex].position = snapPositionToGrid(newPosition)
            }
        }
        
        self.currentCanvas = canvases[index]
        saveCanvases()
    }
    
    func stackSelectedVertically(spacing: CGFloat = 20) {
        guard let currentCanvas = currentCanvas,
              let index = canvases.firstIndex(where: { $0.id == currentCanvas.id }),
              !selectedElementIds.isEmpty else { return }
        
        var selectedElements = canvases[index].elements.filter { selectedElementIds.contains($0.id) }
        guard !selectedElements.isEmpty else { return }
        
        // Sort by current Y position
        selectedElements.sort { $0.position.y < $1.position.y }
        
        // Use first element's X position and top position as anchor
        let anchorX = selectedElements[0].position.x
        var currentY = selectedElements[0].position.y - selectedElements[0].size.height/2
        
        for element in selectedElements {
            let newPosition = CGPoint(
                x: anchorX,
                y: currentY + element.size.height/2
            )
            
            if let elementIndex = canvases[index].elements.firstIndex(where: { $0.id == element.id }) {
                canvases[index].elements[elementIndex].position = snapPositionToGrid(newPosition)
            }
            
            currentY += element.size.height + spacing
        }
        
        self.currentCanvas = canvases[index]
        saveCanvases()
    }
    
    func stackSelectedHorizontally(spacing: CGFloat = 20) {
        guard let currentCanvas = currentCanvas,
              let index = canvases.firstIndex(where: { $0.id == currentCanvas.id }),
              !selectedElementIds.isEmpty else { return }
        
        var selectedElements = canvases[index].elements.filter { selectedElementIds.contains($0.id) }
        guard !selectedElements.isEmpty else { return }
        
        // Sort by current X position
        selectedElements.sort { $0.position.x < $1.position.x }
        
        // Use first element's Y position and left position as anchor
        let anchorY = selectedElements[0].position.y
        var currentX = selectedElements[0].position.x - selectedElements[0].size.width/2
        
        for element in selectedElements {
            let newPosition = CGPoint(
                x: currentX + element.size.width/2,
                y: anchorY
            )
            
            if let elementIndex = canvases[index].elements.firstIndex(where: { $0.id == element.id }) {
                canvases[index].elements[elementIndex].position = snapPositionToGrid(newPosition)
            }
            
            currentX += element.size.width + spacing
        }
        
        self.currentCanvas = canvases[index]
        saveCanvases()
    }
    
    func tidyUpSelected() {
        guard let currentCanvas = currentCanvas,
              let index = canvases.firstIndex(where: { $0.id == currentCanvas.id }),
              !selectedElementIds.isEmpty else { return }
        
        // Snap all selected elements to grid
        for elementId in selectedElementIds {
            if let elementIndex = canvases[index].elements.firstIndex(where: { $0.id == elementId }) {
                let position = canvases[index].elements[elementIndex].position
                canvases[index].elements[elementIndex].position = CGPoint(
                    x: round(position.x / gridSize) * gridSize,
                    y: round(position.y / gridSize) * gridSize
                )
            }
        }
        
        self.currentCanvas = canvases[index]
        saveCanvases()
    }
    
    func distributeSelectedEvenly(direction: DistributionDirection) {
        guard let currentCanvas = currentCanvas,
              let index = canvases.firstIndex(where: { $0.id == currentCanvas.id }),
              selectedElementIds.count >= 3 else { return }
        
        var selectedElements = canvases[index].elements.filter { selectedElementIds.contains($0.id) }
        guard selectedElements.count >= 3 else { return }
        
        switch direction {
        case .horizontal:
            selectedElements.sort { $0.position.x < $1.position.x }
            let firstX = selectedElements.first!.position.x
            let lastX = selectedElements.last!.position.x
            let spacing = (lastX - firstX) / CGFloat(selectedElements.count - 1)
            
            for (i, element) in selectedElements.enumerated() {
                if let elementIndex = canvases[index].elements.firstIndex(where: { $0.id == element.id }) {
                    canvases[index].elements[elementIndex].position.x = firstX + spacing * CGFloat(i)
                }
            }
            
        case .vertical:
            selectedElements.sort { $0.position.y < $1.position.y }
            let firstY = selectedElements.first!.position.y
            let lastY = selectedElements.last!.position.y
            let spacing = (lastY - firstY) / CGFloat(selectedElements.count - 1)
            
            for (i, element) in selectedElements.enumerated() {
                if let elementIndex = canvases[index].elements.firstIndex(where: { $0.id == element.id }) {
                    canvases[index].elements[elementIndex].position.y = firstY + spacing * CGFloat(i)
                }
            }
        }
        
        self.currentCanvas = canvases[index]
        saveCanvases()
    }
    
    enum DistributionDirection {
        case horizontal, vertical
    }
    
    // MARK: - Alignment Guide Helpers
    
    func getAlignmentGuides(for element: CanvasElement, excluding: UUID) -> [AlignmentGuide] {
        guard showAlignmentGuides, isDraggingElement,
              draggingElementId == element.id,
              let currentCanvas = currentCanvas else { return [] }
        
        var guides: [AlignmentGuide] = []
        let threshold: CGFloat = 10
        
        // Use the real-time dragging position instead of stored position
        let currentPosition = draggingElementPosition
        
        let elementLeft = currentPosition.x - element.size.width/2
        let elementRight = currentPosition.x + element.size.width/2
        let elementTop = currentPosition.y - element.size.height/2
        let elementBottom = currentPosition.y + element.size.height/2
        let elementCenterX = currentPosition.x
        let elementCenterY = currentPosition.y
        
        for other in currentCanvas.elements where other.id != excluding {
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
    
    func startPlacementMode(type: CanvasElement.ElementType, content: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name("EnterPlacementMode"),
            object: nil,
            userInfo: ["type": type, "content": content]
        )
    }
    
    func addElementAtPosition(type: CanvasElement.ElementType, content: String, position: CGPoint) {
        guard let currentCanvas = currentCanvas,
              let index = canvases.firstIndex(where: { $0.id == currentCanvas.id }) else {
            return
        }
        
        let size = sizeForElementType(type)
        
        let newElement = CanvasElement(
            id: UUID(),
            type: type,
            position: position,
            size: size,
            rotation: 0,
            zIndex: canvases[index].elements.count,
            content: content,
            state: nil,
            thumbnail: nil
        )
        
        canvases[index].elements.append(newElement)
        self.currentCanvas = canvases[index]
        saveCanvases()
    }
    
    func removeElement(_ element: CanvasElement) {
        guard let currentCanvas = currentCanvas,
              let canvasIndex = canvases.firstIndex(where: { $0.id == currentCanvas.id }) else {
            return
        }
        
        canvases[canvasIndex].elements.removeAll { $0.id == element.id }
        self.currentCanvas = canvases[canvasIndex]
        saveCanvases()
    }
    
    func updateElement(_ element: CanvasElement) {
        guard let currentCanvas = currentCanvas,
              let canvasIndex = canvases.firstIndex(where: { $0.id == currentCanvas.id }),
              let elementIndex = canvases[canvasIndex].elements.firstIndex(where: { $0.id == element.id }) else {
            return
        }
        
        canvases[canvasIndex].elements[elementIndex] = element
        self.currentCanvas = canvases[canvasIndex]
        saveCanvases()
    }
    
    func updateElementWebState(elementId: UUID, state: String?, content: String?) {
        guard let currentCanvas = currentCanvas,
              let canvasIndex = canvases.firstIndex(where: { $0.id == currentCanvas.id }),
              let elementIndex = canvases[canvasIndex].elements.firstIndex(where: { $0.id == elementId }) else {
            return
        }
        
        // Only update state and content, preserve position and size
        if let state = state {
            canvases[canvasIndex].elements[elementIndex].state = state
        }
        if let content = content {
            canvases[canvasIndex].elements[elementIndex].content = content
        }
        self.currentCanvas = canvases[canvasIndex]
        saveCanvases()
    }
    
    func updateTextStyle(elementId: UUID, size: CGFloat?, color: Color?) {
        guard let currentCanvas = currentCanvas,
              let canvasIndex = canvases.firstIndex(where: { $0.id == currentCanvas.id }),
              let elementIndex = canvases[canvasIndex].elements.firstIndex(where: { $0.id == elementId }) else {
            return
        }
        
        let element = canvases[canvasIndex].elements[elementIndex]
        
        // Parse existing content
        var text = ""
        var currentSize: CGFloat = 16
        var currentColor = "#000000"
        
        if let data = element.content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            text = json["text"] as? String ?? ""
            currentSize = json["size"] as? CGFloat ?? 16
            currentColor = json["color"] as? String ?? "#000000"
        }
        
        // Update with new values
        let newSize = size ?? currentSize
        let newColor = color?.hexString ?? currentColor
        
        let jsonData: [String: Any] = [
            "text": text,
            "size": newSize,
            "color": newColor
        ]
        
        if let json = try? JSONSerialization.data(withJSONObject: jsonData),
           let jsonString = String(data: json, encoding: .utf8) {
            canvases[canvasIndex].elements[elementIndex].content = jsonString
            self.currentCanvas = canvases[canvasIndex]
            saveCanvases()
        }
    }
    
    func importPDF() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf]
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.addElement(type: .pdf, content: url.path)
            }
        }
    }
    
    func addPDFNote(pdfElementId: UUID, pageNumber: Int, selectedText: String, position: CGPoint) {
        guard let currentCanvas = currentCanvas,
              let canvasIndex = canvases.firstIndex(where: { $0.id == currentCanvas.id }) else {
            return
        }
        
        // Find the PDF element
        guard let pdfElement = canvases[canvasIndex].elements.first(where: { $0.id == pdfElementId }) else {
            return
        }
        
        // Calculate smart position for the note
        let smartPosition = calculateNotePosition(for: pdfElement, in: canvases[canvasIndex])
        
        // Create note content with link back to PDF page
        let noteData: [String: Any] = [
            "text": "",
            "pdfElementId": pdfElementId.uuidString,
            "pageNumber": pageNumber,
            "selectedText": selectedText
        ]
        let noteContent = try? JSONSerialization.data(withJSONObject: noteData)
        
        let newElement = CanvasElement(
            id: UUID(),
            type: .text,
            position: smartPosition,
            size: CGSize(width: 250, height: 150),
            rotation: 0,
            zIndex: canvases[canvasIndex].elements.count,
            content: String(data: noteContent ?? Data(), encoding: .utf8) ?? ""
        )
        
        canvases[canvasIndex].elements.append(newElement)
        self.currentCanvas = canvases[canvasIndex]
        saveCanvases()
    }
    
    private func calculateNotePosition(for pdfElement: CanvasElement, in canvas: Canvas) -> CGPoint {
        // Find all existing notes for this PDF
        let existingNotes = canvas.elements.filter { element in
            guard let data = element.content.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pdfIdString = json["pdfElementId"] as? String,
                  let pdfId = UUID(uuidString: pdfIdString) else {
                return false
            }
            return pdfId == pdfElement.id
        }
        
        // Start position: to the right of the PDF
        let baseX = pdfElement.position.x + pdfElement.size.width + 20
        let baseY = pdfElement.position.y
        
        // Stack notes vertically with slight offset
        let noteIndex = existingNotes.count
        let verticalSpacing: CGFloat = 160 // Height + small gap
        let horizontalOffset: CGFloat = CGFloat(noteIndex % 2) * 15 // Alternate slight horizontal offset for visual appeal
        
        return CGPoint(
            x: baseX + horizontalOffset,
            y: baseY + (CGFloat(noteIndex) * verticalSpacing)
        )
    }
}

struct Canvas: Identifiable, Codable {
    let id: UUID
    var name: String
    var elements: [CanvasElement]
    var connections: [Connection] // Links between elements
    var createdDate: Date
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.elements = []
        self.connections = []
        self.createdDate = Date()
    }
    
    // For backward compatibility with existing canvases
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        elements = try container.decode([CanvasElement].self, forKey: .elements)
        connections = try container.decodeIfPresent([Connection].self, forKey: .connections) ?? []
        createdDate = try container.decode(Date.self, forKey: .createdDate)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, elements, connections, createdDate
    }
}

// MARK: - Connection Model
struct Connection: Identifiable, Codable, Equatable {
    let id: UUID
    var fromElementId: UUID
    var toElementId: UUID
    var style: ConnectionStyle
    var color: String // Hex color
    var label: String?
    
    init(from: UUID, to: UUID, style: ConnectionStyle = .arrow, color: String = "#007AFF", label: String? = nil) {
        self.id = UUID()
        self.fromElementId = from
        self.toElementId = to
        self.style = style
        self.color = color
        self.label = label
    }
    
    enum ConnectionStyle: String, Codable {
        case line
        case arrow
        case dashed
        case curved
    }
}

struct CanvasElement: Identifiable, Codable, Equatable {
    let id: UUID
    let type: ElementType
    var position: CGPoint
    var size: CGSize
    var rotation: Double
    var zIndex: Int
    var content: String // JSON-encoded content or URL
    var state: String? // JSON-encoded state (scroll position, page number, etc.)
    var thumbnail: String? // Base64-encoded thumbnail image
    var lastAccessedTime: Date? // Track when element was last interacted with
    
    // Frame-specific properties
    var frameColor: String? // Hex color for frame background
    var isCollapsed: Bool? // For collapsible frames
    var childElements: [UUID]? // IDs of elements contained in this frame
    
    enum ElementType: String, Codable {
        case drawing, text, webview, pdf, frame
    }
    
    static func == (lhs: CanvasElement, rhs: CanvasElement) -> Bool {
        lhs.id == rhs.id
    }
    
    // For backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(ElementType.self, forKey: .type)
        position = try container.decode(CGPoint.self, forKey: .position)
        size = try container.decode(CGSize.self, forKey: .size)
        rotation = try container.decode(Double.self, forKey: .rotation)
        zIndex = try container.decode(Int.self, forKey: .zIndex)
        content = try container.decode(String.self, forKey: .content)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        lastAccessedTime = try container.decodeIfPresent(Date.self, forKey: .lastAccessedTime)
        frameColor = try container.decodeIfPresent(String.self, forKey: .frameColor)
        isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed)
        childElements = try container.decodeIfPresent([UUID].self, forKey: .childElements)
    }
    
    init(id: UUID, type: ElementType, position: CGPoint, size: CGSize, rotation: Double, zIndex: Int, content: String, state: String? = nil, thumbnail: String? = nil, frameColor: String? = nil, isCollapsed: Bool? = nil, childElements: [UUID]? = nil) {
        self.id = id
        self.type = type
        self.position = position
        self.size = size
        self.rotation = rotation
        self.zIndex = zIndex
        self.content = content
        self.state = state
        self.thumbnail = thumbnail
        self.lastAccessedTime = nil
        self.frameColor = frameColor
        self.isCollapsed = isCollapsed
        self.childElements = childElements
    }
    
    enum CodingKeys: String, CodingKey {
        case id, type, position, size, rotation, zIndex, content, state, thumbnail, lastAccessedTime, frameColor, isCollapsed, childElements
    }
}

// MARK: - Alignment Guide
struct AlignmentGuide: Identifiable {
    let id = UUID()
    let type: GuideType
    let position: CGFloat
    
    enum GuideType {
        case horizontal
        case vertical
    }
}

// MARK: - Frame Colors
struct FrameColors {
    static let presets: [(name: String, hex: String)] = [
        ("Charcoal", "#2D2D2D"),
        ("Slate", "#3D4551"),
        ("Graphite", "#4A4A4A"),
        ("Steel", "#5C6670"),
        ("Smoke", "#6E7781"),
        ("Stone", "#8B8B8B"),
        ("Silver", "#A8A8A8"),
        ("Ash", "#B8C0C8"),
        ("Mist", "#D0D7DE"),
        ("Cloud", "#E8ECF0")
    ]
}
