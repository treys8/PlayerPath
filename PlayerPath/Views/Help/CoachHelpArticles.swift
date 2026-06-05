//
//  CoachHelpArticles.swift
//  PlayerPath
//
//  Coach-facing help article content. Kept separate from the athlete
//  HelpArticle enum so each audience's content stays focused and easy to diff.
//

import SwiftUI

enum CoachHelpArticle: HelpArticleProtocol {
    case coachGettingStarted
    case managingInvitations
    case reviewingClips
    case leavingFeedback
    case liveSessions
    case coachTiersLimits

    var title: String {
        switch self {
        case .coachGettingStarted: return "Coaching on PlayerPath"
        case .managingInvitations: return "Connecting with Athletes"
        case .reviewingClips: return "Reviewing Shared Clips"
        case .leavingFeedback: return "Leaving Feedback"
        case .liveSessions: return "Live Sessions"
        case .coachTiersLimits: return "Plans & Athlete Limits"
        }
    }

    var icon: String {
        switch self {
        case .coachGettingStarted: return "graduationcap.fill"
        case .managingInvitations: return "person.crop.circle.badge.plus"
        case .reviewingClips: return "rectangle.stack.badge.play"
        case .leavingFeedback: return "pencil.and.outline"
        case .liveSessions: return "dot.radiowaves.left.and.right"
        case .coachTiersLimits: return "person.3.fill"
        }
    }

    var content: String {
        switch self {
        case .coachGettingStarted:
            return """
            Welcome to coaching on PlayerPath! Your coach account is built around reviewing the clips your athletes share and giving them feedback they can act on.

            **What a Coach Account Does**
            • Connect with athletes by invitation
            • Review the game and lesson clips they share with you
            • Leave notes, drawings, drill cards, and quick cues on their videos
            • Run live sessions and capture clips during a lesson

            **Your Dashboard**
            Your Dashboard surfaces a "Needs Your Review" queue — the clips your athletes have shared that you haven't reviewed yet. Start there to stay on top of new videos.

            **An Important Note on Privacy**
            You only ever see the clips an athlete explicitly shares with you through a shared folder. You cannot browse an athlete's full video library, statistics, or account — only what they choose to share.

            **Next Steps**
            • Connect with your first athlete (see "Connecting with Athletes")
            • Learn how shared clips are organized (see "Reviewing Shared Clips")
            • Explore your feedback tools (see "Leaving Feedback")
            """

        case .managingInvitations:
            return """
            There are two ways to connect with an athlete — they can invite you, or you can invite them.

            **An Athlete Invites You**
            1. The athlete adds your email address to share a folder with you
            2. Open the Invitations screen and go to the "Received" tab
            3. Tap "Accept" on the pending invitation
            4. You're connected — their shared folder appears in your athletes

            **You Invite an Athlete**
            1. Tap "Invite Athlete" from your Dashboard
            2. Enter the athlete's name and the Parent/Guardian Email
            3. Optionally add a personal message
            4. Send the invitation

            The parent or guardian receives an email invitation. Once they accept, you'll be able to view the clips they share.

            **Tracking Your Invitations**
            • The "Received" tab shows invitations athletes sent you
            • The "Sent" tab shows invitations you've sent, with their status (awaiting response, accepted, or declined)
            • You can cancel a pending invitation you sent from the "Sent" tab

            **Note:** Invitations expire after 30 days if they aren't accepted. If yours expires, just send a new one.

            **If You're at Your Limit**
            If accepting an athlete would put you over your plan's athlete limit, the invitation shows "Couldn't Accept — Limit Reached." Upgrade your plan to connect with more athletes (see "Plans & Athlete Limits").
            """

        case .reviewingClips:
            return """
            Once you're connected, an athlete's shared clips appear in their folder. Here's how they're organized.

            **Where Clips Live**
            Each connected athlete has a shared folder. Depending on how it was created, you'll see:
            • Games folders — a simple list of all shared clips
            • Lessons folders — two tabs: "My Drafts" (clips you recorded) and "Shared" (clips the athlete shared with you)

            **The Review Queue**
            Your Dashboard's "Needs Your Review" queue collects shared clips you haven't reviewed yet, newest first. Within a games folder you can also filter to "Needs My Review."

            **Filtering**
            If clips have tags, a filter bar appears so you can narrow down to a specific type of play or drill.

            **What You Can and Can't See**
            • You see only the clips an athlete shares in a folder with you
            • You do not see their full library, other coaches' folders, their statistics, or account details
            • Marking a clip reviewed is just for your own tracking — it doesn't change what the athlete sees
            """

        case .leavingFeedback:
            return """
            PlayerPath gives you four ways to give feedback on a clip. All feedback is delivered to your athlete in real time as you create it.

            **1. Notes**
            Leave a written note on a clip. Each clip has one coaching note — saving a new note replaces the previous one. Notes are plain text, not pinned to a specific moment in the video.

            **2. Drawings (Telestration)**
            Tap the pencil icon to draw directly on a frame — circles, arrows, and freehand lines to point out mechanics. Drawings are tied to the moment in the video where you made them, and the athlete sees them play back in place. You get color options, shapes, line widths, and undo.

            **3. Drill Cards**
            Build a structured drill card with categories (each rated 1–5 with optional notes), an optional overall rating, and a summary. Great for a repeatable lesson checklist your athlete can work through.

            **4. Quick Cues**
            Quick cues are short reusable coaching phrases (like "Stay back" or "Follow through"). Create a cue once and tap to apply it to any clip. They appear on the clip as labels.

            **A Note on Replies**
            In this version, feedback is one-way — from coach to athlete. Athletes can see everything you leave, but can't reply to it in-app yet.
            """

        case .liveSessions:
            return """
            Live sessions let you capture clips during an in-person lesson and review them with your athlete.

            **Starting a Session**
            1. Tap "New Session" from your Dashboard
            2. Pick one or more athletes
            3. Optionally set a date and time, or add session notes
            4. Create the session

            **Going Live and Recording**
            When you're ready, start the session to go live. Tap "Record" on the live session card to capture clips with the built-in camera. Each clip is linked to the session.

            **Sharing What You Record**
            Clips you record in a session start as drafts in the athlete's Lessons folder, under "My Drafts." They are not visible to the athlete until you tap "Share Now." Review your drafts, then share the ones you want the athlete to see.

            **Wrapping Up**
            End the session when the lesson is over. You can keep reviewing and sharing clips afterward, then mark the session complete to archive it.
            """

        case .coachTiersLimits:
            return """
            Your coach plan determines how many athletes you can be connected with at once.

            **Plans**
            • Free — up to 2 athletes
            • Instructor — up to 10 athletes
            • Pro Instructor — up to 30 athletes
            • Academy — unlimited athletes

            You can see your current plan and athlete count any time in Profile, under the Subscription section. Tap "Upgrade Plan" or "Manage Plan" to make changes.

            **How the Limit Works**
            The limit counts the athletes you're actively connected with. If accepting a new athlete would put you over, that invitation can't be accepted until you upgrade or free up a slot.

            **If You Downgrade Over Your Limit**
            If you switch to a plan with a lower limit while connected to more athletes than it allows, you get a 7-day grace period. During that window you keep full access and a banner reminds you to choose. After it ends, you'll select which athletes to keep — the rest are disconnected and can re-invite you later.
            """
        }
    }
}

#Preview {
    NavigationStack {
        HelpArticleDetailView(article: CoachHelpArticle.leavingFeedback)
    }
}
