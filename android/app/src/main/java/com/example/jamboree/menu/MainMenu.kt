package com.example.jamboree.menu

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.example.jamboree.games.bluffmarket.BluffMarketScreen
import com.example.jamboree.games.bureaucrat.BureaucratScreen
import com.example.jamboree.games.cheat.CheatScreen
import com.example.jamboree.games.codenames.CodenamesScreen
import com.example.jamboree.games.connectfour.ConnectFourScreen
import com.example.jamboree.games.crazyeights.CrazyEightsScreen
import com.example.jamboree.games.president.PresidentScreen
import com.example.jamboree.games.imposter.ImposterScreen
import com.example.jamboree.games.mafia.MafiaScreen
import com.example.jamboree.games.realtime.RealtimeScreen
import com.example.jamboree.games.secrethitler.SecretHitlerScreen
import com.example.jamboree.games.tag.TagLobbyScreen
import com.example.jamboree.games.tictactoe.TicTacToeScreen
import com.example.jamboree.games.werewolf.WerewolfScreen
import com.example.jamboree.join.JoinFlowScreen
import com.example.jamboree.settings.SettingsScreen
import com.example.jamboree.stats.StatBoardScreen
import com.example.jamboree.theme.GameGlyph
import com.example.jamboree.theme.GameGlyphView
import com.example.jamboree.theme.MonoLabel
import com.example.jamboree.theme.PipMark
import com.example.jamboree.theme.Ub
import com.example.jamboree.theme.JamboreeTheme
import com.example.jamboree.theme.Wordmark
import com.example.jamboree.theme.ubAccentCard
import com.example.jamboree.theme.ubCard

private data class MenuItem(
    val route: String,
    val title: String,
    val subtitle: String,
    val players: String,
    val minutes: String?,
    val glyph: GameGlyph,
)
private data class MenuGroup(val title: String, val trailing: String?, val items: List<MenuItem>)

private val groups = listOf(
    MenuGroup(
        "Host a game", "16 in library",
        listOf(
            MenuItem("crazy_eights", "Crazy 8s", "Match suit or rank — eights are wild.",
                     "2–7", "8–15 min", GameGlyph.Crazy8s),
            MenuItem("cheat", "Cheat", "Claim what you played; get called and take the pile.",
                     "3–8", "10–20 min", GameGlyph.Cheat),
            MenuItem("president", "President", "Shed your hand to climb from Scum to President.",
                     "4–7", "15–30 min", GameGlyph.President),
            MenuItem("bluff_market", "Bluff Market", "Trade face-down. One bomb is worth −25.",
                     "3–6", "6–12 min", GameGlyph.BluffMarket),
            MenuItem("mafia", "Mafia", "Mafia kill by night; the town hangs by day.",
                     "5–12", "15–30 min", GameGlyph.Mafia),
            MenuItem("werewolf", "Werewolf", "Seer, Doctor, Hunter. Day vote, night kills.",
                     "5–14", "20–40 min", GameGlyph.Werewolf),
            MenuItem("imposter", "Imposter", "Everyone shares a word — except one.",
                     "4–10", "5–10 min", GameGlyph.Imposter),
            MenuItem("codenames", "Codenames", "Word-association duel for two teams.",
                     "4+", null, GameGlyph.Letter("C")),
            MenuItem("secret_hitler", "Secret Hitler", "Politics, lies, and hidden roles.",
                     "5–10", null, GameGlyph.Letter("S")),
            MenuItem("bureaucrat", "The Bureaucrat", "Deny every request — until a citizen finds the loophole.",
                     "3–10", "10–20 min", GameGlyph.Letter("B")),
        ),
    ),
    MenuGroup(
        "On the move", null,
        listOf(
            MenuItem("tag", "Tag", "BLE proximity tag in the room.", "2+", null, GameGlyph.Letter("T")),
            MenuItem("realtime", "Real-time", "Sandbox realtime networking demo.", "2+", null, GameGlyph.Letter("R")),
        ),
    ),
    MenuGroup(
        "Two-player", null,
        listOf(
            MenuItem("tictactoe", "Tic-Tac-Toe", "Three in a row.", "2", null, GameGlyph.Letter("#")),
            MenuItem("connect_four", "Connect Four", "Four in a row, drop tokens.", "2", null, GameGlyph.Letter("4")),
        ),
    ),
    MenuGroup(
        "More", null,
        listOf(
            MenuItem("statboard", "Stat board", "Play counts and recent games.", "—", null, GameGlyph.Letter("≡")),
        ),
    ),
)

@Composable
fun MainMenu() {
    val nav = rememberNavController()
    NavHost(navController = nav, startDestination = "menu") {
        composable("menu") {
            JamboreeTheme {
                Column(
                    Modifier
                        .fillMaxSize()
                        .statusBarsPadding()
                        .verticalScroll(rememberScrollState())
                        .padding(bottom = 40.dp),
                ) {
                    Header(onSettings = { nav.navigate("settings") })
                    JoinCallout(onClick = { nav.navigate("join") })
                    Spacer(Modifier.height(8.dp))
                    for (group in groups) {
                        MenuSection(group, onItemClick = { nav.navigate(it.route) })
                        Spacer(Modifier.height(24.dp))
                    }
                }
            }
        }
        composable("mafia") { MafiaScreen() }
        composable("werewolf") { WerewolfScreen() }
        composable("imposter") { ImposterScreen() }
        composable("codenames") { CodenamesScreen() }
        composable("crazy_eights") { CrazyEightsScreen() }
        composable("cheat") { CheatScreen() }
        composable("president") { PresidentScreen() }
        composable("bluff_market") { BluffMarketScreen() }
        composable("secret_hitler") { SecretHitlerScreen() }
        composable("bureaucrat") { BureaucratScreen() }
        composable("tag") { TagLobbyScreen() }
        composable("realtime") { RealtimeScreen() }
        composable("tictactoe") { TicTacToeScreen() }
        composable("connect_four") { ConnectFourScreen() }
        composable("statboard") { StatBoardScreen(onBack = { nav.popBackStack() }) }
        composable("join") { JoinFlowScreen() }
        composable("settings") { SettingsScreen(onBack = { nav.popBackStack() }) }
    }
}

@Composable
private fun Header(onSettings: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 16.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            PipMark(size = 20.dp)
            Spacer(Modifier.width(8.dp))
            Wordmark(size = 17)
            Spacer(Modifier.weight(1f))
            Text("⚙", color = Ub.Accent, fontSize = 20.sp,
                 modifier = Modifier.clickable(onClick = onSettings))
        }
        Text("jamboree", fontSize = 32.sp, fontWeight = FontWeight.ExtraBold,
             letterSpacing = (-1).sp, color = Color_White)
        Text("Pass the QR — everyone plays in their browser.",
             fontSize = 13.sp, color = Ub.Muted)
    }
}

@Composable
private fun JoinCallout(onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .ubAccentCard()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(44.dp).clip(RoundedCornerShape(10.dp)).background(Ub.Accent.copy(alpha = 0.22f)),
            contentAlignment = Alignment.Center,
        ) {
            PipMark(size = 22.dp, color = Ub.Accent, accentIndex = 3)
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text("Join a game", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Color_White)
            Text("Scan the host's QR or enter a code.", fontSize = 12.sp, color = Ub.Muted)
        }
        Text("›", fontSize = 18.sp, color = Ub.Muted)
    }
}

@Composable
private fun MenuSection(group: MenuGroup, onItemClick: (MenuItem) -> Unit) {
    Column {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            MonoLabel(group.title)
            Spacer(Modifier.weight(1f))
            if (group.trailing != null) MonoLabel(group.trailing, size = 10, color = Ub.Faint)
        }
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            for (item in group.items) GameTile(item, onClick = { onItemClick(item) })
        }
    }
}

@Composable
private fun GameTile(item: MenuItem, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .ubCard()
            .clickable(onClick = onClick)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        GameGlyphView(item.glyph, size = 56.dp)
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(item.title, fontSize = 17.sp, fontWeight = FontWeight.Bold,
                 letterSpacing = (-0.3).sp, color = Color_White)
            Text(item.subtitle, fontSize = 12.sp, color = Ub.Muted, maxLines = 1)
            Spacer(Modifier.height(4.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                MonoLabel(item.players, size = 9)
                if (item.minutes != null) MonoLabel(item.minutes, size = 9)
            }
        }
        Spacer(Modifier.width(8.dp))
        Text("›", fontSize = 20.sp, color = Ub.Faint)
    }
}

private val Color_White = androidx.compose.ui.graphics.Color.White
