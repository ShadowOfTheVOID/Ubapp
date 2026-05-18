package com.example.ubapp.menu

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
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
import com.example.ubapp.settings.SettingsScreen
import com.example.ubapp.social.SocialScreen
import com.example.ubapp.theme.UbappTheme

private data class MenuItem(val route: String, val title: String, val subtitle: String)
private data class MenuGroup(val title: String, val subtitle: String?, val items: List<MenuItem>)

private val groups = listOf(
    MenuGroup(
        "Party games",
        "Pass the QR — guests play in their browser.",
        listOf(
            MenuItem("mafia", "Mafia", "Hidden roles, find the killer in the dark."),
            MenuItem("werewolf", "Werewolf", "Moonlight whodunit with a hunter twist."),
            MenuItem("imposter", "Imposter", "Bluff your way through a secret word."),
            MenuItem("codenames", "Codenames", "Word association duel for two teams."),
            MenuItem("crazy_eights", "Crazy Eights", "Race to empty your hand."),
            MenuItem("secret_hitler", "Secret Hitler", "Politics, lies, and hidden roles."),
        ),
    ),
    MenuGroup(
        "On the move",
        "Get up, walk around, use your phone's radios.",
        listOf(
            MenuItem("tag", "Tag", "BLE proximity tag in the room."),
            MenuItem("realtime", "Real-time", "Sandbox realtime networking demo."),
        ),
    ),
    MenuGroup(
        "Two-player",
        "Quick turn-based classics for one phone.",
        listOf(
            MenuItem("tictactoe", "Tic-Tac-Toe", "Three in a row."),
            MenuItem("connect_four", "Connect Four", "Four in a row, drop tokens."),
        ),
    ),
    MenuGroup(
        "More",
        null,
        listOf(MenuItem("social", "Social", "Friends, chat, presence demo.")),
    ),
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainMenu() {
    val nav = rememberNavController()
    NavHost(navController = nav, startDestination = "menu") {
        composable("menu") {
            UbappTheme {
                Scaffold(topBar = {
                    TopAppBar(
                        title = { Text("Ubapp") },
                        actions = {
                            TextButton(onClick = { nav.navigate("settings") }) {
                                Text("Settings")
                            }
                        },
                    )
                }) { pad ->
                    Column(
                        Modifier
                            .padding(pad)
                            .padding(horizontal = 20.dp, vertical = 16.dp)
                            .verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(24.dp),
                    ) {
                        JoinCallout(onClick = { nav.navigate("join") })
                        for (group in groups) MenuSection(group, onItemClick = { nav.navigate(it.route) })
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
        composable("settings") { SettingsScreen(onBack = { nav.popBackStack() }) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun JoinCallout(onClick: () -> Unit) {
    val accent = MaterialTheme.colorScheme.primary
    OutlinedCard(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        border = BorderStroke(1.dp, accent.copy(alpha = 0.5f)),
        colors = CardDefaults.outlinedCardColors(containerColor = accent.copy(alpha = 0.12f)),
    ) {
        Row(
            Modifier.fillMaxWidth().padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier
                    .size(44.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(accent.copy(alpha = 0.22f)),
                contentAlignment = Alignment.Center,
            ) {
                Text("QR", fontWeight = FontWeight.Bold, color = accent)
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text("Join a game", style = MaterialTheme.typography.titleMedium)
                Text(
                    "Scan a QR or type an app code.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                )
            }
            Text("›", style = MaterialTheme.typography.titleLarge,
                 color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        }
    }
}

@Composable
private fun MenuSection(group: MenuGroup, onItemClick: (MenuItem) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Column {
            Text(group.title, style = MaterialTheme.typography.titleMedium,
                 fontWeight = FontWeight.Bold)
            if (group.subtitle != null) {
                Text(group.subtitle, style = MaterialTheme.typography.bodySmall,
                     color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f))
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (item in group.items) GameTile(item, onClick = { onItemClick(item) })
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun GameTile(item: MenuItem, onClick: () -> Unit) {
    val accent = MaterialTheme.colorScheme.primary
    OutlinedCard(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.08f)),
        colors = CardDefaults.outlinedCardColors(
            containerColor = Color.White.copy(alpha = 0.04f),
        ),
    ) {
        Row(
            Modifier.fillMaxWidth().padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(accent.copy(alpha = 0.15f)),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    item.title.take(1),
                    color = accent,
                    fontWeight = FontWeight.Bold,
                    style = MaterialTheme.typography.titleMedium,
                )
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(item.title, style = MaterialTheme.typography.titleMedium)
                Text(
                    item.subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                )
            }
            Text("›", style = MaterialTheme.typography.titleLarge,
                 color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        }
    }
}
