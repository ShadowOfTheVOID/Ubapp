package com.example.ubapp.games.realtime

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import androidx.compose.material3.Text
import com.example.ubapp.theme.UbappTheme
import kotlinx.coroutines.delay
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

/**
 * Single-device demo: a player (blue) seeks the last tap; four enemies (red)
 * wander, then chase when they get close. Pure Compose Canvas.
 */
@Composable
fun RealtimeScreen() {
    val world = remember { RealtimeWorld() }
    var tick by remember { mutableLongStateOf(0L) }

    LaunchedEffect(Unit) {
        var last = System.nanoTime()
        while (true) {
            delay(16)
            val now = System.nanoTime()
            val dt = ((now - last) / 1_000_000_000.0).toFloat().coerceAtMost(0.05f)
            last = now
            world.tick(dt)
            tick++
        }
    }

    UbappTheme {
    Box(
        Modifier.fillMaxSize().background(Color.Black)
            .pointerInput(Unit) {
                detectTapGestures { o -> world.target = Offset(o.x, o.y) }
            }
            .pointerInput(Unit) {
                detectDragGestures { change, _ -> world.target = change.position }
            },
    ) {
        Canvas(Modifier.fillMaxSize()) {
            if (!world.spawned) world.seed(Size(size.width, size.height))
            world.bounds = Size(size.width, size.height)
            @Suppress("UNUSED_EXPRESSION") tick
            drawCircle(Color(0xFF4FC3F7), radius = 14f, center = world.player)
            for (e in world.enemies) {
                drawCircle(if (e.chasing) Color.Red else Color(0xFFFFB74D),
                           radius = 12f, center = e.position)
            }
        }
        Text("Drag to move. Enemies wander, then chase.",
             modifier = Modifier.padding(12.dp), color = Color.White.copy(alpha = 0.7f))
    }
    }
}

class RealtimeWorld {
    var player: Offset = Offset(200f, 400f)
    var target: Offset = Offset(200f, 400f)
    val enemies = mutableListOf<Enemy>()
    var bounds: Size = Size(0f, 0f)
    var spawned = false

    class Enemy(var position: Offset) {
        var heading: Offset
        var chasing = false
        init {
            val a = Random.nextDouble(0.0, 2 * Math.PI).toFloat()
            heading = Offset(cos(a), sin(a))
        }
    }

    fun seed(size: Size) {
        bounds = size
        player = Offset(size.width / 2, size.height / 2)
        target = player
        enemies.clear()
        repeat(4) {
            enemies.add(Enemy(Offset(
                Random.nextFloat() * (size.width - 60) + 30,
                Random.nextFloat() * (size.height - 60) + 30)))
        }
        spawned = true
    }

    fun tick(dt: Float) {
        if (!spawned) return
        // Player seeks target.
        val dp = target - player
        if (dp.getDistance() > 2f) player += dp.normalize() * (180f * dt)

        for (e in enemies) {
            val toPlayer = player - e.position
            e.chasing = toPlayer.getDistance() < 160f
            if (e.chasing && toPlayer.getDistance() > 1f) {
                e.heading = toPlayer.normalize()
            } else {
                e.heading = Offset(
                    e.heading.x + Random.nextFloat() * 0.1f - 0.05f,
                    e.heading.y + Random.nextFloat() * 0.1f - 0.05f,
                ).normalize()
            }
            val speed = if (e.chasing) 140f else 60f
            e.position += e.heading * (speed * dt)
            if (e.position.x < 12f || e.position.x > bounds.width - 12f)
                e.heading = Offset(-e.heading.x, e.heading.y)
            if (e.position.y < 12f || e.position.y > bounds.height - 12f)
                e.heading = Offset(e.heading.x, -e.heading.y)
            e.position = Offset(
                e.position.x.coerceIn(12f, bounds.width - 12f),
                e.position.y.coerceIn(12f, bounds.height - 12f),
            )
        }
    }

    private fun Offset.normalize(): Offset {
        val d = getDistance(); return if (d == 0f) Offset.Zero else this / d
    }
}
