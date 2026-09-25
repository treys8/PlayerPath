//
//  JournalUpNextStrip.swift
//  PlayerPath
//
//  The Journal's "Up Next" strip: the next few scheduled games/practices,
//  soonest first. Scheduled events used to sit in the feed itself, sorted
//  newest-first — so a pre-loaded season schedule put the LAST game of the
//  season at the top of Home and buried everything the athlete had actually
//  done. The feed is a record of what happened; what's coming lives here.
//

import SwiftUI

/// One scheduled item in the strip.
enum JournalUpcomingItem: Identifiable {
    case game(Game)
    case practice(Practice)

    var id: String {
        switch self {
        case .game(let g):     return "upcoming-game-\(g.id.uuidString)"
        case .practice(let p): return "upcoming-practice-\(p.id.uuidString)"
        }
    }

    /// Always non-nil in practice — `JournalUpcoming.isScheduled` requires a date.
    var date: Date {
        switch self {
        case .game(let g):     return g.date ?? .distantFuture
        case .practice(let p): return p.date ?? .distantFuture
        }
    }
}

/// The single rule for "scheduled" on the Journal. The feed EXCLUDES exactly
/// what the strip INCLUDES, so an item can never show in both or neither.
enum JournalUpcoming {
    /// Not live, not finished, and either dated later than `now`, or dated
    /// today and still untouched.
    ///
    /// Deliberately NOT `Game.displayStatus == .scheduled`: that also calls a
    /// nil-date game "scheduled", and such a game belongs in the feed (sorted by
    /// createdAt), not in a strip ordered by a date it doesn't have.
    static func isScheduled(_ game: Game, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !game.isLive, !game.isComplete, let date = game.date else { return false }
        if date > now { return true }
        // Past its start time today but never started or touched: the athlete is
        // probably running late, so keep the Start button up until midnight
        // instead of dropping an empty card into the feed. Anything with media,
        // entered stats, or a golf score was logged after the fact and belongs in
        // the feed. (Every game gets a GameStatistics at creation, so "has stats"
        // is `countsTowardStats`, not `gameStats != nil`.)
        return calendar.isDate(date, inSameDayAs: now)
            && (game.videoClips ?? []).isEmpty
            && (game.photos ?? []).isEmpty
            && !game.countsTowardStats
            && game.effectiveTotalScore == nil
    }

    /// Practices have no completed flag, and are often logged the same day
    /// after the fact — so only a strictly future-dated one counts as scheduled.
    static func isScheduled(_ practice: Practice, now: Date = .now) -> Bool {
        !practice.isLive && (practice.date ?? .distantPast) > now
    }

    /// Every scheduled game/practice, soonest first. The id breaks date ties so
    /// the order can't shuffle between renders (Swift's sort isn't stable).
    static func items(games: [Game], practices: [Practice], now: Date = .now) -> [JournalUpcomingItem] {
        let scheduled = games.filter { isScheduled($0, now: now) }.map(JournalUpcomingItem.game)
            + practices.filter { isScheduled($0, now: now) }.map(JournalUpcomingItem.practice)
        return scheduled.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
}

struct JournalUpNextStrip: View {
    /// Already sorted soonest-first (`JournalUpcoming.items`).
    let items: [JournalUpcomingItem]
    /// The profile's pinned sport. A seasonless game can't answer `isGolf`
    /// itself, so the Start label falls back to this.
    let isGolfProfile: Bool
    let onStart: (Game) -> Void

    @Environment(\.ppAccent) private var ppAccent

    /// Enough to see what's next without the strip turning back into the flood
    /// it replaced. The full schedule lives on the Games tab.
    private static let visibleLimit = 3

    var body: some View {
        VStack(spacing: .spacingMedium) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                Text("Up Next").smallCapsLabel()
                Spacer()
                if items.count > Self.visibleLimit {
                    Button {
                        Haptics.light()
                        postSwitchTab(.games)
                    } label: {
                        Text("See all \(items.count)")
                            .font(.ppFootnote)
                            .foregroundStyle(ppAccent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)

            ForEach(items.prefix(Self.visibleLimit)) { item in
                NavigationLink(value: route(item)) {
                    row(item)
                        .padding(.horizontal, 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(_ item: JournalUpcomingItem) -> some View {
        HStack(alignment: .center, spacing: .spacingMedium) {
            VStack(alignment: .leading, spacing: 4) {
                Text(whenText(item.date)).smallCapsLabel()
                Text(title(item))
                    .font(.ppHeadline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: .spacingSmall)
            // Start is offered only for TODAY's game: that's the one you're about
            // to play. Future games open their detail screen, which has Start too.
            // A seasonless game gets no Start here: the Games tab refuses to
            // start one ("needs a season"), and clips recorded into it would
            // land seasonless. Its detail screen is one tap away.
            if case .game(let game) = item, game.season != nil, Calendar.current.isDateInToday(item.date) {
                Button {
                    Haptics.medium()
                    onStart(game)
                } label: {
                    Text(isGolf(game) ? "Start Round" : "Start Game")
                        .font(.custom("Inter18pt-Bold", size: 13, relativeTo: .footnote))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(ppAccent))
                }
                // Borderless keeps the tap on this button instead of bubbling to
                // the row's NavigationLink — same as LiveGameCard's pills.
                .buttonStyle(.borderless)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.spacingLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ppCard()
    }

    private func isGolf(_ game: Game) -> Bool {
        (game.season?.sport).map { $0 == .golf } ?? isGolfProfile
    }

    /// "Today · 6:30 PM" / "Tomorrow · 6:30 PM" / "Sat, Sep 27 · 6:30 PM".
    private func whenText(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Today · \(time)" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow · \(time)" }
        return "\(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(time)"
    }

    /// Same wording the feed card would use — one source for event titles.
    private func title(_ item: JournalUpcomingItem) -> String {
        switch item {
        case .game(let g):     return JournalEntry.game(g).fallbackHeadline
        case .practice(let p): return JournalEntry.practice(p).fallbackHeadline
        }
    }

    /// Value-based push so MainTabView's `homePath` tracks it (see JournalRoute);
    /// JournalView's `.navigationDestination` resolves it.
    private func route(_ item: JournalUpcomingItem) -> JournalRoute {
        switch item {
        case .game(let g):     return .game(g.id)
        case .practice(let p): return .practice(p.id)
        }
    }
}
