package cjls

import std.io.{InputStream, IOException}

// Not `read`: see `readStdin`.
@When[os != "Windows"]
foreign func readv(fd: Int32, iov: CPointer<IoVec>, iovcnt: Int32): IntNative

@When[os == "macOS"]
foreign func __error(): CPointer<Int32>

@When[os == "Linux"]
foreign func __errno_location(): CPointer<Int32>

@When[os == "Windows"]
foreign func _read(fd: Int32, buf: CPointer<Byte>, count: UInt32): Int32

@When[os == "Windows"]
foreign func _setmode(fd: Int32, mode: Int32): Int32

@When[os == "Windows"]
foreign func _errno(): CPointer<Int32>

@When[os != "Windows"]
@C
struct IoVec {
    var base: CPointer<Byte>
    var len: UIntNative
    init(base: CPointer<Byte>, len: UIntNative) {
        this.base = base
        this.len = len
    }
}

const STDIN_FILENO: Int32 = 0
const STDOUT_FILENO: Int32 = 1
const EINTR: Int32 = 4

/**
 * The process's stdin, read straight from its file descriptor.
 *
 * @note `std.env.getStdIn()` can't serve a client: its `read` returns only once the buffer is
 * full or at EOF, even a one-byte one - so a server sending nothing until it has an answer waits
 * forever for a request that has already arrived. This returns whatever `read(2)` returns (`_read`
 * on Windows, which on a pipe returns as soon as anything has arrived just the same).
 *
 * @note The read blocks in C for as long as the editor is idle, which is only harmless because
 * the call goes through the runtime's switch to native code (C5, D13).
 */
class StdinStream <: InputStream {
    /**
     * @throws IOException - if the read fails with anything but `EINTR`
     */
    public func read(buffer: Array<Byte>): Int64 {
        if (buffer.size == 0) {
            return 0
        }
        while (true) {
            let n = unsafe {
                let raw = acquireArrayRawData(buffer)
                let n = readStdin(raw.pointer, buffer.size)
                releaseArrayRawData(raw)
                n
            }
            if (n >= 0) {
                return n
            }
            let errno = lastErrno()
            if (errno != EINTR) {
                throw IOException("reading stdin failed with errno ${errno}")
            }
        }
        0
    }
}

/**
 * Makes stdin and stdout carry bytes as they are. On Windows the C runtime opens both in text
 * mode, which turns every `\n` written into `\r\n` and every `\r\n` read into `\n` - and a frame's
 * `Content-Length` counts the bytes before that. Elsewhere there is no such mode.
 */
@When[os == "Windows"]
func useBinaryStdio(): Unit {
    // _O_BINARY
    let binary: Int32 = 0x8000
    unsafe {
        _setmode(STDIN_FILENO, binary)
        _setmode(STDOUT_FILENO, binary)
    }
}

@When[os != "Windows"]
func useBinaryStdio(): Unit {}

/**
 * `read(2)` as `readv` of one buffer. cjc compiles a foreign function named like a C library
 * function LLVM knows (`read`, `write`, `open`, `getchar`, ...) as `@FastNative`, without switching
 * the thread to native code, so while it blocks the garbage collector waits for it at full CPU and
 * every other thread stops at its next allocation; `readv` is not one of those names (C5, D13).
 */
@When[os != "Windows"]
unsafe func readStdin(buf: CPointer<Byte>, count: Int64): Int64 {
    var iov = IoVec(buf, UIntNative(count))
    Int64(readv(STDIN_FILENO, inout iov, 1))
}

/**
 * `_read` is not a name LLVM knows, so it can block (D13).
 */
@When[os == "Windows"]
unsafe func readStdin(buf: CPointer<Byte>, count: Int64): Int64 {
    // `_read` takes an unsigned int, and a buffer is never near 4 GiB
    Int64(_read(STDIN_FILENO, buf, UInt32(count)))
}

@When[os == "macOS"]
func lastErrno(): Int32 {
    unsafe { __error().read() }
}

@When[os == "Linux"]
func lastErrno(): Int32 {
    unsafe { __errno_location().read() }
}

@When[os == "Windows"]
func lastErrno(): Int32 {
    unsafe { _errno().read() }
}
