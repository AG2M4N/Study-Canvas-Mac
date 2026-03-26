import SwiftUI

struct ConnectionsView: View {
    let connections: [Connection]
    let elements: [CanvasElement]
    let canvasManager: CanvasManager
    let zoomLevel: CGFloat
    
    var body: some View {
        ForEach(connections) { connection in
            ConnectionLineView(
                connection: connection,
                elements: elements,
                canvasManager: canvasManager
            )
        }
    }
}

struct ConnectionLineView: View {
    let connection: Connection
    let elements: [CanvasElement]
    let canvasManager: CanvasManager
    
    @State private var isHovered = false
    
    private var fromElement: CanvasElement? {
        elements.first { $0.id == connection.fromElementId }
    }
    
    private var toElement: CanvasElement? {
        elements.first { $0.id == connection.toElementId }
    }
    
    private var connectionColor: Color {
        Color(hex: connection.color)
    }
    
    var body: some View {
        if let from = fromElement, let to = toElement {
            ZStack {
                // The connection path
                ConnectionPath(
                    from: from.position,
                    to: to.position,
                    fromSize: from.size,
                    toSize: to.size,
                    style: connection.style
                )
                .stroke(
                    connectionColor,
                    style: strokeStyle
                )
                
                // Arrow head for arrow style
                if connection.style == .arrow {
                    ArrowHead(
                        from: from.position,
                        to: to.position,
                        fromSize: from.size,
                        toSize: to.size
                    )
                    .fill(connectionColor)
                }
                
                // Label if present
                if let label = connection.label, !label.isEmpty {
                    connectionLabel(label, from: from.position, to: to.position)
                }
                
                // Invisible wider path for easier click detection
                ConnectionPath(
                    from: from.position,
                    to: to.position,
                    fromSize: from.size,
                    toSize: to.size,
                    style: connection.style
                )
                .stroke(Color.clear, lineWidth: 20)
                .contentShape(
                    ConnectionPath(
                        from: from.position,
                        to: to.position,
                        fromSize: from.size,
                        toSize: to.size,
                        style: connection.style
                    )
                    .stroke(style: StrokeStyle(lineWidth: 20))
                )
                .onHover { hovering in
                    isHovered = hovering
                }
                .contextMenu {
                    Button("Delete Connection", role: .destructive) {
                        canvasManager.removeConnection(connection.id)
                    }
                }
            }
            .overlay {
                // Delete button on hover
                if isHovered {
                    deleteButton(from: from.position, to: to.position)
                }
            }
        }
    }
    
    private var strokeStyle: StrokeStyle {
        switch connection.style {
        case .line, .arrow:
            return StrokeStyle(lineWidth: 2, lineCap: .round)
        case .dashed:
            return StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 4])
        case .curved:
            return StrokeStyle(lineWidth: 2, lineCap: .round)
        }
    }
    
    private func connectionLabel(_ text: String, from: CGPoint, to: CGPoint) -> some View {
        let midPoint = CGPoint(
            x: (from.x + to.x) / 2,
            y: (from.y + to.y) / 2
        )
        
        return Text(text)
            .font(.system(size: 11))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(4)
            .position(midPoint)
    }
    
    private func deleteButton(from: CGPoint, to: CGPoint) -> some View {
        let midPoint = CGPoint(
            x: (from.x + to.x) / 2,
            y: (from.y + to.y) / 2 - 15
        )
        
        return Button(action: {
            canvasManager.removeConnection(connection.id)
        }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.red)
                .background(Circle().fill(Color.white))
        }
        .buttonStyle(.plain)
        .position(midPoint)
    }
}

// MARK: - Connection Path Shape
struct ConnectionPath: Shape {
    let from: CGPoint
    let to: CGPoint
    let fromSize: CGSize
    let toSize: CGSize
    let style: Connection.ConnectionStyle
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Calculate edge points
        let (startPoint, endPoint) = calculateEdgePoints()
        
        path.move(to: startPoint)
        
        if style == .curved {
            // Curved path
            let midX = (startPoint.x + endPoint.x) / 2
            let controlPoint1 = CGPoint(x: midX, y: startPoint.y)
            let controlPoint2 = CGPoint(x: midX, y: endPoint.y)
            path.addCurve(to: endPoint, control1: controlPoint1, control2: controlPoint2)
        } else {
            // Straight line
            path.addLine(to: endPoint)
        }
        
        return path
    }
    
    private func calculateEdgePoints() -> (CGPoint, CGPoint) {
        // Calculate direction
        let dx = to.x - from.x
        let dy = to.y - from.y
        let angle = atan2(dy, dx)
        
        // Calculate start point on edge of from element
        let startPoint = pointOnEdge(center: from, size: fromSize, angle: angle)
        
        // Calculate end point on edge of to element (opposite direction)
        let endPoint = pointOnEdge(center: to, size: toSize, angle: angle + .pi)
        
        return (startPoint, endPoint)
    }
    
    private func pointOnEdge(center: CGPoint, size: CGSize, angle: CGFloat) -> CGPoint {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        
        // Calculate intersection with rectangle edge
        let tanAngle = tan(angle)
        
        var x: CGFloat
        var y: CGFloat
        
        if abs(tanAngle) < halfHeight / halfWidth {
            // Intersects left or right edge
            x = cos(angle) > 0 ? halfWidth : -halfWidth
            y = x * tanAngle
        } else {
            // Intersects top or bottom edge
            y = sin(angle) > 0 ? halfHeight : -halfHeight
            x = y / tanAngle
        }
        
        return CGPoint(x: center.x + x, y: center.y + y)
    }
}

// MARK: - Arrow Head Shape
struct ArrowHead: Shape {
    let from: CGPoint
    let to: CGPoint
    let fromSize: CGSize
    let toSize: CGSize
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Calculate direction
        let dx = to.x - from.x
        let dy = to.y - from.y
        let angle = atan2(dy, dx)
        
        // Calculate end point on edge of to element
        let endPoint = pointOnEdge(center: to, size: toSize, angle: angle + .pi)
        
        // Arrow head size
        let arrowLength: CGFloat = 12
        let arrowWidth: CGFloat = 8
        
        // Arrow head points
        let tip = endPoint
        let left = CGPoint(
            x: tip.x - arrowLength * cos(angle) - arrowWidth * sin(angle) / 2,
            y: tip.y - arrowLength * sin(angle) + arrowWidth * cos(angle) / 2
        )
        let right = CGPoint(
            x: tip.x - arrowLength * cos(angle) + arrowWidth * sin(angle) / 2,
            y: tip.y - arrowLength * sin(angle) - arrowWidth * cos(angle) / 2
        )
        
        path.move(to: tip)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        
        return path
    }
    
    private func pointOnEdge(center: CGPoint, size: CGSize, angle: CGFloat) -> CGPoint {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        
        let tanAngle = tan(angle)
        
        var x: CGFloat
        var y: CGFloat
        
        if abs(tanAngle) < halfHeight / halfWidth {
            x = cos(angle) > 0 ? halfWidth : -halfWidth
            y = x * tanAngle
        } else {
            y = sin(angle) > 0 ? halfHeight : -halfHeight
            x = y / tanAngle
        }
        
        return CGPoint(x: center.x + x, y: center.y + y)
    }
}

// MARK: - Connection Mode Overlay
struct ConnectionModeOverlay: View {
    let canvasManager: CanvasManager
    let elements: [CanvasElement]
    
    var body: some View {
        if canvasManager.isConnectionMode {
            ZStack {
                // Semi-transparent overlay
                Color.black.opacity(0.1)
                    .ignoresSafeArea()
                
                // Instructions
                VStack {
                    Text("Connection Mode")
                        .font(.headline)
                    if canvasManager.connectionStartElement == nil {
                        Text("Click on an element to start connecting")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Click on another element to connect, or press Escape to cancel")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.windowBackgroundColor))
                        .shadow(radius: 10)
                )
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 60)
            }
            .onTapGesture {
                // Cancel connection mode when clicking empty area
                canvasManager.isConnectionMode = false
                canvasManager.connectionStartElement = nil
            }
        }
    }
}
