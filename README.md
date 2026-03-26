<p align="center">
  <img src="https://img.icons8.com/sf-regular/96/ffffff/layers.png" width="80" alt="Study Canvas Icon"/>
</p>

<h1 align="center">Study Canvas</h1>

<p align="center">
  <em>Your infinite workspace for macOS — organize notes, web pages, PDFs, and drawings on a single boundless canvas.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2012%2B-111111?style=flat&logo=apple&logoColor=white" alt="macOS 12+"/>
  <img src="https://img.shields.io/badge/Swift-5.7+-F05138?style=flat&logo=swift&logoColor=white" alt="Swift 5.7+"/>
  <img src="https://img.shields.io/badge/SwiftUI-Native-007AFF?style=flat&logo=swift&logoColor=white" alt="SwiftUI"/>
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat" alt="MIT License"/>
</p>

---

## ✨ Features

### 🖼️ Infinite Canvas
- Dynamically expanding workspace that grows with your content
- Smooth scrolling with momentum and elastic bounce
- **Zoom** from 10% to 300% — via trackpad pinch, `⌘+` / `⌘-`, or `⌘ + scroll wheel`
- Zoom anchors to cursor position for pixel-perfect navigation

### 📝 Rich Element Types
| Element | Description |
|---------|-------------|
| **Text** | Editable rich-text blocks with configurable font size (12–32pt) and color palette |
| **Web View** | Fully interactive embedded browser (WKWebView) — browse any URL directly on canvas |
| **PDF** | Import and view PDF documents with per-page navigation |
| **Drawing** | Freehand drawing canvas |
| **Section / Frame** | Group related elements inside collapsible, color-coded sections |

### 🔗 Element Connections
- Draw **connections** between any two elements
- Four styles: **Line**, **Arrow**, **Dashed**, **Curved**
- Customizable colors — hover to reveal inline delete button
- Context menu for quick connection management

### 🗂️ Sections & Frames
- **Draw-to-create** sections: enter section drawing mode, drag a rectangle on the canvas, name it, and pick a color
- Sections auto-detect contained elements (≥50% overlap)
- Drag a section to **move all child elements** together
- Collapsible — hide section contents with one click
- 10 built-in color presets (Charcoal → Cloud)

### 🔍 Search (`⌘F`)
- Spotlight-style search overlay with fuzzy matching across all element types
- Searches text content, web URLs/domain names, PDF filenames, and section titles
- Keyboard navigation: `↑` `↓` to browse, `⏎` to jump, `ESC` to close
- Results sorted by relevance with type badges and match context

### 🗺️ Mini Map
- Collapsible bird's-eye overview in the bottom-right corner
- Color-coded element dots and section outlines
- **Click or drag** on the mini map to instantly navigate
- Viewport indicator shows current visible area
- Toggle with `⌘M`

### 📐 Organization Tools
- **Grid overlay** with configurable grid size
- **Snap to grid** for precise element placement
- **Alignment guides** — pink guide lines appear automatically when dragging elements near edges/centers of others
- **Magnetic snap** during placement — new elements snap to edges of nearby elements
- **Quick arrange** selected elements:
  - Grid layout (configurable columns)
  - Vertical / Horizontal stack
  - Even distribution
  - Tidy up (snap all to grid)
- **Multi-select** with `Shift` or `⌘` + click

### 🎨 Theming
- **Light** and **Dark** mode with one-click toggle
- Theme persists across sessions

### 💾 Persistence
- Auto-save on every change
- Data stored as JSON in `~/Documents/StudyCanvas_Data.json`
- Full state preservation — element positions, sizes, z-order, web view state, and connections
- Graceful migration from legacy UserDefaults storage

### 📋 Canvas Management
- Create, rename, and delete canvases from a minimal landing page
- Quick-switch between canvases via the header dropdown
- Element count shown per canvas

---

## 🚀 Getting Started

### Requirements

| Requirement | Version |
|------------|---------|
| macOS | 12.0 (Monterey) or later |
| Xcode | 14.0 or later |
| Swift | 5.7 or later |

### Build & Run

```bash
# Clone the repository
git clone https://github.com/your-username/Study-Canvas-Mac.git
cd Study-Canvas-Mac

# Open in Xcode
open StudyCanvas/StudyCanvas.xcodeproj

# Select the StudyCanvas target, then press ⌘R to build and run
```

> **Note:** The app requires network access (for embedded web views) and file system read/write access (for PDF import). These entitlements are pre-configured.

---

## 🏗️ Architecture

```
StudyCanvas/
├── StudyCanvasApp.swift              # App entry point, window configuration
├── Models/
│   └── CanvasManager.swift           # Core state manager (ObservableObject)
│       ├── Canvas                    #   Canvas model with elements & connections
│       ├── CanvasElement             #   Element model (text/web/pdf/drawing/frame)
│       ├── Connection                #   Connection between elements
│       └── AlignmentGuide / FrameColors  #   Layout helpers & presets
├── Views/
│   ├── MainView.swift                # Root view: landing page ↔ canvas router
│   ├── LandingView.swift             # Home screen with canvas list
│   ├── ContentView.swift             # Infinite scrollable canvas + zoom engine
│   ├── CanvasElementView.swift       # Individual element rendering & interaction
│   ├── FrameElementView.swift        # Section/frame rendering
│   ├── ConnectionsView.swift         # Connection lines & arrows
│   ├── MiniMapView.swift             # Mini map navigation overlay
│   ├── SearchOverlayView.swift       # ⌘F search interface
│   ├── OrganizationViews.swift       # Grid, alignment guides, section drawing
│   ├── DrawingCanvas.swift           # Freehand drawing (NSView)
│   └── SettingsView.swift            # App settings
└── Assets.xcassets/                  # App icon & accent color
```

### Key Design Decisions

- **`CanvasManager`** is a single `ObservableObject` acting as the source of truth for all canvas state, with `@Published` properties for reactive SwiftUI updates.
- **Zoom is handled in SwiftUI** via `scaleEffect` rather than `NSScrollView` magnification — this avoids conflicts with embedded AppKit views (WKWebView, PDFView).
- **`ZoomStableClipView`** locks scroll position during zoom to prevent jitter from NSScrollView's automatic bounds adjustment.
- **JSON file storage** (instead of Core Data) keeps the data format simple, portable, and human-readable.

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘ +` | Zoom in |
| `⌘ -` | Zoom out |
| `⌘ 0` | Reset zoom to 100% |
| `⌘ F` | Toggle search overlay |
| `⌘ M` | Toggle mini map |
| `⌘ ⌫` | Delete selected element |
| `⌘ + scroll` | Zoom at cursor |
| `Shift + click` | Multi-select elements |
| `⌘ + click` | Toggle element selection |
| `ESC` | Deselect / cancel mode / close overlay |

---

## 🛣️ Roadmap

- [ ] Advanced drawing tools (colors, brush sizes, eraser, layers)
- [ ] Rich text formatting (bold, italic, markdown)
- [ ] Collaboration and real-time sharing
- [ ] Export to PDF / image
- [ ] Browser extension for web clipping
- [ ] Undo / redo system
- [ ] Tags and canvas organization
- [ ] iCloud sync

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.