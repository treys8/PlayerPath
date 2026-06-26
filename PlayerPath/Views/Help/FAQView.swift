//
//  FAQView.swift
//  PlayerPath
//
//  Frequently Asked Questions
//

import SwiftUI

struct FAQView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.ppIsGolf) private var isGolf
    @State private var expandedQuestions: Set<Int> = []
    @State private var searchText = ""

    private var isCoach: Bool { authManager.userRole == .coach }

    /// The active question set for the current role (and sport, for athletes).
    private var faqs: [(question: String, answer: String)] {
        if isCoach { return coachFAQs }
        return isGolf ? golfAthleteFAQs : athleteFAQs
    }

    private var filteredFaqs: [(question: String, answer: String)] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return faqs }
        let q = searchText.lowercased()
        return faqs.filter {
            $0.question.lowercased().contains(q) || $0.answer.lowercased().contains(q)
        }
    }

    var body: some View {
        List {
            if filteredFaqs.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ForEach(Array(filteredFaqs.enumerated()), id: \.offset) { index, faq in
                    FAQItem(
                        question: faq.question,
                        answer: faq.answer,
                        isExpanded: expandedQuestions.contains(index)
                    ) {
                        if expandedQuestions.contains(index) {
                            expandedQuestions.remove(index)
                        } else {
                            expandedQuestions.insert(index)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search FAQ")
        .onChange(of: searchText) { expandedQuestions.removeAll() }
        .navigationTitle("FAQ")
    }

    private let athleteFAQs: [(question: String, answer: String)] = [
        (
            question: "How do I record my first video?",
            answer: "Tap the 'Quick Record' button on your Dashboard. The camera opens instantly—just record your at-bat and tag the play result. Done!"
        ),
        (
            question: "Why aren't my videos syncing to my other devices?",
            answer: "Videos are uploaded to the cloud automatically when you have an internet connection. If a video isn't showing on another device, make sure both devices are signed into the same account and connected to the internet. Try pulling to refresh to trigger a manual sync."
        ),
        (
            question: "What's the difference between Quick Record and the Videos tab?",
            answer: "Quick Record opens the camera instantly for fast recording—perfect during games. The Videos tab gives you more options like quality settings, trimming, and choosing between recording or uploading existing videos."
        ),
        (
            question: "Can I edit a video after recording?",
            answer: "Yes! After recording, you'll see a trimming tool. You can also change play result tags later by viewing the video in your library."
        ),
        (
            question: "How do I mark a game as 'Live'?",
            answer: "When creating a game, toggle the 'Start as Live Game' switch. Or for an existing upcoming game, swipe left on it in the Games tab and tap 'Start' (or open the game and tap 'Start Game' from the ••• menu). When a game is live, all videos automatically link to it."
        ),
        (
            question: "What do the statistics mean?",
            answer: "AVG (Batting Average) = Hits ÷ At-Bats. SLG (Slugging) = Total Bases ÷ At-Bats. OBP (On-Base %) = (Hits + Walks + Hit-by-Pitch) ÷ (At-Bats + Walks + Hit-by-Pitch). OPS = OBP + SLG. Higher is better for all stats! See 'Understanding Statistics' in Help for detailed explanations."
        ),
        (
            question: "Can I track multiple athletes (my kids)?",
            answer: "Yes! You can create multiple athlete profiles. Tap the athlete name at the top of the Dashboard to switch between them. Each athlete has separate games, videos, and statistics."
        ),
        (
            question: "How do I delete a game?",
            answer: "In the Games tab, swipe left on a game and tap 'Delete'. This removes the game but keeps any videos you recorded—they'll still be in your video library."
        ),
        (
            question: "What happens to my data if I delete the app?",
            answer: "Video files stored locally will be deleted. However, if you're signed in, all your athletes, games, and statistics sync to the cloud and will reappear when you reinstall and sign in again."
        ),
        (
            question: "Do I need an internet connection?",
            answer: "No! PlayerPath works fully offline. You can record videos, tag plays, and view statistics without internet. When you reconnect, any changes sync automatically to your other devices."
        ),
        (
            question: "Why did my play result tag disappear?",
            answer: "This shouldn't happen! If you see missing tags, try pulling to refresh in the Videos tab to force a sync. If the problem persists, contact support."
        ),
        (
            question: "Can I share videos with my coach?",
            answer: "Yes! With a Pro subscription, you can create Shared Folders and invite coaches by email. Coaches can view your videos and leave notes and drawings directly on them. Go to More → Shared Folders to get started."
        ),
        (
            question: "How much storage do videos use?",
            answer: "High-quality videos use about 60MB per minute. A typical 30-second at-bat uses ~30MB. You can check your available storage in iOS Settings → General → iPhone Storage."
        ),
        (
            question: "Can I export my statistics?",
            answer: "Yes! Go to More → Export Data to download all your information as a JSON file. You can open this in Excel or Google Sheets for further analysis."
        ),
        (
            question: "What's the maximum video length?",
            answer: "Videos are limited to 10 minutes. For typical at-bats (15-45 seconds), this is more than enough."
        ),
        (
            question: "Do walks count as at-bats?",
            answer: "No. Walks increase your On-Base Percentage but do NOT count as at-bats. This is standard baseball statistics."
        ),
        (
            question: "Can I change a video's play result tag?",
            answer: "Yes! View the video in your library, tap the info button, and select a new play result tag. Statistics update automatically."
        ),
        (
            question: "Why is my batting average different from my coach's calculation?",
            answer: "Make sure all your at-bats are tagged correctly. Walks don't count as at-bats. If you're still seeing differences, you may have tagged some outs incorrectly."
        ),
        (
            question: "How do I backup my videos?",
            answer: "Save important videos to your Photos app using the share button. Then enable iCloud Photo Library in iOS Settings to backup to iCloud."
        ),
        (
            question: "Is my data private?",
            answer: "Yes! Your data is protected with industry-standard encryption. Videos are uploaded to Firebase Storage (Google Cloud) for backup and cross-device access. Only you and coaches you explicitly invite can see your content. See our Privacy Policy for full details."
        )
    ]

    private let golfAthleteFAQs: [(question: String, answer: String)] = [
        (
            question: "How do I score a round?",
            answer: "Go to the Rounds tab and tap '+'. Pick your course and date, then enter your score hole-by-hole — strokes, putts, fairway hit (FIR), and green in regulation (GIR). Your score to par updates as you play. See 'Scoring Your Round' in Help for the full walkthrough."
        ),
        (
            question: "What do FIR and GIR mean?",
            answer: "FIR (Fairways in Regulation) is how often your tee shot finds the fairway on par 4s and 5s. GIR (Greens in Regulation) is how often you reach the green in regulation — by your 1st shot on a par 3, 2nd on a par 4, or 3rd on a par 5. They're the two core accuracy stats."
        ),
        (
            question: "How is my handicap estimate calculated?",
            answer: "PlayerPath estimates a handicap from your recent rounds' scores relative to par, so you can track your trend over time. It's a quick estimate — not an official USGA Handicap Index, which requires rated courses and a sanctioned system."
        ),
        (
            question: "Do I have to track every shot?",
            answer: "No. Shot-by-shot tracking is completely optional. You can score a round with just strokes and putts, or turn on shot tracking for a hole to log each shot's lie, club, and distance. Shot tracking unlocks deeper stats like driving distance and miss patterns, but score-only rounds still give you scoring, FIR, GIR, and putts."
        ),
        (
            question: "What's the difference between a round and a tournament?",
            answer: "A round is a single trip around the course. A tournament groups several rounds together — handy for a multi-day event — and shows your combined scoring. You create rounds in the Rounds tab and can link them to a tournament."
        ),
        (
            question: "What happens to my rounds if I delete a tournament?",
            answer: "Nothing is lost. Deleting a tournament only unlinks its rounds — the rounds themselves, with all their scores and videos, stay in your history."
        ),
        (
            question: "Why don't I see driving distance or some shot stats?",
            answer: "Those come from shot-by-shot tracking. Estimated driving distance also needs a tee shot plus a recorded approach distance on a par 4 or 5. If you only scored a round (strokes and putts), you'll still see scoring, FIR, GIR, and putts, but the shot-derived stats won't appear."
        ),
        (
            question: "How are highlight reels created for golf?",
            answer: "When you post a birdie or better in a round, PlayerPath automatically bundles that round's clips into a highlight reel — no setup needed. You can save or share it from the Highlights area."
        ),
        (
            question: "Can I track practice rounds?",
            answer: "Yes. Log a round as a practice round to keep range days and casual rounds separate from competitive ones. Practice rounds still count toward your stats."
        ),
        (
            question: "Can I share my golf videos with a coach?",
            answer: "Yes! Create a Shared Folder, add your swing clips, and invite your coach by email. They can view the clips you share and leave notes and drawings. Go to More → Shared Folders to start."
        ),
        (
            question: "Can I track more than one player?",
            answer: "Yes! You can create multiple athlete profiles and switch between them by tapping the name at the top of the Dashboard. Each profile keeps its own rounds, videos, and stats."
        ),
        (
            question: "Why aren't my videos syncing to my other devices?",
            answer: "Videos upload to the cloud automatically when you have an internet connection. If a clip isn't showing on another device, make sure both are signed into the same account and online. Pull to refresh to trigger a manual sync."
        ),
        (
            question: "How much storage do videos use?",
            answer: "High-quality video uses about 60MB per minute. A typical swing clip of 10–20 seconds uses roughly 10–20MB. Check your available space in iOS Settings → General → iPhone Storage."
        ),
        (
            question: "Can I export my data?",
            answer: "Yes. Go to More → Export Data to download all your rounds, stats, and video info as a JSON file you can open in Excel or Google Sheets."
        ),
        (
            question: "Do I need an internet connection?",
            answer: "No! PlayerPath works fully offline — score rounds, record swings, and view stats without a connection. Everything syncs automatically when you're back online."
        ),
        (
            question: "Is my data private?",
            answer: "Yes! Your data is protected with industry-standard encryption. Videos are uploaded to Firebase Storage (Google Cloud) for backup and cross-device access. Only you and coaches you explicitly invite can see your content. See our Privacy Policy for full details."
        )
    ]

    private let coachFAQs: [(question: String, answer: String)] = [
        (
            question: "How do I accept an athlete's request to connect with me?",
            answer: "Open the Invitations screen and go to the 'Received' tab. Tap 'Accept' on the pending invitation. Once accepted, the athlete's shared folder appears in your athletes and you can start reviewing their clips."
        ),
        (
            question: "How do I invite an athlete who isn't on PlayerPath yet?",
            answer: "Tap 'Invite Athlete' from your Dashboard, then enter the athlete's name and the Parent/Guardian Email. They'll receive an email invitation, and once they accept you'll be able to see the clips they share. You can track invitations you've sent in the 'Sent' tab."
        ),
        (
            question: "Why can't I see all of an athlete's videos?",
            answer: "You only see the clips an athlete explicitly shares with you in a shared folder. You can't browse their full video library, statistics, or account — only what they choose to share."
        ),
        (
            question: "How do I leave feedback on a clip?",
            answer: "Open the clip and use any of four tools: write a note, draw on a frame with the pencil (telestration), build a drill card with ratings, or apply a quick cue. Your athlete sees feedback in real time as you add it."
        ),
        (
            question: "What's the difference between a note, a drawing, a drill card, and a quick cue?",
            answer: "A note is plain written feedback (one per clip — a new note replaces the old one). A drawing is marked up directly on a video frame. A drill card is a structured checklist with 1–5 ratings per category. A quick cue is a short reusable phrase like 'Stay back' you can tap to apply to any clip."
        ),
        (
            question: "Can my athlete reply to my feedback?",
            answer: "Not in this version. Feedback is one-way — from coach to athlete. Your athlete can see everything you leave, but in-app replies aren't available yet."
        ),
        (
            question: "How do I run a live session?",
            answer: "Tap 'New Session' from your Dashboard, pick one or more athletes, and optionally set a date or notes. Start the session to go live, then tap 'Record' to capture clips during the lesson."
        ),
        (
            question: "Why isn't my athlete seeing the clips from my live session?",
            answer: "Clips you record in a session start as drafts under 'My Drafts' and aren't visible to the athlete until you Publish them. Review your drafts, then publish the ones you want them to see."
        ),
        (
            question: "How many athletes can I coach, and what happens if I go over my limit?",
            answer: "Free supports 2 athletes, Instructor 10, Pro Instructor 30, and Academy is unlimited. If you downgrade while over your limit, you get a 7-day grace period to upgrade or choose which athletes to keep. You can see your plan and athlete count in Profile."
        ),
        (
            question: "Do invitations expire?",
            answer: "Yes — invitations expire after 30 days if they aren't accepted. If one expires, just send a new one."
        )
    ]
}

struct FAQItem: View {
    let question: String
    let answer: String
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onTap) {
                HStack {
                    Text(question)
                        .font(.headingMedium)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(answer)
                    .font(.bodyLarge)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }
}

#Preview {
    NavigationStack {
        FAQView()
            .environmentObject(ComprehensiveAuthManager())
    }
}
