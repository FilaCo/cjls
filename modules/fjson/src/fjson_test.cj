package fjson

import std.collection.*

import std.unittest.*
import std.unittest.testmacro.*

func reader(text: String): FjReader {
    FjReader(text.toArray())
}

@Test
class FjReaderTest {
    @TestCase
    func readsAnObjectKeyByKey() {
        // arrange
        let r = reader(#" { "a" : 1 , "b": "x", "c": [true, false, null], "d": {} } "#)
        var a = 0
        var b = ""
        var c = 0

        // act
        r.beginObject()
        while (r.nextKey()) {
            if (r.keyIs("a")) {
                a = r.readInt64()
            } else if (r.keyIs("b")) {
                b = r.readString()
            } else if (r.keyIs("c")) {
                r.beginArray()
                while (r.nextItem()) {
                    r.skipValue()
                    c++
                }
            } else {
                r.skipValue()
            }
        }
        r.end()

        // assert
        @Expect(a, 1)
        @Expect(b, "x")
        @Expect(c, 3)
    }

    @TestCase
    func unescapesEveryEscapeAndSurrogatePairs() {
        // act
        let s = reader(#""a\"b\\c\/d\b\f\n\r\t\u00e9\u4e2d\ud83d\ude00 мир 😀""#).readString()

        // assert
        @Expect(s, "a\"b\\c/d\u{8}\u{c}\n\r\té中😀 мир 😀")
    }

    @TestCase
    func readsAnEscapeOrANonAsciiCharacterAtEveryOffset() {
        // arrange
        let body = "abcdefgh" * 4
        for (at in 0..body.size) {
            for ((escaped, plain) in [("\\n", "\n"), ("\\\"", "\""), ("é", "é"), ("中", "中")]) {
                let json = "\"${body[0..at]}${escaped}${body[at..]}\""

                // act
                let s = reader(json).readString()

                // assert
                @Expect(s, body[0..at] + plain + body[at..])
            }
        }
    }

    @TestCase
    func refusesInvalidUtf8AndLoneSurrogatesAndControlCharacters() {
        // arrange
        let cases: Array<Array<Byte>> = [
            [0x22, 0x61, 0xC0, 0x80, 0x22], // overlong
            [0x22, 0xED, 0xA0, 0x80, 0x22], // an encoded surrogate
            [0x22, 0xF4, 0x90, 0x80, 0x80, 0x22], // past U+10FFFF
            [0x22, 0x61, 0x0A, 0x22], // a raw newline
            "\"\\ud800\"".toArray(),
            "\"\\udc00\"".toArray(),
            "\"abc".toArray()
        ]

        for (bytes in cases) {
            // act, assert
            @AssertThrows[FjException](FjReader(bytes).readString())
        }
    }

    @TestCase
    func readsIntegersToTheirLimits() {
        // act, assert
        @Expect(reader("-9223372036854775808").readInt64(), Int64.Min)
        @Expect(reader("9223372036854775807").readInt64(), Int64.Max)
        @Expect(reader("4294967295").readUInt32(), UInt32.Max)
        @Expect(reader("0").readInt64(), 0)
        @AssertThrows[FjException](reader("9223372036854775808").readInt64())
        @AssertThrows[FjException](reader("-1").readUInt32())
        @AssertThrows[FjException](reader("01").readInt64())
        @AssertThrows[FjException](reader("1.5").readInt64())
    }

    @TestCase
    func rawValueIsTheValuesOwnBytes() {
        // arrange
        let r = reader(#"{"params": {"a": [1, "}", {"b": null}]}, "method": "m"}"#)

        // act
        r.beginObject()
        r.nextKey()
        let raw = r.rawValue()
        r.nextKey()
        let method = r.readString()

        // assert
        @Expect(String.fromUtf8(raw), #"{"a": [1, "}", {"b": null}]}"#)
        @Expect(method, "m")
        let isObject = match (FjReader(raw).peekKind()) {
            case FjKind.Object => true
            case _ => false
        }
        @Expect(isObject)
    }

    @TestCase
    func refusesMissingAndTrailingCommas() {
        // act, assert
        @AssertThrows[FjException](skipObject(#"{"a": 1 "b": 2}"#))
        @AssertThrows[FjException](readIntegers(#"[1,]"#))
    }
}

func skipObject(text: String): Unit {
    let r = reader(text)
    r.beginObject()
    while (r.nextKey()) {
        r.skipValue()
    }
}

func readIntegers(text: String): Unit {
    let r = reader(text)
    r.beginArray()
    while (r.nextItem()) {
        r.readInt64()
    }
}

@Test
class FjWriterTest {
    @TestCase
    func writesNestedContainersWithCommas() {
        // arrange
        let w = FjWriter(capacity: 1)

        // act
        w.beginObject()
        w.name("a")
        w.beginArray()
        w.int64(1)
        w.int64(-22)
        w.beginObject()
        w.endObject()
        w.null()
        w.endArray()
        w.name("b")
        w.bool(true)
        w.name("c")
        w.int64(Int64.Min)
        w.endObject()

        // assert
        @Expect(String.fromUtf8(w.bytes()), #"{"a":[1,-22,{},null],"b":true,"c":-9223372036854775808}"#)
    }

    @TestCase
    func writesEveryIntegerAsItsDecimal() {
        // arrange
        let values = ArrayList<Int64>([0, Int64.Max, Int64.Min, Int64.Min + 1])
        var p: Int64 = 1
        for (_ in 0..18) {
            p *= 10
            values.add(all: [p - 1, p, p + 1, -(p - 1), -p])
        }

        for (value in values) {
            // act
            let w = FjWriter(capacity: 1)
            w.int64(value)

            // assert
            @Expect(String.fromUtf8(w.bytes()), value.toString())
        }
    }

    @TestCase
    func escapesWhatJsonRequiresAndNothingElse() {
        // arrange
        let w = FjWriter()

        // act
        w.string("a\"b\\c\n\t\u{1}é中😀 long enough for a word or two")

        // assert
        @Expect(String.fromUtf8(w.bytes()), #""a\"b\\c\n\t\u0001é中😀 long enough for a word or two""#)
    }

    @TestCase
    func clearKeepsNothingOfTheLastMessage() {
        // arrange
        let w = FjWriter()
        w.beginArray()
        w.int64(1)
        w.endArray()

        // act
        w.clear()
        w.beginObject()
        w.endObject()

        // assert
        @Expect(String.fromUtf8(w.bytes()), "{}")
    }

    @TestCase
    func whatItWritesReadsBack() {
        // arrange
        let text = "héllo, \"мир\"\t // 😀\n" * 50
        let w = FjWriter()
        w.string(text)

        // act
        let back = FjReader(w.bytes()).readString()

        // assert
        @Expect(back, text)
    }
}
