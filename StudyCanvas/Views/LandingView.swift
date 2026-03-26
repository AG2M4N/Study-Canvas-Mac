import SwiftUI

struct LandingView: View {
    @EnvironmentObject var canvasManager: CanvasManager
    @State private var showNewCanvasDialog = false
    @State private var newCanvasName = ""
    @State private var selectedCanvas: Canvas?
    @State private var showDeleteConfirmation = false
    @State private var canvasToDelete: Canvas?
    
    var body: some View {
        ZStack {
            // Dynamic background based on theme
            (canvasManager.theme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Theme toggle button
                HStack {
                    Spacer()
                    Button(action: {
                        canvasManager.toggleTheme()
                    }) {
                        Image(systemName: canvasManager.theme == .dark ? "sun.max.fill" : "moon.fill")
                            .font(.system(size: 20))
                            .foregroundColor(canvasManager.theme == .dark ? .white : .black)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .padding()
                }
                
                Spacer()
                
                // Header
                VStack(spacing: 20) {
                    Image(systemName: "square.on.square.dashed")
                        .font(.system(size: 80, weight: .ultraLight))
                        .foregroundColor(canvasManager.theme == .dark ? .white : .black)
                    
                    Text("Study Canvas")
                        .font(.system(size: 64, weight: .ultraLight, design: .default))
                        .foregroundColor(canvasManager.theme == .dark ? .white : .black)
                        .tracking(2)
                    
                    Text("Your infinite workspace")
                        .font(.system(size: 16, weight: .light))
                        .foregroundColor(canvasManager.theme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        .tracking(1)
                }
                .padding(.bottom, 60)
                
                // Create New Canvas Button
                Button(action: {
                    showNewCanvasDialog = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .light))
                        Text("New Canvas")
                            .font(.system(size: 16, weight: .light))
                            .tracking(1)
                    }
                    .foregroundColor(canvasManager.theme == .dark ? .black : .white)
                    .frame(width: 200, height: 50)
                    .background(canvasManager.theme == .dark ? Color.white : Color.black)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 40)
                
                // Recent Canvases
                if !canvasManager.canvases.isEmpty {
                    VStack(spacing: 30) {
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 1)
                            .frame(maxWidth: 600)
                        
                        VStack(spacing: 20) {
                            Text("RECENT")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                                .tracking(2)
                            
                            ScrollView {
                                VStack(spacing: 1) {
                                    ForEach(canvasManager.canvases) { canvas in
                                        CanvasRow(
                                            canvas: canvas,
                                            onOpen: {
                                                canvasManager.cleanupCurrentCanvas()
                                                canvasManager.currentCanvas = canvas
                                            },
                                            onDelete: {
                                                canvasToDelete = canvas
                                                showDeleteConfirmation = true
                                            }
                                        )
                                    }
                                }
                            }
                            .frame(maxWidth: 600, maxHeight: 300)
                        }
                    }
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showNewCanvasDialog) {
            NewCanvasDialog(
                canvasName: $newCanvasName,
                onCreate: {
                    if !newCanvasName.isEmpty {
                        canvasManager.createNewCanvas(name: newCanvasName)
                        newCanvasName = ""
                        showNewCanvasDialog = false
                    }
                },
                onCancel: {
                    newCanvasName = ""
                    showNewCanvasDialog = false
                }
            )
        }
        .alert("Delete Canvas", isPresented: $showDeleteConfirmation, presenting: canvasToDelete) { canvas in
            Button("Cancel", role: .cancel) {
                canvasToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let canvas = canvasToDelete {
                    canvasManager.deleteCanvas(canvas)
                }
                canvasToDelete = nil
            }
        } message: { canvas in
            Text("Are you sure you want to delete '\(canvas.name)'? This action cannot be undone.")
        }
    }
}

struct CanvasRow: View {
    let canvas: Canvas
    let onOpen: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false
    @EnvironmentObject var canvasManager: CanvasManager
    
    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 0) {
                // Canvas name
                Text(canvas.name)
                    .font(.system(size: 16, weight: .light))
                    .foregroundColor(canvasManager.theme == .dark ? .white : .black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Element count
                Text("\(canvas.elements.count)")
                    .font(.system(size: 14, weight: .ultraLight))
                    .foregroundColor(canvasManager.theme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                    .frame(width: 60, alignment: .trailing)
                
                // Delete button
                Button(action: {
                    onDelete()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .light))
                        .foregroundColor(canvasManager.theme == .dark ? .white.opacity(isHovering ? 0.8 : 0.3) : .black.opacity(isHovering ? 0.8 : 0.3))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 16)
            .background(isHovering ? (canvasManager.theme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

struct NewCanvasDialog: View {
    @Binding var canvasName: String
    let onCreate: () -> Void
    let onCancel: () -> Void
    @EnvironmentObject var canvasManager: CanvasManager
    
    var body: some View {
        ZStack {
            (canvasManager.theme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Text("NEW CANVAS")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(canvasManager.theme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    .tracking(2)
                
                TextField("", text: $canvasName, prompt: Text("Untitled").foregroundColor(canvasManager.theme == .dark ? .white.opacity(0.3) : .black.opacity(0.3)))
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(canvasManager.theme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 200, idealWidth: 300, maxWidth: 300)
                    .padding(.bottom, 8)
                    .overlay(
                        Rectangle()
                            .fill(canvasManager.theme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2))
                            .frame(height: 1),
                        alignment: .bottom
                    )
                    .onSubmit {
                        if !canvasName.isEmpty {
                            onCreate()
                        }
                    }
                
                HStack(spacing: 20) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(canvasManager.theme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Create") {
                        if canvasName.isEmpty {
                            canvasName = "Untitled"
                        }
                        onCreate()
                    }
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(canvasManager.theme == .dark ? .white : .black)
                    .keyboardShortcut(.defaultAction)
                }
                .buttonStyle(.plain)
            }
            .padding(60)
        }
        .frame(width: 500, height: 300)
    }
}

#Preview {
    LandingView()
        .environmentObject(CanvasManager())
}
