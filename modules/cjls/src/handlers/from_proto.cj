package cjls.handlers

import rope.LineColumn
import loupe.vfs.VfsPath
import loupe.db.SourceFile
import cjls.lsp_types.*
import cjls.server.DatabaseSnapshot

/**
 * The file a document of the client is, as the snapshot has it; `None` for one the server does
 * not know.
 */
func fileOf(db: DatabaseSnapshot, uri: DocumentUri): ?SourceFile {
    db.sourceFile(VfsPath.fromUri(uri))
}

/**
 * The offset of `position` in `file`, as the snapshot has the file: the text the position was
 * meant for, in the encoding agreed on.
 */
func offsetOf(db: DatabaseSnapshot, file: SourceFile, position: Position): Int64 {
    file.text(db.analysis).offsetOf(lineColumn(position), db.encoding)
}

func lineColumn(position: Position): LineColumn {
    LineColumn(Int64(position.line), Int64(position.character))
}
