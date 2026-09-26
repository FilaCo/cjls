package cjls

import std.io.{InputStream, IOException}

@When[os != "Windows"]
foreign func read(fd: Int32, buf: CPointer<Byte>, count: UIntNative): IntNative

@When[os == "macOS"]
foreign func poll(fds: CPointer<PollFd>, nfds: UInt32, timeout: Int32): Int32

@When[os == "Linux"]
foreign func poll(fds: CPointer<PollFd>, nfds: UInt64, timeout: Int32): Int32

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

@When[os == "Windows"]
foreign func _get_osfhandle(fd: Int32): IntNative

@When[os == "Windows"]
foreign func PeekNamedPipe(pipe: IntNative, buf: CPointer<Unit>, size: UInt32, read: CPointer<UInt32>,
    available: CPointer<UInt32>, leftInMessage: CPointer<UInt32>): Int32

@When[os != "Windows"]
@C
struct PollFd {
    var fd: Int32 = 0
    var events: Int16 = 0
    var revents: Int16 = 0
}

const STDIN_FILENO: Int32 = 0
const STDOUT_FILENO: Int32 = 1
const EINTR: Int32 = 4

/**
 * How long a wait for input stays in C at a time: every time it comes back, a collection the
 * runtime has started can finish.
 */
const WAIT_SLICE_MS: Int32 = 50

/**
 * The process's stdin, read straight from its file descriptor.
 *
 * @note `std.env.getStdIn()` can't serve a client: its `read` returns only once the buffer is
 * full or at EOF, even a one-byte one - so a server sending nothing until it has an answer waits
 * forever for a request that has already arrived. This returns whatever `read(2)` returns (`_read`
 * on Windows, which on a pipe returns as soon as anything has arrived just the same).
 *
 * @note It never blocks inside C: it waits for input in slices of `WAIT_SLICE_MS`, and reads only
 * once there is something to read. The Cangjie runtime cannot finish a garbage collection while a
 * thread sits in a foreign call - the collector waits for it at full CPU - and a read blocked
 * until the client next writes lasts as long as the editor is idle: minutes, or hours.
 */
class StdinStream <: InputStream {
    /**
     * @throws IOException - if the wait or the read fails with anything but `EINTR`
     */
    public func read(buffer: Array<Byte>): Int64 {
        if (buffer.size == 0) {
            return 0
        }
        while (true) {
            waitForInput()
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
 * Returns once stdin has input, or has ended: then a read does not block.
 */
@When[os != "Windows"]
func waitForInput(): Unit {
    // POLLIN; the end of the input, or an error, is reported whatever is asked for
    var fd = PollFd()
    fd.fd = STDIN_FILENO
    fd.events = 1
    while (true) {
        let ready = unsafe { poll(inout fd, 1, WAIT_SLICE_MS) }
        if (ready > 0) {
            return
        }
        if (ready < 0) {
            let errno = lastErrno()
            if (errno != EINTR) {
                throw IOException("waiting for stdin failed with errno ${errno}")
            }
        }
    }
}

/**
 * Returns once the stdin pipe has input, or is broken: then a read does not block. Stdin that is
 * not a pipe (a console, a file) is read without waiting.
 */
@When[os == "Windows"]
func waitForInput(): Unit {
    let pipe = unsafe { _get_osfhandle(STDIN_FILENO) }
    while (true) {
        var available: UInt32 = 0
        let peeked = unsafe {
            PeekNamedPipe(pipe, CPointer<Unit>(), 0, CPointer<UInt32>(), inout available, CPointer<UInt32>())
        }
        if (peeked == 0 || available > 0) {
            return
        }
        // a Cangjie sleep parks the thread, and the collector can finish meanwhile
        sleep(Duration.millisecond * Int64(WAIT_SLICE_MS / 5))
    }
}

@When[os != "Windows"]
unsafe func readStdin(buf: CPointer<Byte>, count: Int64): Int64 {
    Int64(read(STDIN_FILENO, buf, UIntNative(count)))
}

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
