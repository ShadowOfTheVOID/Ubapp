package com.example.jamboree.social

import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.snapshots.SnapshotStateList
import com.example.jamboree.settings.AppSettings

/**
 * On-screen host instrumentation, gated behind the **Diagnostics**
 * developer toggle ([AppSettings]). [HostServer] writes connection
 * lifecycle events here; `HostingChrome` renders them when the toggle is on
 * so the host phone can be screen-recorded while debugging join issues.
 */
object HostDiagnostics {
    val lines: SnapshotStateList<String> = mutableStateListOf()

    @Volatile private var start = 0L

    fun reset() {
        synchronized(this) {
            start = System.currentTimeMillis()
            lines.clear()
        }
    }

    fun log(s: String) {
        if (!AppSettings.diagnosticsOn) return
        synchronized(this) {
            if (start == 0L) start = System.currentTimeMillis()
            val t = (System.currentTimeMillis() - start) / 1000.0
            lines.add("[%.1fs] %s".format(t, s))
            if (lines.size > 60) lines.removeAt(0)
        }
    }
}
