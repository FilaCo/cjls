package lsp.base_proto.json

import stdx.encoding.json.stream.*
import std.io.ByteBuffer
import std.unittest.* // cjlint-ignore !G.PKG.01
import std.unittest.testmacro.* // cjlint-ignore !G.PKG.01

@Test
class IntegerOrStringTest {
    @TestCase[pairs in [ 
("\"string\"", IntegerOrString.String("string")), 
("\"123\"", IntegerOrString.String("123")), 
("123", IntegerOrString.Integer(123)), 
 ] 
]
    func smoke(pairs: (String, IntegerOrString)) {
        // arrange
        let (input, expected) = pairs

        // act
        let actual = IntegerOrString.fromJson(getReader(input))

        // assert
        @PowerAssert(expected == actual)
    }

    static func getReader(input: String): JsonReader {
        JsonReader(ByteBuffer(input.toArray()))
    }
}
