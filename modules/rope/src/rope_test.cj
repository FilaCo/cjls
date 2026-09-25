package rope

import std.collection.*
import std.random.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * Pieces of every width UTF-8 has, and both line ends.
 */
let PIECES: Array<String> = ["a", "bc", " ", "\n", "\r\n", "й", "中", "😀", "xyz", "\t"]

func randomText(random: Random, pieces: Int64): String {
    String.join(Array(pieces) {_ => PIECES[random.nextInt64(PIECES.size)]})
}

/**
 * The offsets of `text` between characters, both ends included.
 */
func boundaries(text: String): Array<Int64> {
    (0..=text.size) |> filter {i: Int64 => i == text.size || !isContinuation(text[i])} |> collectArray
}

/**
 * The last offset of `text` between characters at most `offset`.
 */
func floorBoundary(text: String, offset: Int64): Int64 {
    var boundary = offset
    while (boundary < text.size && isContinuation(text[boundary])) {
        boundary--
    }
    boundary
}

/**
 * The position of `offset` in `text`, counted the slow way.
 */
func naivePosition(text: String, offset: Int64, encoding: Encoding): LineColumn {
    var line = 0
    var lineStart = 0
    for (i in 0..offset where text[i] == b'\n') {
        line++
        lineStart = i + 1
    }
    var column = 0
    for (r in text[lineStart..offset].runes()) {
        column += match (encoding) {
            case Utf8 => String(r).size
            case Utf16 => if (UInt32(r) > 0xFFFF) { 2 } else { 1 }
            case Utf32 => 1
        }
    }
    LineColumn(line, column)
}

@Test
class RopeTest {
    @TestCase
    func aRopeHoldsTheTextItIsMadeFrom() {
        // arrange
        let random = Random(7)
        for (pieces in [0, 1, 300, 3000, 40000]) {
            let text = randomText(random, pieces)

            // act
            let rope = Rope(text)

            // assert
            @Expect(rope.toString(), text)
            @Expect(rope.summary, TextSummary.of(text))
            rope.checkInvariants()
        }
    }

    @TestCase
    func editsAgreeWithEditingAString() {
        // arrange
        let random = Random(42)
        var text = randomText(random, 2000)
        var rope = Rope(text)

        for (step in 0..2000) {
            let offsets = boundaries(text)
            let a = offsets[random.nextInt64(offsets.size)]
            let b = offsets[random.nextInt64(offsets.size)]
            let (start, end) = (min(a, b), max(a, b))
            // mostly typing, sometimes a paste or a large deletion
            let inserted = match (random.nextInt64(10)) {
                case 0 => randomText(random, random.nextInt64(3000))
                case 1 | 2 => ""
                case _ => randomText(random, random.nextInt64(4))
            }
            let from = start
            let upTo = if (random.nextInt64(3) == 0) { end } else { floorBoundary(text, min(end, start + 8)) }

            // act
            let edited = rope.replace(from..upTo, inserted)
            text = text[..from] + inserted + text[upTo..]

            // assert
            @Assert(edited.toString(), text)
            @Assert(edited.summary, TextSummary.of(text))
            edited.checkInvariants()
            rope = edited
            if (step % 100 == 0 && text.size > 50000) {
                text = text[..floorBoundary(text, 20000)]
                rope = Rope(text)
            }
        }
    }

    @TestCase
    func anEditLeavesTheRopeItWasMadeFromAsItWas() {
        // arrange
        let text = randomText(Random(3), 5000)
        let rope = Rope(text)

        // act
        let edited = rope.replace(100..4000, "x").insert(0, "y")

        // assert
        @Expect(rope.toString(), text)
        @Expect(edited.toString(), "y" + text[..100] + "x" + text[4000..])
    }

    @TestCase
    func positionsAgreeWithCountingThemTheSlowWay() {
        // arrange
        let random = Random(11)
        let text = randomText(random, 3000)
        let rope = Rope(text)

        for (offset in boundaries(text)) {
            for (encoding in [Utf8, Utf16, Utf32]) {
                // act
                let position = rope.positionOf(offset, encoding)

                // assert
                @Assert(position, naivePosition(text, offset, encoding))
                // between the `\r` and the `\n` of a line end is past the line, which is before the `\r`
                let insideLineEnd = offset > 0 && offset < text.size && text[offset - 1] == b'\r' && text[offset] == b'\n'
                @Assert(rope.offsetOf(position, encoding), if (insideLineEnd) { offset - 1 } else { offset })
            }
        }
    }

    @TestCase
    func aColumnCountsWhatItsEncodingSays() {
        // arrange
        let rope = Rope("й😀x\n")
        let x = "й😀".size

        // act, assert
        @Expect(rope.positionOf(x, Utf8), LineColumn(0, 6))
        @Expect(rope.positionOf(x, Utf16), LineColumn(0, 3))
        @Expect(rope.positionOf(x, Utf32), LineColumn(0, 2))
        @Expect(rope.offsetOf(LineColumn(0, 3), Utf16), x)
    }

    @TestCase
    func aColumnInsideACharacterIsItsStart() {
        // arrange
        let rope = Rope("a😀b")

        // act, assert
        @Expect(rope.offsetOf(LineColumn(0, 2), Utf16), 1)
        @Expect(rope.offsetOf(LineColumn(0, 3), Utf8), 1)
    }

    @TestCase
    func aColumnPastTheLineIsItsEnd() {
        // arrange
        let rope = Rope("ab\r\ncd")

        // act, assert - before the `\r`: text put at the end of the line must not split the `\r\n`
        @Expect(rope.offsetOf(LineColumn(0, 99), Utf16), 2)
        @Expect(rope.offsetOf(LineColumn(1, 99), Utf16), 6)
        @Expect(rope.offsetOf(LineColumn(7, 0), Utf16), 6)
    }

    @TestCase
    func typingAtTheEndOfAWindowsLineKeepsItsLineEnd() {
        // arrange
        let rope = Rope("let a\r\nlet b\r\n")

        // act - an editor asking for the end of the line by a column past it
        let offset = rope.offsetOf(LineColumn(0, 1_000_000), Utf16)
        let edited = rope.insert(offset, " = 1")

        // assert
        @Expect(edited.toString(), "let a = 1\r\nlet b\r\n")
        @Expect(edited.lineEnd(1), edited.size - 2)
    }

    @TestCase
    func onlyALineFeedBreaksALine() {
        // arrange
        let rope = Rope("a\rb\r\nc\n")

        // act, assert
        @Expect(rope.lineCount, 3)
        @Expect(rope.lineStart(1), 5)
        @Expect(rope.lineEnd(0), 3)
        @Expect(rope.lineStart(2), 7)
        @Expect(rope.lineEnd(2), 7)
        @Expect(rope.lineOf(4), 0)
        @Expect(rope.lineOf(5), 1)
    }

    @TestCase
    func anOffsetInsideACharacterIsRefused() {
        // arrange
        let rope = Rope("й")

        // act, assert
        @AssertThrows[IllegalArgumentException](rope.insert(1, "x"))
        @AssertThrows[IllegalArgumentException](rope.positionOf(1, Utf16))
        @AssertThrows[IndexOutOfBoundsException](rope.remove(0..3))
    }

    @TestCase
    func ropesOfOneTextAreEqualHoweverTheyAreChunked() {
        // arrange
        let text = randomText(Random(5), 4000)
        let whole = Rope(text)
        let cut = floorBoundary(text, 1000)
        let pieced = Rope(text[..cut]).insert(cut, text[cut..])

        // act, assert
        @Expect(whole == pieced)
        @Expect(whole != pieced.insert(0, "x"))
        @Expect(whole != whole.replace(0..1, "#"))
        @Expect(Rope() == Rope(""))
    }

    @TestCase
    func aSliceIsThePartOfTheText() {
        // arrange
        let text = randomText(Random(9), 4000)
        let offsets = boundaries(text)
        let (start, end) = (offsets[100], offsets[3000])

        // act
        let slice = Rope(text).slice(start..end)

        // assert
        @Expect(slice.toString(), text[start..end])
        slice.checkInvariants()
    }
}
