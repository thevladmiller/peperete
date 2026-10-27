import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import WidgetKit
#if canImport(PepereteCore)
import PepereteCore
#endif

@MainActor @Observable final class BoardModel {
    var database = Database()
    var error: String?
    let store = Store()
    init() { reload() }
    func reload() {
        do { let value = try store.read(); if database != value { database = value } }
        catch { self.error = error.localizedDescription }
    }
    func change(_ mutation: (inout Database) throws -> Void) {
        do { try store.update(mutation); reload(); WidgetCenter.shared.reloadAllTimelines() }
        catch { self.error = error.localizedDescription }
    }
    func importBoards() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.message = "Add boards from a Peperete JSON export. Existing cards are kept."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.importFile(url); reload(); WidgetCenter.shared.reloadAllTimelines() }
        catch { self.error = error.localizedDescription }
    }
    func exportBoards() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Peperete.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.export(to: url) } catch { self.error = error.localizedDescription }
    }
}

@main struct PepereteApp: App {
    @State private var model = BoardModel()
    var body: some Scene {
        WindowGroup {
            BoardView(model: model)
                .frame(minWidth: 880, minHeight: 600)
                .tint(.orange)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import boards…", action: model.importBoards)
                Button("Export boards…", action: model.exportBoards)
            }
        }
    }
}

struct BoardView: View {
    @Bindable var model: BoardModel
    @State private var selection: String?
    @State private var search = ""
    @State private var archived = false
    @State private var editing: Card?
    @State private var newBoard = false
    @State private var newColumn = false
    @State private var name = ""
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private var current: Board? { model.database.boards.first { $0.id == selection } ?? model.database.boards.first }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up.fill").font(.title2).foregroundStyle(.orange)
                    Text("peperete").font(.system(size: 24, weight: .bold, design: .rounded))
                }.padding(.top, 18).padding(.horizontal, 16)
                Text("A LITTLE ROOM TO GET THINGS DONE")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 16)
                List(selection: $selection) {
                    Section("Your boards") {
                        ForEach(model.database.boards) { board in
                            Label(board.title, systemImage: "rectangle.split.3x1").tag(board.id)
                                .padding(.vertical, 5)
                        }
                    }
                }.listStyle(.sidebar)
                Button { name = ""; newBoard = true } label: { Label("New board", systemImage: "plus") }
                    .buttonStyle(.plain).padding(.horizontal, 16)
                Divider()
                HStack {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("Stored on this Mac").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Button("Import boards…", action: model.importBoards)
                        Button("Export boards…", action: model.exportBoards)
                        Button("Show data folder") { NSWorkspace.shared.open(model.store.directory) }
                    } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 24)
                }.padding(16)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            if let board = current {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(board.title).font(.system(size: 28, weight: .bold, design: .rounded))
                            let items = model.database.columns(in: board.id).flatMap { model.database.cards(in: $0.id) }
                            Text("\(items.filter { !$0.completed }.count) open · \(items.filter(\.completed).count) completed")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle(isOn: $archived) { Image(systemName: "archivebox") }.toggleStyle(.button).help("Show archived cards")
                        Button { name = ""; newColumn = true } label: { Label("Column", systemImage: "plus") }
                    }.padding(28)
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Find a card…", text: $search).textFieldStyle(.plain)
                        if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                    }.padding(10).background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 28).padding(.bottom, 22)
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 18) {
                            ForEach(model.database.columns(in: board.id)) { column in
                                columnView(column)
                            }
                        }.padding(.horizontal, 28).padding(.bottom, 24)
                    }
                }
                .background(Color(red: 0.97, green: 0.96, blue: 0.94))
            } else {
                ContentUnavailableView {
                    Label("Your space, your pace", systemImage: "rectangle.split.3x1")
                } description: { Text("Start with a board, or import your existing work.") }
                actions: {
                    Button("Create a board") { name = ""; newBoard = true }
                    Button("Import boards…", action: model.importBoards)
                }
            }
        }
        .preferredColorScheme(.light)
        .sheet(item: $editing) { card in CardEditor(model: model, draft: card) }
        .alert("New board", isPresented: $newBoard) {
            TextField("Board name", text: $name)
            Button("Create") { model.change { _ = $0.addBoard(title: name.trimmingCharacters(in: .whitespacesAndNewlines)) }; selection = model.database.boards.last?.id }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        .alert("New column", isPresented: $newColumn) {
            TextField("Column name", text: $name)
            Button("Create") {
                guard let board = current else { return }
                model.change { db in db.columns.append(Column(boardID: board.id, title: name.trimmingCharacters(in: .whitespacesAndNewlines), position: (db.columns(in: board.id).last?.position ?? -1) + 1)) }
            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn’t save", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onReceive(timer) { _ in model.reload() }
        .onOpenURL { url in
            guard url.scheme == "peperete", url.host == "card" else { return }
            let id = url.lastPathComponent
            if let card = model.database.cards.first(where: { $0.id == id }) {
                selection = model.database.columns.first(where: { $0.id == card.columnID })?.boardID; editing = card
            }
        }
    }
    private func matching(_ column: Column) -> [Card] {
        model.database.cards(in: column.id, includeArchived: archived).filter {
            (!archived || $0.archived) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.notes.localizedCaseInsensitiveContains(search))
        }
    }
    private func move(_ ids: [String], to column: Column, before: String? = nil) -> Bool {
        guard let id = ids.first, model.database.cards.contains(where: { $0.id == id }) else { return false }
        model.change { try $0.move(cardID: id, to: column.id, before: before) }; return true
    }
    private func columnView(_ column: Column) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(column.title.lowercased() == "done" ? .green : .orange.opacity(0.65)).frame(width: 7, height: 7)
                Text(column.title).font(.system(size: 13, weight: .semibold))
                Text("\(matching(column).count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { editing = Card(columnID: column.id, title: "", position: (model.database.cards(in: column.id).last?.position ?? -1) + 1) } label: { Image(systemName: "plus") }.buttonStyle(.plain).help("Add card")
            }.padding(.horizontal, 4)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(matching(column)) { card in
                        Button { editing = card } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: card.completed ? "checkmark.circle.fill" : "circle").foregroundStyle(card.completed ? .green : .secondary)
                                    Text(card.title).font(.system(size: 13, weight: .medium)).strikethrough(card.completed).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                                }
                                if let due = card.due {
                                    Label(due.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                                        .font(.caption2).foregroundStyle(due < Date() && !card.completed ? .red : .secondary)
                                }
                                if !card.notes.isEmpty {
                                    Text(card.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                                }
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black.opacity(0.055)))
                        }.buttonStyle(.plain)
                            .draggable(card.id)
                            .dropDestination(for: String.self) { ids, _ in move(ids, to: column, before: card.id) }
                            .contextMenu {
                                Button(card.completed ? "Mark incomplete" : "Mark complete") { model.change { db in if let i = db.cards.firstIndex(where: { $0.id == card.id }) { db.cards[i].completed.toggle(); db.cards[i].updatedAt = Date() } } }
                                Menu("Move to") { ForEach(model.database.columns) { destination in Button(destination.title) { _ = move([card.id], to: destination) } } }
                                Button(card.archived ? "Restore" : "Archive") { model.change { db in if let i = db.cards.firstIndex(where: { $0.id == card.id }) { db.cards[i].archived.toggle(); db.cards[i].updatedAt = Date() } } }
                            }
                    }
                    if matching(column).isEmpty { Text("Drop a card here").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, minHeight: 80).background(.black.opacity(0.025), in: RoundedRectangle(cornerRadius: 12)) }
                    Color.clear.frame(height: 25)
                }.padding(2)
            }
            Button { editing = Card(columnID: column.id, title: "", position: (model.database.cards(in: column.id).last?.position ?? -1) + 1) } label: { Label("Add card", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain).foregroundStyle(.secondary).padding(5)
        }.frame(width: 270).frame(maxHeight: .infinity)
            .contentShape(Rectangle()).dropDestination(for: String.self) { ids, _ in move(ids, to: column) }
    }
}

struct CardEditor: View {
    @Bindable var model: BoardModel
    @State var draft: Card
    @Environment(\.dismiss) private var dismiss
    @State private var hasDue = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(model.database.cards.contains(where: { $0.id == draft.id }) ? "Edit card" : "New card").font(.headline)
                Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            TextField("What needs doing?", text: $draft.title).font(.title2).textFieldStyle(.plain)
            HStack {
                Picker("Column", selection: $draft.columnID) { ForEach(model.database.columns) { column in Text(column.title).tag(column.id) } }.frame(maxWidth: 300)
                Toggle("Complete", isOn: $draft.completed)
            }
            Divider()
            Text("Notes").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $draft.notes).font(.system(size: 13)).frame(minHeight: 240)
                .padding(6).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            HStack {
                Toggle("Due date", isOn: $hasDue)
                if hasDue { DatePicker("", selection: Binding(get: { draft.due ?? Date() }, set: { draft.due = $0 })).labelsHidden() }
                Spacer()
                Toggle("Archived", isOn: $draft.archived)
            }
            if let source = draft.sourceURL, let url = URL(string: source) { Link("Original Trello card ↗", destination: url).font(.caption) }
        }.padding(24).frame(width: 640).onAppear { hasDue = draft.due != nil }
    }
    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.due = hasDue ? (draft.due ?? Date()) : nil; draft.updatedAt = Date()
        model.change { db in
            if let i = db.cards.firstIndex(where: { $0.id == draft.id }) { db.cards[i] = draft }
            else { db.cards.append(draft) }
        }
        if model.error == nil { dismiss() }
    }
}
