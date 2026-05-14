package com.example.ubapp.games

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/** Placeholder Compose screens wired to their pure engines but without the
 *  full UI. TODO: port each game's screen.dart to a dedicated Compose file
 *  under its games/<name>/ package. These exist to keep MainMenu compiling
 *  while the engines (which carry the real game logic) are already in place. */

@Composable internal fun TODOScreen(title: String, note: String) {
    Surface { Column(Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(64.dp))
        Text(title, style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(16.dp))
        Text(note, textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyMedium)
    } }
}
