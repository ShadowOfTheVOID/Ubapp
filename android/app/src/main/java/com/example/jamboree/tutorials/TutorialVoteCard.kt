package com.example.jamboree.tutorials

import androidx.compose.foundation.layout.*
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/** Snapshot of TutorialVote used for rendering. */
fun TutorialVote.snapshot() = TutorialVoteCardState(
    isOpen = isOpen, yesCount = yesCount, noCount = noCount,
    eligibleCount = eligibleCount, result = result, tutorialShown = tutorialShown,
)

data class TutorialVoteCardState(
    val isOpen: Boolean,
    val yesCount: Int,
    val noCount: Int,
    val eligibleCount: Int,
    val result: Boolean?,
    val tutorialShown: Boolean,
)

/** Shared lobby card mirroring TutorialVoteCard.swift. */
@Composable
fun TutorialVoteCard(
    state: TutorialVoteCardState,
    tutorial: GameTutorial,
    onCall: () -> Unit,
    onVote: (Boolean) -> Unit,
    onDismiss: () -> Unit,
) {
    if (state.tutorialShown) return
    var myVote by remember { mutableStateOf<Boolean?>(null) }

    when {
        state.isOpen -> ElevatedCard {
            Column(Modifier.padding(12.dp)) {
                Text("Show tutorial first?", style = MaterialTheme.typography.titleSmall)
                Text("${state.yesCount + state.noCount} / ${state.eligibleCount} voted — majority wins.",
                     style = MaterialTheme.typography.bodySmall)
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        onClick = { myVote = true; onVote(true) },
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (myVote == true) Color(0xFF2E7D32) else Color.Gray),
                    ) { Text("Yes (${state.yesCount})") }
                    Button(
                        onClick = { myVote = false; onVote(false) },
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (myVote == false) Color(0xFFC62828) else Color.Gray),
                    ) { Text("No (${state.noCount})") }
                }
            }
        }
        state.result == true -> ElevatedCard {
            Column(Modifier.padding(12.dp)) {
                var pageIndex by remember { mutableIntStateOf(0) }
                val sections = tutorial.sections
                val total = sections.size
                val section = sections[pageIndex]

                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(tutorial.title, style = MaterialTheme.typography.titleMedium)
                    Text("${pageIndex + 1} / $total",
                         style = MaterialTheme.typography.bodySmall,
                         color = MaterialTheme.colorScheme.onSurfaceVariant)
                }

                Spacer(Modifier.height(8.dp))
                Text(section.heading, style = MaterialTheme.typography.titleSmall)
                Spacer(Modifier.height(2.dp))
                Text(section.body, style = MaterialTheme.typography.bodyMedium)
                Spacer(Modifier.height(12.dp))

                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    OutlinedButton(onClick = onDismiss) { Text("Skip") }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (pageIndex > 0) {
                            OutlinedButton(onClick = { pageIndex-- }) { Text("← Back") }
                        }
                        if (pageIndex < total - 1) {
                            Button(onClick = { pageIndex++ }) { Text("Next →") }
                        } else {
                            Button(onClick = onDismiss) { Text("Got it — start") }
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
