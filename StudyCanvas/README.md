# Study Canvas - macOS App

A powerful note-taking and collaboration app for macOS that combines drawing, text, web content, and PDF support on a single infinite canvas.

## Features

- **White Canvas**: Infinite white canvas as your workspace
- **Drawing Tools**: Freehand drawing and scribbling
- **Text Support**: Add and edit text directly on the canvas
- **Web Integration**: Embed webpages and browser content
- **PDF Support**: Import and resize PDF documents
- **Project Management**: Create and manage multiple canvases for different subjects
- **Save & Load**: Persistent storage of all canvases and content
- **Resizable Elements**: Drag and resize all elements to fit your needs

## Project Structure

```
StudyCanvas/
├── StudyCanvasApp.swift          # Main app entry point
├── Models/
│   └── CanvasManager.swift       # Canvas and element management
├── Views/
│   ├── ContentView.swift         # Main canvas view with toolbar
│   ├── DrawingCanvas.swift       # Drawing functionality
│   ├── CanvasElementView.swift   # Element rendering and interaction
│   └── SettingsView.swift        # Settings and canvas management
└── package.json                  # Project metadata
```

## Getting Started

### Requirements
- macOS 12.0 or later
- Xcode 14.0 or later
- Swift 5.7 or later

### Building the App

1. Open the project in Xcode:
   ```bash
   open StudyCanvas -a Xcode
   ```

2. Select the target and press `Cmd + R` to build and run

### Architecture

- **CanvasManager**: Manages canvas creation, deletion, and persistence using UserDefaults
- **Drawing**: Native NSView implementation for smooth drawing
- **Web Support**: WKWebView for embedding web content
- **Element System**: Unified system for all canvas elements (drawing, text, web, PDF)

## Core Components

### Canvas
- Each canvas contains multiple elements
- Persistent storage with auto-save
- Unique identifiers for tracking

### Elements
Supported element types:
- **Drawing**: Freehand paths and sketches
- **Text**: Editable text blocks
- **WebView**: Embedded web content
- **PDF**: Imported PDF documents

Each element supports:
- Positioning and resizing
- Z-index layering
- Rotation
- Custom content storage

## Usage

1. **Create a Canvas**: Use the "+" button in the canvas selector
2. **Switch Canvases**: Click the canvas dropdown to switch between projects
3. **Add Content**:
   - Click the **pencil icon** for drawing (coming soon)
   - Click the **text icon** to add a text box
   - Click the **globe icon** to add a webpage (enter URL in dialog)
   - Click the **PDF icon** to import a PDF document
4. **Manage Elements**: 
   - **Move**: Drag the blue title bar
   - **Resize**: Drag the blue circle in bottom-right corner
   - **Delete**: Click the X button on the title bar
5. **Infinite Canvas**: Scroll horizontally and vertically for unlimited space
6. **Save**: Auto-saves all changes

## Future Enhancements

- [ ] Advanced drawing tools (colors, brush sizes, layers)
- [ ] Text formatting (fonts, sizes, colors)
- [ ] Collaboration and sharing
- [ ] Export functionality (PDF, images)
- [ ] Browser extension for web capture
- [ ] Undo/redo system
- [ ] Search within canvases
- [ ] Tags and organization

## License

MIT License
