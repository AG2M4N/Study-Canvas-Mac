import SwiftUI

// MARK: - Mini Map View
/// A miniature overview of the canvas for quick navigation
struct MiniMapView: View {
    @ObservedObject var canvasManager: CanvasManager
    let canvasSize: CGSize
    let zoomLevel: CGFloat
    let onNavigate: (CGPoint) -> Void
    
    @State private var isExpanded = true
    @State private var isHovering = false
    
    // Mini map dimensions
    private let miniMapWidth: CGFloat = 200
    private let miniMapHeight: CGFloat = 150
    private let cornerRadius: CGFloat = 8
    
    // Calculate the scale factor for mini map
    private var scale: CGFloat {
        let scaleX = miniMapWidth / canvasSize.width
        let scaleY = miniMapHeight / canvasSize.height
        return min(scaleX, scaleY)
    }
    
    // Actual mini map content size
    private var contentSize: CGSize {
        CGSize(
            width: canvasSize.width * scale,
            height: canvasSize.height * scale
        )
    }
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Spacer()
            
            HStack {
                Spacer()
                
                if isExpanded {
                    miniMapContent
                } else {
                    collapsedButton
                }
            }
        }
        .padding(16)
    }
    
    // MARK: - Collapsed Button
    private var collapsedButton: some View {
        Button(action: { withAnimation(.spring(response: 0.3)) { isExpanded = true }}) {
            Image(systemName: "map")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(canvasManager.theme == .dark ? Color(white: 0.2) : Color.white)
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                )
        }
        .buttonStyle(.plain)
        .help("Show Mini Map")
    }
    
    // MARK: - Expanded Mini Map
    private var miniMapContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Mini Map")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: { withAnimation(.spring(response: 0.3)) { isExpanded = false }}) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(canvasManager.theme == .dark ? Color(white: 0.15) : Color(white: 0.95))
            
            // Map content
            ZStack(alignment: .topLeading) {
                // Background
                Rectangle()
                    .fill(canvasManager.theme == .dark ? Color(white: 0.1) : Color(white: 0.98))
                
                // Elements - render sections first (behind), then other elements
                if let elements = canvasManager.currentCanvas?.elements {
                    // Sections (frames) first - behind other elements
                    ForEach(elements.filter { $0.type == .frame }, id: \.id) { element in
                        miniMapSection(for: element)
                    }
                    
                    // Other elements on top
                    ForEach(elements.filter { $0.type != .frame }, id: \.id) { element in
                        miniMapElement(for: element)
                    }
                }
                
                // Viewport indicator
                viewportIndicator
            }
            .frame(width: contentSize.width, height: contentSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Immediately navigate on any touch/drag
                        handleTap(at: value.location)
                    }
            )
            .padding(8)
        }
        .frame(width: miniMapWidth)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(canvasManager.theme == .dark ? Color(white: 0.2) : Color.white)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .opacity(isHovering ? 1.0 : 0.85)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
    }
    
    // MARK: - Mini Map Section (Frame)
    private func miniMapSection(for element: CanvasElement) -> some View {
        let scaledPosition = CGPoint(
            x: (element.position.x - element.size.width / 2) * scale,
            y: (element.position.y - element.size.height / 2) * scale
        )
        let scaledSize = CGSize(
            width: max(10, element.size.width * scale),
            height: max(8, element.size.height * scale)
        )
        
        let sectionColor = element.frameColor.map { Color(hex: $0) } ?? Color.gray
        
        return ZStack {
            // Fill - more visible
            RoundedRectangle(cornerRadius: 2)
                .fill(sectionColor.opacity(0.5))
            // Border - thicker and more visible
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(sectionColor, lineWidth: 2)
            // Section name indicator line at top
            VStack(spacing: 0) {
                Rectangle()
                    .fill(sectionColor)
                    .frame(height: 3)
                Spacer()
            }
        }
        .frame(width: scaledSize.width, height: scaledSize.height)
        .offset(x: scaledPosition.x, y: scaledPosition.y)
    }
    
    // MARK: - Mini Map Element
    private func miniMapElement(for element: CanvasElement) -> some View {
        let scaledPosition = CGPoint(
            x: (element.position.x - element.size.width / 2) * scale,
            y: (element.position.y - element.size.height / 2) * scale
        )
        let scaledSize = CGSize(
            width: max(3, element.size.width * scale),
            height: max(3, element.size.height * scale)
        )
        
        return Rectangle()
            .fill(colorForElementType(element.type, frameColor: element.frameColor))
            .frame(width: scaledSize.width, height: scaledSize.height)
            .offset(x: scaledPosition.x, y: scaledPosition.y)
    }
    
    // MARK: - Viewport Indicator
    private var viewportIndicator: some View {
        GeometryReader { geometry in
            let viewportSize = getViewportSize()
            let viewportPosition = getViewportPosition()
            
            Rectangle()
                .strokeBorder(Color.blue, lineWidth: 1.5)
                .background(Color.blue.opacity(0.1))
                .frame(width: viewportSize.width, height: viewportSize.height)
                .offset(x: viewportPosition.x, y: viewportPosition.y)
        }
    }
    
    // MARK: - Helper Functions
    private func colorForElementType(_ type: CanvasElement.ElementType, frameColor: String?) -> Color {
        switch type {
        case .frame:
            if let hex = frameColor {
                return Color(hex: hex).opacity(0.6)
            }
            return Color.gray.opacity(0.3)
        case .webview:
            return Color.blue.opacity(0.7)
        case .pdf:
            return Color.red.opacity(0.7)
        case .text:
            return Color.green.opacity(0.7)
        case .drawing:
            return Color.orange.opacity(0.7)
        }
    }
    
    private func getViewportSize() -> CGSize {
        guard let scrollView = ScrollViewHelper.shared.scrollView else {
            return CGSize(width: miniMapWidth * 0.3, height: miniMapHeight * 0.3)
        }
        
        let visibleSize = scrollView.contentView.bounds.size
        return CGSize(
            width: max(10, (visibleSize.width / zoomLevel) * scale),
            height: max(10, (visibleSize.height / zoomLevel) * scale)
        )
    }
    
    private func getViewportPosition() -> CGPoint {
        guard let scrollView = ScrollViewHelper.shared.scrollView else {
            return .zero
        }
        
        let offset = scrollView.contentView.bounds.origin
        return CGPoint(
            x: (offset.x / zoomLevel) * scale,
            y: (offset.y / zoomLevel) * scale
        )
    }
    
    private func handleTap(at location: CGPoint) {
        // Convert mini map location to canvas location
        let canvasX = location.x / scale
        let canvasY = location.y / scale
        
        // Navigate to center the view on this point
        onNavigate(CGPoint(x: canvasX, y: canvasY))
    }
}

#Preview {
    MiniMapView(
        canvasManager: CanvasManager(),
        canvasSize: CGSize(width: 3000, height: 3000),
        zoomLevel: 1.0,
        onNavigate: { _ in }
    )
    .frame(width: 400, height: 400)
    .background(Color.gray.opacity(0.2))
}
