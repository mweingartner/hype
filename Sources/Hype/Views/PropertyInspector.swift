import SwiftUI
import HypeCore
import UniformTypeIdentifiers

/// System font families, loaded once for the font picker.
private let systemFontFamilies: [String] = NSFontManager.shared.availableFontFamilies.sorted()

struct PropertyInspector: View {
    @Binding var document: HypeDocumentWrapper
    @Binding var selectedPartIds: Set<UUID>
    @State private var showingScript = false

    var body: some View {
        Group {
            if selectedPartIds.count > 1 {
                multiSelectionView
            } else if let partId = selectedPartIds.first,
               let part = document.document.parts.first(where: { $0.id == partId }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Properties")
                            .font(.headline)
                            .padding(.bottom, 4)

                        commonSection(part: part)

                        Divider()

                        switch part.partType {
                        case .button: buttonSection(part: part)
                        case .field: fieldSection(part: part)
                        case .shape: shapeSection(part: part)
                        case .webpage: webpageSection(part: part)
                        case .image: imageSection(part: part)
                        case .video: videoSection(part: part)
                        case .chart: chartSection(part: part)
                        }

                        // Font controls for buttons and fields
                        if part.partType == .button || part.partType == .field {
                            Divider()
                            textFormattingSection(part: part)
                        }

                        Divider()

                        // Script section
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SCRIPT")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)

                            Button(action: { showingScript = true }) {
                                HStack {
                                    Image(systemName: "applescript")
                                    Text(part.script.isEmpty ? "Add Script..." : "Edit Script...")
                                }
                            }

                            if !part.script.isEmpty {
                                Text(String(part.script.prefix(100)) + (part.script.count > 100 ? "..." : ""))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        .sheet(isPresented: $showingScript) {
                            ScriptEditorSheet(document: $document, partId: partId)
                                .frame(width: 500, height: 400)
                        }

                        Divider()

                        // Constraints section
                        constraintsSection(partId: part.id)

                        Divider()

                        // Delete part
                        Button(role: .destructive, action: {
                            let idToDelete = part.id
                            selectedPartIds = []
                            document.document.removeConstraintsForPart(idToDelete)
                            document.document.removePart(id: idToDelete)
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Part")
                            }
                            .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                }
            } else {
                VStack {
                    Spacer()
                    Text("Select a part to\nedit its properties")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
            }
        }
        .frame(width: 260)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Multi-selection view

    private var multiSelectionView: some View {
        let selectedParts = document.document.parts.filter { selectedPartIds.contains($0.id) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(selectedParts.count) Parts Selected")
                    .font(.headline)
                    .padding(.bottom, 4)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("ALIGNMENT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        alignButton("Align Left", icon: "align.horizontal.left", notificationName: .alignLeft)
                        alignButton("Align Center", icon: "align.horizontal.center", notificationName: .alignHCenter)
                        alignButton("Align Right", icon: "align.horizontal.right", notificationName: .alignRight)
                    }
                    HStack(spacing: 4) {
                        alignButton("Align Top", icon: "align.vertical.top", notificationName: .alignTop)
                        alignButton("Align Middle", icon: "align.vertical.center", notificationName: .alignVCenter)
                        alignButton("Align Bottom", icon: "align.vertical.bottom", notificationName: .alignBottom)
                    }
                    HStack(spacing: 4) {
                        alignButton("Distribute H", icon: "distribute.horizontal.center", notificationName: .distributeH)
                        alignButton("Distribute V", icon: "distribute.vertical.center", notificationName: .distributeV)
                    }
                }

                Divider()

                // Common properties that can be bulk-edited
                VStack(alignment: .leading, spacing: 6) {
                    Text("COMMON PROPERTIES")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    Toggle("Visible", isOn: Binding(
                        get: { selectedParts.allSatisfy(\.visible) },
                        set: { newVal in for id in selectedPartIds { document.document.updatePart(id: id) { $0.visible = newVal } } }
                    ))
                    Toggle("Enabled", isOn: Binding(
                        get: { selectedParts.allSatisfy(\.enabled) },
                        set: { newVal in for id in selectedPartIds { document.document.updatePart(id: id) { $0.enabled = newVal } } }
                    ))
                }

                // Font properties if all selected parts are buttons or fields
                let hasText = selectedParts.allSatisfy { $0.partType == .button || $0.partType == .field }
                if hasText {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TEXT FORMATTING")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        HStack {
                            Text("Font").font(.system(size: 11))
                            TextField("", text: Binding(
                                get: { selectedParts.first?.textFont ?? "" },
                                set: { newVal in for id in selectedPartIds { document.document.updatePart(id: id) { $0.textFont = newVal } } }
                            )).textFieldStyle(.roundedBorder).font(.system(size: 11))
                        }
                        HStack {
                            Text("Size").font(.system(size: 11))
                            TextField("", value: Binding(
                                get: { selectedParts.first?.textSize ?? 14 },
                                set: { newVal in for id in selectedPartIds { document.document.updatePart(id: id) { $0.textSize = newVal } } }
                            ), format: .number).textFieldStyle(.roundedBorder).font(.system(size: 11)).frame(width: 60)
                        }
                    }
                }

                Divider()

                // Delete all selected
                Button(role: .destructive, action: {
                    let ids = selectedPartIds
                    selectedPartIds = []
                    for id in ids {
                        document.document.removePart(id: id)
                    }
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete \(selectedParts.count) Parts")
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
    }

    private func alignButton(_ tooltip: String, icon: String, notificationName: Notification.Name) -> some View {
        Button(action: {
            NotificationCenter.default.post(name: notificationName, object: nil)
        }) {
            Image(systemName: icon)
                .frame(width: 28, height: 28)
        }
        .help(tooltip)
    }

    // MARK: - Sections

    @ViewBuilder
    private func commonSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Identity").font(.subheadline).foregroundColor(.secondary)
            propertyRow("Name", binding: bindPartString(part.id, \.name))
            propertyRow("Type", value: part.partType.rawValue.capitalized)
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Position").font(.subheadline).foregroundColor(.secondary)
            HStack {
                numberField("X", binding: bindPartDouble(part.id, \.left))
                numberField("Y", binding: bindPartDouble(part.id, \.top))
            }
            HStack {
                numberField("W", binding: bindPartDouble(part.id, \.width))
                numberField("H", binding: bindPartDouble(part.id, \.height))
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("State").font(.subheadline).foregroundColor(.secondary)
            Toggle("Visible", isOn: bindPartBool(part.id, \.visible))
            Toggle("Enabled", isOn: bindPartBool(part.id, \.enabled))
        }
    }

    @ViewBuilder
    private func buttonSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Button").font(.subheadline).foregroundColor(.secondary)
            Picker("Style", selection: bindPartButtonStyle(part.id)) {
                ForEach(HypeCore.ButtonStyle.pickerCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            propertyRow("Label", binding: bindPartString(part.id, \.textContent))
            Toggle("Show Name", isOn: bindPartBool(part.id, \.showName))
            Toggle("Auto Hilite", isOn: bindPartBool(part.id, \.autoHilite))

            // Popup items editor (only shown for popup style)
            if part.buttonStyle == .popup {
                Divider()
                Text("POPUP ITEMS").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                Text("One item per line. First item is the default selection.")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                TextEditor(text: bindPartString(part.id, \.popupItems))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 80)
                    .border(Color.gray.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private func fieldSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Field").font(.subheadline).foregroundColor(.secondary)
            Picker("Style", selection: bindPartFieldStyle(part.id)) {
                ForEach(HypeCore.FieldStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            Toggle("Lock Text", isOn: bindPartBool(part.id, \.lockText))
            Toggle("Don't Wrap", isOn: bindPartBool(part.id, \.dontWrap))
            Toggle("Rich Text", isOn: bindPartBool(part.id, \.richText))
            Toggle("Wide Margins", isOn: bindPartBool(part.id, \.wideMargins))

            Divider()
            Text("Events").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
            Toggle("Enter Key Event", isOn: Binding(
                get: { document.document.parts.first(where: { $0.id == part.id })?.enterKeyEnabled ?? false },
                set: { newValue in
                    document.document.updatePart(id: part.id) { p in
                        p.enterKeyEnabled = newValue
                        // Auto-add template script if enabling and no enterKey handler exists
                        if newValue && !p.script.lowercased().contains("on enterkey") {
                            let template = "on enterKey\n  -- Runs when Enter is pressed in this field\n  \nend enterKey"
                            if p.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                p.script = template
                            } else {
                                p.script += "\n\n" + template
                            }
                        }
                    }
                }
            ))
            if part.enterKeyEnabled {
                Text("Press Enter in browse mode to trigger the enterKey handler")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading) {
                Text("Content").font(.system(size: 11)).foregroundColor(.secondary)
                TextEditor(text: bindPartString(part.id, \.textContent))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 80)
                    .border(Color.gray.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private func shapeSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shape").font(.subheadline).foregroundColor(.secondary)
            Picker("Shape", selection: bindPartShapeType(part.id)) {
                ForEach(HypeCore.ShapeType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            ColorPicker("Fill", selection: bindPartColor(part.id, \.fillColor))
            ColorPicker("Stroke", selection: bindPartColor(part.id, \.strokeColor))
            numberField("Stroke Width", binding: bindPartDouble(part.id, \.strokeWidth))
            numberField("Corner Radius", binding: bindPartDouble(part.id, \.cornerRadius))
        }
    }

    @ViewBuilder
    private func webpageSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Web Page").font(.subheadline).foregroundColor(.secondary)
            propertyRow("URL", binding: bindPartString(part.id, \.url))
        }
    }

    @ViewBuilder
    private func imageSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Image").font(.subheadline).foregroundColor(.secondary)

            Button("Choose Image...") {
                chooseImageForPart(partId: part.id)
            }

            Toggle("Invert on Click", isOn: bindPartBool(part.id, \.invertOnClick))

            if let data = part.imageData {
                Text("Image loaded (\(data.count / 1024) KB)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func videoSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Video").font(.subheadline).foregroundColor(.secondary)
            propertyRow("URL/Path", binding: bindPartString(part.id, \.videoURL))
            Button("Choose Video...") {
                chooseVideoForPart(partId: part.id)
            }
            if !part.videoURL.isEmpty {
                Text(part.videoURL)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func chooseVideoForPart(partId: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .movie, .quickTimeMovie]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            document.document.updatePart(id: partId) { $0.videoURL = url.absoluteString }
        }
    }

    private func chooseImageForPart(partId: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? Data(contentsOf: url) {
                document.document.updatePart(id: partId) { $0.imageData = data }
            }
        }
    }

    @ViewBuilder
    private func textFormattingSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Text Formatting").font(.subheadline).foregroundColor(.secondary)
            HStack {
                Text("Font").frame(width: 40, alignment: .trailing).font(.system(size: 11))
                Picker("", selection: bindPartString(part.id, \.textFont)) {
                    ForEach(systemFontFamilies, id: \.self) { fontName in
                        Text(fontName).font(.system(size: 11)).tag(fontName)
                    }
                }
                .labelsHidden()
                .font(.system(size: 11))
            }
            numberField("Size", binding: bindPartDouble(part.id, \.textSize))
            Picker("Align", selection: bindPartTextAlign(part.id)) {
                Image(systemName: "text.alignleft").tag(HypeCore.TextAlignment.left)
                Image(systemName: "text.aligncenter").tag(HypeCore.TextAlignment.center)
                Image(systemName: "text.alignright").tag(HypeCore.TextAlignment.right)
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private func chartSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Chart").font(.subheadline).foregroundColor(.secondary)

            let config = ChartConfig.fromJSON(part.chartData) ?? ChartConfig()

            Picker("Type", selection: bindChartType(part.id)) {
                ForEach(ChartType.allCases, id: \.self) { type in
                    Text(type.rawValue.capitalized).tag(type)
                }
            }

            propertyRow("Title", binding: bindChartField(part.id, \.title))
            Toggle("Show Legend", isOn: bindChartBool(part.id, \.showLegend))
            Toggle("Show Grid", isOn: bindChartBool(part.id, \.showGrid))

            propertyRow("X Label", binding: bindChartField(part.id, \.xAxisLabel))
            propertyRow("Y Label", binding: bindChartField(part.id, \.yAxisLabel))

            Divider()

            // Series management
            ForEach(Array(config.series.enumerated()), id: \.element.id) { index, series in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Series \(index + 1)").font(.system(size: 10, weight: .bold))
                        Spacer()
                        ColorPicker("", selection: bindSeriesColor(part.id, seriesIndex: index))
                            .labelsHidden().frame(width: 20)
                        Button(action: { removeSeries(partId: part.id, index: index) }) {
                            Image(systemName: "minus.circle").foregroundColor(.red)
                        }.buttonStyle(.borderless)
                    }
                    TextField("Name", text: bindSeriesName(part.id, seriesIndex: index))
                        .textFieldStyle(.roundedBorder).font(.system(size: 11))

                    // Data points
                    ForEach(Array(series.data.enumerated()), id: \.element.id) { di, _ in
                        HStack(spacing: 4) {
                            TextField("Label", text: bindDataLabel(part.id, seriesIndex: index, dataIndex: di))
                                .textFieldStyle(.roundedBorder).font(.system(size: 10))
                            TextField("Value", value: bindDataValue(part.id, seriesIndex: index, dataIndex: di), format: .number)
                                .textFieldStyle(.roundedBorder).font(.system(size: 10)).frame(width: 60)
                            Button(action: { removeDataPoint(partId: part.id, seriesIndex: index, dataIndex: di) }) {
                                Image(systemName: "xmark").font(.system(size: 8))
                            }.buttonStyle(.borderless)
                        }
                    }
                    Button("+ Add Data Point") { addDataPoint(partId: part.id, seriesIndex: index) }
                        .font(.system(size: 10))
                }
                .padding(4)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(4)
            }

            Button("+ Add Series") { addSeries(partId: part.id) }
                .font(.system(size: 10))
        }
    }

    // MARK: - Chart Binding Helpers

    private func modifyChartConfig(partId: UUID, transform: (inout ChartConfig) -> Void) {
        let existing = document.document.parts.first(where: { $0.id == partId })?.chartData ?? ""
        var config = ChartConfig.fromJSON(existing) ?? ChartConfig()
        transform(&config)
        document.document.updatePart(id: partId) { $0.chartData = config.toJSON() }
    }

    private func bindChartType(_ id: UUID) -> Binding<ChartType> {
        Binding(
            get: { ChartConfig.fromJSON(document.document.parts.first(where: { $0.id == id })?.chartData ?? "")?.chartType ?? .bar },
            set: { newVal in modifyChartConfig(partId: id) { $0.chartType = newVal } }
        )
    }

    private func bindChartField(_ id: UUID, _ keyPath: WritableKeyPath<ChartConfig, String>) -> Binding<String> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                return ChartConfig.fromJSON(json)?[keyPath: keyPath] ?? ""
            },
            set: { newVal in modifyChartConfig(partId: id) { $0[keyPath: keyPath] = newVal } }
        )
    }

    private func bindChartBool(_ id: UUID, _ keyPath: WritableKeyPath<ChartConfig, Bool>) -> Binding<Bool> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                return ChartConfig.fromJSON(json)?[keyPath: keyPath] ?? true
            },
            set: { newVal in modifyChartConfig(partId: id) { $0[keyPath: keyPath] = newVal } }
        )
    }

    private func bindSeriesName(_ id: UUID, seriesIndex: Int) -> Binding<String> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                let config = ChartConfig.fromJSON(json) ?? ChartConfig()
                guard seriesIndex < config.series.count else { return "" }
                return config.series[seriesIndex].name
            },
            set: { newVal in
                modifyChartConfig(partId: id) { config in
                    guard seriesIndex < config.series.count else { return }
                    config.series[seriesIndex].name = newVal
                }
            }
        )
    }

    private func bindSeriesColor(_ id: UUID, seriesIndex: Int) -> Binding<Color> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                let config = ChartConfig.fromJSON(json) ?? ChartConfig()
                guard seriesIndex < config.series.count else { return .blue }
                return Color(hex: config.series[seriesIndex].color)
            },
            set: { newVal in
                modifyChartConfig(partId: id) { config in
                    guard seriesIndex < config.series.count else { return }
                    config.series[seriesIndex].color = newVal.toHex()
                }
            }
        )
    }

    private func bindDataLabel(_ id: UUID, seriesIndex: Int, dataIndex: Int) -> Binding<String> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                let config = ChartConfig.fromJSON(json) ?? ChartConfig()
                guard seriesIndex < config.series.count, dataIndex < config.series[seriesIndex].data.count else { return "" }
                return config.series[seriesIndex].data[dataIndex].label
            },
            set: { newVal in
                modifyChartConfig(partId: id) { config in
                    guard seriesIndex < config.series.count, dataIndex < config.series[seriesIndex].data.count else { return }
                    config.series[seriesIndex].data[dataIndex].label = newVal
                }
            }
        )
    }

    private func bindDataValue(_ id: UUID, seriesIndex: Int, dataIndex: Int) -> Binding<Double> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                let config = ChartConfig.fromJSON(json) ?? ChartConfig()
                guard seriesIndex < config.series.count, dataIndex < config.series[seriesIndex].data.count else { return 0 }
                return config.series[seriesIndex].data[dataIndex].value
            },
            set: { newVal in
                modifyChartConfig(partId: id) { config in
                    guard seriesIndex < config.series.count, dataIndex < config.series[seriesIndex].data.count else { return }
                    config.series[seriesIndex].data[dataIndex].value = newVal
                }
            }
        )
    }

    private func addSeries(partId: UUID) {
        modifyChartConfig(partId: partId) { config in
            let colors = ["#4A90D9", "#E74C3C", "#2ECC71", "#F39C12", "#9B59B6", "#1ABC9C"]
            let colorIndex = config.series.count % colors.count
            config.series.append(ChartSeries(name: "Series \(config.series.count + 1)", color: colors[colorIndex]))
        }
    }

    private func removeSeries(partId: UUID, index: Int) {
        modifyChartConfig(partId: partId) { config in
            guard index < config.series.count else { return }
            config.series.remove(at: index)
        }
    }

    private func addDataPoint(partId: UUID, seriesIndex: Int) {
        modifyChartConfig(partId: partId) { config in
            guard seriesIndex < config.series.count else { return }
            let count = config.series[seriesIndex].data.count
            config.series[seriesIndex].data.append(ChartDataPoint(label: "Item \(count + 1)", value: 0))
        }
    }

    private func removeDataPoint(partId: UUID, seriesIndex: Int, dataIndex: Int) {
        modifyChartConfig(partId: partId) { config in
            guard seriesIndex < config.series.count, dataIndex < config.series[seriesIndex].data.count else { return }
            config.series[seriesIndex].data.remove(at: dataIndex)
        }
    }

    // MARK: - Constraints section

    @ViewBuilder
    private func constraintsSection(partId: UUID) -> some View {
        let partConstraints = document.document.constraintsForPart(partId)
        VStack(alignment: .leading, spacing: 4) {
            Text("CONSTRAINTS").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
            if partConstraints.isEmpty {
                Text("Option+drag from this part to another part or canvas edge to create a constraint")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
            ForEach(partConstraints) { constraint in
                HStack {
                    Text("\(constraint.sourceEdge.rawValue) -> \(constraint.targetType == .canvas ? "canvas " : "")\(constraint.targetEdge.rawValue)")
                        .font(.system(size: 10))
                    Spacer()
                    TextField("", value: Binding(
                        get: { abs(constraint.distance) },
                        set: { newVal in
                            if let idx = document.document.constraints.firstIndex(where: { $0.id == constraint.id }) {
                                // Preserve the sign (direction), update magnitude
                                let sign: Double = document.document.constraints[idx].distance >= 0 ? 1 : -1
                                document.document.constraints[idx].distance = sign * abs(newVal)
                            }
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                    .font(.system(size: 10))
                    Text("px").font(.system(size: 10)).foregroundColor(.secondary)
                    Button(action: { document.document.removeConstraint(id: constraint.id) }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: - Binding helpers

    private func bindPartString(_ id: UUID, _ keyPath: WritableKeyPath<Part, String>) -> Binding<String> {
        Binding(
            get: { document.document.parts.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" },
            set: { newValue in document.document.updatePart(id: id) { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func bindPartDouble(_ id: UUID, _ keyPath: WritableKeyPath<Part, Double>) -> Binding<Double> {
        Binding(
            get: { document.document.parts.first(where: { $0.id == id })?[keyPath: keyPath] ?? 0 },
            set: { newValue in document.document.updatePart(id: id) { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func bindPartBool(_ id: UUID, _ keyPath: WritableKeyPath<Part, Bool>) -> Binding<Bool> {
        Binding(
            get: { document.document.parts.first(where: { $0.id == id })?[keyPath: keyPath] ?? false },
            set: { newValue in document.document.updatePart(id: id) { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func bindPartButtonStyle(_ id: UUID) -> Binding<HypeCore.ButtonStyle> {
        Binding(
            get: { document.document.parts.first(where: { $0.id == id })?.buttonStyle ?? .roundRect },
            set: { newValue in document.document.updatePart(id: id) { $0.buttonStyle = newValue } }
        )
    }

    private func bindPartFieldStyle(_ id: UUID) -> Binding<HypeCore.FieldStyle> {
        Binding(
            get: { document.document.parts.first(where: { $0.id == id })?.fieldStyle ?? .rectangle },
            set: { newValue in document.document.updatePart(id: id) { $0.fieldStyle = newValue } }
        )
    }

    private func bindPartShapeType(_ id: UUID) -> Binding<HypeCore.ShapeType> {
        Binding(
            get: { document.document.parts.first(where: { $0.id == id })?.shapeType ?? .rectangle },
            set: { newValue in document.document.updatePart(id: id) { $0.shapeType = newValue } }
        )
    }

    private func bindPartTextAlign(_ id: UUID) -> Binding<HypeCore.TextAlignment> {
        Binding(
            get: { document.document.parts.first(where: { $0.id == id })?.textAlign ?? .center },
            set: { newValue in document.document.updatePart(id: id) { $0.textAlign = newValue } }
        )
    }

    private func bindPartColor(_ id: UUID, _ keyPath: WritableKeyPath<Part, String>) -> Binding<Color> {
        Binding(
            get: {
                let hex = document.document.parts.first(where: { $0.id == id })?[keyPath: keyPath] ?? "#FFFFFF"
                return Color(hex: hex)
            },
            set: { newValue in
                document.document.updatePart(id: id) { $0[keyPath: keyPath] = newValue.toHex() }
            }
        )
    }

    // MARK: - Helper views

    private func propertyRow(_ label: String, binding: Binding<String>) -> some View {
        HStack {
            Text(label).frame(width: 60, alignment: .trailing).font(.system(size: 11))
            TextField("", text: binding).textFieldStyle(.roundedBorder).font(.system(size: 11))
        }
    }

    private func propertyRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).frame(width: 60, alignment: .trailing).font(.system(size: 11)).foregroundColor(.secondary)
            Text(value).font(.system(size: 11))
        }
    }

    private func numberField(_ label: String, binding: Binding<Double>) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundColor(.secondary)
            TextField("", value: binding, format: .number)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .frame(width: 60)
        }
    }
}

// MARK: - Script Editor Sheet

struct ScriptEditorSheet: View {
    @Binding var document: HypeDocumentWrapper
    let partId: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScriptEditor(document: $document, partId: partId, onDone: {
                dismiss()
            })
            HStack {
                Spacer()
                Button("Done") {
                    // Trigger the onDone callback which applies script and dismisses
                    dismiss()
                }
                .keyboardShortcut(.return)
            }
            .padding(8)
        }
    }
}

// MARK: - Color hex conversion

extension Color {
    init(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let rgb = UInt64(hex, radix: 16) else {
            self = .white; return
        }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }

    func toHex() -> String {
        guard let components = NSColor(self).cgColor.components, components.count >= 3 else {
            return "#FFFFFF"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
