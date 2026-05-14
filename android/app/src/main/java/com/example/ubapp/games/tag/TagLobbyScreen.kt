package com.example.ubapp.games.tag

import androidx.compose.runtime.Composable
import com.example.ubapp.games.TODOScreen

@Composable
fun TagLobbyScreen() = TODOScreen(
    title = "Tag (BLE proximity)",
    note = "Engine + protocol ported. BLE central/peripheral via android.bluetooth pending.",
)
