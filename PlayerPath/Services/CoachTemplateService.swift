//
//  CoachTemplateService.swift
//  PlayerPath
//
//  Firestore CRUD for coach quick cues and annotation templates.
//

import Foundation
import FirebaseFirestore
import os

private let templateLog = Logger(subsystem: "com.playerpath.app", category: "CoachTemplates")

@MainActor
@Observable
class CoachTemplateService {
    static let shared = CoachTemplateService()

    var quickCues: [QuickCue] = []
    var drillTemplates: [SavedDrillTemplate] = []
    var isLoading = false

    private let db = Firestore.firestore()

    /// Which coach `quickCues` currently holds, so a different account signing in on
    /// this device doesn't briefly see the previous coach's cues.
    private var lastLoadedCueCoachID: String?

    private static let seededCuesKeyPrefix = "didSeedDefaultCues_"

    /// Coach IDs with a cue load in flight. `loadQuickCues` is fired from an
    /// unstructured Task per player open, so two overlapping loads for a brand-new
    /// coach would both see zero cues and both seed — 16 duplicates.
    private var cueLoadsInFlight = Set<String>()

    /// Sign-out teardown — this singleton otherwise carries one coach's cues and
    /// drill templates into the next account signed in on the same device.
    func reset() {
        quickCues = []
        drillTemplates = []
        lastLoadedCueCoachID = nil
        cueLoadsInFlight = []
        isLoading = false
    }

    // MARK: - Quick Cues

    func loadQuickCues(coachID: String) async {
        // Drop another account's cues before the fetch resolves — this singleton
        // survives sign-out, and a failed fetch leaves `quickCues` untouched.
        if lastLoadedCueCoachID != coachID {
            quickCues = []
            lastLoadedCueCoachID = coachID
        }

        // Concurrent opens must not both seed (see cueLoadsInFlight).
        guard !cueLoadsInFlight.contains(coachID) else { return }
        cueLoadsInFlight.insert(coachID)
        defer { cueLoadsInFlight.remove(coachID) }

        isLoading = true
        let loaded = await fetchQuickCues(coachID: coachID)
        if let loaded { quickCues = loaded }
        isLoading = false

        // Seeding runs OUTSIDE the loading window: Firestore write completions only
        // fire on server ack, so offline these suspend indefinitely — awaiting them
        // under `isLoading` would spin the cue strip forever instead of showing what
        // loaded.
        if let loaded {
            await seedDefaultCuesIfNeeded(coachID: coachID, existingCueCount: loaded.count)
        }
    }

    /// - Returns: the fetched cues, or nil if the fetch failed. The nil case must stay
    ///   distinguishable from an empty result — seeding keys off "empty AND succeeded".
    private func fetchQuickCues(coachID: String) async -> [QuickCue]? {
        do {
            let snapshot = try await db.collection(FC.coachTemplates)
                .document(coachID)
                .collection(FC.quickCues)
                .order(by: "usageCount", descending: true)
                .limit(to: 50)
                .getDocuments()

            return snapshot.documents.compactMap { doc in
                do {
                    var cue = try doc.data(as: QuickCue.self)
                    cue.id = doc.documentID
                    return cue
                } catch {
                    templateLog.warning("Failed to decode QuickCue from doc \(doc.documentID): \(error.localizedDescription)")
                    return nil
                }
            }
        } catch {
            templateLog.warning("Failed to load quick cues: \(error.localizedDescription)")
            return nil
        }
    }

    /// Gives a brand-new coach the default cue set once. Only ever called after a
    /// SUCCESSFUL fetch — seeding on a failed fetch would duplicate an existing
    /// coach's cues. The flag is also set when the coach already has cues (seeded on
    /// another device), so a later transient empty read can't double-seed.
    private func seedDefaultCuesIfNeeded(coachID: String, existingCueCount: Int) async {
        let seedKey = Self.seededCuesKeyPrefix + coachID
        guard !UserDefaults.standard.bool(forKey: seedKey) else { return }

        guard existingCueCount == 0 else {
            UserDefaults.standard.set(true, forKey: seedKey)
            return
        }

        // Claim the seed BEFORE writing. Firestore queues writes made offline and
        // replays them on reconnect, so a seed that looks like it failed may still
        // land later; combined with a retry that would give the coach two of every
        // default cue, and there is no coach-facing way to delete one. Losing the
        // defaults is a much smaller harm than an unremovable duplicate set.
        UserDefaults.standard.set(true, forKey: seedKey)

        let added = await seedDefaultCues(coachID: coachID)
        guard added > 0 else {
            templateLog.warning("Default cue seeding wrote nothing for \(coachID)")
            return
        }

        if let reloaded = await fetchQuickCues(coachID: coachID) {
            quickCues = reloaded
        }
    }

    func addQuickCue(coachID: String, text: String, category: AnnotationCategory) async throws -> QuickCue {
        let data: [String: Any] = [
            "text": text,
            "category": category.rawValue,
            "usageCount": 0,
            "createdAt": FieldValue.serverTimestamp()
        ]

        let docRef = try await db.collection(FC.coachTemplates)
            .document(coachID)
            .collection(FC.quickCues)
            .addDocument(data: data)

        var cue = QuickCue(
            text: text,
            category: category.rawValue,
            usageCount: 0,
            createdAt: Date()
        )
        cue.id = docRef.documentID
        quickCues.insert(cue, at: 0)
        return cue
    }

    func deleteQuickCue(coachID: String, cueID: String) async throws {
        try await db.collection(FC.coachTemplates)
            .document(coachID)
            .collection(FC.quickCues)
            .document(cueID)
            .delete()

        quickCues.removeAll { $0.id == cueID }
    }

    func incrementUsage(coachID: String, cueID: String) async {
        do {
            try await db.collection(FC.coachTemplates)
                .document(coachID)
                .collection(FC.quickCues)
                .document(cueID)
                .updateData(["usageCount": FieldValue.increment(Int64(1))])

            if let index = quickCues.firstIndex(where: { $0.id == cueID }) {
                quickCues[index].usageCount += 1
            }
        } catch {
            templateLog.warning("Failed to increment cue usage: \(error.localizedDescription)")
        }
    }

    // MARK: - Drill Card Templates

    func loadDrillTemplates(coachID: String) async {
        do {
            let snapshot = try await db.collection(FC.coachTemplates)
                .document(coachID)
                .collection(FC.drillCardTemplates)
                .order(by: "usageCount", descending: true)
                .limit(to: 50)
                .getDocuments()

            drillTemplates = snapshot.documents.compactMap { doc in
                do {
                    var t = try doc.data(as: SavedDrillTemplate.self)
                    t.id = doc.documentID
                    return t
                } catch {
                    templateLog.warning("Failed to decode SavedDrillTemplate from doc \(doc.documentID): \(error.localizedDescription)")
                    return nil
                }
            }
        } catch {
            templateLog.warning("Failed to load drill templates: \(error.localizedDescription)")
        }
    }

    func saveDrillTemplate(
        coachID: String,
        name: String,
        templateType: String,
        categoryNames: [String],
        defaultSummary: String?
    ) async throws -> SavedDrillTemplate {
        var data: [String: Any] = [
            "name": name,
            "templateType": templateType,
            "categoryNames": categoryNames,
            "usageCount": 0,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let defaultSummary, !defaultSummary.isEmpty {
            data["defaultSummary"] = defaultSummary
        }

        let docRef = try await db.collection(FC.coachTemplates)
            .document(coachID)
            .collection(FC.drillCardTemplates)
            .addDocument(data: data)

        var template = SavedDrillTemplate(
            id: docRef.documentID,
            name: name,
            templateType: templateType,
            categoryNames: categoryNames,
            defaultSummary: defaultSummary?.isEmpty == true ? nil : defaultSummary,
            usageCount: 0,
            createdAt: Date()
        )
        template.id = docRef.documentID
        drillTemplates.insert(template, at: 0)
        return template
    }

    func deleteDrillTemplate(coachID: String, templateID: String) async throws {
        try await db.collection(FC.coachTemplates)
            .document(coachID)
            .collection(FC.drillCardTemplates)
            .document(templateID)
            .delete()

        drillTemplates.removeAll { $0.id == templateID }
    }

    func incrementDrillTemplateUsage(coachID: String, templateID: String) async {
        do {
            try await db.collection(FC.coachTemplates)
                .document(coachID)
                .collection(FC.drillCardTemplates)
                .document(templateID)
                .updateData(["usageCount": FieldValue.increment(Int64(1))])

            if let index = drillTemplates.firstIndex(where: { $0.id == templateID }) {
                drillTemplates[index].usageCount += 1
            }
        } catch {
            templateLog.warning("Failed to increment drill template usage: \(error.localizedDescription)")
        }
    }

    // MARK: - Default Cues

    /// Seeds default quick cues for a new coach.
    /// - Returns: how many cues were actually written, so the caller only records
    ///   "seeded" when at least one landed (a total network failure must retry later).
    @discardableResult
    func seedDefaultCues(coachID: String) async -> Int {
        let defaults: [(String, AnnotationCategory)] = [
            ("Good follow-through", .positive),
            ("Elbow drop", .mechanics),
            ("Stay back", .timing),
            ("Good approach", .positive),
            ("Check swing path", .mechanics),
            ("Timing early", .timing),
            ("Timing late", .timing),
            ("Nice rep", .positive)
        ]

        var added = 0
        for (text, category) in defaults {
            if (try? await addQuickCue(coachID: coachID, text: text, category: category)) != nil {
                added += 1
            }
        }
        return added
    }
}
