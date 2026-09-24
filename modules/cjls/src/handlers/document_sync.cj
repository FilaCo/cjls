package cjls.handlers

import std.fs.{File, FSException}
import stdx.log.Logger
import rope.{Encoding, LineColumn, Rope}
import vfs.VfsPath
import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.LspHandler

/**
 * From now until `didClose`, the file holds what the editor's buffer does.
 */
@LspHandler
func handleDidOpen(db: Database, params: DidOpenTextDocumentParams): Unit {
    let document = params.textDocument
    let path = VfsPath.fromUri(document.uri)
    db.openDocuments.add(path, document.version)
    db.setFileContents(path, Rope(document.text))
}

/**
 * Applies the edits in order, each to the text the one before it left, and the file takes the
 * result once all of them apply: a batch that does not, or one for a document not open, is
 * dropped whole, with a warning.
 */
@LspHandler
func handleDidChange(db: Database, logger: Logger, params: DidChangeTextDocumentParams): Unit {
    let document = params.textDocument
    let path = VfsPath.fromUri(document.uri)
    let text = match (db.fileContents(path)) {
        case Some(text) where db.openDocuments.contains(path) => text
        case _ =>
            logger.warn("a change to a document not open", [("uri", document.uri)])
            return
    }
    match (edited(text, params.contentChanges, db.encoding)) {
        case Some(result) =>
            db.openDocuments.add(path, document.version)
            db.setFileContents(path, result)
        case None => logger.warn("a change whose range ends before it starts", [("uri", document.uri)])
    }
}

/**
 * The file goes back to what the disk holds, or away if it is not on the disk.
 */
@LspHandler
func handleDidClose(db: Database, params: DidCloseTextDocumentParams): Unit {
    let path = VfsPath.fromUri(params.textDocument.uri)
    db.openDocuments.remove(path)
    db.setFileContents(path, diskContents(path))
}

/**
 * `text` with `changes` applied in order, `None` if a range ends before it starts. A position
 * past its line, or past the text, stands for the end of it, as LSP asks.
 */
func edited(text: Rope, changes: Array<TextDocumentContentChangeEvent>, encoding: Encoding): ?Rope {
    var result = text
    for (change in changes) {
        result = match (change) {
            case AsTextDocumentContentChangeWholeDocument(whole) => Rope(whole.text)
            case AsTextDocumentContentChangePartial(partial) =>
                let start = result.offsetOf(lineColumn(partial.range.start), encoding)
                let end = result.offsetOf(lineColumn(partial.range.end), encoding)
                if (end < start) {
                    return None
                }
                result.replace(start..end, partial.text)
        }
    }
    result
}

func lineColumn(position: Position): LineColumn {
    LineColumn(Int64(position.line), Int64(position.character))
}

/**
 * What the file at `path` holds on disk, `None` if it is not there, cannot be read, or is not
 * UTF-8.
 */
func diskContents(path: VfsPath): ?Rope {
    let filePath = path.filePath ?? return None
    try {
        Rope(String.fromUtf8(File.readFrom(filePath)))
    } catch (_: FSException) {
        None
    } catch (_: IllegalArgumentException) {
        None
    }
}
