import SwiftUI

/// One line in a private team chat.
struct TeamChatMessage: Identifiable, Equatable {
    let id: String
    let fromId: String
    let fromName: String
    let text: String
}

/// Reusable private-team chat panel for hidden-role games (Mafia, Werewolf,
/// Imposter, Secret Hitler). The evil team isn't allowed to talk openly, so
/// this gives them a back channel to coordinate.
///
/// Colors come from `JamboreeTheme` and keep a strong text/background
/// contrast both ways: own messages are dark ink on magenta, team-mates'
/// messages are white on a raised surface.
struct TeamChatView: View {
    let title: String
    var subtitle: String?
    let messages: [TeamChatMessage]
    let myId: String
    var enabled: Bool = true
    let onSend: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(title, color: JamboreeTheme.accent)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12)).foregroundStyle(JamboreeTheme.muted)
            }
            if messages.isEmpty {
                Text("No messages yet — say something to your team.")
                    .font(.system(size: 13)).foregroundStyle(JamboreeTheme.muted)
            } else {
                VStack(spacing: 6) {
                    ForEach(messages) { bubble($0) }
                }
            }
            HStack(spacing: 8) {
                TextField("Message your team", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .tint(JamboreeTheme.accent)
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(JamboreeTheme.lineStrong, lineWidth: 1))
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(sendDraft)
                    .disabled(!enabled)
                Button(action: sendDraft) {
                    Text("Send")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(JamboreeTheme.onAccent)
                        .padding(.vertical, 10).padding(.horizontal, 16)
                        .background(canSend ? JamboreeTheme.accent : JamboreeTheme.accent.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .disabled(!canSend)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ubCard(radius: JamboreeRadius.panel,
                fill: JamboreeTheme.accentSoft, stroke: JamboreeTheme.accentLine)
    }

    private var canSend: Bool {
        enabled && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraft() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, !t.isEmpty else { return }
        onSend(String(t.prefix(240)))
        draft = ""
    }

    @ViewBuilder private func bubble(_ m: TeamChatMessage) -> some View {
        let mine = m.fromId == myId
        VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
            if !mine {
                Text(m.fromName)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(JamboreeTheme.faint)
            }
            Text(m.text)
                .font(.system(size: 14))
                .foregroundStyle(mine ? JamboreeTheme.onAccent : .white)
                .padding(.vertical, 8).padding(.horizontal, 12)
                .background(mine ? JamboreeTheme.accent : JamboreeTheme.surfaceHi)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }
}
