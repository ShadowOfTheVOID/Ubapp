package com.example.ubapp.menu

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.example.ubapp.games.codenames.CodenamesScreen
import com.example.ubapp.games.connectfour.ConnectFourScreen
import com.example.ubapp.games.crazyeights.CrazyEightsScreen
import com.example.ubapp.games.imposter.ImposterScreen
import com.example.ubapp.games.mafia.MafiaScreen
import com.example.ubapp.games.realtime.RealtimeScreen
import com.example.ubapp.games.secrethitler.SecretHitlerScreen
import com.example.ubapp.games.tag.TagLobbyScreen
import com.example.ubapp.games.tictactoe.TicTacToeScreen
import com.example.ubapp.games.werewolf.WerewolfScreen
import com.example.ubapp.join.JoinFlowScreen
import com.example.ubapp.social.SocialScreen
import com.example.ubapp.theme.UbappTheme

private val routes = listOf(
    "mafia" to "Mafia",
    "werewolf" to "Werewolf",
    "imposter" to "Imposter",
    "codenames" to "Codenames",
    "crazy_eights" to "Crazy Eights",
    "secret_hitler" to "Secret Hitler",
    "tag" to "Tag (BLE proximity)",
    "realtime" to "Real-time",
    "tictactoe" to "Turn-based (tic-tac-toe)",
    "connect_four" to "Connect Four",
    "social" to "Social",
    "join" to "Join a game",
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainMenu() {
    val nav = rememberNavController()
    NavHost(navController = nav, startDestination = "menu") {
        composable("menu") {
            UbappTheme {
                Scaffold(topBar = { TopAppBar(title = { Text("Ubapp") }) }) { pad ->
                    Column(
                        Modifier.padding(pad).padding(24.dp).verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        for ((route, label) in routes) {
                            Button(
                                onClick = { nav.navigate(route) },
                                modifier = Modifier.fillMaxWidth(),
                            ) { Text(label) }
                        }
                    }
                }
            }
        }
        composable("mafia") { MafiaScreen() }
        composable("werewolf") { WerewolfScreen() }
        composable("imposter") { ImposterScreen() }
        composable("codenames") { CodenamesScreen() }
        composable("crazy_eights") { CrazyEightsScreen() }
        composable("secret_hitler") { SecretHitlerScreen() }
        composable("tag") { TagLobbyScreen() }
        composable("realtime") { RealtimeScreen() }
        composable("tictactoe") { TicTacToeScreen() }
        composable("connect_four") { ConnectFourScreen() }
        composable("social") { UbappTheme { SocialScreen() } }
        composable("join") { JoinFlowScreen() }
    }
}
