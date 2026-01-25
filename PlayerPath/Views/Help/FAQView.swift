//
//  FAQView.swift
//  PlayerPath
//
//  Frequently Asked Questions
//

import SwiftUI

struct FAQView: View {
    @State private var expandedQuestions: Set<Int> = []

    var body: some View {
        List {
            ForEach(Array(faqs.enumerated()), id: \.offset) { index, faq in
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
        .navigationTitle("FAQ")
    }

    private let faqs: [(question: String, answer: String)] = [
        (
            question: "How do I record my first video?",
            answer: "Tap the 'Quick Record' button on your Dashboard. The camera opens instantly—just record your at-bat and tag the play result. Done!"
        ),
        (
            question: "Why aren't my videos syncing to my other devices?",
            answer: "Video FILES don't sync across devices due to their large size (50-100MB each). However, all the METADATA syncs—you can see what videos exist, their tags, statistics, and which games they're from. The actual video stays on the device that recorded it. To access videos on multiple devices, save them to your Photos app or iCloud."
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
            answer: "When creating a game, toggle the 'Start Live' switch. Or for existing games, swipe right on the game in the Games tab and tap 'Start'. When a game is live, all videos automatically link to it."
        ),
        (
            question: "What do the statistics mean?",
            answer: "AVG (Batting Average) = Hits ÷ At-Bats. SLG (Slugging) = Total Bases ÷ At-Bats. OBP (On-Base %) = (Hits + Walks) ÷ (At-Bats + Walks). OPS = OBP + SLG. Higher is better for all stats! See 'Understanding Statistics' in Help for detailed explanations."
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
            answer: "Currently, you can save videos to your Photos app and share them manually. Coach sharing features are coming in a future update!"
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
            answer: "Yes! Your videos are stored locally on your device. Only metadata (tags, dates, statistics) syncs to our servers. See our Privacy Policy for full details."
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
                        .font(.headline)
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
                    .font(.body)
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
    }
}
