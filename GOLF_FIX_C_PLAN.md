# Stream C — Golf Stat Export (C1) + Rescan Strips Golf Highlights (A2)

_Plan grounded in full reads of every touched file and every export call site. **No schema change** — pure rendering/UI logic plus one small new data file. Stream A's `effectiveTotalScore` / `isGolfRoundScored` are consumed read-only; no Stream A/B files are modified._

---

## The bugs (with a reachability correction the review missed)

**C1** — The Profile export (`StatisticsExportView` → `CSVExportService` / `PDFReportGenerator`) hardcodes baseball columns (At Bats, Hits, AVG, OBP, SLG, OPS, 1B/2B/3B/HR…) with **zero** sport branching. A golf athlete who exports — a Plus/Pro feature, data that can reach college coaches — gets a CSV/PDF showing `At Bats: 0 … AVG: .000` and no score/round data.

**Reachability correction (verified against source, not the review's assumption):** the review names *three* export stacks, but `StatisticsExportService` is **not reachable for golf**. Its only callers are `StatisticsView.exportCSV/exportPDF` (`StatisticsView.swift:231,254`), both nested inside the `if statistics != nil, currentTier >= .plus, !isGolf` menu block (`StatisticsView.swift:156`, comment already reads _"Export is baseball-only"_). So that stack already meets the review's minimum bar — a golf athlete cannot trigger it. **Stream C therefore corrects only the reachable stack**: `StatisticsExportView` (Profile) and the two services it drives. `StatisticsExportService` is left as-is (adding golf rendering there would be unreachable dead code); this plan documents why so it isn't re-flagged.

**A2** — `AutoHighlightSettings.scanLibrary(for:context:)` (`AutoHighlightSettings.swift:93`) is wired to the "Scan Library" button in `AutoHighlightSettingsView` (`:48-58`), itself opened from the wand.and.stars toolbar button in `HighlightsView` (`HighlightsView.swift:359-368`). That button is gated **only** by `currentTier >= .plus` — **not sport**. `HighlightsView` is presented to golf athletes (it carries golf labels — `:341` "Tournaments"). At `scanLibrary` `:97-101`, every clip with `playResult == nil` runs `if clip.isHighlight { clip.isHighlight = false; clip.needsSync = true }`. Golf clips **always** have `playResult == nil` (they're club-tagged, never play-result-tagged), so a rescan silently clears every manual golf highlight and dirties it → cross-device loss. Golf is "manual highlights only."

---

# C1 — Golf-aware export

## Design

Per-call-site baseball columns stay; golf is branched in at the top of each reachable service method on the authoritative sport signal, and the rendered rows come from **one new small data file** so the golf logic isn't smeared across the two large baseball renderers.

**Sport resolver (no new broken `activeSport` copy — uses the existing canonical fields):**
- Athlete-scoped report → `athlete.sport == .golf` (the primary `Sport`, same signal `athlete.sportType` is built from).
- Season-scoped report → `season.sport == .golf` (`Season.SportType`).
- Game-log (athlete + optional season) → `season.map { $0.sport == .golf } ?? (athlete.sport == .golf)`.

**Golf round model (mirrors `GolfStatsSection` exactly so the export and the in-app screen never disagree):**
- A *tournament round* = a `Game` whose `season?.sport == .golf`, `!isLive`, and `isGolfRoundScored` (Stream A). Newest-first.
- A *practice round* = a `Practice` with `practiceType == "practice_round"` and ≥1 `holeScores`.
- Columns: **Date, Course, Holes, Par, Score, +/- (to par), Putts.**
  - Course = `game.opponent` (golf course name; rendered "at {course}" in-app) / `practice.course ?? "Practice Round"`.
  - Holes = `game.holes ?? holeScores.count` (Practice: `practice.holes ?? holeScores.count`).
  - Par = `game.par ?? sum(holeScore.par)` (Practice has **no** `par` field → `sum(holeScore.par)`, nil when no holes).
  - Score = `game.effectiveTotalScore` (Stream A) / `sum(holeScore.score)` for practices.
  - Putts = `sum(holeScore.putts)`, nil when no putts were recorded (column shows "-").
  - GIR / fairways-hit have **no model fields yet** — intentionally *not* emitted (an empty column reads as broken). `GolfRoundRow` is documented as the extension point so adding them later is a one-line struct change, not a caller reshape.
- Summary (athlete/season scope) mirrors `GolfStatsSection`: **Rounds, Best, Worst, Tournament Avg, Practice Avg.**

---

## Edit 1 — NEW FILE `PlayerPath/Services/GolfExportData.swift`

Single source of golf export rows + summary, consumed by both the CSV and PDF stacks. Small, focused, no rendering — just data. Mirrors `GolfStatsSection`'s pools and the Stream-A derived scoring.

```swift
//
//  GolfExportData.swift
//  PlayerPath
//
//  Single source of golf scoring rows + summary for the CSV/PDF export
//  stacks. Mirrors GolfStatsSection's round pools and Stream A's derived
//  totals so an exported document never disagrees with the in-app Stats
//  screen. No rendering here — the CSV/PDF services format these values.
//

import Foundation

/// One golf round's exportable scoring line. Greens-in-regulation and
/// fairways-hit are not tracked yet (no model fields); when they land they
/// become two more stored properties here and two more rendered columns —
/// callers don't change shape. That's the reason this is a struct, not a
/// pile of parallel arrays.
struct GolfRoundRow {
    let date: Date?
    let course: String
    let holes: Int
    let par: Int?
    let score: Int?
    let putts: Int?

    /// Signed strokes relative to par; nil when either side is unknown.
    var toPar: Int? {
        guard let score, let par else { return nil }
        return score - par
    }

    /// "E" / "+3" / "-2" / "—" for display.
    var toParString: String {
        guard let toPar else { return "—" }
        if toPar == 0 { return "E" }
        return toPar > 0 ? "+\(toPar)" : "\(toPar)"
    }
}

/// Career/season scoring roll-up — same five numbers GolfStatsSection shows.
struct GolfExportSummary {
    let totalRounds: Int
    let bestScore: Int?
    let worstScore: Int?
    let tournamentAverage: Double?
    let practiceAverage: Double?
}

enum GolfExportData {
    /// Scored tournament rounds (golf-season `Game`s), newest first. Matches
    /// GolfStatsSection.tournamentRounds: golf season, not live, fully scored.
    /// When `season` is non-nil only that season's games count.
    static func tournamentRounds(for athlete: Athlete, season: Season?) -> [GolfRoundRow] {
        let pool: [Game] = season?.games ?? athlete.games ?? []
        let scored = pool.filter { (g: Game) -> Bool in
            guard g.season?.sport == .golf else { return false }
            guard !g.isLive else { return false }
            return g.isGolfRoundScored
        }
        return scored
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .map { game in
                GolfRoundRow(
                    date: game.date,
                    course: game.opponent.isEmpty ? "Unknown Course" : game.opponent,
                    holes: game.holes ?? (game.holeScores ?? []).count,
                    par: game.par ?? parTotal(game.holeScores),
                    score: game.effectiveTotalScore,
                    putts: puttsTotal(game.holeScores)
                )
            }
    }

    /// Golf practice rounds with ≥1 scored hole, newest first. Mirrors
    /// GolfStatsSection.practiceRounds. Practice has no course-par field, so
    /// par is derived from the per-hole pars.
    static func practiceRounds(for athlete: Athlete, season: Season?) -> [GolfRoundRow] {
        let pool: [Practice] = season?.practices ?? athlete.practices ?? []
        let scored = pool.filter { (p: Practice) -> Bool in
            p.practiceType == PracticeType.practiceRound.rawValue
                && !(p.holeScores ?? []).isEmpty
        }
        return scored
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .map { practice in
                let holes = practice.holeScores ?? []
                return GolfRoundRow(
                    date: practice.date,
                    course: practice.course ?? "Practice Round",
                    holes: practice.holes ?? holes.count,
                    par: parTotal(practice.holeScores),
                    score: holes.reduce(0) { $0 + $1.score },
                    putts: puttsTotal(practice.holeScores)
                )
            }
    }

    /// Five-number scoring summary across both pools (matches GolfStatsSection).
    static func summary(for athlete: Athlete, season: Season?) -> GolfExportSummary {
        let tScores = tournamentRounds(for: athlete, season: season).compactMap { $0.score }
        let pScores = practiceRounds(for: athlete, season: season).compactMap { $0.score }
        let all = tScores + pScores
        return GolfExportSummary(
            totalRounds: all.count,
            bestScore: all.min(),
            worstScore: all.max(),
            tournamentAverage: tScores.isEmpty ? nil
                : Double(tScores.reduce(0, +)) / Double(tScores.count),
            practiceAverage: pScores.isEmpty ? nil
                : Double(pScores.reduce(0, +)) / Double(pScores.count)
        )
    }

    private static func parTotal(_ holeScores: [HoleScore]?) -> Int? {
        let holes = holeScores ?? []
        return holes.isEmpty ? nil : holes.reduce(0) { $0 + $1.par }
    }

    private static func puttsTotal(_ holeScores: [HoleScore]?) -> Int? {
        let recorded = (holeScores ?? []).compactMap { $0.putts }
        return recorded.isEmpty ? nil : recorded.reduce(0, +)
    }
}
```

---

## Edit 2 — `PlayerPath/Services/CSVExportService.swift` (golf branches + builders)

The three reachable methods get a golf guard at the very top (after the existing tier guard); baseball bodies are untouched. `exportPlayByPlay` is left baseball-only and is hidden for golf in the UI (Edit 4).

**2a. `exportAthleteStatistics(for:)` — after the tier guard (current `:32-34`), insert:**
```swift
        if athlete.sport == .golf {
            return golfScoringCSV(for: athlete)
        }
```

**2b. `exportGameLog(for:season:)` — after the tier guard (current `:109-111`), insert:**
```swift
        let isGolf = season.map { $0.sport == .golf } ?? (athlete.sport == .golf)
        if isGolf {
            return golfRoundLogCSV(for: athlete, season: season)
        }
```

**2c. `exportSeasonSummary(for:)` — after the tier guard (current `:229-231`), insert:**
```swift
        if season.sport == .golf {
            return golfSeasonSummaryCSV(for: season)
        }
```

**2d. New private builders — add to the `// MARK: - Helper Methods` region (alongside `escapeCSV`):**
```swift
    // MARK: - Golf CSV

    private func golfScoringCSV(for athlete: Athlete) -> String {
        var csv = "Golf Scoring Export\n"
        csv += "Generated: \(Date().formatted(date: .long, time: .standard))\n\n"
        csv += "Athlete Name,\(escapeCSV(athlete.name))\n"
        if let createdAt = athlete.createdAt {
            csv += "Profile Created,\(createdAt.formatted(date: .abbreviated, time: .omitted))\n"
        }
        csv += "\n"

        let summary = GolfExportData.summary(for: athlete, season: nil)
        csv += "Scoring Summary\n"
        csv += "Metric,Value\n"
        csv += "Total Rounds,\(summary.totalRounds)\n"
        csv += "Best Score,\(summary.bestScore.map { "\($0)" } ?? "—")\n"
        csv += "Worst Score,\(summary.worstScore.map { "\($0)" } ?? "—")\n"
        csv += "Tournament Average,\(summary.tournamentAverage.map { String(format: "%.1f", $0) } ?? "—")\n"
        csv += "Practice Average,\(summary.practiceAverage.map { String(format: "%.1f", $0) } ?? "—")\n"
        csv += "\n"

        let tournaments = GolfExportData.tournamentRounds(for: athlete, season: nil)
        if !tournaments.isEmpty {
            csv += "Tournament Rounds\n"
            csv += golfRoundsTable(tournaments)
            csv += "\n"
        }

        let practices = GolfExportData.practiceRounds(for: athlete, season: nil)
        if !practices.isEmpty {
            csv += "Practice Rounds\n"
            csv += golfRoundsTable(practices)
        }
        return csv
    }

    private func golfRoundLogCSV(for athlete: Athlete, season: Season?) -> String {
        var csv = "Golf Round Log\n"
        csv += "Generated: \(Date().formatted(date: .long, time: .standard))\n"
        csv += "Athlete: \(escapeCSV(athlete.name))\n"
        if let season { csv += "Season: \(escapeCSV(season.displayName))\n" }
        csv += "\n"
        csv += golfRoundsTable(GolfExportData.tournamentRounds(for: athlete, season: season))
        return csv
    }

    private func golfSeasonSummaryCSV(for season: Season) -> String {
        var csv = "Golf Season Summary\n"
        csv += "Generated: \(Date().formatted(date: .long, time: .standard))\n\n"
        csv += "Season Name,\(escapeCSV(season.displayName))\n"
        if let startDate = season.startDate {
            csv += "Start Date,\(startDate.formatted(date: .abbreviated, time: .omitted))\n"
        }
        if let endDate = season.endDate {
            csv += "End Date,\(endDate.formatted(date: .abbreviated, time: .omitted))\n"
        }
        csv += "Status,\(season.isActive ? "Active" : "Completed")\n"
        csv += "Sport,\((season.sport ?? .baseball).displayName)\n\n"

        if let athlete = season.athlete {
            let summary = GolfExportData.summary(for: athlete, season: season)
            csv += "Scoring Summary\n"
            csv += "Metric,Value\n"
            csv += "Total Rounds,\(summary.totalRounds)\n"
            csv += "Best Score,\(summary.bestScore.map { "\($0)" } ?? "—")\n"
            csv += "Worst Score,\(summary.worstScore.map { "\($0)" } ?? "—")\n"
            csv += "Tournament Average,\(summary.tournamentAverage.map { String(format: "%.1f", $0) } ?? "—")\n"
            csv += "Practice Average,\(summary.practiceAverage.map { String(format: "%.1f", $0) } ?? "—")\n\n"

            let tournaments = GolfExportData.tournamentRounds(for: athlete, season: season)
            if !tournaments.isEmpty {
                csv += "Tournament Rounds\n"
                csv += golfRoundsTable(tournaments)
            }
        }
        return csv
    }

    /// Renders a golf rounds block: header row + one line per round.
    private func golfRoundsTable(_ rounds: [GolfRoundRow]) -> String {
        var csv = "Date,Course,Holes,Par,Score,To Par,Putts\n"
        for r in rounds {
            let dateStr = r.date?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown"
            csv += "\(dateStr),"
            csv += "\(escapeCSV(r.course)),"
            csv += "\(r.holes),"
            csv += "\(r.par.map { "\($0)" } ?? "-"),"
            csv += "\(r.score.map { "\($0)" } ?? "-"),"
            csv += "\(r.toParString),"
            csv += "\(r.putts.map { "\($0)" } ?? "-")\n"
        }
        return csv
    }
```

---

## Edit 3 — `PlayerPath/Services/PDFReportGenerator.swift` (golf branches + builders)

Mirror the CSV branches; reuse the existing `drawTitle` / `drawSectionHeader` / `drawText` / `drawTableHeader` helpers (all already in the file, `:241-342`).

**3a. `generateAthleteReport(for:)` — first line of the method body (before `:29` metadata), insert:**
```swift
        if athlete.sport == .golf {
            return generateGolfReport(for: athlete)
        }
```

**3b. `generateGameLogReport(for:season:)` — first line of the method body, insert:**
```swift
        let isGolf = season.map { $0.sport == .golf } ?? (athlete.sport == .golf)
        if isGolf {
            return generateGolfRoundLogReport(for: athlete, season: season)
        }
```

**3c. `generateSeasonSummaryReport(for:)` — first line of the method body, insert:**
```swift
        if season.sport == .golf {
            return generateGolfSeasonSummaryReport(for: season)
        }
```

**3d. New golf renderers + table helpers — add before `// MARK: - File Saving` (`:436`):**
```swift
    // MARK: - Golf Reports

    func generateGolfReport(for athlete: Athlete) -> PDFDocument {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle: "PlayerPath Golf Scoring Report",
            kCGPDFContextAuthor: "PlayerPath",
            kCGPDFContextSubject: "\(athlete.name) Golf Scoring"
        ] as [String: Any]

        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = margin
            y = drawTitle("Golf Scoring Report", at: y, in: pageRect)
            y += 10
            y = drawSectionHeader("Athlete Information", at: y, in: pageRect)
            y = drawText("Name: \(athlete.name)", at: y, in: pageRect, fontSize: 12)
            y = drawText("Generated: \(Date().formatted(date: .long, time: .standard))", at: y, in: pageRect, fontSize: 12)
            y += 20

            y = drawGolfSummary(GolfExportData.summary(for: athlete, season: nil), at: y, in: pageRect)

            let tournaments = GolfExportData.tournamentRounds(for: athlete, season: nil)
            if !tournaments.isEmpty {
                y = drawSectionHeader("Tournament Rounds", at: y, in: pageRect)
                y = drawGolfRoundsTable(tournaments, at: y, in: pageRect, context: context)
            }
            let practices = GolfExportData.practiceRounds(for: athlete, season: nil)
            if !practices.isEmpty {
                if y > pageHeight - 120 { context.beginPage(); y = margin }
                y = drawSectionHeader("Practice Rounds", at: y, in: pageRect)
                y = drawGolfRoundsTable(practices, at: y, in: pageRect, context: context)
            }
        }
        return PDFDocument(data: data) ?? PDFDocument()
    }

    func generateGolfRoundLogReport(for athlete: Athlete, season: Season?) -> PDFDocument {
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = margin
            y = drawTitle("Golf Round Log", at: y, in: pageRect)
            y = drawText("Athlete: \(athlete.name)", at: y, in: pageRect, fontSize: 14, bold: true)
            if let season { y = drawText("Season: \(season.displayName)", at: y, in: pageRect, fontSize: 14, bold: true) }
            y += 20
            y = drawGolfRoundsTable(GolfExportData.tournamentRounds(for: athlete, season: season), at: y, in: pageRect, context: context)
        }
        return PDFDocument(data: data) ?? PDFDocument()
    }

    func generateGolfSeasonSummaryReport(for season: Season) -> PDFDocument {
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = margin
            y = drawTitle("Golf Season Summary", at: y, in: pageRect)
            y += 10
            y = drawSectionHeader("Season Information", at: y, in: pageRect)
            y = drawText("Season: \(season.displayName)", at: y, in: pageRect, fontSize: 12)
            y = drawText("Status: \(season.isActive ? "Active" : "Completed")", at: y, in: pageRect, fontSize: 12)
            y += 20
            if let athlete = season.athlete {
                y = drawGolfSummary(GolfExportData.summary(for: athlete, season: season), at: y, in: pageRect)
                let tournaments = GolfExportData.tournamentRounds(for: athlete, season: season)
                if !tournaments.isEmpty {
                    y = drawSectionHeader("Tournament Rounds", at: y, in: pageRect)
                    y = drawGolfRoundsTable(tournaments, at: y, in: pageRect, context: context)
                }
            }
        }
        return PDFDocument(data: data) ?? PDFDocument()
    }

    private func drawGolfSummary(_ s: GolfExportSummary, at yPosition: CGFloat, in pageRect: CGRect) -> CGFloat {
        var y = drawSectionHeader("Scoring Summary", at: yPosition, in: pageRect)
        y = drawText("Total Rounds: \(s.totalRounds)", at: y, in: pageRect)
        y = drawText("Best: \(s.bestScore.map { "\($0)" } ?? "—")  |  Worst: \(s.worstScore.map { "\($0)" } ?? "—")", at: y, in: pageRect)
        y = drawText("Tournament Avg: \(s.tournamentAverage.map { String(format: "%.1f", $0) } ?? "—")  |  Practice Avg: \(s.practiceAverage.map { String(format: "%.1f", $0) } ?? "—")", at: y, in: pageRect)
        return y + 20
    }

    private func drawGolfRoundsHeader(at y: CGFloat, in pageRect: CGRect) -> CGFloat {
        drawTableHeader(
            headers: ["Date", "Course", "Holes", "Par", "Score", "+/-", "Putts"],
            columnWidths: [70, 140, 45, 45, 55, 45, 50],
            at: y, in: pageRect
        )
    }

    private func drawGolfRoundsTable(_ rounds: [GolfRoundRow], at yPosition: CGFloat, in pageRect: CGRect, context: UIGraphicsPDFRendererContext) -> CGFloat {
        var y = drawGolfRoundsHeader(at: yPosition, in: pageRect)
        let widths: [CGFloat] = [70, 140, 45, 45, 55, 45, 50]
        let font = UIFont.systemFont(ofSize: 9)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        for r in rounds {
            if y > pageHeight - 60 {
                context.beginPage()
                y = margin
                y = drawGolfRoundsHeader(at: y, in: pageRect)
            }
            let values = [
                r.date?.formatted(date: .numeric, time: .omitted) ?? "Unknown",
                String(r.course.prefix(20)),
                "\(r.holes)",
                r.par.map { "\($0)" } ?? "-",
                r.score.map { "\($0)" } ?? "-",
                r.toParString,
                r.putts.map { "\($0)" } ?? "-"
            ]
            var x = margin
            for (i, v) in values.enumerated() {
                NSAttributedString(string: v, attributes: attrs)
                    .draw(in: CGRect(x: x, y: y, width: widths[i], height: 15))
                x += widths[i]
            }
            y += 18
        }
        return y + 10
    }
```

---

## Edit 4 — `PlayerPath/Views/Profile/StatisticsExportView.swift` (UI: labels, hide Play-by-Play for golf, clamp selection)

Routing is unchanged — `generateCSV`/`generatePDF` still call `exportAthleteStatistics` etc., which now branch golf internally. The view only needs golf-aware labels, to drop the baseball-only **Play-by-Play** report for golf, and to clamp a stale selection when the athlete switches to golf.

**4a. `ReportType` — replace the `displayName` / `shortName` / `icon` computed properties (`:306-331`) with sport-aware variants (keep the plain names delegating to baseball so nothing else breaks), and add `cases(isGolf:)`:**
```swift
    var displayName: String { displayName(isGolf: false) }
    func displayName(isGolf: Bool) -> String {
        switch self {
        case .athleteStatistics: return isGolf ? "Scoring Report" : "Athlete Statistics Report"
        case .gameLog:           return isGolf ? "Round-by-Round Log" : "Game-by-Game Log"
        case .seasonSummary:     return "Season Summary"
        case .playByPlay:        return "Play-by-Play Report"
        }
    }

    var shortName: String { shortName(isGolf: false) }
    func shortName(isGolf: Bool) -> String {
        switch self {
        case .athleteStatistics: return isGolf ? "Scoring" : "Stats Report"
        case .gameLog:           return isGolf ? "Round Log" : "Game Log"
        case .seasonSummary:     return "Season Summary"
        case .playByPlay:        return "Play by Play"
        }
    }

    var icon: String { icon(isGolf: false) }
    func icon(isGolf: Bool) -> String {
        switch self {
        case .athleteStatistics: return isGolf ? "figure.golf" : "chart.bar.fill"
        case .gameLog:           return isGolf ? "figure.golf" : "baseball.diamond.bases"
        case .seasonSummary:     return "calendar.badge.checkmark"
        case .playByPlay:        return "list.bullet.clipboard"
        }
    }

    /// Play-by-Play is baseball-only (golf clips carry a club, not a play
    /// result), so it's dropped for golf athletes.
    static func cases(isGolf: Bool) -> [ReportType] {
        isGolf ? [.athleteStatistics, .gameLog, .seasonSummary] : allCases
    }
```
(The `description` and `needsSeasonFilter` properties at `:333-353` are unchanged — `description` stays generic enough for both; `gameLog` still needs the season filter for golf.)

**4b. Add a golf flag near the other computed state in the view body:**
```swift
    private var isGolfAthlete: Bool { selectedAthlete?.sport == .golf }
```

**4c. Report-type picker (`:47-52`) — drive cases + labels off the flag:**
```swift
                    Picker("Report", selection: $selectedReportType) {
                        ForEach(ReportType.cases(isGolf: isGolfAthlete)) { type in
                            Label(type.displayName(isGolf: isGolfAthlete), systemImage: type.icon(isGolf: isGolfAthlete))
                                .tag(type)
                        }
                    }
```

**4d. Preview "Report" short name (`:115`) → `selectedReportType.shortName(isGolf: isGolfAthlete)`.**

**4e. Clamp a stale `.playByPlay` selection when switching to a golf athlete — add a modifier on the `Form` (next to `.navigationTitle`, `:187`):**
```swift
        .onChange(of: selectedAthlete) { _, newAthlete in
            let golf = newAthlete?.sport == .golf
            if !ReportType.cases(isGolf: golf).contains(selectedReportType) {
                selectedReportType = .athleteStatistics
            }
        }
```

_No change to `StatisticsExportService.swift`_ — it is already `!isGolf`-gated at its only call site (`StatisticsView.swift:156`) and is unreachable for golf athletes; adding golf rendering there would be dead code.

---

# A2 — Rescan must not strip golf highlights

## Design

Two complementary fixes — neither alone is sufficient:
1. **Hide the entry for golf-primary athletes.** `AutoHighlightSettingsView` is 100% baseball (Batting/Pitching toggles + a baseball-rules rescan). A golf athlete should never see it. Gate the `HighlightsView` toolbar button on `athlete?.sport != .golf`.
2. **Guard `scanLibrary` per-clip.** A *multi-sport* athlete whose **primary** is baseball but who also has golf clips still reaches the panel (correctly — they have baseball clips to configure). The rescan must skip that athlete's golf clips so it can't clear their manual golf highlights. A per-clip guard (not a blanket `athlete.sport == .golf` early-return) is the correct scope — the early-return would wrongly skip a golf-primary athlete's baseball clips in the inverse case.

A clip is golf when it carries a `club`, or any of its `game` / `practice` / `season` belongs to a golf season — covering both club-tagged clips and not-yet-tagged clips recorded in a golf round.

## Edit 5 — `PlayerPath/AutoHighlightSettings.swift` (`scanLibrary` guard + helper)

**5a. In `scanLibrary`, replace the no-`playResult` branch (`:96-101`):**
```swift
        for clip in clips {
            guard let playResult = clip.playResult else {
                // No play result. Golf clips are manual-only highlights (golf
                // never sets playResult), so a rescan must NOT clear them —
                // skip without touching isHighlight/needsSync. Baseball clips
                // with no play result still get unmarked as before.
                if Self.clipIsGolf(clip) { continue }
                if clip.isHighlight { clip.isHighlight = false; clip.needsSync = true; changed += 1 }
                continue
            }
```
(The tagged-clip branch below `:102-110` is unchanged — golf clips never reach it since `playResult == nil`.)

**5b. Add the helper (private static, after `scanLibrary`):**
```swift
    /// True when a clip belongs to golf — by club tag or by golf-season
    /// context. Used to exempt golf clips from the baseball rescan rules.
    private static func clipIsGolf(_ clip: VideoClip) -> Bool {
        if clip.club != nil { return true }
        if clip.game?.season?.sport == .golf { return true }
        if clip.practice?.season?.sport == .golf { return true }
        if clip.season?.sport == .golf { return true }
        return false
    }
```

## Edit 6 — `PlayerPath/HighlightsView.swift` (hide the settings entry for golf)

**Gate the auto-highlight settings toolbar button (`:359`) on sport as well as tier:**
```swift
        // Auto-highlight settings (Plus+, baseball/softball only — the panel
        // is batting/pitching rules; golf is manual-highlights-only).
        if currentTier >= .plus && athlete?.sport != .golf {
```
(The matching `}` closing the `if` at `:369` is unchanged.)

---

## Out of scope (other streams / deferred)

- Stream A (`effectiveTotalScore`, `isGolfRoundScored`, `holeScoreSum`, `ScoreHoleSheet` total mirroring) and Stream B (reel sync / `VideoClip.delete(cleanupReels:)`) — consumed read-only, not modified.
- `StatisticsExportService.swift` — already golf-gated at its sole call site; deliberately untouched.
- **Golf Play-by-Play / shot log** (club + hole per clip) — a real future feature; for now Play-by-Play is hidden for golf rather than faked.
- **GIR / fairways-hit columns** — no model fields exist; `GolfRoundRow` reserves the shape, columns are added when the data lands.
- The A1 dual-enum / central `SportLabels` refactor — separate cleanup pass.

## Verification

1. `xcodebuild -project PlayerPath.xcodeproj -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` → grep `BUILD SUCCEEDED`, no `error:`.
2. **C1 CSV:** golf athlete → Profile → Export Statistics → Scoring Report (CSV). File shows Rounds/Best/Worst/Tournament Avg/Practice Avg + a Date/Course/Holes/Par/Score/To Par/Putts table — **no** At Bats/AVG. Round-by-Round Log and Season Summary likewise golf.
3. **C1 PDF:** same three reports in PDF render golf headers/rows, paginate past one page, no baseball sections.
4. **C1 UI:** golf athlete sees only Scoring / Round-by-Round Log / Season Summary (no Play-by-Play); switching the picker from a baseball athlete on Play-by-Play to a golf athlete snaps the selection back to Scoring. Baseball athlete export is byte-for-byte unchanged.
5. **C1 regression:** baseball athlete CSV/PDF identical to pre-change (baseball branch untouched).
6. **A2 entry:** golf-primary athlete on the Highlights tab → wand.and.stars button is gone. Baseball athlete still sees it.
7. **A2 scan:** multi-sport athlete (baseball primary + golf clips) → open Auto-Highlight Rules → Scan Library → golf clips keep `isHighlight`, are not dirtied (`needsSync` unchanged); baseball clips re-evaluate as before. Confirm cross-device: the golf clips don't subsequently sync-clear.
```
