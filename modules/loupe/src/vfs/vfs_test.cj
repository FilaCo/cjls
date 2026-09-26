package loupe.vfs

import std.collection.HashSet
import std.unittest.*
import std.unittest.testmacro.*
import std.env.getTempDirectory
import std.fs.Path
import rope.Rope

/**
 * A path in the temporary directory, absolute wherever the tests run; nothing is created there.
 */
func inTemp(name: String): VfsPath {
    VfsPath.file(getTempDirectory().join(name))
}

func kinds(changes: Array<ChangedFile>): Array<String> {
    changes.map {change => change.toString()}
}

@Test
class VfsPathTest {
    @TestCase
    func aUriNotOfAFileIsVirtual() {
        // act
        let path = VfsPath.fromUri("untitled:Untitled-1")

        // assert
        @Expect(path.filePath, None<Path>)
        @Expect(path.toUri(), "untitled:Untitled-1")
        @Expect(path != inTemp("Untitled-1"))
    }

    @TestCase
    func aPathGoesToAUriAndBack() {
        // arrange - `#` and `?` would start a fragment and a query unescaped
        let paths = [inTemp("проект/a b.cj"), inTemp("y#z?.cj")]

        // act, assert
        for (path in paths) {
            @Expect(VfsPath.fromUri(path.toUri()), path)
        }
    }

    @TestCase
    func aMalformedEscapeLeavesTheUriVirtual() {
        // act, assert
        @Expect(VfsPath.fromUri("file:///a%2").filePath, None<Path>)
        @Expect(VfsPath.fromUri("file:///a%FF").filePath, None<Path>)
    }

    @TestCase
    func aRelativePathIsNoFile() {
        // act, assert
        @AssertThrows[IllegalArgumentException](VfsPath.file("a.cj"))
    }
}

@When[os != "Windows"]
@Test
class VfsPathOnPosixTest {
    @TestCase
    func aFileUriIsItsDecodedPath() {
        // act
        let path = VfsPath.fromUri("file:///home/me/%D0%BF%D1%80%D0%BE%D0%B5%D0%BA%D1%82/a%20b.cj")

        // assert
        @Expect(path.filePath, Some(Path("/home/me/проект/a b.cj")))
        @Expect(path.toUri(), "file:///home/me/%D0%BF%D1%80%D0%BE%D0%B5%D0%BA%D1%82/a%20b.cj")
    }

    @TestCase
    func urisSpellingOnePathApartAreOnePath() {
        // act, assert
        @Expect(VfsPath.fromUri("file:///a/./b/../c.cj"), VfsPath.fromUri("file://localhost/a/%63.cj"))
        @Expect(VfsPath.file("//a///c.cj"), VfsPath.file("/a/c.cj"))
    }
}

@When[os == "Windows"]
@Test
class VfsPathOnWindowsTest {
    @TestCase
    func aDrivePathIsKeptWithBackslashesAndALowercaseLetter() {
        // act
        let path = VfsPath.file("C:/src/./app/../a.cj")

        // assert
        @Expect(path.filePath, Some(Path("c:\\src\\a.cj")))
        @Expect(VfsPath.file("C:\\src\\a.cj"), path)
    }

    @TestCase
    func clientsSpellingOneDriveApartGiveOnePath() {
        // arrange
        let vsCode = "file:///c%3A/Users/Me/a.cj"
        let neovim = "file:///C:/Users/Me/a.cj"

        // act, assert
        @Expect(VfsPath.fromUri(vsCode), VfsPath.fromUri(neovim))
        @Expect(VfsPath.fromUri(neovim).filePath, Some(Path("c:\\Users\\Me\\a.cj")))
        @Expect(VfsPath.fromUri(neovim) != VfsPath.fromUri("file:///C:/users/me/a.cj"))
    }

    @TestCase
    func aDrivePathGoesBackToAUriWithTheDriveAsItsFirstSegment() {
        // act
        let uri = VfsPath.file("C:\\Users\\Me\\a b.cj").toUri()

        // assert
        @Expect(uri, "file:///c:/Users/Me/a%20b.cj")
    }
}

@Test
class VfsTest {
    @TestCase
    func aFileKeepsItsIdForGood() {
        // arrange
        let vfs = Vfs()
        let path = inTemp("a.cj")
        vfs.setFileContents(path, Rope("x"))
        let id = vfs.fileId(path).getOrThrow()

        // act
        vfs.setFileContents(path, None)
        let whileGone = vfs.fileId(path)
        vfs.setFileContents(path, Rope("y"))

        // assert
        @Expect(whileGone, None<FileId>)
        @Expect(vfs.fileId(path), Some(id))
        @Expect(vfs.filePath(id), path)
        @Expect(vfs.fileContents(id).getOrThrow().toString(), "y")
    }

    @TestCase
    func settingWhatAFileHoldsAlreadyChangesNothing() {
        // arrange
        let vfs = Vfs()
        let path = inTemp("a.cj")
        vfs.setFileContents(path, Rope("x"))
        vfs.takeChanges()

        // act
        let changed = vfs.setFileContents(path, Rope("x"))

        // assert
        @Expect(!changed)
        @Expect(vfs.takeChanges().size, 0)
    }

    @TestCase
    func changesAreFoldedIntoWhatTheyAmountTo() {
        // arrange
        let vfs = Vfs()
        let (a, b, c, d) = (inTemp("a"), inTemp("b"), inTemp("c"), inTemp("d"))
        vfs.setFileContents(c, Rope("c"))
        vfs.setFileContents(d, Rope("d"))
        vfs.takeChanges()

        // act
        vfs.setFileContents(a, Rope("1"))
        vfs.setFileContents(a, Rope("2"))
        vfs.setFileContents(b, Rope("1"))
        vfs.setFileContents(b, None)
        vfs.setFileContents(c, None)
        vfs.setFileContents(c, Rope("c2"))
        vfs.setFileContents(d, Rope("d2"))
        vfs.setFileContents(d, None)
        vfs.setFileContents(b, Rope("again"))

        // assert
        @Expect(kinds(vfs.takeChanges()), ["Create(FileId(2))", "Modify(FileId(0))", "Delete(FileId(1))", "Create(FileId(3))"])
        @Expect(vfs.takeChanges().size, 0)
    }
}

@Test
class PathInternerTest {
    @TestCase
    func idsAreGivenInTheOrderPathsAreFirstSeen() {
        // arrange
        let interner = PathInterner()
        let (a, b) = (inTemp("a.cj"), inTemp("b.cj"))

        // act
        let ids = [interner.intern(a), interner.intern(b), interner.intern(a)]

        // assert
        @Expect(ids, [FileId(0), FileId(1), FileId(0)])
        @Expect(interner.lookup(b), Some(FileId(1)))
        @Expect(interner.path(FileId(1)), b)
        @Expect(interner.lookup(inTemp("c.cj")), None<FileId>)
    }

    @TestCase
    func threadsInterningThePathsAtOnceAgreeOnTheirIds() {
        // arrange
        let interner = PathInterner()
        let paths = Array(100) {i => inTemp("${i}.cj")}

        // act
        let seen = Array(8) {
            reader => spawn {
                Array(paths.size) {i => interner.intern(paths[(i + reader * 13) % paths.size])}
            }
        }.map {reader => reader.get()}

        // assert
        let ids = paths.map {path => interner.lookup(path).getOrThrow()}
        @Expect(HashSet(ids.map {id => id.index}), HashSet(Array(paths.size) {i => i}))
        @Expect(ids.map {id => interner.path(id)}, paths)
        for (reader in 0..seen.size) {
            @Expect(seen[reader], Array(paths.size) {i => ids[(i + reader * 13) % paths.size]})
        }
    }

    @TestCase
    func aPathIsOnlyForAnIdGiven() {
        // arrange
        let interner = PathInterner()
        interner.intern(inTemp("a.cj"))

        // act, assert
        @AssertThrows[IndexOutOfBoundsException](interner.path(FileId(1)))
    }
}
