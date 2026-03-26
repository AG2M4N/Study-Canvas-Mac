import SwiftUI

struct DrawingCanvas: NSViewRepresentable {
    @Binding var isDrawing: Bool
    
    func makeNSView(context: Context) -> DrawingView {
        let view = DrawingView()
        return view
    }
    
    func updateNSView(_ nsView: DrawingView, context: Context) {}
}

class DrawingView: NSView {
    private var path = NSBezierPath()
    private var lines: [[NSPoint]] = []
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        NSColor.black.setStroke()
        for line in lines {
            let bezierPath = NSBezierPath()
            for (index, point) in line.enumerated() {
                if index == 0 {
                    bezierPath.move(to: point)
                } else {
                    bezierPath.line(to: point)
                }
            }
            bezierPath.lineWidth = 2.0
            bezierPath.stroke()
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        var currentLine: [NSPoint] = []
        currentLine.append(event.locationInWindow)
        
        while let event = self.window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if event.type == .leftMouseDragged {
                currentLine.append(event.locationInWindow)
                needsDisplay = true
            } else {
                currentLine.append(event.locationInWindow)
                break
            }
        }
        
        if !currentLine.isEmpty {
            lines.append(currentLine)
            needsDisplay = true
        }
    }
    
    func clearDrawing() {
        lines.removeAll()
        needsDisplay = true
    }
}
