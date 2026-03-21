//
//  CoachTemplateService.swift
//  PlayerPath
//
//  Firestore CRUD for coach quick cues and annotation templates.
//

import Foundation
import Combine
import FirebaseFirestore
import os

private let templateLog = Logger(subsystem: "com.playerpath.app", category: "CoachTemplates")

@MainActor
class CoachTemplateService: ObservableObject {
    static let shared = CoachTemplateService()

    @Published var quickCues: [QuickCue] = []
    @Published var isLoading = false

    private let db = Firestore.firestore()

    // MARK: - Quick Cues

    func loadQuickCues(coachID: String) async {
        isLoading = true
        do {
            let snapshot = try await db.collection("coachTemplates")
                .document(coachID)
                .collection("quickCues")
                .order(by: "usageCount", descending: true)
                .limit(to: 50)
                .getDocuments()

            quickCues = snapshot.documents.compactMap { doc in
                var cue = try? doc.data(as: QuickCue.self)
                cue?.id = doc.documentID
                return cue
            }
        } catch {
            templateLog.warning("Failed to load quick cues: \(error.localizedDescription)")
        }
        isLoading = false
    }

    func addQuickCue(coachID: String, text: String, category: AnnotationCategory) async throws -> QuickCue {
        let data: [String: Any] = [
            "text": text,
            "category": category.rawValue,
            "usageCount": 0,
            "createdAt": FieldValue.serverTimestamp()
        ]

        let docRef = try await db.collection("coachTemplates")
            .document(coachID)
            .collection("quickCues")
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
        try await db.collection("coachTemplates")
            .document(coachID)
            .collection("quickCues")
            .document(cueID)
            .delete()

        quickCues.removeAll { $0.id == cueID }
    }

    func incrementUsage(coachID: String, cueID: String) async {
        do {
            try await db.collection("coachTemplates")
                .document(coachID)
                .collection("quickCues")
                .document(cueID)
                .updateData(["usageCount": FieldValue.increment(Int64(1))])

            if let index = quickCues.firstIndex(where: { $0.id == cueID }) {
                quickCues[index].usageCount += 1
            }
        } catch {
            templateLog.warning("Failed to increment cue usage: \(error.localizedDescription)")
        }
    }

    // MARK: - Default Cues

    /// Seeds default quick cues for a new coach
    func seedDefaultCues(coachID: String) async {
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

        for (text, category) in defaults {
            _ = try? await addQuickCue(coachID: coachID, text: text, category: category)
        }
    }
}
