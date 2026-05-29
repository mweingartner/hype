import Foundation

public enum ToolName: String, CaseIterable, Sendable {
    case browse, button, field, shape, webpage, image, video, chart, spriteArea
    case calendar, pdf, map, colorWell
    case stepper, slider, segmented, audioRecorder, scene3D
    case musicPlayer, pianoKeyboard, stepSequencer, musicMixer, appleMusicBrowser, musicQueue
    case progressView, gauge, divider
    case select
    case pencil, spray, bucket, eraser
    // Removed in dedup: .toggle, .link, .menu, .searchField, .text,
    // .rect, .oval, .line — these are now created through canonical
    // Button / Field / Shape tools and then styled in the inspector.

    /// Human-readable title for the fly-out info window.
    var displayTitle: String {
        switch self {
        case .browse: return "Browse"
        case .button: return "Button"
        case .field: return "Field"
        case .shape: return "Shape"
        case .webpage: return "Web Page"
        case .image: return "Image"
        case .video: return "Video"
        case .chart: return "Chart"
        case .spriteArea: return "Sprite Area"
        case .calendar: return "Calendar"
        case .pdf: return "PDF Viewer"
        case .map: return "Map"
        case .colorWell: return "Color Well"
        case .stepper: return "Stepper"
        case .slider: return "Slider"
        case .segmented: return "Segmented Control"
        case .audioRecorder: return "Audio Recorder"
        case .scene3D: return "3D Scene"
        case .musicPlayer: return "Music Player"
        case .pianoKeyboard: return "Piano Keyboard"
        case .stepSequencer: return "Step Sequencer"
        case .musicMixer: return "Music Mixer"
        case .appleMusicBrowser: return "MusicKit Search"
        case .musicQueue: return "Music Queue (Legacy)"
        case .progressView: return "Progress View"
        case .gauge: return "Gauge"
        case .divider: return "Divider"
        case .select: return "Select"
        case .pencil: return "Pencil"
        case .spray: return "Spray"
        case .bucket: return "Bucket Fill"
        case .eraser: return "Eraser"
        }
    }

    /// Detailed description shown in the fly-out info window when
    /// the user hovers a tool button. Should describe what the tool
    /// creates (or what action it performs in browse / paint mode)
    /// in 2-3 sentences. Quoted forms reference HypeTalk reads.
    var description: String {
        switch self {
        case .browse:
            return "Default mode for navigating cards and clicking buttons. Switch to Browse when you want to interact with the stack as an end user would, without selecting parts for editing."
        case .button:
            return "Click and drag to draw a button. Buttons can navigate cards, run scripts, open links, show choices, or behave like toggles and checkboxes depending on the style you choose."
        case .field:
            return "Click and drag to draw a text field. Fields can show labels, collect user input, support scrolling text, search-style entry, password-style entry, or locked read-only text."
        case .shape:
            return "Click and drag to draw a shape. Use shapes for rectangles, rounded panels, ovals, lines, dividers, highlights, backgrounds, and simple custom artwork."
        case .webpage:
            return "Place a live web page on the card. Set the address in the inspector or by script, then browse the page directly from your stack."
        case .image:
            return "Place a picture or animated image on the card. Images can be filtered, made clickable, inverted on click, or used as visual artwork in a stack."
        case .video:
            return "Place a movie player on the card. Choose a video file or address, then let users play, pause, and scrub through the movie."
        case .chart:
            return "Place a chart on the card. Charts can show bars, lines, areas, points, pie slices, or spider/radar plots from data you provide through the inspector, script, or AI tools."
        case .spriteArea:
            return "Place an interactive 2D game or animation area on the card. Use it for sprites, motion, collisions, tile maps, effects, and game templates created by the AI tools."
        case .calendar:
            return "Place a date picker or calendar on the card. Users can choose dates, and scripts can read or set the selected date."
        case .pdf:
            return "Place a document viewer on the card for PDF files. Users can read pages inside the stack, and scripts can move to a specific page."
        case .map:
            return "Place a map on the card. Show a location, choose a map style, zoom in or out, and add pins for places you want users to notice."
        case .colorWell:
            return "Place a color picker or color swatch on the card. Users can choose a color, and scripts can read or update that color."
        case .stepper:
            return "Place a small up/down value control on the card. Use it when users should increase or decrease a number by fixed steps."
        case .slider:
            return "Place a draggable slider on the card. Use it for volume, progress, ratings, settings, or any value within a range."
        case .segmented:
            return "Place a row of choices on the card. Use it for tabs, view modes, filters, or any small set of mutually exclusive options."
        case .audioRecorder:
            return "Place a recorder on the card so users can capture and play back short audio clips. Turn on Save in Stack when the recording should travel with the stack file."
        case .scene3D:
            return "Place a 3D model viewer on the card. Users can inspect models, orbit around them, zoom in, and use stack assets as the displayed object."
        case .musicPlayer:
            return "Place a music player on the card for songs and loops stored inside the stack. Click it in Browse mode to play the assigned Hype music pattern, or control it from scripts."
        case .pianoKeyboard:
            return "Place a keyboard-style music control on the card. Click or drag across keys in Browse mode to play notes with the assigned instrument, or trigger music scripts."
        case .stepSequencer:
            return "Place a grid-style sequencer on the card. Click or drag across grid squares in Browse mode to audition individual steps, or use scripts for repeating patterns stored in the stack."
        case .musicMixer:
            return "Place a small mixer on the card. Use it to represent track volume and arrangement controls for stack-contained music."
        case .appleMusicBrowser:
            return "Place a MusicKit search control on the card. Users can search, select, play, stop, and seek Apple Music song, album, singer, and playlist references after Apple Music access is enabled and authorized."
        case .musicQueue:
            return "Legacy music queue control retained for older stacks. New stacks should use AudioKit music controls for stack-contained music and the MusicKit Search control for Apple Music lookup."
        case .progressView:
            return "Place a progress indicator on the card. Use it to show task completion, loading state, or a running process."
        case .gauge:
            return "Place a gauge on the card. Use it to show a value within a range, such as speed, score, capacity, health, or status."
        case .divider:
            return "Place a visual separator line. Use dividers to organize layouts and separate groups of controls."
        case .select:
            return "Selection / move tool. Click a part to select it; drag to move; shift-click to extend the selection. Use the inspector on the right to edit the selected part's properties."
        case .pencil:
            return "Free-form pencil drawing onto the card's paint layer. Adjust the brush size with [ and ] keys. Choose color from the status-bar color picker."
        case .spray:
            return "Spray-paint scattering of pixels onto the paint layer. Hold mouse longer for denser fill."
        case .bucket:
            return "Flood-fill the paint layer at the click point. Replaces the contiguous color region under the cursor with the active paint color."
        case .eraser:
            return "Click-drag to erase paint-layer pixels. Adjust eraser size with [ and ] keys."
        }
    }

    var systemImageName: String {
        switch self {
        case .browse: return "hand.point.up"
        case .button: return "rectangle"
        case .field: return "text.alignleft"
        case .shape: return "diamond"
        case .webpage: return "globe"
        case .image: return "photo"
        case .video: return "play.rectangle"
        case .chart: return "chart.bar"
        case .spriteArea: return "gamecontroller"
        case .calendar: return "calendar"
        case .pdf: return "doc.richtext"
        case .map: return "map"
        case .colorWell: return "paintpalette"
        case .stepper: return "plus.slash.minus"
        case .slider: return "slider.horizontal.3"
        case .segmented: return "rectangle.split.3x1"
        case .audioRecorder: return "mic.circle"
        case .scene3D: return "cube.transparent"
        case .musicPlayer: return "music.note.list"
        case .pianoKeyboard: return "pianokeys"
        case .stepSequencer: return "square.grid.4x3.fill"
        case .musicMixer: return "slider.horizontal.3"
        case .appleMusicBrowser: return "music.mic"
        case .musicQueue: return "music.note.list"
        case .progressView: return "chart.bar.xaxis"
        case .gauge: return "gauge"
        case .divider: return "minus"
        case .select: return "cursor.rays"
        case .pencil: return "pencil"
        case .spray: return "aqi.medium"
        case .bucket: return "drop"
        case .eraser: return "eraser"
        }
    }
}
