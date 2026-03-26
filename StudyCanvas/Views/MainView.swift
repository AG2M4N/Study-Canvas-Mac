import SwiftUI

struct MainView: View {
    @EnvironmentObject var canvasManager: CanvasManager
    
    var body: some View {
        Group {
            if canvasManager.currentCanvas == nil {
                LandingView()
            } else {
                CanvasView()
            }
        }
    }
}

struct CanvasView: View {
    @EnvironmentObject var canvasManager: CanvasManager
    @State private var selectedElementId: UUID?
    @State private var zoomLevel: CGFloat = 1.0
    @State private var lastMagnification: CGFloat = 1.0
    @State private var showOrganizationToolbar = true
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                CanvasHeader(selectedElementId: $selectedElementId, zoomLevel: $zoomLevel)
                
                // Canvas Content
                ContentView(selectedElementId: $selectedElementId, zoomLevel: $zoomLevel, lastMagnification: $lastMagnification)
            }
            
            // Floating Organization Toolbar
            if showOrganizationToolbar {
                VStack {
                    HStack {
                        Spacer()
                        OrganizationToolbar(canvasManager: canvasManager)
                            .padding(.trailing, 16)
                            .padding(.top, 60)
                    }
                    Spacer()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Toggle(isOn: $showOrganizationToolbar) {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("Toggle Organization Toolbar")
            }
        }
    }
}

struct CanvasHeader: View {
    @EnvironmentObject var canvasManager: CanvasManager
    @Binding var selectedElementId: UUID?
    @Binding var zoomLevel: CGFloat
    @State private var showCanvasSwitcher = false
    @State private var showDeleteConfirmation = false
    
    private var selectedTextElement: CanvasElement? {
        guard let id = selectedElementId,
              let canvas = canvasManager.currentCanvas else { return nil }
        let element = canvas.elements.first(where: { $0.id == id })
        return element?.type == .text ? element : nil
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Back to home
            Button(action: {
                // Force save all element states before leaving
                canvasManager.cleanupCurrentCanvas()
                canvasManager.currentCanvas = nil
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Home")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            Divider()
                .frame(height: 24)
            
            // Theme toggle
            Button(action: {
                canvasManager.toggleTheme()
            }) {
                Image(systemName: canvasManager.theme == .dark ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            // Tools Menu
            ToolsMenu()
            
            // Text Formatting (only when text is selected)
            if let textElement = selectedTextElement {
                Divider()
                    .frame(height: 24)
                
                // Size buttons
                HStack(spacing: 6) {
                    ForEach([12, 16, 20, 24, 32], id: \.self) { size in
                        Button(action: {
                            canvasManager.updateTextStyle(elementId: textElement.id, size: CGFloat(size), color: nil)
                        }) {
                            Text("\(size)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.primary)
                                .frame(width: 28, height: 28)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Divider()
                    .frame(height: 24)
                
                // Color buttons
                HStack(spacing: 6) {
                    ForEach([Color.black, .red, .orange, .green, .blue, .purple], id: \.self) { color in
                        Button(action: {
                            canvasManager.updateTextStyle(elementId: textElement.id, size: nil, color: color)
                        }) {
                            Circle()
                                .fill(color)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle()
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Current Canvas Info
            Menu {
                ForEach(canvasManager.canvases) { canvas in
                    Button(action: {
                        if canvas.id != canvasManager.currentCanvas?.id {
                            canvasManager.cleanupCurrentCanvas()
                        }
                        canvasManager.currentCanvas = canvas
                    }) {
                        HStack {
                            Text(canvas.name)
                            if canvas.id == canvasManager.currentCanvas?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                
                Divider()
                
                Button(action: {
                    showDeleteConfirmation = true
                }) {
                    Label("Delete Canvas", systemImage: "trash")
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 14))
                    Text(canvasManager.currentCanvas?.name ?? "Canvas")
                        .font(.system(size: 15, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(8)
            }
            .menuStyle(.borderlessButton)
            
            Spacer()
            
            // Zoom Controls
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        zoomLevel = min(zoomLevel + 0.1, 3.0)
                    }
                }) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Zoom In (⌘+)")
                
                // Zoom level indicator
                Text("\(Int(zoomLevel * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 44)
                
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        zoomLevel = max(zoomLevel - 0.1, 0.1)
                    }
                }) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Zoom Out (⌘-)")
                
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        zoomLevel = 1.0
                    }
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Reset Zoom (⌘0)")
            }
            
            // Info
            if let canvas = canvasManager.currentCanvas {
                Text("\(canvas.elements.count) elements")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1),
            alignment: .bottom
        )
        .animation(.easeInOut(duration: 0.2), value: selectedTextElement?.id)
        .alert("Delete Canvas", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let canvas = canvasManager.currentCanvas {
                    canvasManager.deleteCanvas(canvas)
                }
            }
        } message: {
            Text("Are you sure you want to delete '\(canvasManager.currentCanvas?.name ?? "this canvas")'? This action cannot be undone.")
        }
    }
}

struct ToolsMenu: View {
    @EnvironmentObject var canvasManager: CanvasManager
    @State private var showURLInput = false
    @State private var urlInput = "https://www.apple.com"
    
    var body: some View {
        Menu {
            Button(action: {
                // Drawing tool
            }) {
                Label("Drawing", systemImage: "pencil.tip")
            }
            
            Button(action: {
                canvasManager.startPlacementMode(type: .text, content: "")
            }) {
                Label("Add Text", systemImage: "text.quote")
            }
            
            Button(action: {
                canvasManager.startPlacementMode(type: .webview, content: "https://www.google.com")
            }) {
                Label("Add Webpage", systemImage: "globe")
            }
            
            Button(action: {
                importPDFWithPlacement()
            }) {
                Label("Import PDF", systemImage: "doc")
            }
            
            Divider()
            
            Button(action: {
                canvasManager.saveCanvases()
            }) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                Text("Tools")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.15))
            .cornerRadius(8)
        }
        .menuStyle(.borderlessButton)
    }
    
    private func importPDFWithPlacement() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf]
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                canvasManager.startPlacementMode(type: .pdf, content: url.path)
            }
        }
    }
}

#Preview {
    MainView()
        .environmentObject(CanvasManager())
}
