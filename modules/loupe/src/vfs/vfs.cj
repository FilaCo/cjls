package loupe.vfs

import std.collection.*
import std.sync.*
import index_map.{IndexMap, IndexSet}
import rope.Rope

/**
 * A file, by the index its path was given when first seen. Cheap to keep, compare and hash, and
 * the one handle the layers above know a file by; `Vfs` says which path it stands for.
 */
public struct FileId <: Hashable & Equatable<FileId> & ToString {
    public FileId(public let index: Int64) {}

    public func hashCode(): Int64 {
        index
    }

    public operator func ==(other: FileId): Bool {
        index == other.index
    }

    public operator func !=(other: FileId): Bool {
        index != other.index
    }

    public func toString(): String {
        "FileId(${index})"
    }
}

/**
 * Every path a `Vfs` has seen, each with its `FileId`, for good: an id is its path's index in the
 * order they were seen, and never stands for another path, even once its file is gone. Safe to
 * share between threads, so a handler off the main loop can look a path up.
 */
public class PathInterner {
    private let lock = ReadWriteLock()
    private let paths = IndexSet<VfsPath>()

    public init() {}

    /**
     * The id `path` has, or `None` if it was never seen.
     */
    public func lookup(path: VfsPath): ?FileId {
        let index = synchronized(lock.readLock) {
            paths.indexOf(path)
        }
        index.map {i => FileId(i)}
    }

    /**
     * The id `path` has, given it if it had none.
     */
    public func intern(path: VfsPath): FileId {
        match (lookup(path)) {
            case Some(id) => id
            // adding a path already there, as another thread may have meanwhile, keeps its index
            case None => synchronized(lock.writeLock) {
                FileId(paths.addWithIndex(path)[0])
            }
        }
    }

    /**
     * @throws IndexOutOfBoundsException - if the id was not given here
     */
    public func path(id: FileId): VfsPath {
        let path = synchronized(lock.readLock) {
            paths.getAt(id.index)
        }
        path.getOrThrow {=> IndexOutOfBoundsException("no path has ${id}")}
    }
}

public enum ChangeKind <: Equatable<ChangeKind> & ToString {
    | Create
    | Modify
    | Delete

    public operator func ==(other: ChangeKind): Bool {
        match ((this, other)) {
            case (Create, Create) | (Modify, Modify) | (Delete, Delete) => true
            case _ => false
        }
    }

    public operator func !=(other: ChangeKind): Bool {
        !(this == other)
    }

    public func toString(): String {
        match (this) {
            case Create => "Create"
            case Modify => "Modify"
            case Delete => "Delete"
        }
    }
}

/**
 * A file whose contents changed since the changes were last taken, and how, all told.
 */
public struct ChangedFile <: ToString {
    public ChangedFile(public let fileId: FileId, public let kind: ChangeKind) {}

    public func toString(): String {
        "${kind}(${fileId})"
    }
}

/**
 * The contents of every file the server knows, by `FileId`, and what changed in them since they
 * were last passed on — rust-analyzer's `vfs`. It knows no language and no editor: whoever reads a
 * file, from disk or from the editor's buffer, sets its contents here, and whoever keeps the
 * analysis up to date takes the changes. Setting a file to what it holds already changes nothing.
 *
 * Used from one thread; only `paths` may be shared.
 */
public class Vfs {
    public let paths = PathInterner()
    private let contents = ArrayList<?Rope>()
    private let changes = IndexMap<FileId, ChangeKind>()

    public init() {}

    /**
     * The id of `path` if it has contents: `None` for a file never set, or deleted.
     */
    public func fileId(path: VfsPath): ?FileId {
        let id = paths.lookup(path) ?? return None
        match (fileContents(id)) {
            case Some(_) => id
            case None => None
        }
    }

    /**
     * @throws IndexOutOfBoundsException - if the id was not given by this `Vfs`
     */
    public func filePath(id: FileId): VfsPath {
        paths.path(id)
    }

    /**
     * What the file holds, `None` if it does not exist.
     */
    public func fileContents(id: FileId): ?Rope {
        if (id.index < contents.size) {
            contents[id.index]
        } else {
            None
        }
    }

    /**
     * Sets what the file at `path` holds, `None` for no file.
     *
     * @return whether that changed anything
     */
    public func setFileContents(path: VfsPath, text: ?Rope): Bool {
        let id = paths.intern(path)
        while (contents.size <= id.index) {
            contents.add(None)
        }
        let kind = match ((contents[id.index], text)) {
            case (None, None) => return false
            case (Some(old), Some(new)) where old == new => return false
            case (None, Some(_)) => Create
            case (Some(_), Some(_)) => Modify
            case (Some(_), None) => Delete
        }
        contents[id.index] = text
        record(id, kind)
        true
    }

    /**
     * The changes since they were last taken, one per file, folded into what they amount to: a
     * file created then deleted is no change at all. In the order the files began to change,
     * counting from after the last change of each that came to nothing.
     */
    public func takeChanges(): Array<ChangedFile> {
        let taken = changes.toArray().map {change => ChangedFile(change[0], change[1])}
        changes.clear()
        taken
    }

    private func record(id: FileId, kind: ChangeKind): Unit {
        match (changes.get(id)) {
            case None => changes.add(id, kind)
            case Some(Create) where kind == Delete => changes.remove(id)
            case Some(Create) => ()
            case Some(Delete) where kind == Create => changes.add(id, Modify)
            case Some(_) => changes.add(id, kind)
        }
    }
}
