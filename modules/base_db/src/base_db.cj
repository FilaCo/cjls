package base_db

import std.collection.*
import std.sync.*
import calca.*
import calca.macros.*
import rope.Rope
import vfs.*
import cjsyntax.CjParse
import cjsyntax.parse as parseText

/**
 * One file's text as the analysis sees it. The database keeps one per `FileId`, made the first time
 * the file is set, and never drops it: a file deleted is an empty text, as in rust-analyzer.
 */
@CalcaInput
public struct SourceFile {
    public let fileId: FileId
    public var text: Rope
}

/**
 * What a query over source files needs of the database.
 */
public interface SourceDatabase <: Database {
    /**
     * The file's input, `None` for a file never set.
     */
    func sourceFile(fileId: FileId): ?SourceFile
}

/**
 * The file's tree. Remembered until its text changes, and a text changed into one that parses the
 * same (as it was, say) leaves what read the tree alone.
 */
@CalcaTracked
public func parse(db: SourceDatabase, file: SourceFile): CjParse {
    parseText(file.text(db).toString())
}

/**
 * The database the server keeps: `RootDatabase()` makes one and its root handle, `snapshot` another
 * handle for another thread. See calca's `Storage`.
 */
public class RootDatabase <: SourceDatabase {
    private RootDatabase(private let storage_: Storage, private let files: Files) {}

    public init() {
        this(Storage(), Files())
    }

    public prop storage: Storage {
        get() {
            storage_
        }
    }

    public func snapshot(): RootDatabase {
        RootDatabase(storage_.snapshot(), files)
    }

    public func sourceFile(fileId: FileId): ?SourceFile {
        files.get(fileId)
    }

    /**
     * Sets the file's text, in a revision of its own, making its input the first time.
     *
     * @throws IllegalStateException - if this is a snapshot, or a query is running on it
     */
    public func setFileText(fileId: FileId, text: Rope, durability!: Durability = Durability.Low): SourceFile {
        match (files.get(fileId)) {
            case Some(file) =>
                file.setText(this).withDurability(durability).to(text)
                file
            case None =>
                let file = SourceFile(this, fileId, text, durability: durability)
                files.add(fileId, file)
                file
        }
    }

    /**
     * Brings the files in step with `changes`, taken from `vfs`.
     *
     * @throws IllegalStateException - if this is a snapshot, or a query is running on it
     */
    public func applyChanges(vfs: Vfs, changes: Array<ChangedFile>): Unit {
        for (change in changes) {
            setFileText(change.fileId, vfs.fileContents(change.fileId) ?? Rope())
        }
    }
}

/**
 * The input of every file, by id, shared by a database and its snapshots.
 */
class Files {
    private let lock = ReadWriteLock()
    private let byId = HashMap<FileId, SourceFile>()

    func get(fileId: FileId): ?SourceFile {
        synchronized(lock.readLock) {
            byId.get(fileId)
        }
    }

    func add(fileId: FileId, file: SourceFile): Unit {
        synchronized(lock.writeLock) {
            byId.add(fileId, file)
        }
    }
}
