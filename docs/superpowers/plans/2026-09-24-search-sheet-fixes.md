# Search Sheet Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven-development). Steps use `- [ ]`.

**Goal:** Make the athlete Search sheet (`AdvancedSearchView`) work end to end: every result opens, there are no dead-end features, golf athletes see golf options, and the screen uses the Calm Keepsake palette instead of stock white.

**Architecture:** One screen plus its supporting views. Four tasks, ordered by user impact: (1) results open, (2) remove Save Search, (3) sport-aware filters and labels, (4) palette pass and file split. Tasks 1–3 change behavior. Task 4 only changes looks, except that Games/Practices move from `List` to the same card stack Videos/Photos use.

**Tech stack:** SwiftUI and SwiftData. It reuses `VideoClipPagerView`/`VideoPlayerSession`, `.photoViewer`, `PhotoPersistenceService`, `PracticeDetailView`, `GameDetailView`, `ppCard()`, `PPFilterPillRow`, `Theme`, `@Environment(\.ppAccent)` and the `.pp*` fonts. There are no new APIs.

**Spec:** the review in this conversation (2026-09-24), which the screenshot `Screenshot iPhone 17 09-24-2026 at 6.40.39 PM.png` started. Findings: white background and unmigrated palette; video/photo results can't be opened; Save Search is never read back; golf athletes get baseball filters and "Games"; untagged clips have no title; the game picker is capped at 20.

## Global Constraints

- Deployment target **iOS 17.0**. `matchedTransitionSource`/zoom is already gated inside `.photoViewer`, so don't add a new gate.
- Colors: `Theme` tokens and `@Environment(\.ppAccent)` only. **Never** use `.brandNavy`, `.brandGold`, system `.blue`/`.red`/`.yellow`/`.green`/`.gray` in this file after Task 4.
- Type: `.pp*` fonts only in code this plan touches (`Font+PlayerPath.swift`). Don't reach for `.headingMedium`/`.bodySmall`/`.labelSmall`.
- A view struct that newly reads the accent gets exactly one `@Environment(\.ppAccent) private var ppAccent`, directly under its `struct … {` line.
- Sport checks inside this sheet use `athlete.sport == .golf` (one Athlete row = one sport, see [[project_dual_sport_model]]). This matches the existing `:390`.
- **Never hold a deleted `@Model`:** anything shown after a delete must be recomputed from the relationship (`updateFilteredResults()`), and `ForEach`s over cached models skip `modelContext == nil` rows. See memory `feedback_swiftdata_model_access_across_await`.
- Edit by matching the text. Line numbers are for orientation only (`AdvancedSearchView.swift` @ `a442fdb`).
- There's no Swift test target. "Test" means a clean build, the task's grep, and the task's simulator check.
- **Commit only the files each task names.** The working tree has 15 unrelated uncommitted files (other session / Trey). Never `git add -A`. Commit directly to `main`, one commit per task. Never touch version/build numbers.
- Xcode project uses synchronized folders (`PBXFileSystemSynchronizedRootGroup`), so new `.swift` files under `PlayerPath/` build without `pbxproj` edits.

Build (every task):
```bash
cd /Users/Trey/Desktop/PlayerPath && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PlayerPath.xcodeproj \
  -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | head -20
```

## Verified facts (repo @ a442fdb)

| Fact | Source |
|---|---|
| The sheet is presented from 3 places: `VideoClipsView.swift:340`, `JournalView.swift:377`, `MainTabView.swift:821`. All sit under `.ppAccent(forGolf:)` (`MainTabView.swift:239`), so the accent reaches the sheet | grep |
| `VideoSearchResultCard`/`PhotoSearchResultCard` are not wrapped in any link or button, so taps do nothing. `PracticeSearchResultRow` is also not tappable (`:282`). Only Games push (`NavigationLink` → `GameDetailView`, `:257`) | read |
| Video tap pattern: `playerSession = VideoPlayerSession(clipIDs:startID:)` → `.fullScreenCover(item: $playerSession) { VideoClipPagerView(athlete:session:) }`. The pager holds IDs, never models | `VideoClipsView.swift:333,688`; `VideoClipPagerView.swift:23` |
| Photo tap pattern: `.photoViewer($viewerPhoto, in: photos, onDelete:)`, delete = `PhotoPersistenceService().deletePhoto(photo, context: modelContext)` | `PhotoDetailView.swift:356`; `JournalPhotoDaySheet.swift:85,102` |
| `PracticeDetailView(practice:)` exists | `PracticesView.swift:326` |
| `SavedSearch`, `savedSearches`, `persistSavedSearches`, `loadSavedSearches` and the `"savedSearches"` UserDefaults key are referenced **only** in this file. Nothing reads a saved search back | grep |
| Only used in this file: `FilterChip`, `ContentType`, the four result views. **Used elsewhere:** `AsyncThumbnailView` (`UploadStatisticsView.swift`), `DateRange` (`PhotosView.swift`), so both keep their names and signatures | grep |
| `displayTagName` = club name → play-result name → `nil` (untagged) | `VideoClip+DisplayTag.swift:16` |
| `VideoClip.club: Club?`; `Club: String, CaseIterable` with `displayName` | `Models/VideoClip.swift:28`, `Models/Club.swift:15` |
| Sport nouns: `Season.gameUnitNounPlural` ("Rounds"/"Games"), `Season.gameUnitIcon` ("figure.golf"/"baseball.diamond.bases"). `Game.opponentLabel` is already sport-aware | `Season.swift:215-222`, `Game+Sport.swift:22` |
| `ppCard(cornerRadius:)` = `Theme.card` fill + `Theme.divider` hairline + soft shadow; caller pads | `Views/Components/PP/PPCard.swift` |
| `PPFilterPillRow(options:title:selection:)` is the pill row the Journal/Games/Clips filter bars use | `Views/Components/PP/PPFilterPill.swift` |
| Migrated Forms/Lists use `.scrollContentBackground(.hidden)` + `.background(Theme.surface)` | `ProfileView.swift:56` |
| Eager `NavigationLink` inside a `LazyVStack` steals sibling taps; fix with `.buttonStyle(.plain)` + `.contentShape(Rectangle())` | memory `project_journal_navlink_hittest` |

## Review Focus

1. **Deleting from the viewer, then coming back to results.** Deleting a video in the pager or a photo in the photo viewer, then closing, must not crash, and the deleted item must be gone from the list and the count. (Task 1 owns this: sim check 1c/1d.)
2. **Golf athlete, full flow.** The label says "Rounds", the filter sheet offers Clubs, not Play Results, and a club filter actually narrows the results. The accent is green, with no terracotta leaks. (Task 3 check 3b, Task 4 check 4c.)
3. **Filter changes while a result is open.** Opening a clip and closing it again must keep the query, the content tab and the filters. (Task 1 check 1b.)
4. **Tap targets in the card stack.** In Games/Practices, tapping card A must open A, not the card next to it. (Task 4 check 4d.)
5. **Untagged clips are readable.** A clip with no tag shows "Untagged" as its title, not a blank row. (Task 3 check 3d.)

---

### Task 1: Every result opens

**Files:** Modify `PlayerPath/Views/Search/AdvancedSearchView.swift`

**Interfaces:**
- Produces: `@State private var playerSession: VideoPlayerSession?`, `@State private var viewerPhoto: Photo?`, `private func deletePhoto(_ photo: Photo)`. Task 4 keeps these names.

- [ ] **Step 1: state.** Under `@State private var cachedFilteredPhotos …` add:
```swift
    // Result presentation — the pager takes IDs (never models) so a clip deleted
    // inside it can't be held here.
    @State private var playerSession: VideoPlayerSession?
    @State private var viewerPhoto: Photo?
```

- [ ] **Step 2: videos open the pager over the filtered results.** In `videosResultsView`, replace
```swift
                        ForEach(results) { video in
                            VideoSearchResultCard(video: video)
                        }
```
with
```swift
                        ForEach(results.filter { $0.modelContext != nil }) { video in
                            Button {
                                playerSession = VideoPlayerSession(
                                    clipIDs: results.map(\.id),
                                    startID: video.id
                                )
                                Haptics.light()
                            } label: {
                                VideoSearchResultCard(video: video)
                            }
                            .buttonStyle(.plain)
                        }
```

- [ ] **Step 3: photos open the swipe viewer.** In `photosResultsView`, replace
```swift
                        ForEach(results) { photo in
                            PhotoSearchResultCard(photo: photo)
                        }
```
with
```swift
                        ForEach(results.filter { $0.modelContext != nil }) { photo in
                            Button {
                                viewerPhoto = photo
                            } label: {
                                PhotoSearchResultCard(photo: photo)
                            }
                            .buttonStyle(.plain)
                        }
```

- [ ] **Step 4: practices push their detail.** In `practicesResultsView`, replace
```swift
                    ForEach(results) { practice in
                        PracticeSearchResultRow(practice: practice, searchText: searchText)
                    }
```
with
```swift
                    ForEach(results) { practice in
                        NavigationLink {
                            PracticeDetailView(practice: practice)
                        } label: {
                            PracticeSearchResultRow(practice: practice, searchText: searchText)
                        }
                    }
```

- [ ] **Step 5: presenters + refresh on close.** After `.sheet(isPresented: $showingSaveSearch) { saveSearchSheet }` add:
```swift
            .fullScreenCover(item: $playerSession, onDismiss: updateFilteredResults) { session in
                VideoClipPagerView(athlete: athlete, session: session)
            }
            .photoViewer($viewerPhoto, in: cachedFilteredPhotos, onDelete: deletePhoto)
            .onChange(of: viewerPhoto) { _, photo in
                // Viewer closed: re-derive from the relationship so a photo
                // deleted (or re-tagged) inside it drops out of the results.
                if photo == nil { updateFilteredResults() }
            }
```

- [ ] **Step 6: delete handler.** In `// MARK: - Actions`, after `clearAllFilters()` add:
```swift
    private func deletePhoto(_ photo: Photo) {
        // Drop it from the cache BEFORE deleting so no render touches a dead model.
        cachedFilteredPhotos.removeAll { $0.id == photo.id }
        PhotoPersistenceService().deletePhoto(photo, context: modelContext)
        Haptics.light()
    }
```

- [ ] **Step 7: build** (command above). Expected `BUILD SUCCEEDED`. The `swift-footgun-check` hook should be silent.

- [ ] **Step 8: sim checks.** **1a** Open Search from Home: tapping a video opens the player, and swiping moves only through the search results. **1b** Close it: the query, the tab and the filters are unchanged. **1c** Open a video, delete it in the player, close: no crash, the count drops by 1. **1d** Photos tab: tap opens the viewer; delete one, close: no crash, the photo is gone. **1e** Practices tab: a row pushes Practice Detail, and Back returns to Search.

- [ ] **Step 9: commit.**
```bash
git add PlayerPath/Views/Search/AdvancedSearchView.swift
git commit -m "Search: video, photo and practice results open; refresh after viewer closes"
```

---

### Task 2: Remove Save Search (dead end)

Saved searches are written but never shown or applied anywhere, so the button promises something the app doesn't have. Remove it. If saved searches are wanted later, build them as a real feature with a list and a per-athlete key. Don't revive this code.

**Files:** Modify `PlayerPath/Views/Search/AdvancedSearchView.swift`

- [ ] **Step 1: delete state.** Remove `@State private var savedSearches: [SavedSearch] = []`, `@State private var showingSaveSearch = false` and `@State private var newSearchName = ""`.
- [ ] **Step 2: delete the presenter + load.** Remove `.sheet(isPresented: $showingSaveSearch) { saveSearchSheet }` and the `loadSavedSearches()` line inside `.onAppear` (keep `updateFilteredResults()`).
- [ ] **Step 3: simplify the header.** Replace the whole `resultsHeaderView(count:)` body with:
```swift
    private func resultsHeaderView(count: Int) -> some View {
        HStack {
            Text("\(count) result\(count == 1 ? "" : "s")")
                .font(.bodyMedium)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
```
(Task 4 restyles the fonts.)
- [ ] **Step 4: delete** the `// MARK: - Save Search Sheet` block (`saveSearchSheet`), `saveSearch()`, `persistSavedSearches()`, `loadSavedSearches()`, and the whole `struct SavedSearch`.
- [ ] **Step 5: clear the orphaned key once.** In `.onAppear`, before `updateFilteredResults()`:
```swift
                UserDefaults.standard.removeObject(forKey: "savedSearches") // retired Save Search
```
- [ ] **Step 6: verify.** `grep -rn 'SavedSearch\|savedSearches\|showingSaveSearch' PlayerPath` returns only the `removeObject` line. Build succeeds.
- [ ] **Step 7: sim check 2a.** With a filter active, the header shows only the count, with no bookmark button.
- [ ] **Step 8: commit** `git add PlayerPath/Views/Search/AdvancedSearchView.swift && git commit -m "Search: remove Save Search (saved searches were never readable)"`

---

### Task 3: Sport-aware labels and filters; untagged title; full game list

**Files:** Modify `PlayerPath/Views/Search/AdvancedSearchView.swift`

**Interfaces:**
- Produces: `private var isGolf: Bool`, `private func label(for: ContentType) -> String`, `@State private var selectedClubs: Set<Club>`. Task 4 uses `label(for:)`.

- [ ] **Step 1: helpers.** Add under the `@State` block:
```swift
    @State private var selectedClubs: Set<Club> = []

    private var isGolf: Bool { athlete.sport == .golf }

    /// Sport-aware tab label: golfers see "Rounds", not "Games".
    private func label(for type: ContentType) -> String {
        type == .games && isGolf ? "Rounds" : type.displayName
    }
```
- [ ] **Step 2: use it.** The search prompt becomes `TextField("Search \(label(for: selectedContentType).lowercased())...", …)`. In `contentTypeSelectorView`, `Label(type.displayName, …)` becomes `Label(label(for: type), systemImage: type == .games && isGolf ? "figure.golf" : type.icon)`.
- [ ] **Step 3: filter sheet: clubs for golf, play results otherwise.** Replace the `// Play Result Filter` `Section("Play Results") { … }` with:
```swift
                    if isGolf {
                        Section("Clubs") {
                            ForEach(Club.allCases, id: \.self) { club in
                                Toggle(club.displayName, isOn: Binding(
                                    get: { selectedClubs.contains(club) },
                                    set: { isOn in
                                        if isOn { selectedClubs.insert(club) } else { selectedClubs.remove(club) }
                                    }
                                ))
                            }
                        }
                    } else {
                        Section("Play Results") {
                            ForEach(PlayResultType.allCases, id: \.self) { resultType in
                                Toggle(resultType.displayName, isOn: Binding(
                                    get: { selectedPlayResults.contains(resultType) },
                                    set: { isOn in
                                        if isOn { selectedPlayResults.insert(resultType) } else { selectedPlayResults.remove(resultType) }
                                    }
                                ))
                            }
                        }
                    }
```
- [ ] **Step 4: game picker shows every game.** In the Game/Tournament picker, delete `.prefix(20)`. The picker is menu-style, so a long list scrolls.
- [ ] **Step 5: wire `selectedClubs` everywhere the play-result set is wired:**
  - `hasActiveFilters`: `!selectedPlayResults.isEmpty` becomes `!selectedPlayResults.isEmpty || !selectedClubs.isEmpty`.
  - `activeFiltersSummaryView`, after the play-types chip:
```swift
                    if !selectedClubs.isEmpty {
                        FilterChip(text: "\(selectedClubs.count) club\(selectedClubs.count == 1 ? "" : "s")") {
                            selectedClubs.removeAll()
                        }
                    }
```
  - `filteredVideos()`, after the play-results line:
```swift
        if !selectedClubs.isEmpty { videos = videos.filter { $0.club.map { selectedClubs.contains($0) } ?? false } }
```
  - `clearAllFilters()`: add `selectedClubs.removeAll()`.
  - After `.onChange(of: selectedPlayResults)` add `.onChange(of: selectedClubs) { _, _ in updateFilteredResults() }`.
- [ ] **Step 6: untagged title.** In `VideoSearchResultCard`, replace
```swift
                if let tag = video.displayTagName {
                    Text(tag)
                        .font(.headingMedium)
                }
```
with
```swift
                Text(video.displayTagName ?? "Untagged")
                    .font(.headingMedium)
                    .foregroundColor(video.displayTagName == nil ? .secondary : .primary)
```
(Task 4 swaps these for tokens.)
- [ ] **Step 7: verify.** `grep -n 'prefix(20)' PlayerPath/Views/Search/AdvancedSearchView.swift` returns nothing. Build succeeds.
- [ ] **Step 8: sim checks.** **3a** Baseball athlete: the tab says "Games" and the filter shows Play Results. **3b** Golf athlete: the tab says "Rounds" with the golf icon, the prompt says "Search rounds...", the filter shows Clubs, and picking "7i" narrows the videos to 7-iron clips and shows a "1 club" chip. "Clear all" removes it. **3c** An athlete with more than 20 games: the oldest game can be picked. **3d** An untagged clip's card reads "Untagged".
- [ ] **Step 9: commit** `git add PlayerPath/Views/Search/AdvancedSearchView.swift && git commit -m "Search: golf gets Rounds + club filter; untagged title; full game list"`

---

### Task 4: Calm Keepsake palette + split the file

The screen moves onto cream, the result views move to their own file (per the small-files preference, and it drops `AdvancedSearchView.swift` from ~950 to ~600 lines), and all four tabs share one card stack.

**Files:**
- Create: `PlayerPath/Views/Search/SearchResultCards.swift`: `SearchResultCard`, `VideoSearchResultCard`, `PhotoSearchResultCard`, `GameSearchResultRow`, `PracticeSearchResultRow`, `FilterChip`, `AsyncThumbnailView` (moved verbatim, then restyled below; `AsyncThumbnailView` keeps its exact signature for `UploadStatisticsView`).
- Modify: `PlayerPath/Views/Search/AdvancedSearchView.swift`

**Interfaces:** Consumes Task 1's `playerSession`/`viewerPhoto`/`deletePhoto`, Task 3's `label(for:)`/`isGolf`. `SearchResultCard` changes from `private` to internal because it now lives in another file.

- [ ] **Step 1: move.** Cut everything from `// MARK: - Supporting Views` through the end of `AsyncThumbnailView` into the new file, with `import SwiftUI` and `import SwiftData` at the top. Drop `private` from `struct SearchResultCard`. Build: expect success with no visual change yet. Commit this move on its own so the restyle diff reads cleanly:
```bash
git add PlayerPath/Views/Search/AdvancedSearchView.swift PlayerPath/Views/Search/SearchResultCards.swift
git commit -m "Search: move result cards to SearchResultCards.swift (no behavior change)"
```

- [ ] **Step 2: sheet surface.** On the root `VStack(spacing: 0)` in `body`, after `.navigationBarTitleDisplayMode(.inline)`, add `.background(Theme.surface)`. In `filtersSheet`, after `Form { … }` add `.scrollContentBackground(.hidden)` and `.background(Theme.surface)`.

- [ ] **Step 3: search field.** In `searchBarView` add `@Environment(\.ppAccent) private var ppAccent` to `AdvancedSearchView` (one line, directly under `struct AdvancedSearchView: View {`, alongside `athlete`), then replace
```swift
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding()
```
with
```swift
        .font(.ppBody)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        )
        .tint(ppAccent)
        .padding()
```
The two `.foregroundColor(.secondary)` icons in it become `.foregroundStyle(Theme.textSecondary)`.

- [ ] **Step 4: content selector → pill row** (matches the Journal/Games/Clips filter bars). Replace the body of `contentTypeSelectorView` with:
```swift
        PPFilterPillRow(
            options: ContentType.allCases,
            title: { label(for: $0) },
            selection: $selectedContentType
        )
        .padding(.horizontal)
```
Then `ContentType.icon` has no readers left, so delete it and the Task 3 `systemImage:` expression. Verify with `grep -n '\.icon' AdvancedSearchView.swift`.

- [ ] **Step 5: filters strip.** In `activeFiltersSummaryView`, "Clear all": `.font(.labelMedium)` → `.font(.ppCaptionBold)`, `.foregroundColor(.red)` → `.foregroundStyle(ppAccent)`, `.background(Color.red.opacity(0.1))` → `.background(ppAccent.opacity(0.12))`, `.cornerRadius(16)` → `.clipShape(Capsule())`. Delete the strip's `.background(Color(.systemGray6).opacity(0.5))`; it now sits on cream.

- [ ] **Step 6: one card stack for all four tabs.** Replace `gamesResultsView` and `practicesResultsView` `List { … }.listStyle(.plain)` with the same shape as videos:
```swift
                ScrollView {
                    LazyVStack(spacing: 12) {
                        resultsHeaderView(count: results.count)
                        ForEach(results.filter { $0.modelContext != nil }) { game in
                            NavigationLink {
                                GameDetailView(game: game)
                            } label: {
                                GameSearchResultRow(game: game)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .ppCard()
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
```
Practices: identical, with `practice`, `PracticeDetailView(practice: practice)` and `PracticeSearchResultRow(practice: practice, searchText: searchText)`. `.buttonStyle(.plain)` + `.contentShape` is the Journal hit-test fix. Drop the rows' `.padding(.vertical, 4)` since the card pads now.

- [ ] **Step 7: header + empty state.** `resultsHeaderView`: `.font(.ppFootnote)`, `.foregroundStyle(Theme.textSecondary)`. `emptyResultsView`: icon `.foregroundStyle(Theme.textTertiary)`; "No results found" `.font(.ppTitle3)` `.foregroundStyle(Theme.textPrimary)`; hint `.font(.ppFootnote)` `.foregroundStyle(Theme.textSecondary)`; "Clear filters" `.font(.ppCallout)` + `.tint(ppAccent)` on the button.

- [ ] **Step 8: restyle `SearchResultCards.swift`.**
  - `FilterChip`: add `@Environment(\.ppAccent) private var ppAccent` under `struct FilterChip: View {`. `.font(.labelMedium)` → `.font(.ppCaptionBold)`. `.foregroundColor(.brandNavy)` → `.foregroundStyle(ppAccent)`. `.background(Color.brandNavy.opacity(0.1))` → `.background(ppAccent.opacity(0.12))`. `.cornerRadius(16)` → `.clipShape(Capsule())`.
  - `SearchResultCard`: placeholder `Color.gray.opacity(0.3)` → `Theme.divider`, icon `.white` → `Theme.textTertiary`. Replace
```swift
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
```
with `.padding()` then `.ppCard()`. Thumbnails `.cornerRadius(8)` → `.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))`.
  - `VideoSearchResultCard`: title `.font(.ppHeadline)` with `.foregroundStyle(video.displayTagName == nil ? Theme.textSecondary : Theme.textPrimary)`. Star `.foregroundColor(.yellow)` → `.foregroundStyle(Theme.warning)` (the palette's amber; no gold token exists outside legacy `.brandGold`). Opponent `.font(.ppSubheadline)` `.foregroundStyle(Theme.textSecondary)`. Date `.font(.ppCaption)` `.foregroundStyle(Theme.textTertiary)`.
  - `PhotoSearchResultCard`: the same three roles (caption `.ppHeadline`/textPrimary, context `.ppSubheadline`/textSecondary, date `.ppCaption`/textTertiary).
  - `GameSearchResultRow`: add `@Environment(\.ppAccent) private var ppAccent`. Title `.font(.ppHeadline)` `.foregroundStyle(Theme.textPrimary)`. LIVE badge `.background(Color.red)` → `.background(ppAccent)` (LIVE = accent, as in batch 4b R7), `.cornerRadius(4)` → `.clipShape(Capsule())`. Completed check `.green` → `Theme.chipGreenText`. Date/stat lines `.font(.ppFootnote)` `.foregroundStyle(Theme.textSecondary)`.
  - `PracticeSearchResultRow`: "Practice" `.ppHeadline`/textPrimary; date + snippet `.ppFootnote`/textSecondary; notes count `.ppCaption`/textTertiary.
  - `AsyncThumbnailView`: `Color.gray.opacity(0.3)` → `Theme.divider`. Signature unchanged.

- [ ] **Step 9: verify.**
```bash
grep -nE 'brandNavy|brandGold|systemGray|systemBackground|Color\.(red|yellow|green|gray)|\.foregroundColor\(\.(red|yellow|green|secondary)\)|headingMedium|headingLarge|bodySmall|bodyMedium|labelSmall|labelMedium|labelLarge' \
  PlayerPath/Views/Search/AdvancedSearchView.swift PlayerPath/Views/Search/SearchResultCards.swift
```
Expected: **no output**. (The filter sheet's `Form` rows keep system styling; that's intended and uses none of these tokens.) Build succeeds.

- [ ] **Step 10: sim checks.** **4a** Search from Home, Videos and More: all three have a cream background, white hairline cards and a white search field, and none is plain white. **4b** Baseball athlete: chips, Clear all, LIVE and the cursor are terracotta. **4c** Golf athlete: the same elements are green. **4d** Games and Practices tabs: tapping each card opens *that* card's detail (try the 2nd and 3rd card). **4e** Filter sheet is cream behind grouped rows. **4f** Largest Dynamic Type (AX5): card text wraps and nothing clips the thumbnail. **4g** Upload Statistics (uses `AsyncThumbnailView`) still shows thumbnails.

- [ ] **Step 11: commit.**
```bash
git add PlayerPath/Views/Search/AdvancedSearchView.swift PlayerPath/Views/Search/SearchResultCards.swift
git commit -m "Search: Calm Keepsake palette, pp type, pill selector, one card stack for all tabs"
```

---

## Out of scope (note, don't do)

- **Searching `fileName`** (`filteredVideos`): these are generated names users never see, so a query can match invisibly. It's harmless, but a candidate to drop later.
- **Search across athletes/names**: tracked in memory `project_universal_search_todo`.
- **Glass Done/filter capsules' soft shadow**: that's the iOS 26 system toolbar, not this view.
