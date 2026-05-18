package com.example.ubapp.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.ubapp.theme.UbappTheme

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(onBack: () -> Unit) {
    val ctx = LocalContext.current
    var hostName by remember { mutableStateOf(AppSettings.hostName(ctx)) }
    var diagnostics by remember { mutableStateOf(AppSettings.diagnosticsEnabled(ctx)) }

    UbappTheme {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("Settings") },
                    navigationIcon = {
                        TextButton(onClick = onBack) { Text("‹ Back") }
                    },
                )
            },
        ) { pad ->
            Column(
                Modifier
                    .padding(pad)
                    .padding(horizontal = 20.dp, vertical = 16.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Hosting", style = MaterialTheme.typography.titleMedium,
                         fontWeight = FontWeight.Bold)
                    OutlinedTextField(
                        value = hostName,
                        onValueChange = {
                            hostName = it
                            AppSettings.setHostName(ctx, it)
                        },
                        label = { Text("Host name") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Text(
                        "The name other players see when you host a game. " +
                            "Defaults to \"Host\" if left blank.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                    )
                }

                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Developer", style = MaterialTheme.typography.titleMedium,
                         fontWeight = FontWeight.Bold)
                    Row(
                        Modifier.fillMaxWidth(),
                        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                    ) {
                        Text("Diagnostics", Modifier.weight(1f),
                             style = MaterialTheme.typography.bodyLarge)
                        Switch(
                            checked = diagnostics,
                            onCheckedChange = {
                                diagnostics = it
                                AppSettings.setDiagnostics(ctx, it)
                            },
                        )
                    }
                    Text(
                        "Shows the host connection log on the hosting screen. " +
                            "Useful for debugging join issues.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                    )
                }
            }
        }
    }
}
