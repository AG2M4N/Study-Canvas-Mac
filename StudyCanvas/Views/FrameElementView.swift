import SwiftUI

struct FrameElementView: View {
    let element: CanvasElement
    let canvasManager: CanvasManager
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isEditing = false
    @State private var titleText: String
    @State private var showColorPicker = false
    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero
    @State private var position: CGPoint
    @State private var dragStartPosition: CGPoint = .zero  // Store position when drag starts
    @State private var childElements: [(id: UUID, offset: CGPoint)] = []  // Children captured at drag start
    @State private var size: CGSize
    @State private var isResizing = false
    @Environment(\.zoomLevel) private var zoomLevel
    
    init(element: CanvasElement, canvasManager: CanvasManager, isSelected: Bool, onSelect: @escaping () -> Void) {
        self.element = element
        self.canvasManager = canvasManager
        self.isSelected = isSelected
        self.onSelect = onSelect
        _titleText = State(initialValue: element.content)
        _position = State(initialValue: element.position)
        _size = State(initialValue: element.size)
    }
    
    private var frameColor: Color {
        if let hex = element.frameColor {
            return Color(hex: hex)
        }
        return Color(hex: FrameColors.presets[0].hex)
    }
    
    // Determine if we need light text based on background darkness
    private var textColor: Color {
        if let hex = element.frameColor {
            return isLightColor(hex: hex) ? .primary : .white
        }
        return .white  // Default to white for new dark presets
    }
    
    private var secondaryTextColor: Color {
        if let hex = element.frameColor {
            return isLightColor(hex: hex) ? .secondary : .white.opacity(0.7)
        }
        return .white.opacity(0.7)
    }
    
    private func isLightColor(hex: String) -> Bool {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        // Calculate relative luminance
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.5
    }
    
    private var isCollapsed: Bool {
        element.isCollapsed ?? false
    }
    
    private var currentPosition: CGPoint {
        CGPoint(
            x: position.x + dragOffset.width,
            y: position.y + dragOffset.height
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar
            
            // Content area (when not collapsed)
            if !isCollapsed {
                contentArea
            }
        }
        .frame(
            width: size.width,
            height: isCollapsed ? 44 : size.height
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(frameColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.gray.opacity(0.3),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .overlay(alignment: .bottomTrailing) {
            // Resize handle
            if isSelected && !isCollapsed {
                resizeHandle
            }
        }
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .position(currentPosition)
        .simultaneousGesture(dragGesture)
        .onChange(of: element.position) { newValue in
            if !isDragging {
                position = newValue
            }
        }
        .onChange(of: element.size) { newValue in
            if !isResizing {
                size = newValue
            }
        }
    }
    
    private var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartPosition = position  // Capture the position when drag starts
                    // Capture child elements and their offsets at drag start
                    childElements = canvasManager.startFrameDrag(element.id, framePosition: position)
                    onSelect()
                }
                
                let adjustedWidth = value.translation.width / zoomLevel
                let adjustedHeight = value.translation.height / zoomLevel
                
                let offset = CGSize(
                    width: round(adjustedWidth),
                    height: round(adjustedHeight)
                )
                
                dragOffset = offset
                
                // Update visual offset for children (no model update, just visual)
                canvasManager.updateFrameDragOffset(offset)
            }
            .onEnded { value in
                let adjustedWidth = value.translation.width / zoomLevel
                let adjustedHeight = value.translation.height / zoomLevel
                
                let newPosition = CGPoint(
                    x: round(dragStartPosition.x + adjustedWidth),
                    y: round(dragStartPosition.y + adjustedHeight)
                )
                
                // Clear drag state before finalizing
                canvasManager.endFrameDrag()
                
                position = newPosition
                dragOffset = .zero
                isDragging = false
                
                // Finalize positions and save (single model update)
                canvasManager.finalizeFrameWithChildren(element.id, to: newPosition, children: childElements)
                childElements = []  // Clear after drag ends
            }
    }
    
    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .frame(width: 20, height: 20)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
            .cornerRadius(4)
            .padding(6)
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if !isResizing {
                            isResizing = true
                        }
                        
                        let adjustedWidth = value.translation.width / zoomLevel
                        let adjustedHeight = value.translation.height / zoomLevel
                        
                        size = CGSize(
                            width: max(200, element.size.width + adjustedWidth),
                            height: max(100, element.size.height + adjustedHeight)
                        )
                    }
                    .onEnded { value in
                        let adjustedWidth = value.translation.width / zoomLevel
                        let adjustedHeight = value.translation.height / zoomLevel
                        
                        size = CGSize(
                            width: max(200, element.size.width + adjustedWidth),
                            height: max(100, element.size.height + adjustedHeight)
                        )
                        
                        isResizing = false
                        
                        var updatedElement = element
                        updatedElement.size = size
                        canvasManager.updateElement(updatedElement)
                    }
            )
    }
    
    private var headerBar: some View {
        HStack(spacing: 8) {
            // Collapse button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    canvasManager.toggleFrameCollapsed(element.id)
                }
            }) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(secondaryTextColor)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            
            // Title - click to edit
            if isEditing {
                TextField("Section Title", text: $titleText, onCommit: {
                    saveTitle()
                })
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(textColor)
                .frame(minWidth: 100)
                .onExitCommand {
                    titleText = element.content
                    isEditing = false
                }
            } else {
                Text(element.content.isEmpty ? "Click to name section" : element.content)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(element.content.isEmpty ? secondaryTextColor : textColor)
                    .frame(minWidth: 100, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isEditing = true
                        if element.content.isEmpty {
                            titleText = ""
                        }
                    }
            }
            
            Spacer()
            
            // Color picker button
            Menu {
                ForEach(FrameColors.presets, id: \.hex) { preset in
                    Button(action: {
                        canvasManager.updateFrameColor(element.id, color: preset.hex)
                    }) {
                        HStack {
                            Circle()
                                .fill(Color(hex: preset.hex))
                                .frame(width: 16, height: 16)
                            Text(preset.name)
                            if element.frameColor == preset.hex {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(frameColor)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(secondaryTextColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.15))
                .cornerRadius(6)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            // Close button
            Button(action: {
                canvasManager.removeElement(element)
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(secondaryTextColor)
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                onSelect()
            }
        )
    }
    
    private var contentArea: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect()
            }
    }
    
    private func saveTitle() {
        var updatedElement = element
        updatedElement.content = titleText
        canvasManager.updateElement(updatedElement)
        isEditing = false
    }
}

