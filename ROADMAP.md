# PlayerPath Roadmap

Tracking potential features and bug fixes by release.

---

## 5.0.1 — Bug Fixes
<!-- Patch release for any bugs found after 5.0 launch -->

- [ ] _No known issues yet_

---

## 5.1 — Next Feature Release

### Activity Feed
- [ ] Shared feed between coach and athlete (new clips, feedback, drill cards, milestones)
- [ ] Coach-posted updates visible to their athletes
- [ ] Stat milestones surfaced automatically ("You hit .400 this week")

### Side-by-Side Video Comparison
- [ ] Compare two clips (lesson vs game, before vs after, good swing vs bad swing)
- [ ] Available to both athletes (own clips) and coaches (athlete clips)

### Session Templates (Coach)
- [ ] Reusable lesson plan builder (drill name, duration, notes per segment)
- [ ] Start a session from a template to pre-populate structure
- [ ] Template library with create/edit/delete

### Calendar Integration
- [ ] Sync games and scheduled sessions to iOS calendar (EventKit)
- [ ] Reminders for upcoming games and coach sessions

### Video & Uploads
- [ ] Route athlete shared folder uploads through UploadQueueManager for retry support
- [ ] Duplicate detection for athlete shares (check for existing video before upload)

### Anti-Abuse
- [ ] Device fingerprinting to prevent coach free-tier multi-account abuse

### Firestore Cost Optimization
- [ ] Dead code cleanup
- [ ] Query limits and pagination
- [ ] Convert listeners to fetches where appropriate
- [ ] Write reduction

---

## 5.2+ — Future Features

### Telestration / Drawing on Video (Coach)
- [ ] Freeze frame and draw on video (circles, arrows, lines, freehand)
- [ ] Annotate swing path, body position, mechanics
- [ ] Save annotated frames as images or overlay on playback
- [ ] Athlete can view coach drawings alongside the clip

### Shareable Highlight Reel
- [ ] Auto-stitch tagged highlights into a single exportable video
- [ ] Customizable order, transitions, and clip trimming
- [ ] Export for recruiting / social media sharing
- [ ] Tier gating (watermark on free, clean export on Pro)

---

## Future (Unscheduled)

### Multi-Device
- [ ] Cross-device duplicate game detection
- [ ] Per-device storage quota tracking

### Storage
- [ ] Coach delete orphan prevention
- [ ] Photo quota tracking

---

## Completed

### 5.0 — Initial Release (2026-04-01)
- [x] Full athlete video recording and play-by-play tagging
- [x] Coach sharing with annotated feedback
- [x] StoreKit 2 subscriptions (Player + Coach tiers)
- [x] SwiftData + Firestore sync
- [x] Background upload queue with retry
- [x] Coach role enabled for new signups
- [x] Live Instruction Sessions (session recording, clip capture, upload queue)
- [x] Coach downgrade athlete selection flow (grace period + selection UI + banners)
- [x] Coach videoType context passthrough (game vs instruction)
- [x] Server-side Pro tier enforcement (Firestore rules + Cloud Functions)
- [x] Upload progress for athlete shared folder uploads (linear progress bar)
- [x] Compression for athlete shared folder uploads
- [x] Email normalization for accounts
- [x] iPad adaptive layouts for stats views
- [x] Notification toggles (game reminders, uploads, weekly stats, coach review reminders)
