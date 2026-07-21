package lsp

import std.io.{InputStream, OutputStream, BufferedInputStream, ByteBuffer}
import stdx.encoding.json.stream.{JsonReader, JsonWriter}

extend Message {
    @Frozen
    public static func read<T>(input: BufferedInputStream<T>): ?Message where T <: InputStream {
        Header.parse(input).map {header => readContent(input, Int64(header.contentLength))}.map {
            content =>
                let bb = ByteBuffer(content)
                let jr = JsonReader(bb)
                Message.fromJson(jr)
        }
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

@Frozen
private func readContent<T>(input: BufferedInputStream<T>, size: Int64): Array<Byte> where T <: InputStream {
    let res = Array<Byte>(Int64(size), repeat: 0)
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

public class JsonRpcContentTruncatedException <: Exception {
    JsonRpcContentTruncatedException(expected: Int64, actual: Int64) {
        super("JSON-RPC content truncated: expected ${expected} bytes, got ${actual}")
    }
}
