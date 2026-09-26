package loupe.vfs

import std.collection.*
import stdx.encoding.url.{URL, UrlSyntaxException}

/**
 * Where a file is: a normalized absolute path on disk, or, for a document that has none (an
 * editor's `untitled:` buffer), the URI it was given, as is. Two URIs spelling one path apart (a
 * `%`-escape the other does not use, a `/./`) give the one `VfsPath`. The URI itself is stdx's
 * `URL`: parsed, unescaped and written by it.
 *
 * A path is absolute from `/`, or from a drive (`C:\`, `c:/`): alike on every platform, so what a
 * Windows client sends reads the same wherever it is tested. A drive path keeps `/` for its
 * separator and its letter lowercase, as VS Code writes it: clients differ in both (`c%3A`,
 * `C:`), and the letter's case never tells two drives apart. The rest keeps its case, as the
 * client got it from the file system.
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
        let url = try {
            URL.parse(uri)
        } catch (_: UrlSyntaxException) {
            return virtual(uri)
        } catch (_: IllegalArgumentException) {
            // an escape that spells no UTF-8
            return virtual(uri)
        }
        // the host is empty, or `localhost`, for a file on this machine
        let local = url.hostName.isEmpty() || url.hostName == "localhost"
        let path = url.path
        if (url.scheme != "file" || !local || !path.startsWith("/")) {
            virtual(uri)
        } else if (startsWithDrive(path[1..])) {
            // `/c:/src`: in a URI the drive is the first segment
            file(path[1..])
        } else {
            file(path)
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
     * A `file:` URI for a path on disk (`file:///c:/src/a.cj` for a drive), the URI given for a
     * virtual one.
     */
    public func toUri(): String {
        if (onDisk && startsWithDrive(value)) {
            URL(scheme: "file", hostName: "", path: "/" + value).toString()
        } else if (onDisk) {
            URL(scheme: "file", hostName: "", path: value).toString()
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
