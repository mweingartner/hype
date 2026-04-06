import SwiftUI
import HypeCore

struct PropertyInspector: View {
    @Binding var document: HypeDocumentWrapper
    let partId: UUID?
    @Binding var selectedPartId: UUID?
    @State private var showingScript = false

    var body: some View {
        Group {
            if let partId = partId,
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

                        // Delete part
                        Button(role: .destructive, action: {
                            let idToDelete = part.id
                            selectedPartId = nil
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
                ForEach(HypeCore.ButtonStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            propertyRow("Label", binding: bindPartString(part.id, \.textContent))
            Toggle("Show Name", isOn: bindPartBool(part.id, \.showName))
            Toggle("Auto Hilite", isOn: bindPartBool(part.id, \.autoHilite))
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
    private func textFormattingSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Text Formatting").font(.subheadline).foregroundColor(.secondary)
            propertyRow("Font", binding: bindPartString(part.id, \.textFont))
            numberField("Size", binding: bindPartDouble(part.id, \.textSize))
            Picker("Align", selection: bindPartTextAlign(part.id)) {
                Image(systemName: "text.alignleft").tag(HypeCore.TextAlignment.left)
                Image(systemName: "text.aligncenter").tag(HypeCore.TextAlignment.center)
                Image(systemName: "text.alignright").tag(HypeCore.TextAlignment.right)
            }
            .pickerStyle(.segmented)
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
            ScriptEditor(document: $document, partId: partId)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
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
