package cjls.handlers

import rope.LineColumn
import loupe.vfs.VfsPath
import loupe.db.SourceFile
import cjls.lsp_types as lsp
import cjls.server.ServerSnapshot

/**
 * The file a document of the client is, as the snapshot has it; `None` for one the server does
 * not know.
 */
func fileOf(snap: ServerSnapshot, uri: lsp.DocumentUri): ?SourceFile {
    snap.sourceFile(VfsPath.fromUri(uri))
}

/**
 * The offset of `position` in `file`, as the snapshot has the file: the text the position was
 * meant for, in the encoding agreed on.
 */
func offsetOf(snap: ServerSnapshot, file: SourceFile, position: lsp.Position): Int64 {
    file.text(snap.analysis).offsetOf(lineColumn(position), snap.encoding)
}

func lineColumn(position: lsp.Position): LineColumn {
    LineColumn(Int64(position.line), Int64(position.character))
}
