import Foundation
import PepereteCore

let usage = """
peperete — your local board
Usage: peperete COMMAND [arguments]
  doctor                               Show data location and counts
  boards                               List boards
  columns BOARD_ID                     List columns in board order
  cards [BOARD_ID]                      List cards, including archived
  search TEXT                          Find cards by title or notes
  get CARD_ID                          Read one card
  board-add TITLE                      Create board with To do / Doing / Done
  column-add BOARD_ID TITLE             Add column
  create COLUMN_ID TITLE               Create card
  update CARD_ID TITLE NOTES            Update title and notes
  due CARD_ID ISO8601|none              Set or clear due date
  move CARD_ID COLUMN_ID [BEFORE_ID]     Move/reorder card
  complete CARD_ID true|false           Mark complete/incomplete
  archive CARD_ID true|false            Archive/restore card
  import FILE                          Add missing IDs from Peperete export
  export FILE                          Export full database
  dump                                 Read full database as JSON
All output is JSON. PEPERETE_DATA_DIR overrides the data directory.
Writes use file locking and create a backup first. No network or authentication.
"""

func output<T: Encodable>(_ value: T) throws {
    print(String(decoding: try Store.encoder().encode(value), as: UTF8.self))
}
func run() throws {
    let args = Array(CommandLine.arguments.dropFirst()).filter { $0 != "--json" }
    guard let command = args.first, command != "--help", command != "help" else { print(usage); return }
    func arg(_ i: Int) throws -> String {
        guard args.count > i else { throw StoreError.invalid("Missing argument. Run peperete --help.") }; return args[i]
    }
    func boolean(_ i: Int) throws -> Bool {
        let value = try arg(i); guard ["true", "false"].contains(value) else { throw StoreError.invalid("Use true or false.") }; return value == "true"
    }
    let store = Store()
    func modify(_ mutation: (inout Card) throws -> Void) throws {
        let id = try arg(1)
        let result = try store.update { db -> Card in
            guard let i = db.cards.firstIndex(where: { $0.id == id }) else { throw StoreError.invalid("Card not found.") }
            try mutation(&db.cards[i]); db.cards[i].updatedAt = Date(); return db.cards[i]
        }
        try output(result)
    }
    switch command {
    case "doctor":
        let db = try store.read()
        try output(["status": "ok", "dataFile": store.file.path, "boards": String(db.boards.count), "cards": String(db.cards.count), "auth": "not required", "network": "offline"])
    case "boards": try output(store.read().boards)
    case "columns": try output(store.read().columns(in: arg(1)))
    case "cards":
        let db = try store.read(), board = args.count > 1 ? args[1] : nil
        let columnIDs = Set(db.columns.filter { board == nil || $0.boardID == board }.map(\.id))
        try output(db.cards.filter { columnIDs.contains($0.columnID) })
    case "search":
        let needle = try arg(1), db = try store.read()
        try output(db.cards.filter { $0.title.localizedCaseInsensitiveContains(needle) || $0.notes.localizedCaseInsensitiveContains(needle) })
    case "get":
        let id = try arg(1)
        guard let card = try store.read().cards.first(where: { $0.id == id }) else { throw StoreError.invalid("Card not found.") }
        try output(card)
    case "dump": try output(store.read())
    case "board-add":
        let title = try arg(1); try output(store.update { $0.addBoard(title: title) })
    case "column-add":
        let boardID = try arg(1), title = try arg(2)
        try output(store.update { db -> Column in
            guard db.boards.contains(where: { $0.id == boardID }) else { throw StoreError.invalid("Board not found.") }
            let column = Column(boardID: boardID, title: title, position: (db.columns(in: boardID).last?.position ?? -1) + 1)
            db.columns.append(column); return column
        })
    case "create":
        let columnID = try arg(1), title = try arg(2)
        try output(store.update { db -> Card in
            guard db.columns.contains(where: { $0.id == columnID }) else { throw StoreError.invalid("Column not found.") }
            let card = Card(columnID: columnID, title: title, position: (db.cards(in: columnID).last?.position ?? -1) + 1)
            db.cards.append(card); return card
        })
    case "update":
        let title = try arg(2), notes = try arg(3); try modify { $0.title = title; $0.notes = notes }
    case "complete": let value = try boolean(2); try modify { $0.completed = value }
    case "archive": let value = try boolean(2); try modify { $0.archived = value }
    case "due":
        let value = try arg(2)
        let date = ISO8601DateFormatter().date(from: value)
        guard value == "none" || date != nil else { throw StoreError.invalid("Use ISO8601, e.g. 2026-11-01T09:00:00Z, or none.") }
        try modify { $0.due = date }
    case "move":
        let id = try arg(1), columnID = try arg(2), before = args.count > 3 ? args[3] : nil
        try store.update { try $0.move(cardID: id, to: columnID, before: before) }; try output(["moved": id, "columnID": columnID])
    case "export": let path = try arg(1); try store.export(to: URL(fileURLWithPath: path)); try output(["exported": path])
    case "import": let path = try arg(1); try output(["importedCards": store.importFile(URL(fileURLWithPath: path))])
    default: throw StoreError.invalid("Unknown command: \(command). Run peperete --help.")
    }
}
do { try run() } catch {
    let data = (try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription], options: [.sortedKeys])) ?? Data()
    FileHandle.standardError.write(data); FileHandle.standardError.write(Data("\n".utf8)); exit(1)
}
