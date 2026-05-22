import SwiftUI

/// Read-only rules sheet for the local single-device games (Tic-Tac-Toe,
/// Connect Four) which have no lobby tutorial vote. Renders a `GameTutorial`'s
/// sections.
struct TutorialSheet: View {
    let tutorial: GameTutorial
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(tutorial.sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.heading).font(.headline)
                            Text(section.body).font(.body).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(tutorial.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
