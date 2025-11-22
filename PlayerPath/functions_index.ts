/**
 * Firebase Cloud Functions for PlayerPath
 * 
 * This file contains Cloud Functions to support secure video operations,
 * particularly generating signed URLs with expiration for enhanced security.
 * 
 * DEPLOYMENT INSTRUCTIONS:
 * 
 * 1. Install Firebase CLI:
 *    npm install -g firebase-tools
 * 
 * 2. Initialize Cloud Functions (if not already done):
 *    firebase init functions
 *    - Select TypeScript or JavaScript
 *    - Choose to install dependencies
 * 
 * 3. Copy this file to:
 *    functions/src/index.ts (TypeScript)
 *    OR
 *    functions/index.js (JavaScript)
 * 
 * 4. Install additional dependencies:
 *    cd functions
 *    npm install firebase-admin @google-cloud/storage
 * 
 * 5. Deploy:
 *    firebase deploy --only functions
 * 
 * USAGE FROM iOS:
 * 
 * Call these functions using Firebase Functions SDK:
 * 
 * ```swift
 * let functions = Functions.functions()
 * let getSignedURL = functions.httpsCallable("getSignedVideoURL")
 * 
 * let data: [String: Any] = [
 *     "folderID": "folder123",
 *     "fileName": "video.mov",
 *     "expirationHours": 24
 * ]
 * 
 * do {
 *     let result = try await getSignedURL.call(data)
 *     if let url = result.data as? [String: Any],
 *        let signedURL = url["signedURL"] as? String {
 *         print("Signed URL: \(signedURL)")
 *     }
 * } catch {
 *     print("Error: \(error)")
 * }
 * ```
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {getStorage} from "firebase-admin/storage";

// Initialize Firebase Admin
admin.initializeApp();

/**
 * Generates a signed URL for a video file with expiration
 * 
 * Request body:
 * - folderID: string - The shared folder ID
 * - fileName: string - The video file name
 * - expirationHours: number - Hours until URL expires (default: 24)
 * 
 * Returns:
 * - signedURL: string - Time-limited download URL
 * - expiresAt: string - ISO timestamp of expiration
 */
export const getSignedVideoURL = functions.https.onCall(async (data, context) => {
  // Check authentication
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated to get signed URLs"
    );
  }

  const {folderID, fileName, expirationHours = 24} = data;

  // Validate inputs
  if (!folderID || !fileName) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "folderID and fileName are required"
    );
  }

  try {
    // Check if user has access to this folder
    const folderDoc = await admin
      .firestore()
      .collection("sharedFolders")
      .doc(folderID)
      .get();

    if (!folderDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Folder not found");
    }

    const folderData = folderDoc.data();
    const userID = context.auth.uid;

    // Check if user is owner or shared coach
    const isOwner = folderData?.ownerAthleteID === userID;
    const isSharedCoach = folderData?.sharedWithCoachIDs?.includes(userID);

    if (!isOwner && !isSharedCoach) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "User does not have access to this folder"
      );
    }

    // Generate signed URL
    const bucket = getStorage().bucket();
    const filePath = `shared_folders/${folderID}/${fileName}`;
    const file = bucket.file(filePath);

    // Check if file exists
    const [exists] = await file.exists();
    if (!exists) {
      throw new functions.https.HttpsError("not-found", "Video file not found");
    }

    // Calculate expiration time
    const expiresAt = new Date();
    expiresAt.setHours(expiresAt.getHours() + expirationHours);

    // Generate signed URL
    const [signedURL] = await file.getSignedUrl({
      action: "read",
      expires: expiresAt,
    });

    return {
      signedURL,
      expiresAt: expiresAt.toISOString(),
      expiresInHours: expirationHours,
    };
  } catch (error) {
    console.error("Error generating signed URL:", error);
    
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    
    throw new functions.https.HttpsError(
      "internal",
      "Failed to generate signed URL"
    );
  }
});

/**
 * Generates a signed URL for a thumbnail image with expiration
 * 
 * Request body:
 * - folderID: string - The shared folder ID
 * - videoFileName: string - The video file name (thumbnail name will be derived)
 * - expirationHours: number - Hours until URL expires (default: 168 = 7 days)
 * 
 * Returns:
 * - signedURL: string - Time-limited download URL
 * - expiresAt: string - ISO timestamp of expiration
 */
export const getSignedThumbnailURL = functions.https.onCall(
  async (data, context) => {
    // Check authentication
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated to get signed URLs"
      );
    }

    const {folderID, videoFileName, expirationHours = 168} = data;

    // Validate inputs
    if (!folderID || !videoFileName) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "folderID and videoFileName are required"
      );
    }

    try {
      // Check if user has access to this folder
      const folderDoc = await admin
        .firestore()
        .collection("sharedFolders")
        .doc(folderID)
        .get();

      if (!folderDoc.exists) {
        throw new functions.https.HttpsError("not-found", "Folder not found");
      }

      const folderData = folderDoc.data();
      const userID = context.auth.uid;

      // Check if user is owner or shared coach
      const isOwner = folderData?.ownerAthleteID === userID;
      const isSharedCoach = folderData?.sharedWithCoachIDs?.includes(userID);

      if (!isOwner && !isSharedCoach) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "User does not have access to this folder"
        );
      }

      // Derive thumbnail file name
      const baseFileName = videoFileName.replace(/\.[^/.]+$/, "");
      const thumbnailFileName = `${baseFileName}_thumbnail.jpg`;

      // Generate signed URL
      const bucket = getStorage().bucket();
      const filePath = `shared_folders/${folderID}/thumbnails/${thumbnailFileName}`;
      const file = bucket.file(filePath);

      // Check if file exists
      const [exists] = await file.exists();
      if (!exists) {
        throw new functions.https.HttpsError(
          "not-found",
          "Thumbnail file not found"
        );
      }

      // Calculate expiration time
      const expiresAt = new Date();
      expiresAt.setHours(expiresAt.getHours() + expirationHours);

      // Generate signed URL
      const [signedURL] = await file.getSignedUrl({
        action: "read",
        expires: expiresAt,
      });

      return {
        signedURL,
        expiresAt: expiresAt.toISOString(),
        expiresInHours: expirationHours,
      };
    } catch (error) {
      console.error("Error generating signed thumbnail URL:", error);
      
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      
      throw new functions.https.HttpsError(
        "internal",
        "Failed to generate signed thumbnail URL"
      );
    }
  }
);

/**
 * Batch generates signed URLs for multiple videos
 * Useful for displaying lists of videos
 * 
 * Request body:
 * - folderID: string - The shared folder ID
 * - fileNames: string[] - Array of video file names
 * - expirationHours: number - Hours until URLs expire (default: 24)
 * 
 * Returns:
 * - urls: Array of {fileName: string, signedURL: string, expiresAt: string}
 */
export const getBatchSignedVideoURLs = functions.https.onCall(
  async (data, context) => {
    // Check authentication
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated to get signed URLs"
      );
    }

    const {folderID, fileNames, expirationHours = 24} = data;

    // Validate inputs
    if (!folderID || !Array.isArray(fileNames)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "folderID and fileNames array are required"
      );
    }

    // Limit batch size
    if (fileNames.length > 50) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Maximum 50 files per batch request"
      );
    }

    try {
      // Check if user has access to this folder
      const folderDoc = await admin
        .firestore()
        .collection("sharedFolders")
        .doc(folderID)
        .get();

      if (!folderDoc.exists) {
        throw new functions.https.HttpsError("not-found", "Folder not found");
      }

      const folderData = folderDoc.data();
      const userID = context.auth.uid;

      // Check if user is owner or shared coach
      const isOwner = folderData?.ownerAthleteID === userID;
      const isSharedCoach = folderData?.sharedWithCoachIDs?.includes(userID);

      if (!isOwner && !isSharedCoach) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "User does not have access to this folder"
        );
      }

      // Calculate expiration time
      const expiresAt = new Date();
      expiresAt.setHours(expiresAt.getHours() + expirationHours);

      const bucket = getStorage().bucket();

      // Generate signed URLs for all files
      const urlPromises = fileNames.map(async (fileName) => {
        try {
          const filePath = `shared_folders/${folderID}/${fileName}`;
          const file = bucket.file(filePath);

          const [exists] = await file.exists();
          if (!exists) {
            return {fileName, error: "File not found"};
          }

          const [signedURL] = await file.getSignedUrl({
            action: "read",
            expires: expiresAt,
          });

          return {
            fileName,
            signedURL,
            expiresAt: expiresAt.toISOString(),
          };
        } catch (error) {
          console.error(`Error generating URL for ${fileName}:`, error);
          return {fileName, error: "Failed to generate URL"};
        }
      });

      const urls = await Promise.all(urlPromises);

      return {
        urls,
        expiresInHours: expirationHours,
      };
    } catch (error) {
      console.error("Error generating batch signed URLs:", error);
      
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      
      throw new functions.https.HttpsError(
        "internal",
        "Failed to generate batch signed URLs"
      );
    }
  }
);
