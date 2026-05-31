package com.example.jamboree.join

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import org.json.JSONObject

/** Mirrors GuestTutorialState in iOS. */
data class GuestTutorialState(
    var isOpen: Boolean = false,
    var yesCount: Int = 0,
    var noCount: Int = 0,
    var eligibleCount: Int = 0,
    var result: Boolean? = null,
    var tutorialShown: Boolean = false,
) {
    companion object {
        fun from(m: JSONObject): GuestTutorialState = GuestTutorialState(
            isOpen = m.optBoolean("isOpen", false),
            yesCount = m.optInt("yesCount", 0),
            noCount = m.optInt("noCount", 0),
            eligibleCount = m.optInt("eligibleCount", 0),
            result = if (m.isNull("result")) null else m.optBoolean("result"),
            tutorialShown = m.optBoolean("tutorialShown", false),
        )
    }
}

data class GuestTutorialContent(
    val title: String,
    val sections: List<Pair<String, String>>,
    val menuSections: List<Pair<String, String>>,
) {
    companion object {
        fun readSections(arr: org.json.JSONArray?): List<Pair<String, String>> {
            if (arr == null) return emptyList()
            return (0 until arr.length()).map {
                val o = arr.getJSONObject(it)
                o.optString("heading") to o.optString("body")
            }
        }
    }
}

/** Mirrors the iOS GuestSeriesState — the running series tally a guest sees. */
data class GuestSeriesState(
    val rounds: Int = 0,
    val scores: List<Pair<String, Int>> = emptyList(),
) {
    val banner: String
        get() = if (rounds == 0) "" else "Series — " + scores.joinToString(" · ") { "${it.first} ${it.second}" }

    companion object {
        fun from(m: JSONObject): GuestSeriesState {
            val obj = m.optJSONObject("scores")
            val list = if (obj == null) emptyList()
                       else obj.keys().asSequence().map { it to obj.optInt(it) }.toList()
            return GuestSeriesState(rounds = m.optInt("rounds", 0), scores = list)
        }
    }
}

@Composable
fun SeriesBannerCard(state: GuestSeriesState) {
    if (state.rounds == 0) return
    Text(state.banner, style = MaterialTheme.typography.bodyMedium)
}

@Composable
fun TutorialGuestCard(
    state: GuestTutorialState,
    content: GuestTutorialContent?,
    myVote: Boolean?,
    onCall: () -> Unit,
    onVote: (Boolean) -> Unit,
) {
    if (state.tutorialShown) return
    when {
        state.isOpen -> ElevatedCard(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp)) {
                Text("Show tutorial first?", style = MaterialTheme.typography.titleSmall)
                Text("${state.yesCount + state.noCount} / ${state.eligibleCount} voted — majority wins.",
                     style = MaterialTheme.typography.bodySmall)
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { onVote(true) }, modifier = Modifier.weight(1f),
                           colors = ButtonDefaults.buttonColors(
                               containerColor = if (myVote == true) Color(0xFF2E7D32) else Color.Gray))
                    { Text("Yes (${state.yesCount})") }
                    Button(onClick = { onVote(false) }, modifier = Modifier.weight(1f),
                           colors = ButtonDefaults.buttonColors(
                               containerColor = if (myVote == false) Color(0xFFC62828) else Color.Gray))
                    { Text("No (${state.noCount})") }
                }
            }
        }
        state.result == true && content != null -> {
            val allSections = content.sections + content.menuSections
            if (allSections.isNotEmpty()) {
                Dialog(
                    onDismissRequest = {},
                    properties = DialogProperties(usePlatformDefaultWidth = false)
                ) {
                    var pageIndex by remember { mutableIntStateOf(0) }
                    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                        Column(
                            Modifier
                                .fillMaxSize()
                                .statusBarsPadding()
                                .navigationBarsPadding()
                                .padding(24.dp)
                        ) {
                            Row(
                                Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(content.title, fontSize = 26.sp, fontWeight = FontWeight.ExtraBold)
                                Text("${pageIndex + 1} / ${allSections.size}",
                                     style = MaterialTheme.typography.bodySmall,
                                     color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Spacer(Modifier.height(24.dp))
                            val (h, b) = allSections[pageIndex]
                            Text(h, style = MaterialTheme.typography.titleMedium)
                            Spacer(Modifier.height(8.dp))
                            Text(b, style = MaterialTheme.typography.bodyMedium,
                                 color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Spacer(Modifier.weight(1f))
                            Row(
                                Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.End,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                if (pageIndex > 0) {
                                    OutlinedButton(onClick = { pageIndex-- }) { Text("← Back") }
                                    Spacer(Modifier.width(8.dp))
                                }
                                if (pageIndex < allSections.size - 1) {
                                    Button(onClick = { pageIndex++ }) { Text("Next →") }
                                } else {
                                    Text("Waiting for the host to finish reading…",
                                         style = MaterialTheme.typography.bodySmall,
                                         color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                }
            }
        }
        state.result == false -> Text("Majority voted to skip the tutorial.",
                                       style = MaterialTheme.typography.bodySmall)
        else -> OutlinedButton(onClick = onCall) { Text("Call tutorial vote") }
    }
}
