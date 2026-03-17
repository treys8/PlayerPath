---
name: feedback_versioning
description: App Store version and build numbers must always increase — never suggest going backwards
type: feedback
---

App Store Connect requires version numbers and build numbers to always increase. Never suggest a lower version than what's been previously uploaded.

**Why:** Apple rejects uploads with version/build numbers equal to or lower than previous submissions. The project previously uploaded version 3.11.26, so the App Store version must be 4.0+. Version 1.0 was not accepted for App Store submission because 3.9.26 was already submitted.

**How to apply:** Before suggesting version/build number changes, always check TestFlight/App Store Connect history for the highest previously used numbers. Current state: App Store version is 4.0, build 88. Next build must be 89+.
