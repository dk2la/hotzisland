import AppKit
import Foundation
import SwiftUI

/// Scripted content for demo mode: one week in the life of Alex Rivera,
/// Head of Marketing at a mid-size software company — agency mail, a
/// launch campaign, a board deck, a conference trip. Dates are relative to
/// "now" so the fixtures never go stale on screen.
@MainActor
enum DemoFixtures {
    // MARK: - Account

    static let userName = "Alex Rivera"
    static let userEmail = "alex@halolabs.co"

    static let emailAccount = EmailAccountConfig(
        email: userEmail,
        imapHost: "imap.gmail.com",
        imapPort: 993,
        smtpHost: "smtp.gmail.com",
        smtpPort: 465,
        smtpUsesSTARTTLS: false,
        presetID: EmailProvider.gmail.rawValue
    )

    static let sentFolder = "[Gmail]/Sent Mail"
    static let spamFolder = "[Gmail]/Spam"
    static let importantFolder = "[Gmail]/Important"

    static let mailFolders = IMAPClient.SpecialFolders(
        junk: spamFolder,
        sent: sentFolder,
        flagged: "[Gmail]/Starred",
        important: importantFolder,
        all: "[Gmail]/All Mail",
        trash: "[Gmail]/Trash",
        drafts: "[Gmail]/Drafts"
    )

    // MARK: - Mail

    static func mailLists(now: Date = Date()) -> [Mailbox: [EmailMessage]] {
        let inbox: [EmailMessage] = [
            mail(1042, from: ("Priya Nair", "priya@studiobloom.agency"),
                 subject: "Fall Launch: final creative round (3 options)",
                 ago: 12 * 60, unread: true, now: now,
                 body: """
                 Hi Alex,

                 Three directions for the hero, links in the shared folder:

                 • "Less noise" — the quiet one, mostly type. Your favourite last week.
                 • "Built for Mondays" — warmer, people-first, works best on LinkedIn.
                 • "Switch on" — bold, product-forward, the one Daniel will like.

                 We need a pick by end of day tomorrow to hold the media dates. Happy to walk you through them at 13:00.

                 Priya
                 """),
            mail(1041, from: ("Google Ads", "ads-noreply@google.com"),
                 subject: "Budget alert: Fall Launch — Search reached its daily limit",
                 ago: 38 * 60, unread: true, now: now,
                 body: """
                 Your campaign "Fall Launch — Search" reached its daily budget of $1,200 at 11:14.

                 Impressions today: 48,210
                 Clicks: 1,943 (CTR 4.0%)
                 Conversions: 87

                 Raise the budget or adjust bids to keep ads running for the rest of the day.
                 """),
            mail(1040, from: ("Daniel Cho", "daniel@halolabs.co"),
                 subject: "Board deck — growth slide by Thursday?",
                 ago: 65 * 60, unread: true, now: now,
                 body: """
                 Alex,

                 Board is Friday morning. Can I have the growth slide by Thursday noon? Pipeline from marketing, CAC trend, and one line on the Fall Launch plan.

                 Keep it to one slide. They loved the last one because it was short.

                 D.
                 """),
            mail(1039, from: ("Sofia Marchetti", "sofia@marchettipr.com"),
                 subject: "Re: TechCrunch embargo — Tuesday 9am ET",
                 ago: 2 * 3600, unread: false, now: now,
                 body: """
                 Confirmed with the reporter: embargo lifts Tuesday 9am ET. She wants two customer quotes and a screenshot by Friday.

                 The Verge passed, but Fast Company is interested in a founder angle — worth 20 minutes of Daniel's time next week?

                 Sofia
                 """),
            mail(1038, from: ("Canva", "receipts@canva.com"),
                 subject: "Your receipt from Canva Teams (#CT-58210)",
                 ago: 3 * 3600, unread: false, now: now,
                 body: """
                 Receipt from Canva
                 Amount paid: $149.90
                 Date paid: today
                 Payment method: Visa •••• 4242

                 Canva Teams — 10 seats, monthly.
                 """),
            mail(1037, from: ("Marcus Lee", "marcus@northpeak.io"),
                 subject: "Co-marketing webinar in October?",
                 ago: 5 * 3600, unread: true, now: now,
                 body: """
                 Hi Alex!

                 Loved your talk at SaaStock. Our audiences overlap a lot — would you be up for a joint webinar in October? "Marketing ops for teams under 50" or similar. We'd co-promote to our 40k list and share leads 50/50.

                 Free for a quick call Tuesday or Wednesday afternoon?

                 Marcus
                 """),
            mail(1036, from: ("Asana", "no-reply@asana.com"),
                 subject: "6 tasks due this week in Fall Launch",
                 ago: 26 * 3600, unread: false, now: now,
                 body: """
                 Due this week

                 • Approve hero creative — Alex Rivera
                 • Landing page copy v3 — Jess Alvarez
                 • Email sequence (3 sends) — Jess Alvarez
                 • Paid social assets — Studio Bloom
                 • Press kit — Sofia Marchetti
                 • Launch day checklist — Alex Rivera

                 Open project
                 """),
            mail(1035, from: ("Web Summit", "speakers@websummit.com"),
                 subject: "Your speaker slot is confirmed",
                 ago: 30 * 3600, unread: false, now: now,
                 body: """
                 Dear Alex,

                 Your talk "Brand in the age of AI: what still needs a human" is confirmed for the Marketing stage, Thursday 14:30.

                 Speaker badge pickup opens Wednesday at 09:00 at the Altice Arena. See you in Lisbon!

                 The Web Summit team
                 """),
            mail(1034, from: ("Jess Alvarez", "jess@halolabs.co"),
                 subject: "Draft: launch blog post v3",
                 ago: 2 * 86_400, unread: false, now: now,
                 body: """
                 v3 is in the doc. Changes since v2:

                 1. Cut the intro in half — we get to the product by line 4.
                 2. Customer quote from Rivera Dental moved up.
                 3. New closing CTA: "Start with one workflow."

                 If you're happy I'll hand it to Sofia for the press kit.
                 Jess
                 """),
            mail(1033, from: ("LinkedIn", "notifications@linkedin.com"),
                 subject: "Your post reached 24,300 members",
                 ago: 3 * 86_400, unread: false, now: now,
                 body: """
                 Your post "We killed our 40-page brand book. Here's what replaced it." is doing well.

                 24,300 impressions · 612 reactions · 88 comments · 41 reposts
                 """),
        ]

        let starredUIDs: Set<UInt32> = [1042, 1040, 1035]
        let importantUIDs: Set<UInt32> = [1042, 1040, 1039]

        let sent: [EmailMessage] = [
            mail(310, in: sentFolder, from: (userName, userEmail),
                 to: ["priya@studiobloom.agency"], toName: "Priya Nair",
                 subject: "Re: Fall Launch: final creative round (3 options)",
                 ago: 8 * 60, unread: false, now: now,
                 body: """
                 Thanks Priya — let's do 13:00. Leaning "Less noise", but I want to see all three on a phone first.
                 """),
            mail(309, in: sentFolder, from: (userName, userEmail),
                 to: ["daniel@halolabs.co"], toName: "Daniel Cho",
                 subject: "Re: Board deck — growth slide by Thursday?",
                 ago: 50 * 60, unread: false, now: now,
                 body: """
                 Thursday noon works. One slide, three numbers, one line on the launch.
                 """),
            mail(308, in: sentFolder, from: (userName, userEmail),
                 to: ["sofia@marchettipr.com"], toName: "Sofia Marchetti",
                 subject: "Re: TechCrunch embargo — Tuesday 9am ET",
                 ago: 28 * 3600, unread: false, now: now,
                 body: """
                 Great news. Quotes and screenshot by Friday — Jess is on it. Yes to Fast Company; I'll find 20 minutes in Daniel's calendar.
                 """),
        ]

        let spam: [EmailMessage] = [
            mail(77, in: spamFolder, from: ("Growth Hacks Pro", "win@fast-leads.biz"),
                 subject: "10,000 guaranteed leads for $99 — today only",
                 ago: 4 * 3600, unread: true, now: now,
                 body: "Click now, limited seats."),
            mail(76, in: spamFolder, from: ("Prize Desk", "claim@lucky-draw.top"),
                 subject: "FINAL NOTICE: your package is waiting",
                 ago: 20 * 3600, unread: true, now: now,
                 body: "Confirm your address to release the parcel."),
        ]

        return [
            .primary: inbox,
            .starred: inbox.filter { starredUIDs.contains($0.uid) },
            .important: inbox.filter { importantUIDs.contains($0.uid) },
            .sent: sent,
            .spam: spam,
        ]
    }

    private static func mail(
        _ uid: UInt32,
        in folder: String = "INBOX",
        from: (String, String),
        to: [String] = [userEmail],
        toName: String? = userName,
        subject: String,
        ago: TimeInterval,
        unread: Bool,
        now: Date,
        body: String
    ) -> EmailMessage {
        EmailMessage(
            uid: uid,
            mailbox: folder,
            subject: subject,
            fromName: from.0,
            fromAddress: from.1,
            to: to,
            toName: toName,
            date: now.addingTimeInterval(-ago),
            isUnread: unread,
            messageID: "<demo-\(folder.lowercased().filter(\.isLetter))-\(uid)@halolabs.co>",
            references: [],
            bodyPlain: body
        )
    }

    // MARK: - Calendar

    static let workCalendar = CalendarInfo(
        id: "demo.work", title: "Work", sourceTitle: "Google",
        color: Color(red: 0.24, green: 0.52, blue: 1.0)
    )
    static let personalCalendar = CalendarInfo(
        id: "demo.personal", title: "Personal", sourceTitle: "iCloud",
        color: Color(red: 0.30, green: 0.78, blue: 0.47)
    )
    static let familyCalendar = CalendarInfo(
        id: "demo.family", title: "Family", sourceTitle: "iCloud",
        color: Color(red: 1.0, green: 0.62, blue: 0.24)
    )

    static var calendars: [CalendarInfo] { [personalCalendar, familyCalendar, workCalendar] }

    static func calendarEvents(calendar: Calendar, now: Date = Date()) -> [CalendarEvent] {
        let today = calendar.startOfDay(for: now)
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func allDay(_ firstOffset: Int, _ lastOffset: Int) -> (Date, Date) {
            let first = calendar.date(byAdding: .day, value: firstOffset, to: today) ?? today
            let last = calendar.date(byAdding: .day, value: lastOffset, to: today) ?? today
            let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: last) ?? last
            return (first, end)
        }
        let me = CalendarEvent.Attendee(name: userName, email: userEmail, status: .accepted, isOrganizer: false, isCurrentUser: true)
        let priya = CalendarEvent.Attendee(name: "Priya Nair", email: "priya@studiobloom.agency", status: .accepted, isOrganizer: true, isCurrentUser: false)
        let jess = CalendarEvent.Attendee(name: "Jess Alvarez", email: "jess@halolabs.co", status: .accepted, isOrganizer: false, isCurrentUser: false)
        let daniel = CalendarEvent.Attendee(name: "Daniel Cho", email: "daniel@halolabs.co", status: .accepted, isOrganizer: true, isCurrentUser: false)
        let sofia = CalendarEvent.Attendee(name: "Sofia Marchetti", email: "sofia@marchettipr.com", status: .tentative, isOrganizer: false, isCurrentUser: false)
        let marcus = CalendarEvent.Attendee(name: "Marcus Lee", email: "marcus@northpeak.io", status: .pending, isOrganizer: false, isCurrentUser: false)
        let sam = CalendarEvent.Attendee(name: "Sam Okafor", email: "sam@halolabs.co", status: .accepted, isOrganizer: false, isCurrentUser: false)

        var events: [CalendarEvent] = []
        func add(
            _ title: String,
            _ start: Date,
            minutes: Int,
            in info: CalendarInfo,
            allDayEnd: Date? = nil,
            link: String? = nil,
            location: String? = nil,
            notes: String? = nil,
            attendees: [CalendarEvent.Attendee] = [],
            organizer: String? = nil,
            editable: Bool = true
        ) {
            let id = "demo.event.\(events.count + 1)"
            events.append(CalendarEvent(
                id: id,
                title: title,
                start: start,
                end: allDayEnd ?? start.addingTimeInterval(TimeInterval(minutes * 60)),
                isAllDay: allDayEnd != nil,
                color: info.color,
                joinURL: link.flatMap(URL.init(string:)),
                location: location,
                notes: notes,
                url: link.flatMap(URL.init(string:)),
                calendarTitle: info.title,
                calendarIdentifier: info.id,
                attendees: attendees,
                organizerName: organizer,
                isEditable: editable,
                eventIdentifier: id
            ))
        }

        add("Q4 planning", at(-3, 11), minutes: 90, in: workCalendar,
            link: "https://meet.google.com/q4p-lann-ing", attendees: [daniel, jess, sam, me], organizer: "Daniel Cho", editable: false)
        add("Dentist", at(-1, 9, 30), minutes: 60, in: personalCalendar, location: "Bright Smile, 4th Ave")
        add("Podcast recording: Marketing Weekly", at(-1, 16), minutes: 45, in: workCalendar,
            link: "https://zoom.us/j/91234567890", notes: "Topic: killing the brand book.")
        add("Marketing standup", at(0, 9, 30), minutes: 15, in: workCalendar,
            link: "https://meet.google.com/mkt-stand-up", attendees: [jess, sam, me])
        add("Campaign review: Fall Launch", at(0, 13), minutes: 60, in: workCalendar,
            link: "https://meet.google.com/fall-laun-ch", location: "Room 2A",
            notes: "Pick the hero direction. Priya walks through all three; check them on a phone.",
            attendees: [priya, jess, sofia, me], organizer: "Priya Nair", editable: false)
        add("1:1 with Jess", at(0, 15, 30), minutes: 30, in: workCalendar,
            link: "https://meet.google.com/one-on-one", attendees: [jess, me])
        add("Yoga", at(0, 19), minutes: 60, in: personalCalendar, location: "Flow Studio, Alameda")
        add("Board deck working session", at(1, 11), minutes: 60, in: workCalendar,
            link: "https://meet.google.com/boa-rdde-ck", attendees: [daniel, me], organizer: "Daniel Cho", editable: false)
        add("Call with Marcus (North Peak)", at(1, 15), minutes: 30, in: workCalendar,
            link: "https://zoom.us/j/98765432100", attendees: [marcus, me])
        add("Dinner with Nina", at(1, 19, 30), minutes: 120, in: personalCalendar, location: "Osteria Nove")
        add("Webinar dry run", at(2, 14), minutes: 60, in: workCalendar,
            link: "https://zoom.us/j/95551234567", notes: "Slides v2, test the demo account.", attendees: [jess, sam, me])
        add("Growth slide due", at(2, 12), minutes: 30, in: workCalendar, notes: "Pipeline, CAC trend, one line on the launch.")
        let (summitStart, summitEnd) = allDay(4, 6)
        add("Web Summit", summitStart, minutes: 0, in: workCalendar, allDayEnd: summitEnd,
            location: "Lisbon", notes: "Talk on Thursday 14:30, Marketing stage.")
        let (birthdayStart, birthdayEnd) = allDay(5, 5)
        add("Mom's birthday", birthdayStart, minutes: 0, in: familyCalendar)
        add("Launch day", at(8, 9), minutes: 30, in: workCalendar, notes: "Embargo lifts 9am ET.")
        add("Flight SFO → LIS", at(3, 18, 45), minutes: 660, in: personalCalendar, location: "SFO, Terminal 2")
        add("Piano lesson (Leo)", at(-6, 17), minutes: 45, in: familyCalendar)
        add("Team offsite", at(12, 9), minutes: 480, in: workCalendar, location: "Half Moon Bay")
        return events
    }

    // MARK: - Playbooks

    static var playbooks: [Playbook] {
        [
            Playbook(name: "Morning review", icon: "sunrise.fill", steps: [
                .openApps(id: UUID(), bundleIDs: ["com.google.Chrome", "com.tinyspeck.slackmacgap", "com.apple.iCal"], layout: .thirds),
                .startTimer(id: UUID(), minutes: 15),
            ]),
            Playbook(name: "Campaign work", icon: "megaphone.fill", steps: [
                .openApps(id: UUID(), bundleIDs: ["com.figma.Desktop", "com.google.Chrome", "com.apple.Notes"], layout: .mainAndSide),
                .startTimer(id: UUID(), minutes: 45),
            ]),
            Playbook(name: "Board deck", icon: "chart.bar.fill", steps: [
                .openApps(id: UUID(), bundleIDs: ["com.apple.iWork.Keynote", "com.apple.iWork.Numbers"], layout: .leftRight),
                .openURLs(id: UUID(), urls: ["https://analytics.google.com"]),
            ]),
            Playbook(name: "Wind down", icon: "moon.stars.fill", steps: [
                .openApps(id: UUID(), bundleIDs: ["com.spotify.client"], layout: .none),
                .startTimer(id: UUID(), minutes: 20),
            ]),
        ]
    }

    // MARK: - Clipboard

    static func clipboardEntries(now: Date = Date()) -> [ClipboardStore.Entry] {
        let items: [(String, TimeInterval)] = [
            ("https://halolabs.co/fall?utm_source=linkedin&utm_medium=social&utm_campaign=fall_launch", 3 * 60),
            ("Less noise. More Mondays that work.", 11 * 60),
            ("Q4 paid budget: $86,400 — search 45%, social 35%, partnerships 20%", 24 * 60),
            ("Embargo lifts Tuesday 9am ET — quotes + screenshot to Sofia by Friday", 48 * 60),
            ("#1F6FEB", 62 * 60),
            ("https://docs.google.com/document/d/launch-blog-post-v3", 2 * 3600),
            ("priya@studiobloom.agency", 3 * 3600),
            ("Alex Rivera · Head of Marketing, Halo Labs · +1 415 555 0142", 5 * 3600),
        ]
        return items.map { text, ago in
            ClipboardStore.Entry(id: UUID(), text: text, copiedAt: now.addingTimeInterval(-ago))
        }
    }

    // MARK: - Assistant

    static func assistantTranscript() -> [AssistantMessage] {
        [
            AssistantMessage(role: .user, text: "What's on my calendar today?"),
            AssistantMessage(
                role: .tool,
                text: "09:30–09:45 Marketing standup\n13:00–14:00 Campaign review: Fall Launch\n15:30–16:00 1:1 with Jess\n19:00–20:00 Yoga",
                toolLabel: "today_events()"
            ),
            AssistantMessage(
                role: .assistant,
                text: "Four things: standup at 9:30, the Fall Launch campaign review at 13:00, your 1:1 with Jess at 15:30 and yoga at 19:00. Want a focus block before the review?"
            ),
        ]
    }

    /// The canned answer the demo assistant gives once its tool has run.
    static func assistantReply(for text: String, toolResult: String?) -> String {
        let lower = text.lowercased()
        if lower.contains("timer") || lower.contains("focus") || lower.contains("pomodoro") {
            return "Timer's running. I'll let you know when it's up."
        }
        if lower.contains("pause") || lower.contains("stop the music") {
            return "Paused. Say \"play\" whenever you're ready."
        }
        if lower.contains("play") || lower.contains("next") || lower.contains("skip") {
            return "Done."
        }
        if lower.contains("mail") || lower.contains("inbox") || lower.contains("unread") {
            return "Four unread. Priya's creative round needs a pick before 13:00 and Daniel wants the growth slide by Thursday; the rest can wait."
        }
        if lower.contains("today") || lower.contains("calendar") || lower.contains("meeting") || lower.contains("schedule") {
            return "That's your day. The campaign review at 13:00 is the big one — everything else is short."
        }
        if lower.contains("note") || lower.contains("remember") || lower.contains("write down") {
            return "Saved to your notes."
        }
        if let toolResult, !toolResult.isEmpty {
            return toolResult
        }
        return "On it. Timers, mail, calendar, playbooks — just ask."
    }

    // MARK: - Files on disk

    /// Root of everything demo mode writes; removed when the mode ends.
    static func makeScratchFolder() -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("HotzIsland Demo", isDirectory: true)
        try? FileManager.default.removeItem(at: base)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func notesFolder(in root: URL, now: Date = Date()) -> URL {
        let folder = root.appendingPathComponent("Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let notes: [(String, String, TimeInterval)] = [
            ("Fall Launch — messaging", """
            # Fall Launch — messaging

            One idea: your team's Monday, without the noise.

            ## Hero options (Studio Bloom)
            - Less noise — quiet, type-led. My pick so far.
            - Built for Mondays — warm, people-first. Best for LinkedIn.
            - Switch on — bold, product-forward. Daniel's pick, probably.

            ## Proof points
            - 2,400 teams on the beta
            - 38% fewer status meetings (Rivera Dental)
            - setup in an afternoon
            """, 25 * 60),
            ("Board deck — growth slide", """
            # Growth slide (one slide!)

            - Marketing-sourced pipeline: $3.1M, +42% QoQ
            - CAC: $412 → $377, trending down 3 quarters straight
            - Fall Launch: press embargo Tue 9am ET, paid live same day, webinar Oct

            Keep it to three numbers and one line. They liked short.
            """, 3 * 3600),
            ("Ideas — Q1 campaigns", """
            # Q1 campaign ideas

            - "The last status meeting" — short film, one office, one Monday
            - Customer stories series: 5 teams, 5 Mondays
            - Partner webinar with North Peak (Marcus) — marketing ops for small teams
            - Retarget the LinkedIn brand-book post: it's still getting comments
            """, 26 * 3600),
            ("Meeting — agency kickoff", """
            # Studio Bloom kickoff

            - Scope: hero creative, 6 paid social sets, landing page visuals
            - Timeline: creative round 1 in 2 weeks, final by the 20th
            - Budget: $48k, 20% held for iterations
            - Next: Priya sends the brief back with questions by Friday
            """, 2 * 86_400),
            ("Podcast questions", """
            # Marketing Weekly — prep

            - Why did you kill the brand book?
            - What replaced it? (one page, five rules, examples)
            - How do you keep 12 people on-message without it?
            - Biggest marketing mistake of the last year — the rebrand teaser
            """, 5 * 86_400),
        ]
        for (title, body, ago) in notes {
            let url = folder.appendingPathComponent(title + ".md")
            try? body.write(to: url, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(-ago)], ofItemAtPath: url.path
            )
        }
        return folder
    }

    static func shelfFiles(in root: URL) -> [URL] {
        let folder = root.appendingPathComponent("Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files: [(String, Int)] = [
            ("Fall Launch deck.key", 4_200_000),
            ("hero-video-v3.mp4", 3_800_000),
            ("Logo pack.zip", 640_000),
            ("Budget Q4.numbers", 210_000),
            ("Press release — Fall Launch.pdf", 1_900_000),
        ]
        return files.map { name, size in
            let url = folder.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: Data(count: size))
            return url
        }
    }
}
