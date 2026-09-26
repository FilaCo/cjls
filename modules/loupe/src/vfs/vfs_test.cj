package loupe.vfs

import std.unittest.*
import std.unittest.testmacro.*
import rope.Rope

func kinds(changes: Array<ChangedFile>): Array<String> {
    changes.map {change => change.toString()}
}

@Test
class VfsPathTest {
    @TestCase
    func aFileUriIsItsDecodedPath() {
        // act
        let path = VfsPath.fromUri("file:///home/me/%D0%BF%D1%80%D0%BE%D0%B5%D0%BA%D1%82/a%20b.cj")

        // assert
        @Expect(path.filePath, Some("/home/me/проект/a b.cj"))
    }

    @TestCase
    func urisSpellingOnePathApartAreOnePath() {
        // act, assert
        @Expect(VfsPath.fromUri("file:///a/./b/../c.cj"), VfsPath.fromUri("file://localhost/a/%63.cj"))
        @Expect(VfsPath.file("//a///c.cj"), VfsPath.file("/a/c.cj"))
    }

    @TestCase
    func aUriNotOfAFileIsVirtual() {
        // act
        let path = VfsPath.fromUri("untitled:Untitled-1")

        // assert
        @Expect(path.filePath, None<String>)
        @Expect(path.toUri(), "untitled:Untitled-1")
        @Expect(path != VfsPath.file("/untitled:Untitled-1"))
    }

    @TestCase
    func aPathGoesBackToAUriEscaped() {
        // act, assert
        @Expect(VfsPath.file("/home/проект/a b.cj").toUri(), "file:///home/%D0%BF%D1%80%D0%BE%D0%B5%D0%BA%D1%82/a%20b.cj")
        @Expect(VfsPath.fromUri(VfsPath.file("/x/y#z?.cj").toUri()), VfsPath.file("/x/y#z?.cj"))
    }

    @TestCase
    func aMalformedEscapeLeavesTheUriVirtual() {
        // act, assert
        @Expect(VfsPath.fromUri("file:///a%2").filePath, None<String>)
        @Expect(VfsPath.fromUri("file:///a%FF").filePath, None<String>)
    }

    @TestCase
    func aDrivePathIsAbsoluteAsWindowsSpellsIt() {
        // act
        let path = VfsPath.file("C:\\src\\.\\app\\..\\a.cj")

        // assert
        @Expect(path.filePath, Some("c:/src/a.cj"))
        @Expect(VfsPath.file("c:"), VfsPath.file("C:\\"))
        @AssertThrows[IllegalArgumentException](VfsPath.file("C:a.cj"))
    }

    @TestCase
    func clientsSpellingOneDriveApartGiveOnePath() {
        // arrange
        let vsCode = "file:///c%3A/Users/Me/a.cj"
        let neovim = "file:///C:/Users/Me/a.cj"

        // act, assert
        @Expect(VfsPath.fromUri(vsCode), VfsPath.fromUri(neovim))
        @Expect(VfsPath.fromUri(neovim).filePath, Some("c:/Users/Me/a.cj"))
        @Expect(VfsPath.fromUri(neovim) != VfsPath.fromUri("file:///C:/users/me/a.cj"))
    }

    @TestCase
    func aDrivePathGoesBackToAUriWithTheDriveAsItsFirstSegment() {
        // act
        let uri = VfsPath.file("C:\\Users\\Me\\a b.cj").toUri()

        // assert
        @Expect(uri, "file:///c:/Users/Me/a%20b.cj")
        @Expect(VfsPath.fromUri(uri), VfsPath.fromUri("file:///c%3A/Users/Me/a%20b.cj"))
    }
}

@Test
class VfsTest {
    @TestCase
    func aFileKeepsItsIdForGood() {
        // arrange
        let vfs = Vfs()
        let path = VfsPath.file("/a.cj")
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
        let path = VfsPath.file("/a.cj")
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
        let (a, b, c, d) = (VfsPath.file("/a"), VfsPath.file("/b"), VfsPath.file("/c"), VfsPath.file("/d"))
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
