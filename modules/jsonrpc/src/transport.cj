package jsonrpc

import std.io.*
import std.sync.AtomicBool
import stdx.log.*
import stdx.serialization.serialization.*
import stdx.encoding.json.*

public interface JsonRpcReader <: Resource {
    // @note `None` = clean EOF
    func read(): ?Body
}

public interface JsonRpcWriter <: Resource {
    func write(body: Body): Unit
}

public interface JsonRpcTransport <: JsonRpcReader & JsonRpcWriter {}

public class FramedJsonRpcTransport <: JsonRpcTransport {
    // 32 Mb
    public static const BODY_BYTES_MAX: Int64 = 32 * 1024 * 1024

    private let input: BufferedInputStream<InputStream>
    private let output: BufferedOutputStream<OutputStream>
    private let closed = AtomicBool(false)

    public FramedJsonRpcTransport(private let source: InputStream, private let sink: OutputStream,
        private let logger: Logger) {
        this.input = BufferedInputStream(source)
        this.output = BufferedOutputStream(sink)
    }

    public func isClosed(): Bool {
        closed.load()
    }

    public func close(): Unit {
        if (closed.swap(true)) {
            return
        }

        try {
            output.flush()
        } catch (e: Exception) {
            // the peer is already gone, so there is nothing left to salvage - but a
            // close that throws would mask whatever is being torn down alongside it
            logger.warn("flushing the JSON-RPC transport on close failed", [("cause", e)])
        }

        if (let Some(closeableSink) <- (sink as Resource)) {
            closeableSink.close()
        }
        if (let Some(closeableSource) <- (source as Resource)) {
            closeableSource.close()
        }
    }

    /**
     * @note the stream stays in sync after an `RpcException`, so the caller may
     * answer it with `toResponseError()` and keep reading. A `TransportException`
     * means the framing itself is lost - there is no next message to find.
     *
     * @note a closed transport reads as EOF: shutting down is not a framing fault,
     * and a read loop that already ends on `None` needs no second exit.
     *
     * @throws RpcException - if the frame carries no decodable message
     * @throws TransportException - if the framing is malformed or truncated
     */
    public func read(): ?Body {
        if (isClosed()) {
            return None
        }
        let header = Header.parse(input) ?? return None
        if (header.contentLength == 0) {
            throw RpcException(ErrorCode.PARSE_ERROR, "JSON-RPC frame declares an empty content")
        }
        let payload = readExactly(Int64(header.contentLength))
        let jv = try {
            JsonValue.fromStr(String.fromUtf8(payload))
        } catch (e: Exception) {
            throw RpcException(ErrorCode.PARSE_ERROR, "JSON-RPC content is not valid JSON\nCause: ${e.message}")
        }

        try {
            Body.deserialize(DataModel.fromJson(jv))
        } catch (e: DataModelException) {
            throw RpcException(ErrorCode.INVALID_REQUEST, "JSON-RPC content is not a valid message\nCause: ${e.message}",)
        }
    }

    /**
     * @throws TransportException - if the transport is closed
     */
    public func write(msg: Body): Unit {
        if (isClosed()) {
            throw TransportException("JSON-RPC transport is closed")
        }
        let payload = msg.serialize().toJson().toString().toArray()
        output.write("Content-Length: ${payload.size}\r\n\r\n".toArray())
        output.write(payload)
        output.flush()
    }

    /**
     * @note `count` must be positive
     *
     * @throws TransportException - if read less bytes than declared
     */
    private func readExactly(count: Int64): Array<Byte> {
        if (count > BODY_BYTES_MAX) {
            throw TransportException(
                "JSON-RPC body size limit exceeded: expected at most ${BODY_BYTES_MAX}, got ${count} bytes")
        }
        let res = Array<Byte>(count, repeat: 0)
        // no need to read in cycle - buffered input stream already reads up to EOF or desired bytes
        let readBytes = input.read(res)

        if (readBytes < count) {
            throw TransportException("JSON-RPC content truncated: expected ${count} bytes, got ${readBytes}")
        }

        res
    }
}
