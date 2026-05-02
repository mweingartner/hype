# Apple Frameworks → Hype Controls Roadmap

A survey of Apple platform frameworks and the controls each could expose to Hype users. Everything in **Phase 1** is recommended to ship in the immediate window. **Phase 2** is high-value, moderate effort. **Phase 3** is interesting-but-niche.

Hype already supports: Button, Field, Shape, Image, Animated GIF, Video (AVKit), Web Page (WebKit), Chart (Swift Charts), Sprite Area (SpriteKit + SKScene + nodes/labels/emitters/joints/constraints/fields), Tile Map.

---

## Phase 1 — Ship next

### 1. Calendar / Date Picker (EventKit + AppKit) ✅ implemented in this commit
**User value**: schedule pickers, deadline displays, recurring task widgets — staple HyperCard-style "stack with a calendar on it" use case.
**Backing API**: `NSDatePicker(.graphical)` for the visual grid; `EKEventStore` (deferred to v2) for surfacing real macOS calendar events.
**Hype properties**: `selectedDate`, `displayMonth`, `minDate`, `maxDate`, `style` (`graphical` / `textualWithStepper` / `clockAndCalendar`).
**HypeTalk**:
```
put the selectedDate of calendar "due" into d
set the selectedDate of calendar "due" to "2026-12-25"
```
**AI tools**: `create_calendar`, generic `set_part_property` / `get_part_property` cover read/write.
**Effort**: ~600 lines + 8-10 tests (this commit).

### 2. PDF Viewer (PDFKit) ✅ shipped
**Backing API**: `PDFView` from PDFKit.
**Hype properties**: `pdfurl`, `currentPage`, `displayMode` (single / continuous / twoUp / twoUpContinuous), `autoScales`.
**HypeTalk**: `set the currentPage of pdf "manual" to 5`, `set the pdfurl of pdf "manual" to "/path/to/file.pdf"`.
**AI tools**: `create_pdf`; per-property reads/writes via `set_part_property` / `get_part_property`.

### 3. Map (MapKit) ✅ shipped
**Backing API**: `MKMapView`.
**Hype properties**: `centerLat`, `centerLon`, `span`, `mapType` (standard / satellite / hybrid / mutedStandard), `annotations` (JSON array of {lat, lon, title}).
**HypeTalk**: `set the centerLat of map "store" to 37.7749`. Pins via `add_map_annotation` AI tool or by writing the `annotations` property directly.
**AI tools**: `create_map`, `add_map_annotation`, `clear_map_annotations`, `set_part_property` for everything else.
**Note**: `showsUserLocation` deferred to v2 — would require `NSLocationUsageDescription` and a CoreLocation auth round-trip.

---

## Phase 2 — High value, moderate effort

### 4. Contact Picker (ContactsUI)
**User value**: address-book-aware stacks (CRM-lite, mailers, custom invitations).
**Backing API**: `CNContactPickerViewController` (sheet) or read-only `CNContactStore` queries.
**Hype properties**: `selectedContactName`, `selectedContactEmail`, `selectedContactPhone`.
**HypeTalk**: `pick contact then put it into field "name"`.
**Effort**: ~400 lines. Requires `NSContactsUsageDescription`.

### 5. SceneKit (3D scene viewer)
**User value**: 3D model display alongside the existing 2D SpriteKit. Educational stacks (anatomy, geometry, product configurators).
**Backing API**: `SCNView` + `.usdz` / `.dae` / `.scn` loading.
**Hype properties**: `sceneURL`, `cameraName`, `allowsCameraControl`, `autoenablesDefaultLighting`, `backgroundColor`, `antialiasingMode`.
**Effort**: ~800 lines. Significant — 3D camera math + lighting controls have a learning curve.

### 6. Audio Recorder (AVFoundation)
**User value**: voice-memo style recording into a stack (lecture notes, audio annotations, talking-card stacks).
**Backing API**: `AVAudioRecorder` + waveform visualization.
**Hype properties**: `recording`, `duration`, `peakLevel`, `outputFile`, `format`.
**HypeTalk**: `start recording into recorder "memo"` / `stop recording recorder "memo"`.
**Effort**: ~500 lines + Info.plist mic description (already added for AI voice).

### 7. Color Well (AppKit `NSColorWell`) ✅ shipped
**Backing API**: `NSColorWell`.
**Hype properties**: `color` (hex string), `interactive` (bool — false makes it a static swatch).
**HypeTalk**: `put the color of colorWell "fill" into c`. The `colorChanged` message fires on the part when the user picks a new color.
**AI tools**: `create_color_well`, `set_part_property` for color/interactive.

### 8. Stepper / Slider / Toggle / SegmentedControl (AppKit)
**User value**: classic form controls — currently faked as Buttons. Native controls give native interaction (keyboard nav, accessibility).
**Backing API**: `NSStepper`, `NSSlider`, `NSSwitch`, `NSSegmentedControl`.
**Hype properties** (each control): `value`, `minValue`, `maxValue`, `increment`, `segments` (for segmented), `selectedSegment`.
**Effort**: ~500 lines combined for all four (one new PartType per).

---

## Phase 3 — Interesting but niche

### 9. EventKit Real Calendar Events
Surface actual macOS calendar events inside the Calendar control. Requires `NSCalendarsUsageDescription` and async event fetches. Useful for productivity stacks but invasive to wire up. **Effort**: ~600 lines on top of the basic Calendar.

### 10. WebAuthenticationServices
For OAuth flows in stacks that talk to web services. Not generally useful in a HyperCard model — defer until a stack actually needs this.

### 11. CoreImage Filter Effects on Image Parts
Apply CIFilter (sepia, blur, vignette, etc.) to existing image parts. Could enhance the existing `image` part rather than be a new control. **Effort**: ~400 lines.

### 12. PassKit / GameKit / HomeKit / HealthKit
Skip. Not relevant to the HyperCard usage model on macOS.

### 13. CoreNFC / CoreBluetooth
NFC isn't supported on macOS. Bluetooth would be interesting for device-controlled stacks but the entitlement setup is non-trivial. Defer.

### 14. ARKit / RealityKit
Mac apps don't generally do AR. Defer until iPadOS/visionOS port.

### 15. UserNotifications
Local notifications for `remind me at <date>` type behavior in stacks. Modest value, ~200 lines. Could pair with the Calendar control.

### 16. ScreenCaptureKit
Real-time desktop screen capture for stacks that record their own surface. Privacy-sensitive — defer.

### 17. AVKit Picture-in-Picture
Adds PiP to existing video parts. Single bool property + small wiring change. Could ship trivially as an enhancement to `video` part rather than a new part type.

---

## Tracking

When a phase-1 item ships, move its row to "Already supported" at the top of this file. When a corresponding seed of HypeTalk + AI examples is added to `HypeTalkGuide.llmContext`, link them here.

Last updated: 2026-05-01.
