package com.example.ubapp.games.mafia

import androidx.compose.runtime.Composable
import com.example.ubapp.games.TODOScreen

@Composable
fun MafiaScreen() = TODOScreen(
    title = "Mafia",
    note = "Engine ported (MafiaEngine.kt). Host server adapter + UI port pending. " +
           "See ios/Ubapp/Games/Mafia/ for the reference end-to-end wiring.",
)
