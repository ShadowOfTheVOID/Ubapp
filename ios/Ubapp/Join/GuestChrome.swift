import SwiftUI

/// Snapshot of the host's `tutorial_vote_state` message, used by every guest
/// view's lobby tutorial card. Mirrors the host-side `TutorialVoteCard.State`.
struct GuestTutorialState {
    var isOpen = false
    var yesCount = 0
    var noCount = 0
    var eligibleCount = 0
    var result: Bool?
    var tutorialShown = false

    mutating func apply(_ m: [String: Any]) {
        isOpen = m["isOpen"] as? Bool ?? false
        yesCount = m["yesCount"] as? Int ?? 0
        noCount = m["noCount"] as? Int ?? 0
        eligibleCount = m["eligibleCount"] as? Int ?? 0
        result = m["result"] as? Bool
        tutorialShown = m["tutorialShown"] as? Bool ?? false
    }
}

struct GuestTutorialContent {
    let title: String
    let sections: [(heading: String, body: String)]
    let menuSections: [(heading: String, body: String)]

    static func readSections(_ raw: Any?) -> [(String, String)] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.map { ($0["heading"] as? String ?? "", $0["body"] as? String ?? "") }
    }
}

/// Lobby tutorial card for app guests — mirrors the browser bundle's
/// `viewTutorialVote` + `viewTutorialBanner` blocks.
struct TutorialGuestCard: View {
    let state: GuestTutorialState
    let content: GuestTutorialContent?
    let myVote: Bool?
    let onCall: () -> Void
    let onVote: (Bool) -> Void

    var body: some View {
        if state.tutorialShown {
            EmptyView()
        } else if state.isOpen {
            GroupBox("Show tutorial first?") {
                Text("\(state.yesCount + state.noCount) / \(state.eligibleCount) voted — majority wins.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button { onVote(true) } label: {
                        Text("Yes (\(state.yesCount))").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(myVote == true ? .green : .gray)
                    Button { onVote(false) } label: {
                        Text("No (\(state.noCount))").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(myVote == false ? .red : .gray)
                }
            }
        } else if state.result == true, let c = content {
            GroupBox(c.title) {
                ForEach(Array(c.sections.enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.heading).font(.subheadline.bold())
                        Text(s.body).font(.callout).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
                ForEach(Array(c.menuSections.enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.heading).font(.subheadline.bold())
                        Text(s.body).font(.callout).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
                Text("Waiting for the host to finish reading…")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } else if state.result == false {
            Text("Majority voted to skip the tutorial.")
                .foregroundStyle(.secondary).font(.caption)
        } else {
            Button("Call tutorial vote", action: onCall).buttonStyle(.bordered)
        }
    }
}
