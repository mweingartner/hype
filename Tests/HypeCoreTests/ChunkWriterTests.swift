import Testing
import Foundation
@testable import HypeCore

// MARK: - ChunkWriter Pure-Layer Tests

@Suite("ChunkWriter Tests")
struct ChunkWriterTests {

    // MARK: - T1: Split/join symmetry

    @Test func splitJoinSymmetryChar() {
        let text = "hello"
        let parts = ChunkWriter.split(text, as: .char)
        #expect(parts == ["h", "e", "l", "l", "o"])
        #expect(ChunkWriter.join(parts, as: .char) == text)
    }

    @Test func splitJoinSymmetryWord() {
        let text = "one two three"
        let parts = ChunkWriter.split(text, as: .word)
        #expect(parts == ["one", "two", "three"])
        #expect(ChunkWriter.join(parts, as: .word) == text)
    }

    @Test func splitJoinSymmetryItem() {
        let text = "a,b,c"
        let parts = ChunkWriter.split(text, as: .item)
        #expect(parts == ["a", "b", "c"])
        #expect(ChunkWriter.join(parts, as: .item) == text)
    }

    @Test func splitJoinSymmetryLine() {
        let text = "line1\nline2\nline3"
        let parts = ChunkWriter.split(text, as: .line)
        #expect(parts == ["line1", "line2", "line3"])
        #expect(ChunkWriter.join(parts, as: .line) == text)
    }

    @Test func splitItemKeepsEmptySequences() {
        // Adjacent commas produce empty items — no trimming of empties.
        let parts = ChunkWriter.split("a,,b", as: .item)
        #expect(parts == ["a", "", "b"])
    }

    @Test func splitLineNormalizesCarriageReturns() {
        let parts = ChunkWriter.split("a\rb\r\nc", as: .line)
        #expect(parts == ["a", "b", "c"])
    }

    @Test func splitEmptyStringYieldsEmptyArray() {
        #expect(ChunkWriter.split("", as: .char).isEmpty)
        #expect(ChunkWriter.split("", as: .word).isEmpty)
        #expect(ChunkWriter.split("", as: .item).isEmpty)
        #expect(ChunkWriter.split("", as: .line).isEmpty)
    }

    // MARK: - T2: Item padding

    @Test func itemPaddingPastExtent() {
        // put "X" into item 5 of "a,b" → "a,b,,,X"
        let result = ChunkWriter.apply(
            chunkType: .item,
            indices: .single(5),
            preposition: .into,
            container: "a,b",
            value: "X"
        )
        #expect(result == "a,b,,,X")
    }

    @Test func itemPaddingFromEmpty() {
        // item 3 of "" → ",,x"
        let result = ChunkWriter.apply(
            chunkType: .item,
            indices: .single(3),
            preposition: .into,
            container: "",
            value: "x"
        )
        #expect(result == ",,x")
    }

    // MARK: - T3: Range into (collapse)

    @Test func rangeIntoCollapsesSpan() {
        // put "ZZ" into item 2 to 3 of "a,b,c,d" → "a,ZZ,d"
        let result = ChunkWriter.apply(
            chunkType: .item,
            indices: .range(2, 3),
            preposition: .into,
            container: "a,b,c,d",
            value: "ZZ"
        )
        #expect(result == "a,ZZ,d")
    }

    @Test func rangeIntoLineCollapsesSpan() {
        // put "X\nY\nZ" into line 2 to 3 of "l1\nl2\nl3\nl4" → "l1\nX\nY\nZ\nl4"
        let result = ChunkWriter.apply(
            chunkType: .line,
            indices: .range(2, 3),
            preposition: .into,
            container: "l1\nl2\nl3\nl4",
            value: "X\nY\nZ"
        )
        #expect(result == "l1\nX\nY\nZ\nl4")
    }

    // MARK: - T5: Before / after

    @Test func afterLastChar() {
        // put "." after last char of "ab" → "ab."
        // last = -1 (sentinel)
        let result = ChunkWriter.apply(
            chunkType: .char,
            indices: .single(-1),
            preposition: .after,
            container: "ab",
            value: "."
        )
        #expect(result == "ab.")
    }

    @Test func beforeFirstItem() {
        // put ">" before item 1 of "a,b" → ">a,b"
        let result = ChunkWriter.apply(
            chunkType: .item,
            indices: .single(1),
            preposition: .before,
            container: "a,b",
            value: ">"
        )
        #expect(result == ">a,b")
    }

    @Test func afterRangeItems() {
        // put "!" after item 2 to 3 of "a,b,c,d" → "a,b,c!,d"
        let result = ChunkWriter.apply(
            chunkType: .item,
            indices: .range(2, 3),
            preposition: .after,
            container: "a,b,c,d",
            value: "!"
        )
        #expect(result == "a,b,c!,d")
    }

    // MARK: - T8: Empty-container ordinals no-op + item padding

    @Test func lastOfEmptyIsNoOp() {
        // "last" (-1) of empty → no-op, return unchanged
        let result = ChunkWriter.apply(
            chunkType: .item,
            indices: .single(-1),
            preposition: .into,
            container: "",
            value: "x"
        )
        #expect(result == "")
    }

    @Test func middleOfEmptyIsNoOp() {
        // "middle" (0) of empty → no-op
        let result = ChunkWriter.apply(
            chunkType: .word,
            indices: .single(0),
            preposition: .into,
            container: "",
            value: "x"
        )
        #expect(result == "")
    }

    @Test func anyOfEmptyIsNoOp() {
        // "any" (-2) of empty → no-op
        let result = ChunkWriter.apply(
            chunkType: .char,
            indices: .single(-2),
            preposition: .into,
            container: "",
            value: "x"
        )
        #expect(result == "")
    }

    // MARK: - T9: Item spacing preserved (no-trim write path)

    @Test func itemSpacingPreservedOnWrite() {
        // put "Z" into item 2 of "a, b, c" → "a,Z, c"
        // Items are NOT trimmed on the write path so surrounding spaces survive.
        let result = ChunkWriter.apply(
            chunkType: .item,
            indices: .single(2),
            preposition: .into,
            container: "a, b, c",
            value: "Z"
        )
        #expect(result == "a,Z, c")
    }

    // MARK: - T10: Word padding

    @Test func wordPaddingPastExtent() {
        // put "Z" into word 4 of "a b" → "a b  Z"
        let result = ChunkWriter.apply(
            chunkType: .word,
            indices: .single(4),
            preposition: .into,
            container: "a b",
            value: "Z"
        )
        #expect(result == "a b  Z")
    }

    // MARK: - T11: Negative non-sentinel no-op

    @Test func negativeLiteralIndexIsNoOp() {
        // Negative values that are NOT -1 (last) or -2 (any) or 0 (middle) should no-op.
        // (Parser sends exact sentinel values; -3, -5, etc. cannot come from the parser
        //  but ChunkWriter must guard against them.)
        let result = ChunkWriter.apply(
            chunkType: .item,
            indices: .single(-3),
            preposition: .into,
            container: "a,b,c",
            value: "X"
        )
        #expect(result == "a,b,c")
    }

    // MARK: - Line range replacement

    @Test func lineRangeReplacement() {
        // put "X\nY\nZ" into line 2 to 3 of "l1\nl2\nl3\nl4" → "l1\nX\nY\nZ\nl4"
        let input = "l1\nl2\nl3\nl4"
        let result = ChunkWriter.apply(
            chunkType: .line,
            indices: .range(2, 3),
            preposition: .into,
            container: input,
            value: "X\nY\nZ"
        )
        #expect(result == "l1\nX\nY\nZ\nl4")
    }

    // MARK: - Char padding

    @Test func charPaddingEmptyContainer() {
        // put "Z" into char 6 of "" → "     Z" (5 spaces then Z)
        let result = ChunkWriter.apply(
            chunkType: .char,
            indices: .single(6),
            preposition: .into,
            container: "",
            value: "Z"
        )
        #expect(result == "     Z")
    }

    @Test func charPaddingNonEmptyContainer() {
        // put "Z" into char 6 of "abc" → "abc  Z" (2 spaces then Z)
        let result = ChunkWriter.apply(
            chunkType: .char,
            indices: .single(6),
            preposition: .into,
            container: "abc",
            value: "Z"
        )
        #expect(result == "abc  Z")
    }

    // MARK: - Basic single-index into

    @Test func singleItemInto() {
        let result = ChunkWriter.apply(
            chunkType: .item,
            indices: .single(2),
            preposition: .into,
            container: "a,b,c",
            value: "X"
        )
        #expect(result == "a,X,c")
    }

    @Test func singleLineInto() {
        let result = ChunkWriter.apply(
            chunkType: .line,
            indices: .single(2),
            preposition: .into,
            container: "line1\nline2\nline3",
            value: "replaced"
        )
        #expect(result == "line1\nreplaced\nline3")
    }

    @Test func singleCharInto() {
        let result = ChunkWriter.apply(
            chunkType: .char,
            indices: .single(2),
            preposition: .into,
            container: "abc",
            value: "X"
        )
        #expect(result == "aXc")
    }

    // MARK: - put empty into line keeps delimiters

    @Test func putEmptyIntoLineKeepsDelimiters() {
        // put empty into line 2 of "l1\nl2\nl3" → "l1\\n\nl3" (empty middle line)
        let result = ChunkWriter.apply(
            chunkType: .line,
            indices: .single(2),
            preposition: .into,
            container: "l1\nl2\nl3",
            value: ""
        )
        #expect(result == "l1\n\nl3")
    }
}
