package jsonrpc

import std.unittest.*
import std.unittest.testmacro.*

@Test
class ExceptionTest {
    @TestCase
    func transportExceptionIdentifiesItself() {
        // arrange
        let e = TransportException("framing lost")

        // act
        let rendered = e.toString()

        // assert
        @Assert(rendered.contains("TransportException"))
        @Assert(rendered.contains("framing lost"))
    }

    @TestCase
    func rpcExceptionIdentifiesItself() {
        // arrange
        let e = RpcException(ErrorCode.METHOD_NOT_FOUND, "no such method")

        // act
        let rendered = e.toString()

        // assert
        @Assert(rendered.contains("RpcException"))
        @Assert(rendered.contains("no such method"))
    }
}
