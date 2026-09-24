package cjls

import std.io.{InputStream, IOException}

foreign func read(fd: Int32, buf: CPointer<Byte>, count: UIntNative): IntNative

@When[os == "macOS"]
foreign func __error(): CPointer<Int32>

@When[os == "Linux"]
foreign func __errno_location(): CPointer<Int32>

const STDIN_FILENO: Int32 = 0
const EINTR: Int32 = 4

/**
 * The process's stdin, read straight from its file descriptor.
 *
 * @note `std.env.getStdIn()` can't serve a client: its `read` returns only once the buffer is
 * full or at EOF, even a one-byte one - so a server sending nothing until it has an answer waits
 * forever for a request that has already arrived. This returns whatever `read(2)` returns.
 */
class StdinStream <: InputStream {
    /**
     * @throws IOException - if `read(2)` fails with anything but `EINTR`
     */
    public func read(buffer: Array<Byte>): Int64 {
        if (buffer.size == 0) {
            return 0
        }
        while (true) {
            let n = unsafe {
                let raw = acquireArrayRawData(buffer)
                let n = read(STDIN_FILENO, raw.pointer, UIntNative(buffer.size))
                releaseArrayRawData(raw)
                n
            }
            if (n >= 0) {
                return Int64(n)
            }
            let errno = lastErrno()
            if (errno != EINTR) {
                throw IOException("reading stdin failed with errno ${errno}")
            }
        }
        0
    }
}

@When[os == "macOS"]
func lastErrno(): Int32 {
    unsafe { __error().read() }
}

@When[os == "Linux"]
func lastErrno(): Int32 {
    unsafe { __errno_location().read() }
}
