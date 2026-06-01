import SwiftUI

/// Read-only rules sheet for the local single-device games (Tic-Tac-Toe,
/// Connect Four) which have no lobby tutorial vote. Renders a `GameTutorial`'s
/// sections.
struct TutorialSheet: View {
    let tutorial: GameTutorial
    @Environment(\.dismiss) private var dismiss
    @State private var pageIndex = 0

    var body: some View {
        NavigationStack {
            let sections = tutorial.sections
            let total = sections.count
            let section = sections[pageIndex]

            VStack(alignment: .leading, spacing: 16) {
                Text("\(pageIndex + 1) / \(total)")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                VStack(alignment: .leading, spacing: 4) {
                    Text(section.heading).font(.headline)
                    Text(section.body).font(.body).foregroundStyle(.secondary)
                }

                Spacer()

                HStack {
                    Button("Skip") { dismiss() }
                        .buttonStyle(.bordered)
                        .tint(.secondary)

                    Spacer()

                    if pageIndex > 0 {
                        Button("← Back") { pageIndex -= 1 }
                            .buttonStyle(.bordered)
                    }

                    if pageIndex < total - 1 {
                        Button("Next →") { pageIndex += 1 }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Done") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .navigationTitle(tutorial.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
