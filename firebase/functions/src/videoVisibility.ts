/**
 * Pure helpers for deciding when a shared-folder video should notify anyone.
 *
 * Kept free of firebase-admin so they can be exercised without an emulator.
 *
 * Why "became visible" and not "was created": every shared-folder video doc is
 * written metadata-first as `uploadStatus: 'pending'` and flipped to
 * 'completed' after the bytes land (FirestoreManager.createPendingVideoMetadata
 * → markVideoCompleted). Coach lesson clips additionally start
 * `visibility: 'private'` and are published later. An onCreate-only trigger
 * therefore never saw a visible athlete share — coaches went un-notified from
 * 2026-04-11 until this moved to a visibility transition.
 */

type VideoData = { [key: string]: any } | undefined | null;
type FolderData = { [key: string]: any } | undefined | null;

/** A clip other folder members can see: finished uploading and not a private draft. */
export function isVisibleVideo(video: VideoData): boolean {
  if (!video) return false;
  // Legacy docs carry no uploadStatus at all — those were always visible.
  if (video.uploadStatus === 'pending' || video.uploadStatus === 'failed') return false;
  return video.visibility !== 'private';
}

/** True on the single write where a clip turns visible (upload finished, or draft published). */
export function becameVisible(before: VideoData, after: VideoData): boolean {
  return !isVisibleVideo(before) && isVisibleVideo(after);
}

/**
 * Who uploaded the clip, derived from folder membership rather than the
 * client-written `uploadedByType`. Older builds never wrote 'athlete', and the
 * old in-folder upload path stamped athlete clips as 'coach' — the folder owner
 * is always the athlete regardless of what the doc claims.
 */
export function uploaderRole(video: VideoData, folder: FolderData): 'athlete' | 'coach' | null {
  const uploader: string = video?.uploadedBy || '';
  if (!uploader || !folder) return null;
  if (uploader === folder.ownerAthleteID) return 'athlete';
  const coachIDs: string[] = folder.sharedWithCoachIDs || [];
  return coachIDs.includes(uploader) ? 'coach' : null;
}

/**
 * Coach-facing description of an athlete's clip. `clipDescription()` in index.ts
 * says "your … clip", which is right for the athlete and wrong for the coach.
 */
export function coachFacingClipLabel(video: VideoData): string {
  const opponent = typeof video?.gameOpponent === 'string' ? video.gameOpponent.trim() : '';
  if (opponent) return `a clip vs ${opponent}`;
  if (video?.practiceDate) return 'a practice clip';
  if (video?.isHighlight === true) return 'a highlight';
  return 'a new clip';
}
