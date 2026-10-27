import WidgetKit
import SwiftUI
import AppIntents

struct BoardEntry: TimelineEntry {
    let date: Date
    let cards: [Card]
    let openCount: Int
    let problem: String?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> BoardEntry {
        BoardEntry(date: .now, cards: [Card(id: "preview", columnID: "", title: "Your next small step", due: .now)], openCount: 1, problem: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (BoardEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BoardEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(900))))
    }
    private func entry() -> BoardEntry {
        do {
            let db = try Store().read()
            return BoardEntry(date: .now, cards: Array(db.upcoming.prefix(5)), openCount: db.upcoming.count, problem: nil)
        } catch { return BoardEntry(date: .now, cards: [], openCount: 0, problem: "Open Peperete to check your data.") }
    }
}

struct CompleteCardIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete card"
    @Parameter(title: "Card ID") var cardID: String
    init() {}
    init(cardID: String) { self.cardID = cardID }
    func perform() async throws -> some IntentResult {
        try Store().update { db in
            guard let i = db.cards.firstIndex(where: { $0.id == cardID }) else { return }
            db.cards[i].completed = true; db.cards[i].updatedAt = .now
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct PepereteWidgetView: View {
    let entry: BoardEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(.orange)
                Text("peperete").font(.system(.headline, design: .rounded))
                Spacer()
                Text("\(entry.openCount)").font(.caption).foregroundStyle(.secondary)
            }
            if let problem = entry.problem { Text(problem).font(.caption).foregroundStyle(.secondary) }
            else if entry.cards.isEmpty { Text("A little breathing room.").font(.subheadline).foregroundStyle(.secondary) }
            else {
                ForEach(Array(entry.cards.prefix(family == .systemSmall ? 2 : family == .systemMedium ? 3 : 5))) { card in
                    HStack(alignment: .top, spacing: 8) {
                        Button(intent: CompleteCardIntent(cardID: card.id)) { Image(systemName: "circle").foregroundStyle(.orange) }.buttonStyle(.plain)
                        Link(destination: URL(string: "peperete://card/\(card.id)")!) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(card.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                if let due = card.due { Text(due, style: .date).font(.system(size: 10)).foregroundStyle(due < entry.date ? .red : .secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .containerBackground(Color(red: 0.98, green: 0.97, blue: 0.95), for: .widget)
        .widgetURL(URL(string: "peperete://boards"))
    }
}

@main struct PepereteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PepereteUpcoming", provider: Provider()) { PepereteWidgetView(entry: $0) }
            .configurationDisplayName("Your next cards")
            .description("Upcoming and overdue work, with a tap to complete.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
