import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var canvasManager: CanvasManager
    @State private var newCanvasName = ""
    
    var body: some View {
        TabView {
            // Canvases Tab
            VStack {
                List {
                    ForEach(canvasManager.canvases) { canvas in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(canvas.name)
                                    .font(.headline)
                                Text(canvas.createdDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                canvasManager.deleteCanvas(canvas)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
                
                HStack {
                    TextField("New Canvas Name", text: $newCanvasName)
                        .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                    Button("Add") {
                        if !newCanvasName.isEmpty {
                            canvasManager.createNewCanvas(name: newCanvasName)
                            newCanvasName = ""
                        }
                    }
                }
                .padding()
            }
            .tabItem {
                Label("Canvases", systemImage: "square.grid.2x2")
            }
            
            // About Tab
            VStack {
                Text("Study Canvas")
                    .font(.title)
                Text("Version 1.0")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text("A powerful note-taking and canvas app for macOS with drawing, web, and PDF support.")
                    .padding()
            }
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .frame(width: 500, height: 400)
    }
}

#Preview {
    SettingsView()
        .environmentObject(CanvasManager())
}
