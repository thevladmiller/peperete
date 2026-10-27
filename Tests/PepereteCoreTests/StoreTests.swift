import XCTest
@testable import PepereteCore

final class StoreTests: XCTestCase {
    func temporaryStore() throws -> Store {
        Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent("Peperete-test-\(UUID().uuidString)"))
    }
    func testImportIsIdempotentAndPreservesLocalEdits() throws {
        let store = try temporaryStore()
        var source = Database(); let board = source.addBoard(title: "Work")
        source.cards.append(Card(id: "trello-card", columnID: source.columns(in: board.id)[0].id, title: "Original"))
        let first = source
        try store.update { _ = try $0.merge(first) }
        try store.update { $0.cards[0].title = "Edited locally" }
        let count = try store.update { try $0.merge(first) }
        XCTAssertEqual(count, 0)
        XCTAssertEqual(try store.read().cards[0].title, "Edited locally")
        XCTAssertEqual(try store.read().cards.count, 1)
    }
    func testTwoStoresNeverSaveStaleSnapshots() throws {
        let first = try temporaryStore(), second = Store(directory: first.directory)
        try first.update { _ = $0.addBoard(title: "First") }
        _ = try second.read()
        try first.update { _ = $0.addBoard(title: "Second") }
        try second.update { _ = $0.addBoard(title: "Third") }
        XCTAssertEqual(try first.read().boards.map(\.title), ["First", "Second", "Third"])
    }
    func testMoveReordersAndChangesParentWithoutDuplicates() throws {
        var db = Database(); let board = db.addBoard(title: "Test"), columns = db.columns(in: board.id)
        db.cards = [Card(id: "a", columnID: columns[0].id, title: "A"), Card(id: "b", columnID: columns[1].id, title: "B")]
        try db.move(cardID: "a", to: columns[1].id, before: "b")
        XCTAssertEqual(db.cards(in: columns[1].id).map(\.id), ["a", "b"])
        XCTAssertTrue(db.cards(in: columns[0].id).isEmpty)
        XCTAssertEqual(db.cards.count, 2)
    }
    func testInvalidUpdateDoesNotDamageStoredData() throws {
        let store = try temporaryStore()
        try store.update { _ = $0.addBoard(title: "Valid") }
        XCTAssertThrowsError(try store.update { $0.cards.append(Card(columnID: "missing", title: "Broken")) })
        XCTAssertTrue(try store.read().cards.isEmpty)
        XCTAssertEqual(try store.read().revision, 1)
    }
    func testCorruptFileIsNotSilentlyReplaced() throws {
        let store = try temporaryStore(); _ = try store.read()
        try Data("broken".utf8).write(to: store.file)
        XCTAssertThrowsError(try store.update { _ = $0.addBoard(title: "Lost") })
        XCTAssertEqual(try String(contentsOf: store.file, encoding: .utf8), "broken")
    }
    func testBackupAndExportRoundTripPreserveContent() throws {
        let store = try temporaryStore()
        try store.update { db in
            let board = db.addBoard(title: "Work")
            db.cards.append(Card(columnID: db.columns(in: board.id)[0].id, title: "日本語 & café", notes: "Notes\nSecond line", due: Date(timeIntervalSince1970: 1_800_000_000)))
        }
        try store.update { $0.cards[0].completed = true }
        let backups = try FileManager.default.contentsOfDirectory(atPath: store.directory.appendingPathComponent("Backups").path)
        XCTAssertEqual(backups.count, 1)
        let export = store.directory.appendingPathComponent("export.json"); try store.export(to: export)
        let other = try temporaryStore(); try other.importFile(export)
        XCTAssertEqual(try store.read().cards, try other.read().cards)
    }
    func testWidgetQueueExcludesCompleteAndArchived() throws {
        var db = Database(); let b = db.addBoard(title: "Test"), c = db.columns(in: b.id)[0].id
        db.cards = [Card(columnID: c, title: "Done", completed: true), Card(columnID: c, title: "Archived", archived: true), Card(columnID: c, title: "Later"), Card(columnID: c, title: "Due", due: .distantPast)]
        XCTAssertEqual(db.upcoming.map(\.title), ["Due", "Later"])
    }
}
