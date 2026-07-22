package lsp

import std.io.{InputStream, OutputStream, BufferedInputStream, ByteBuffer}
import stdx.encoding.json.stream.{JsonReader, JsonWriter}

extend Message {
    @Frozen
    public static func read<T>(input: BufferedInputStream<T>): ?Message where T <: InputStream {
        let header = Header.parse(input) ?? return None
        let content = readContent(input, header.contentLength)
        let bb = ByteBuffer(content)
        let jr = JsonReader(bb)
        Message.fromJson(jr)
    }

    @Frozen
    public func write<T>(output: T): Unit where T <: OutputStream {
        let bb = ByteBuffer()
        let jw = JsonWriter(bb)
        toJson(jw)
        jw.flush()
        let headerBytes = unsafe { "Content-Length: ${bb.length}\r\n\r\n".rawData() }
        output.write(headerBytes)
        output.write(bb.bytes())
        output.flush()
    }
}

extend ResponseMessage {
    @Frozen
    public func write<T>(output: T): Unit where T <: OutputStream {
        Response(this).write(output)
    }
}

/**
* @throws JsonRpcContentTruncatedException - if read less bytes than declared
*/
private func readContent<T>(input: BufferedInputStream<T>, size: Int64): Array<Byte> where T <: InputStream {
    let res = Array<Byte>(size, repeat: 0)
    var readBytes = input.read(res)
    while (readBytes < size && let Some(b) <- input.readByte()) {
        res[readBytes] = b
        readBytes++
    }

    if (readBytes < size) {
        throw JsonRpcContentTruncatedException(size, readBytes)
    }

    res
}

public class JsonRpcContentTruncatedException <: LspException {
    @Frozen
    JsonRpcContentTruncatedException(expected: Int64, actual: Int64) {
        super("JSON-RPC content truncated: expected ${expected} bytes, got ${actual}")
    }
}
