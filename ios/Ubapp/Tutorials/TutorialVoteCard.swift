import SwiftUI

/// Shared lobby card: "call tutorial vote" → live tally → result, then a
/// readable summary of the tutorial sections with a "Got it" dismiss button
/// once the vote passes. Used by every browser-tier host view.
struct TutorialVoteCard: View {
    /// Mirrors `TutorialVote` snapshot fields we need for rendering.
    struct State {
        var isOpen: Bool
        var yesCount: Int
        var noCount: Int
        var eligibleCount: Int
        var result: Bool?
        var tutorialShown: Bool
    }

    let state: State
    let tutorial: GameTutorial
    let onCall: () -> Void
    let onVote: (Bool) -> Void
    let onDismiss: () -> Void

    @State private var myVote: Bool?

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
                ForEach(tutorial.sections.indices, id: \.self) { i in
                    let s = tutorial.sections[i]
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.heading).font(.subheadline.bold())
                        Text(s.body).font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Button("Got it — start") { onDismiss() }
                    .buttonStyle(.borderedProminent)
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
