import SwiftUI
import HypeCore

struct PropertyInspector: View {
    @Binding var document: HypeDocumentWrapper
    let partId: UUID?

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
