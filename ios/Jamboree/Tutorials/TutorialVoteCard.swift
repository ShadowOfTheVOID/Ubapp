import SwiftUI

/// Shared lobby card: "call tutorial vote" → live tally → result, then a
/// readable summary of the tutorial sections with a "Got it" dismiss button
/// once the vote passes. Used by every browser-tier host view.
struct TutorialVoteCard: View {
    /// Mirrors `TutorialVote` snapshot fields we need for rendering.
    struct VoteState {
        var isOpen: Bool
        var yesCount: Int
        var noCount: Int
        var eligibleCount: Int
        var result: Bool?
        var tutorialShown: Bool
    }

    let state: VoteState
    let tutorial: GameTutorial
    let onCall: () -> Void
    let onVote: (Bool) -> Void
    let onDismiss: () -> Void

    @State private var myVote: Bool?
    @State private var pageIndex = 0

    init(state: VoteState, tutorial: GameTutorial, onCall: @escaping () -> Void, onVote: @escaping (Bool) -> Void, onDismiss: @escaping () -> Void) {
        self.state = state
        self.tutorial = tutorial
        self.onCall = onCall
        self.onVote = onVote
        self.onDismiss = onDismiss
    }

    var body: some View {
        if state.tutorialShown {
            EmptyView()
        } else if state.isOpen {
            GroupBox("Show tutorial first?") {
                Text("\(state.yesCount + state.noCount) / \(state.eligibleCount) voted — majority wins.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button { myVote = true; onVote(true) } label: {
                        Text("Yes (\(state.yesCount))").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(myVote == true ? .green : .gray)

                    Button { myVote = false; onVote(false) } label: {
                        Text("No (\(state.noCount))").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(myVote == false ? .red : .gray)
                }
            }
        } else if state.result == true {
            GroupBox(tutorial.title) {
                let sections = tutorial.sections
                let total = sections.count
                let section = sections[pageIndex]

                Text("\(pageIndex + 1) / \(total)")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                VStack(alignment: .leading, spacing: 4) {
                    Text(section.heading).font(.subheadline.bold())
                    Text(section.body).font(.callout).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)

                HStack {
                    Button("Skip") { onDismiss() }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                    Spacer()
                    if pageIndex > 0 {
                        Button("← Back") { pageIndex -= 1 }.buttonStyle(.bordered)
                    }
                    if pageIndex < total - 1 {
                        Button("Next →") { pageIndex += 1 }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Got it — start") { onDismiss() }.buttonStyle(.borderedProminent)
                    }
                }
            }
        } else if state.result == false {
            Text("Majority voted to skip the tutorial.")
                .foregroundStyle(.secondary)
        } else {
            Button("Call tutorial vote", action: onCall)
                .buttonStyle(.bordered)
        }
    }
}
