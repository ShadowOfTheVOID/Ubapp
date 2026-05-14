import SwiftUI

struct MainMenuView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    NavigationLink("Mafia") { MafiaView() }
                    NavigationLink("Werewolf") { WerewolfView() }
                    NavigationLink("Imposter") { ImposterView() }
                    NavigationLink("Codenames") { CodenamesView() }
                    NavigationLink("Crazy Eights") { CrazyEightsView() }
                    NavigationLink("Tag (BLE proximity)") { TagLobbyView() }
                    NavigationLink("Real-time") { RealtimeView() }
                    NavigationLink("Turn-based (tic-tac-toe)") { TicTacToeView() }
                    NavigationLink("Connect Four") { ConnectFourView() }
                    NavigationLink("Social") { SocialView() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(24)
            }
            .navigationTitle("Ubapp")
        }
    }
}

#Preview { MainMenuView() }
