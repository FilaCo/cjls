package loupe.vfs

import std.collection.*

/**
 * Where a file is: a normalized absolute path on disk, or, for a document that has none (an
 * editor's `untitled:` buffer), the URI it was given, as is. Two URIs spelling one path apart (a
 * `%`-escape the other does not use, a `/./`) give the one `VfsPath`.
 *
 * A path is absolute from `/`, or from a drive (`C:\`, `c:/`): alike on every platform, so what a
 * Windows client sends reads the same wherever it is tested. A drive path keeps `/` for its
 * separator and its letter lowercase, as VS Code writes it (`file:///c%3A/src/a.cj`): clients
 * differ in both, and the letter's case never tells two drives apart. The rest keeps its case, as
 * the client got it from the file system.
 */
public struct VfsPath <: Hashable & Equatable<VfsPath> & ToString {
    private VfsPath(private let onDisk: Bool, private let value: String) {}

    /**
     * @throws IllegalArgumentException - if `path` is not absolute
     */
    public static func file(path: String): VfsPath {
        if (path.startsWith("/")) {
            VfsPath(true, normalize("/", path))
        } else if (startsWithDrive(path)) {
            VfsPath(true, normalize(path[..2].toAsciiLower() + "/", path[2..].replace("\\", "/")))
        } else {
            throw IllegalArgumentException("not an absolute path: ${path}")
        }
    }

    public static func virtual(name: String): VfsPath {
        VfsPath(false, name)
    }

    /**
     * The path a `file:` URI names, anything else a virtual path of the URI itself.
     */
    public static func fromUri(uri: String): VfsPath {
        if (!uri.startsWith("file://")) {
            return virtual(uri)
        }
        let rest = uri["file://".size..]
        // the authority is empty, or `localhost`, for a file on this machine
        let path = match (rest.indexOf("/")) {
            case Some(slash) where slash == 0 || rest[..slash] == "localhost" => rest[slash..]
            case _ => return virtual(uri)
        }
        match (percentDecoded(path)) {
            // `/c:/src`: in a URI the drive is the first segment
            case Some(decoded) where startsWithDrive(decoded[1..]) => file(decoded[1..])
            case Some(decoded) => file(decoded)
            case None => virtual(uri)
        }
    }

    /**
     * The path on disk, `None` for a virtual one.
     */
    public prop filePath: ?String {
        get() {
            if (onDisk) {
                value
            } else {
                None
            }
        }
    }

    /**
     * A `file:` URI for a path on disk, escaped the way VS Code does, the URI given for a virtual one.
     */
    public func toUri(): String {
        if (onDisk && startsWithDrive(value)) {
            "file:///" + percentEncoded(value)
        } else if (onDisk) {
            "file://" + percentEncoded(value)
        } else {
            value
        }
    }

    public func hashCode(): Int64 {
        var hasher = DefaultHasher()
        hasher.write(onDisk)
        hasher.write(value)
        hasher.finish()
    }

    public operator func ==(other: VfsPath): Bool {
        onDisk == other.onDisk && value == other.value
    }

    public operator func !=(other: VfsPath): Bool {
        !(this == other)
    }

    public func toString(): String {
        value
    }
}

/**
 * `C:` and the like, alone or before a separator.
 */
func startsWithDrive(path: String): Bool {
    path.size >= 2 && path[0].isAsciiLetter() && path[1] == b':' &&
        (path.size == 2 || path[2] == b'/' || path[2] == b'\\')
}

/**
 * `root` and then `path`'s segments, with no empty, `.` or `..` ones: `..` above the root stays at
 * the root.
 */
func normalize(root: String, path: String): String {
    let segments = ArrayList<String>()
    for (segment in path.split("/")) {
        match (segment) {
            case "" | "." => ()
            case ".." =>
                if (!segments.isEmpty()) {
                    segments.remove(at: segments.size - 1)
                }
            case _ => segments.add(segment)
        }
    }
    root + String.join(segments.toArray(), delimiter: "/")
}

/**
 * `None` if an escape is malformed, or what they spell is not UTF-8.
 */
func percentDecoded(text: String): ?String {
    if (!text.contains("%")) {
        return text
    }
    let bytes = ArrayList<Byte>()
    var i = 0
    while (i < text.size) {
        let b = text[i]
        if (b == b'%') {
            if (i + 2 >= text.size) {
                return None
            }
            let high = hexValue(text[i + 1]) ?? return None
            let low = hexValue(text[i + 2]) ?? return None
            bytes.add(high * 16 + low)
            i += 3
        } else {
            bytes.add(b)
            i++
        }
    }
    try {
        String.fromUtf8(bytes.toArray())
    } catch (_: IllegalArgumentException) {
        None
    }
}

private func hexValue(b: Byte): ?Byte {
    if (b >= b'0' && b <= b'9') {
        b - b'0'
    } else if (b >= b'a' && b <= b'f') {
        b - b'a' + 10
    } else if (b >= b'A' && b <= b'F') {
        b - b'A' + 10
    } else {
        None
    }
}

private let HEX_DIGITS = "0123456789ABCDEF"

/**
 * Every byte escaped but the unreserved ones and `/`.
 */
func percentEncoded(path: String): String {
    let encoded = StringBuilder()
    for (b in path) {
        let unreserved = b >= b'a' && b <= b'z' || b >= b'A' && b <= b'Z' || b >= b'0' && b <= b'9' ||
            b == b'-' || b == b'.' || b == b'_' || b == b'~' || b == b'/'
        if (unreserved) {
            encoded.append(Rune(b))
        } else {
            encoded.append("%")
            encoded.append(Rune(HEX_DIGITS[Int64(b >> 4)]))
            encoded.append(Rune(HEX_DIGITS[Int64(b & 0xF)]))
        }
    }
    encoded.toString()
}
