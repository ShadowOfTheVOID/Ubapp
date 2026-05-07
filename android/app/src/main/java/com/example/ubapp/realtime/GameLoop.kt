package com.example.ubapp.realtime

import android.graphics.Canvas
import android.view.SurfaceHolder

class GameLoop(
    private val holder: SurfaceHolder,
    private val onUpdate: (Float) -> Unit,
    private val onRender: (Canvas) -> Unit
) : Thread("Ubapp-GameLoop") {

    @Volatile private var running = false
    private val targetFrameNanos = 1_000_000_000L / 60

    fun startLoop() {
        running = true
        start()
    }

    fun stopLoop() {
        running = false
        try { join() } catch (_: InterruptedException) {}
    }

    override fun run() {
        var last = System.nanoTime()
        while (running) {
            val frameStart = System.nanoTime()
            val dtNanos = frameStart - last
            last = frameStart
            val dt = (dtNanos / 1_000_000_000.0).toFloat().coerceAtMost(1f / 20f)

            onUpdate(dt)

            val canvas: Canvas? = try { holder.lockCanvas() } catch (_: IllegalStateException) { null }
            if (canvas != null) {
                try {
                    synchronized(holder) { onRender(canvas) }
                } finally {
                    try { holder.unlockCanvasAndPost(canvas) } catch (_: IllegalStateException) {}
                }
            }

            val elapsed = System.nanoTime() - frameStart
            val remaining = targetFrameNanos - elapsed
            if (remaining > 0) {
                try { sleep(remaining / 1_000_000, (remaining % 1_000_000).toInt()) } catch (_: InterruptedException) {}
            }
        }
    }
}
