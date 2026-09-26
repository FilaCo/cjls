package cjls.server

import std.collection.HashMap
import rope.{Encoding, Rope}
import loupe.vfs.*
import loupe.db.*

/**
 * The server's state, which a handler given a `Context` changes: the files as the editor and the
 * disk give them, the documents the editor has open, and the analysis, kept in step with the
 * files: a query takes `state.analysis`, the root handle of the analysis database.
 */
public class ServerState <: FromContext<ServerState> {
    public let analysis = AnalysisDatabase()
    private let vfs = Vfs()

    /**
     * The documents the editor has open, and the version of each it last sent: between
     * `didOpen` and `didClose` the editor's buffer is what the file holds, not the disk.
     */
    public let openDocuments = HashMap<VfsPath, Int32>()

    /**
     * What a column counts, as agreed on at `initialize`: UTF-16 until then, as LSP has it.
     */
    public var encoding = Encoding.Utf16

    /**
     * Whether the server pushes diagnostics, as agreed on at `initialize`: only to a client that
     * cannot pull them, so no document has two sources (S8).
     */
    public var pushesDiagnostics = false

    private var filesChanged = false

    public static func from<P>(ctx: Context<P>): ServerState {
        ctx.state
    }

    /**
     * What the file at `path` holds, `None` if the server knows no such file.
     */
    public func fileContents(path: VfsPath): ?Rope {
        vfs.fileContents(vfs.fileId(path) ?? return None)
    }

    /**
     * Sets what the file at `path` holds, `None` for no file, and brings the analysis in step:
     * what is in flight on the snapshots is cancelled, if anything changed.
     */
    public func setFileContents(path: VfsPath, text: ?Rope): Unit {
        if (vfs.setFileContents(path, text)) {
            analysis.applyChanges(vfs, vfs.takeChanges())
            filesChanged = true
        }
    }

    /**
     * Whether the files changed since it was last asked; the server asks after every handler that
     * could change them.
     */
    func takeFilesChanged(): Bool {
        let changed = filesChanged
        filesChanged = false
        changed
    }

    /**
     * The state as it is now, for a handler running on a thread of its own. Its queries stop,
     * `Cancelled`, once `cancelledBy` gives `true`: the client cancelled the request.
     */
    public func snapshot(cancelledBy!: () -> Bool = {=> false}): ServerSnapshot {
        ServerSnapshot(analysis.snapshot(cancelledBy: cancelledBy), vfs.paths, encoding)
    }
}

/**
 * The state as it was when a message arrived, for its handler to read on a thread of its own. Once
 * the files change after it, a query on `analysis`, a snapshot of the analysis database, throws
 * `Cancelled`, which the server answers with `ContentModified`.
 */
public class ServerSnapshot <: FromReadOnlyContext<ServerSnapshot> {
    ServerSnapshot(public let analysis: AnalysisDatabase, private let paths: PathInterner,
        public let encoding: Encoding) {}

    public static func from<P>(ctx: ReadOnlyContext<P>): ServerSnapshot {
        ctx.snapshot
    }

    /**
     * The input of the file at `path`, `None` if the server never knew such a file.
     */
    public func sourceFile(path: VfsPath): ?SourceFile {
        analysis.sourceFile(paths.lookup(path) ?? return None)
    }
}
