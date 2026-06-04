package com.example.jamboree.shared

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.jamboree.theme.MonoLabel
import com.example.jamboree.theme.Ub
import com.example.jamboree.theme.ubCard

/** One line in a private team chat. */
data class TeamChatMessage(
    val id: String,
    val fromId: String,
    val fromName: String,
    val text: String,
)

/**
 * Reusable private-team chat panel for hidden-role games (Mafia, Werewolf,
 * Secret Hitler). The evil team isn't allowed to talk openly, so this gives
 * them a back channel to coordinate.
 *
 * Colors come from [Ub] and keep a strong text/background contrast both ways:
 * own messages are dark ink on magenta, team-mates' messages are white on a
 * raised surface.
 */
@Composable
fun TeamChat(
    title: String,
    subtitle: String?,
    messages: List<TeamChatMessage>,
    myId: String,
    enabled: Boolean = true,
    onSend: (String) -> Unit,
) {
    var draft by remember { mutableStateOf("") }
    val canSend = enabled && draft.trim().isNotEmpty()
    val submit = {
        val t = draft.trim()
        if (enabled && t.isNotEmpty()) {
            onSend(t.take(240))
            draft = ""
        }
    }
    Column(
        Modifier.fillMaxWidth()
            .ubCard(radius = Ub.Radius.panel, fill = Ub.AccentSoft, stroke = Ub.AccentLine)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        MonoLabel(title, color = Ub.Accent)
        if (subtitle != null) Text(subtitle, fontSize = 12.sp, color = Ub.Muted)
        if (messages.isEmpty()) {
            Text("No messages yet — say something to your team.",
                 fontSize = 13.sp, color = Ub.Muted)
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                for (m in messages) Bubble(m, m.fromId == myId)
            }
        }
        Row(Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it },
                modifier = Modifier.weight(1f),
                enabled = enabled,
                singleLine = true,
                placeholder = { Text("Message your team", color = Ub.Faint, fontSize = 14.sp) },
                textStyle = androidx.compose.ui.text.TextStyle(color = Ub.Foreground, fontSize = 14.sp),
                shape = RoundedCornerShape(10.dp),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                keyboardActions = KeyboardActions(onSend = { submit() }),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = Ub.Foreground,
                    unfocusedTextColor = Ub.Foreground,
                    disabledTextColor = Ub.Muted,
                    focusedContainerColor = Color.White.copy(alpha = 0.06f),
                    unfocusedContainerColor = Color.White.copy(alpha = 0.06f),
                    disabledContainerColor = Color.White.copy(alpha = 0.03f),
                    focusedBorderColor = Ub.AccentLine,
                    unfocusedBorderColor = Ub.LineStrong,
                    cursorColor = Ub.Accent,
                ),
            )
            Box(
                Modifier.clip(RoundedCornerShape(10.dp))
                    .background(if (canSend) Ub.Accent else Ub.Accent.copy(alpha = 0.4f))
                    .clickable(enabled = canSend) { submit() }
                    .padding(horizontal = 16.dp, vertical = 14.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text("Send", color = Ub.OnAccent, fontWeight = FontWeight.Bold, fontSize = 14.sp)
            }
        }
    }
}

@Composable
private fun Bubble(m: TeamChatMessage, mine: Boolean) {
    Column(
        Modifier.fillMaxWidth(),
        horizontalAlignment = if (mine) Alignment.End else Alignment.Start,
    ) {
        if (!mine) {
            Text(m.fromName, fontFamily = FontFamily.Monospace, fontSize = 10.sp,
                 fontWeight = FontWeight.SemiBold, color = Ub.Faint)
        }
        Box(
            Modifier.clip(RoundedCornerShape(12.dp))
                .background(if (mine) Ub.Accent else Ub.SurfaceHi)
                .padding(horizontal = 12.dp, vertical = 8.dp),
        ) {
            Text(m.text, fontSize = 14.sp, color = if (mine) Ub.OnAccent else Color.White)
        }
    }
}
