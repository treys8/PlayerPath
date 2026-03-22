//
//  FirestoreManager+DrillCards.swift
//  PlayerPath
//
//  Firestore CRUD for drill cards on videos.
//

import Foundation
import FirebaseFirestore
import os

private let drillCardLog = Logger(subsystem: "com.playerpath.app", category: "DrillCards")

extension FirestoreManager {

    // MARK: - Drill Cards

    func createDrillCard(
        videoID: String,
        coachID: String,
        coachName: String,
        templateType: String,
        categories: [DrillCardCategory],
        overallRating: Int?,
        summary: String?
    ) async throws -> DrillCard {
        var data: [String: Any] = [
            "coachID": coachID,
            "coachName": coachName,
            "templateType": templateType,
            "categories": categories.map { [
                "name": $0.name,
                "rating": $0.rating,
                "notes": $0.notes as Any
            ] },
            "isVisibleToAthlete": true,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let overallRating { data["overallRating"] = overallRating }
        if let summary, !summary.isEmpty { data["summary"] = summary }

        let docRef = try await db.collection(FC.videos)
            .document(videoID)
            .collection(FC.drillCards)
            .addDocument(data: data)

        drillCardLog.info("Created drill card \(docRef.documentID) for video \(videoID)")

        var card = DrillCard(
            coachID: coachID,
            coachName: coachName,
            templateType: templateType,
            categories: categories,
            overallRating: overallRating,
            summary: summary,
            createdAt: Date(),
            updatedAt: Date()
        )
        card.id = docRef.documentID
        return card
    }

    func updateDrillCard(
        videoID: String,
        cardID: String,
        categories: [DrillCardCategory],
        overallRating: Int?,
        summary: String?
    ) async throws {
        var data: [String: Any] = [
            "categories": categories.map { [
                "name": $0.name,
                "rating": $0.rating,
                "notes": $0.notes as Any
            ] },
            "isVisibleToAthlete": true,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let overallRating { data["overallRating"] = overallRating }
        else { data["overallRating"] = FieldValue.delete() }
        if let summary, !summary.isEmpty { data["summary"] = summary }
        else { data["summary"] = FieldValue.delete() }

        try await db.collection(FC.videos)
            .document(videoID)
            .collection(FC.drillCards)
            .document(cardID)
            .updateData(data)
    }

    func fetchDrillCards(forVideo videoID: String) async throws -> [DrillCard] {
        let snapshot = try await db.collection(FC.videos)
            .document(videoID)
            .collection(FC.drillCards)
            .order(by: "createdAt", descending: true)
            .limit(to: 10)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            var card = try? doc.data(as: DrillCard.self)
            card?.id = doc.documentID
            return card
        }
    }

    func deleteDrillCard(videoID: String, cardID: String) async throws {
        try await db.collection(FC.videos)
            .document(videoID)
            .collection(FC.drillCards)
            .document(cardID)
            .delete()

        drillCardLog.info("Deleted drill card \(cardID)")
    }
}
