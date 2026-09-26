package loupe.vfs

import std.fs.Path
import stdx.encoding.url.{URL, UrlSyntaxException}

/**
 * Where a file is: a normalized absolute path on disk, or, for a document that has none (an
 * editor's `untitled:` buffer), the URI it was given, as is. Two URIs spelling one path apart (a
 * `%`-escape the other does not use, a `/./`) give the one `VfsPath`.
 *
 * Paths are `std.fs.Path`s and URIs stdx's `URL`s, so a path is absolute as the platform the
 * server runs on says (D12). On Windows a drive path keeps `\` for its separator and its letter
 * lowercase: clients differ in both (VS Code sends `c%3A/`, Neovim `C:/`), and the letter's case
 * never tells two drives apart. The rest keeps its case, as the client got it from the file system.
 */
public struct VfsPath <: Hashable & Equatable<VfsPath> & ToString {
    private VfsPath(private let disk: ?Path, private let uri: String) {}

    /**
     * @throws IllegalArgumentException - if `path` is not absolute
     */
    public static func file(path: Path): VfsPath {
        if (!path.isAbsolute()) {
            throw IllegalArgumentException("not an absolute path: ${path}")
        }
        VfsPath(canonical(path.normalize()), "")
    }

    /**
     * @throws IllegalArgumentException - if `path` is not absolute
     */
    public static func file(path: String): VfsPath {
        file(Path(path))
    }

    public static func virtual(name: String): VfsPath {
        VfsPath(None, name)
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
        if (url.scheme != "file" || !local || url.path.isEmpty()) {
            return virtual(uri)
        }
        let path = Path(pathOfUriPath(url.path))
        if (path.isAbsolute()) {
            file(path)
        } else {
            virtual(uri)
        }
    }

    /**
     * The path on disk, `None` for a virtual one.
     */
    public prop filePath: ?Path {
        get() {
            disk
        }
    }

    /**
     * A `file:` URI for a path on disk (`file:///c:/src/a.cj` for a drive), the URI given for a
     * virtual one.
     */
    public func toUri(): String {
        match (disk) {
            case Some(path) => URL(scheme: "file", hostName: "", path: uriPathOf(path)).toString()
            case None => uri
        }
    }

    public func hashCode(): Int64 {
        var hasher = DefaultHasher()
        hasher.write(disk.isSome())
        hasher.write(toString())
        hasher.finish()
    }

    public operator func ==(other: VfsPath): Bool {
        disk == other.disk && uri == other.uri
    }

    public operator func !=(other: VfsPath): Bool {
        !(this == other)
    }

    public func toString(): String {
        match (disk) {
            case Some(path) => path.toString()
            case None => uri
        }
    }
}

/**
 * A normalized path as `VfsPath` keeps it: on Windows with `\` and a lowercase drive letter.
 */
@When[os == "Windows"]
func canonical(path: Path): Path {
    let text = path.toString().replace("/", "\\")
    if (text.size >= 2 && text[1] == b':') {
        Path(text[..1].toAsciiLower() + text[1..])
    } else {
        Path(text)
    }
}

@When[os != "Windows"]
func canonical(path: Path): Path {
    path
}

/**
 * The path of a `file:` URI's path: in `/c:/src` the drive is the first segment (RFC 8089).
 */
@When[os == "Windows"]
func pathOfUriPath(uriPath: String): String {
    if (uriPath.size >= 3 && uriPath[2] == b':') {
        uriPath[1..]
    } else {
        uriPath
    }
}

@When[os != "Windows"]
func pathOfUriPath(uriPath: String): String {
    uriPath
}

/**
 * The path of a `file:` URI for `path`: a drive goes in as a first segment, `/c:/src`.
 */
@When[os == "Windows"]
func uriPathOf(path: Path): String {
    "/" + path.toString().replace("\\", "/")
}

@When[os != "Windows"]
func uriPathOf(path: Path): String {
    path.toString()
}
