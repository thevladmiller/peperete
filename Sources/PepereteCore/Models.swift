import Foundation

public struct Board: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var documentation: BoardDocumentation?
    public init(id: String = UUID().uuidString, title: String, documentation: BoardDocumentation? = nil) {
        self.id = id; self.title = title; self.documentation = documentation
    }
}

public struct BoardDocumentation: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var folderPath: String
    public var fileName: String
    public var notebookName: String
    public var notebookURL: String?
    public init(enabled: Bool = true, folderPath: String, fileName: String, notebookName: String, notebookURL: String? = nil) {
        self.enabled = enabled; self.folderPath = folderPath; self.fileName = fileName
        self.notebookName = notebookName; self.notebookURL = notebookURL
    }
}

public struct Activity: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var boardID: String
    public var cardID: String?
    public var summary: String
    public var occurredAt: Date
    public init(id: String = UUID().uuidString, boardID: String, cardID: String? = nil, summary: String, occurredAt: Date = Date()) {
        self.id = id; self.boardID = boardID; self.cardID = cardID; self.summary = summary; self.occurredAt = occurredAt
    }
}

public struct Column: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var boardID: String
    public var title: String
    public var position: Double
    public init(id: String = UUID().uuidString, boardID: String, title: String, position: Double) {
        self.id = id; self.boardID = boardID; self.title = title; self.position = position
    }
}

public struct Card: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var columnID: String
    public var title: String
    public var notes: String
    public var due: Date?
    public var completed: Bool
    public var archived: Bool
    public var position: Double
    public var sourceURL: String?
    public var updatedAt: Date
    public init(id: String = UUID().uuidString, columnID: String, title: String, notes: String = "", due: Date? = nil,
                completed: Bool = false, archived: Bool = false, position: Double = 0, sourceURL: String? = nil,
                updatedAt: Date = Date()) {
        self.id = id; self.columnID = columnID; self.title = title; self.notes = notes; self.due = due
        self.completed = completed; self.archived = archived; self.position = position
        self.sourceURL = sourceURL; self.updatedAt = updatedAt
    }
}

public struct Database: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var revision = 0
    public var boards: [Board] = []
    public var columns: [Column] = []
    public var cards: [Card] = []
    public var activities: [Activity]?
    public init() {}
    public func columns(in boardID: String) -> [Column] {
        columns.filter { $0.boardID == boardID }.sorted { $0.position < $1.position }
    }
    public func cards(in columnID: String, includeArchived: Bool = false) -> [Card] {
        cards.filter { $0.columnID == columnID && (includeArchived || !$0.archived) }.sorted { $0.position < $1.position }
    }
    public func validate() throws {
        guard schemaVersion == 1 else { throw StoreError.invalid("This file needs a newer version of Peperete.") }
        guard Set(boards.map(\.id)).count == boards.count, Set(columns.map(\.id)).count == columns.count,
              Set(cards.map(\.id)).count == cards.count else { throw StoreError.invalid("Duplicate IDs in file.") }
        let boardIDs = Set(boards.map(\.id)), columnIDs = Set(columns.map(\.id))
        guard columns.allSatisfy({ boardIDs.contains($0.boardID) }), cards.allSatisfy({ columnIDs.contains($0.columnID) })
        else { throw StoreError.invalid("A card or column has a missing parent.") }
        guard (activities ?? []).allSatisfy({ boardIDs.contains($0.boardID) })
        else { throw StoreError.invalid("An activity has a missing board.") }
        guard boards.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              columns.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.position.isFinite }),
              cards.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.position.isFinite })
        else { throw StoreError.invalid("Titles cannot be empty and positions must be finite.") }
    }
    public var activityLog: [Activity] { activities ?? [] }
    @discardableResult public mutating func addBoard(title: String) -> Board {
        let board = Board(title: title); boards.append(board)
        for (i, name) in ["To do", "Doing", "Done"].enumerated() {
            columns.append(Column(boardID: board.id, title: name, position: Double(i)))
        }
        return board
    }
    public mutating func move(cardID: String, to columnID: String, before targetID: String? = nil) throws {
        guard let index = cards.firstIndex(where: { $0.id == cardID }), columns.contains(where: { $0.id == columnID })
        else { throw StoreError.invalid("Card or destination column not found.") }
        var siblings = self.cards(in: columnID).filter { $0.id != cardID }
        var card = cards[index]; card.columnID = columnID; card.updatedAt = Date()
        let insertion = targetID.flatMap { target in siblings.firstIndex { $0.id == target } } ?? siblings.count
        siblings.insert(card, at: insertion)
        for (i, var item) in siblings.enumerated() {
            item.position = Double(i)
            if let destination = cards.firstIndex(where: { $0.id == item.id }) { cards[destination] = item }
        }
    }
    public mutating func merge(_ other: Database) throws -> Int {
        try other.validate()
        // Import only new IDs: re-import never overwrites edits made in Peperete.
        let existingBoards = Set(boards.map(\.id)), existingColumns = Set(columns.map(\.id)), existingCards = Set(cards.map(\.id))
        boards += other.boards.filter { !existingBoards.contains($0.id) }
        columns += other.columns.filter { !existingColumns.contains($0.id) }
        let additions = other.cards.filter { !existingCards.contains($0.id) }
        cards += additions
        return additions.count
    }
    public var upcoming: [Card] {
        cards.filter { !$0.completed && !$0.archived }.sorted {
            if $0.due != $1.due { return ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            return $0.updatedAt > $1.updatedAt
        }
    }
}

public enum StoreError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let message): message } }
}
