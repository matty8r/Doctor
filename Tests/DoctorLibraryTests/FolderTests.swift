import XCTest
import SwiftData
@testable import DoctorLibrary

@MainActor
final class FolderTests: XCTestCase {
    private func makeContext() -> ModelContext {
        ModelContext(Persistence.makeInMemoryContainer())
    }

    func testMoveIntoOwnDescendantIsRefused() {
        let context = makeContext()
        let a = Folder(name: "A"), b = Folder(name: "B", parent: a), c = Folder(name: "C", parent: b)
        [a, b, c].forEach(context.insert)

        XCTAssertFalse(a.move(to: c), "A can't move beneath its own grandchild")
        XCTAssertFalse(a.move(to: a), "A can't move into itself")
        XCTAssertNil(a.parent)
        XCTAssertTrue(c.move(to: nil))
        XCTAssertNil(c.parent)
    }

    func testDeletingAFolderRefilesItsContentsIntoTheParent() throws {
        let context = makeContext()
        let outer = Folder(name: "Outer"), inner = Folder(name: "Inner", parent: outer)
        let note = Document(title: "Note", body: "x", folder: inner)
        let sub = Folder(name: "Sub", parent: inner)
        [outer, inner, sub].forEach(context.insert)
        context.insert(note)
        try context.save()

        inner.delete(in: context)
        try context.save()

        XCTAssertTrue(note.folder === outer, "the note moves up, it isn't deleted or sent to the root")
        XCTAssertTrue(sub.parent === outer)
        let remaining = try context.fetch(FetchDescriptor<Document>())
        XCTAssertEqual(remaining.count, 1)
    }

    func testDeletingARootFolderMovesContentsToTheRoot() throws {
        let context = makeContext()
        let folder = Folder(name: "Top")
        let note = Document(title: "Note", folder: folder)
        context.insert(folder); context.insert(note)
        try context.save()

        folder.delete(in: context)
        try context.save()

        XCTAssertNil(note.folder)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Document>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Folder>()), 0)
    }

    func testSortedChildrenAreAlphabeticalAndDocumentsNewestFirst() {
        let context = makeContext()
        let root = Folder(name: "Root")
        let b = Folder(name: "b", parent: root), a = Folder(name: "A", parent: root)
        let old = Document(title: "old", folder: root), new = Document(title: "new", folder: root)
        old.modifiedAt = Date(timeIntervalSince1970: 100)
        new.modifiedAt = Date(timeIntervalSince1970: 200)
        [root, a, b].forEach(context.insert); context.insert(old); context.insert(new)

        XCTAssertEqual(root.sortedChildren.map(\.name), ["A", "b"])
        XCTAssertEqual(root.sortedDocuments.map(\.title), ["new", "old"])
    }
}
