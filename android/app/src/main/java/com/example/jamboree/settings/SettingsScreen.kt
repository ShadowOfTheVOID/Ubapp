package com.example.ubapp.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.ubapp.ads.AdManager
import com.example.ubapp.theme.MonoLabel
import com.example.ubapp.theme.Ub
import com.example.ubapp.theme.UbappTheme
import com.example.ubapp.theme.ubCard

@Composable
fun SettingsScreen(onBack: () -> Unit) {
    val ctx = LocalContext.current
    var hostName by remember { mutableStateOf(AppSettings.hostName(ctx)) }
    var diagnostics by remember { mutableStateOf(AppSettings.diagnosticsEnabled(ctx)) }
    var adFree by remember { mutableStateOf(AdManager.isAdFree(ctx)) }

    UbappTheme {
        Column(
            Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("‹", color = Ub.Accent, fontSize = 26.sp,
                     modifier = Modifier.clickable(onClick = onBack))
                Spacer(Modifier.width(10.dp))
                Text("Settings", fontSize = 22.sp, color = Ub.Foreground)
            }

            Group("Hosting",
                  "The name other players see when you host. Defaults to \"Host\" if left blank.") {
                Row(
                    Modifier.fillMaxWidth().ubCard().padding(horizontal = 16.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Host name", fontSize = 15.sp, color = Ub.Foreground)
                    Spacer(Modifier.weight(1f))
                    BasicTextField(
                        value = hostName,
                        onValueChange = { hostName = it; AppSettings.setHostName(ctx, it) },
                        singleLine = true,
                        textStyle = TextStyle(color = Ub.Accent, fontSize = 15.sp, textAlign = TextAlign.End),
                        cursorBrush = SolidColor(Ub.Accent),
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                        modifier = Modifier.weight(1f),
                        decorationBox = { inner ->
                            Box(contentAlignment = Alignment.CenterEnd) {
                                if (hostName.isEmpty()) {
                                    Text("Host", color = Ub.Faint, fontSize = 15.sp,
                                         modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.End)
                                }
                                inner()
                            }
                        },
                    )
                }
            }

            Group("Developer",
                  "Shows the host connection log on the hosting screen. Useful for debugging join issues.") {
                Row(
                    Modifier.fillMaxWidth().ubCard().padding(horizontal = 16.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Diagnostics", Modifier.weight(1f), fontSize = 15.sp, color = Ub.Foreground)
                    Switch(
                        checked = diagnostics,
                        onCheckedChange = { diagnostics = it; AppSettings.setDiagnostics(ctx, it) },
                    )
                }
            }

            Group("Upgrade",
                  "One-time purchase. Removes all ad banners and post-game interstitials permanently. No content is locked.") {
                if (adFree) {
                    Row(
                        Modifier.fillMaxWidth().ubCard().padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("Remove Ads", Modifier.weight(1f), fontSize = 15.sp, color = Ub.Foreground)
                        Text("Purchased ✓", fontSize = 13.sp, color = Ub.Accent)
                    }
                } else {
                    Row(
                        Modifier.fillMaxWidth().ubCard().padding(horizontal = 16.dp, vertical = 14.dp)
                            .clickable {
                                // TODO: launch Play Billing flow via BillingClient
                                // On purchase success, call: AdManager.setAdFree(ctx, true); adFree = true
                            },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("Remove Ads", Modifier.weight(1f), fontSize = 15.sp, color = Ub.Foreground)
                        Text("\$2.99", fontSize = 13.sp, color = Ub.Accent)
                    }
                }
            }
        }
    }
}

@Composable
private fun Group(title: String, footer: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        MonoLabel(title)
        content()
        Text(footer, fontSize = 12.sp, color = Ub.Muted)
    }
}
