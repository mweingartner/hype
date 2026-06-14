import SwiftUI
import Foundation

@MainActor
struct ChatMarkdownRenderer: View {
    let content: String
    var fontSize: CGFloat = 13
    var foregroundColor: Color = .primary

    private var document: ChatMarkdownDocument {
        ChatMarkdownDocument.cached(content)
    }

    var body: some View {
        if document.containsMarkdown {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let text):
                        ChatMarkdownText(text: text, fontSize: fontSize, foregroundColor: foregroundColor)
                    case .table(let table):
                        ChatMarkdownTableView(table: table, fontSize: max(fontSize - 1, 10))
                    }
                }
            }
        } else {
            Text(content)
                .font(.system(size: fontSize))
                .foregroundColor(foregroundColor)
        }
    }
}

@MainActor
struct ChatMarkdownDocument: Equatable {
    enum Block: Equatable {
        case text(String)
        case table(ChatMarkdownTable)
    }

    let blocks: [Block]
    let containsMarkdown: Bool

    private static let maximumCachedDocuments = 200
    private static var cachedDocuments: [String: ChatMarkdownDocument] = [:]

    static func cached(_ content: String) -> ChatMarkdownDocument {
        if let document = cachedDocuments[content] {
            return document
        }

        let document = ChatMarkdownDocument(content)
        if cachedDocuments.count >= maximumCachedDocuments {
            cachedDocuments.removeAll(keepingCapacity: true)
        }
        cachedDocuments[content] = document
        return document
    }

    init(_ content: String) {
        blocks = Self.parseBlocks(from: content)
        containsMarkdown = Self.detectMarkdown(in: content) || blocks.contains { block in
            if case .table = block { return true }
            return false
        }
    }

    private static func parseBlocks(from content: String) -> [Block] {
        let lines = content.components(separatedBy: .newlines)
        var result: [Block] = []
        var textBuffer: [String] = []
        var index = 0

        func flushTextBuffer() {
            guard !textBuffer.isEmpty else { return }
            result.append(contentsOf: textBlocks(from: textBuffer).map(Block.text))
            textBuffer.removeAll()
        }

        while index < lines.count {
            if let table = parseTable(at: index, in: lines) {
                flushTextBuffer()
                result.append(.table(table.table))
                index = table.nextIndex
            } else {
                textBuffer.append(lines[index])
                index += 1
            }
        }

        flushTextBuffer()
        return result.isEmpty ? [.text(content)] : result
    }

    private enum TextLineKind {
        case heading
        case list
        case quote
        case fencedCode
        case paragraph
    }

    private static func textBlocks(from lines: [String]) -> [String] {
        var blocks: [String] = []
        var current: [String] = []
        var currentKind: TextLineKind?
        var index = 0

        func flushCurrent() {
            guard !current.isEmpty else { return }
            blocks.append(current.joined(separator: "\n"))
            current.removeAll()
            currentKind = nil
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushCurrent()
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                flushCurrent()
                var fenceLines = [line]
                index += 1
                while index < lines.count {
                    fenceLines.append(lines[index])
                    if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    index += 1
                }
                blocks.append(fenceLines.joined(separator: "\n"))
                continue
            }

            let kind = textLineKind(for: trimmed)
            if let currentKind, shouldStartNewTextBlock(after: currentKind, before: kind) {
                flushCurrent()
            }
            current.append(line)
            currentKind = kind
            index += 1
        }

        flushCurrent()
        return blocks
    }

    private static func textLineKind(for trimmedLine: String) -> TextLineKind {
        if trimmedLine.range(of: #"^#{1,6}\s+\S"#, options: .regularExpression) != nil {
            return .heading
        }
        if trimmedLine.range(of: #"^([-*+]|\d+\.)\s+\S"#, options: .regularExpression) != nil {
            return .list
        }
        if trimmedLine.range(of: #"^>\s+\S"#, options: .regularExpression) != nil {
            return .quote
        }
        if trimmedLine.hasPrefix("```") {
            return .fencedCode
        }
        return .paragraph
    }

    private static func shouldStartNewTextBlock(after previous: TextLineKind, before next: TextLineKind) -> Bool {
        if previous == .heading || next == .heading {
            return true
        }
        if previous == .list || next == .list {
            return previous != next
        }
        if previous == .quote || next == .quote {
            return previous != next
        }
        if previous == .fencedCode || next == .fencedCode {
            return true
        }
        return false
    }

    private static func parseTable(at index: Int, in lines: [String]) -> (table: ChatMarkdownTable, nextIndex: Int)? {
        guard index + 1 < lines.count else { return nil }
        let header = tableCells(in: lines[index])
        let separator = tableSeparatorCells(in: lines[index + 1])
        guard header.count >= 2, header.count == separator.count else { return nil }

        var rows: [[String]] = []
        var nextIndex = index + 2
        while nextIndex < lines.count {
            let cells = tableCells(in: lines[nextIndex])
            guard cells.count == header.count else { break }
            rows.append(cells)
            nextIndex += 1
        }

        return (ChatMarkdownTable(headers: header, rows: rows), nextIndex)
    }

    private static func tableCells(in line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return [] }
        let withoutOuterPipes = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        return withoutOuterPipes
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    private static func tableSeparatorCells(in line: String) -> [String] {
        let cells = tableCells(in: line)
        guard !cells.isEmpty else { return [] }
        let separatorCharacters = CharacterSet(charactersIn: "-: ")
        guard cells.allSatisfy({ cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            return trimmed.count >= 3 && trimmed.rangeOfCharacter(from: separatorCharacters.inverted) == nil
        }) else {
            return []
        }
        return cells
    }

    private static func detectMarkdown(in content: String) -> Bool {
        let lines = content.components(separatedBy: .newlines)
        if content.contains("```") { return true }
        if content.range(of: #"(^|\s)(\*\*|__)[^\n]+(\*\*|__)(\s|$)"#, options: .regularExpression) != nil { return true }
        if content.range(of: #"(^|\s)(\*|_)[^\n]+(\*|_)(\s|$)"#, options: .regularExpression) != nil { return true }
        if content.range(of: #"`[^`\n]+`"#, options: .regularExpression) != nil { return true }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: #"^#{1,6}\s+\S"#, options: .regularExpression) != nil { return true }
            if trimmed.range(of: #"^([-*+]|\d+\.)\s+\S"#, options: .regularExpression) != nil { return true }
            if trimmed.range(of: #"^>\s+\S"#, options: .regularExpression) != nil { return true }
        }
        return false
    }
}

struct ChatMarkdownTable: Equatable {
    var headers: [String]
    var rows: [[String]]
}

@MainActor
private struct ChatMarkdownText: View {
    let text: String
    let fontSize: CGFloat
    let foregroundColor: Color

    private var attributedText: AttributedString {
        Self.cachedAttributedText(for: text)
    }

    private static let maximumCachedAttributedStrings = 300
    private static var cachedAttributedStrings: [String: AttributedString] = [:]

    private static func cachedAttributedText(for text: String) -> AttributedString {
        if let attributed = cachedAttributedStrings[text] {
            return attributed
        }

        let attributed = (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        )) ?? AttributedString(text)
        if cachedAttributedStrings.count >= maximumCachedAttributedStrings {
            cachedAttributedStrings.removeAll(keepingCapacity: true)
        }
        cachedAttributedStrings[text] = attributed
        return attributed
    }

    var body: some View {
        Text(attributedText)
            .font(.system(size: fontSize))
            .foregroundColor(foregroundColor)
            .lineSpacing(2)
    }
}

private struct ChatMarkdownTableView: View {
    let table: ChatMarkdownTable
    let fontSize: CGFloat

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(table.headers.enumerated()), id: \.offset) { _, header in
                    cell(header, isHeader: true)
                }
            }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(normalized(row).enumerated()), id: \.offset) { _, value in
                        cell(value, isHeader: false)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.24), lineWidth: 0.5)
        )
    }

    private func normalized(_ row: [String]) -> [String] {
        if row.count >= table.headers.count {
            return Array(row.prefix(table.headers.count))
        }
        return row + Array(repeating: "", count: table.headers.count - row.count)
    }

    private func cell(_ value: String, isHeader: Bool) -> some View {
        ChatMarkdownText(text: value, fontSize: fontSize, foregroundColor: isHeader ? .primary : .secondary)
            .fontWeight(isHeader ? .semibold : .regular)
            .lineLimit(nil)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: 120, alignment: .leading)
            .background(isHeader ? Color.secondary.opacity(0.12) : Color.clear)
            .border(Color.secondary.opacity(0.18), width: 0.5)
    }
}
