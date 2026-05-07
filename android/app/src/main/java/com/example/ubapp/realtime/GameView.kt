package com.example.ubapp.realtime

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import kotlin.random.Random

class GameView(context: Context) : SurfaceView(context), SurfaceHolder.Callback {

    private val player = PlayerEntity(0f, 0f)
    private val enemies = mutableListOf<EnemyEntity>()
    private val hudPaint = Paint().apply {
        color = Color.WHITE
        textSize = 36f
        isAntiAlias = true
    }

    private var loop: GameLoop? = null
    private var spawned = false

    init {
        holder.addCallback(this)
        isFocusable = true
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        if (!spawned) spawnWorld()
        loop = GameLoop(holder, ::update, ::render).also { it.startLoop() }
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        loop?.stopLoop()
        loop = null
    }

    private fun spawnWorld() {
        player.sprite.x = width / 2f
        player.sprite.y = height / 2f

        repeat(4) {
            val ex = Random.nextFloat() * width
            val ey = Random.nextFloat() * height
            enemies += EnemyEntity(
                ex, ey,
                target = player.sprite,
                worldWidth = { width.toFloat() },
                worldHeight = { height.toFloat() }
            )
        }
        spawned = true
    }

    fun update(dt: Float) {
        player.entity.update(dt)
        for (enemy in enemies) enemy.update(dt)
    }

    fun render(canvas: Canvas) {
        canvas.drawColor(Color.BLACK)
        for (enemy in enemies) enemy.entity.render(canvas)
        player.entity.render(canvas)
        canvas.drawText("Tap to move. Enemies wander, then chase.", 24f, 56f, hudPaint)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_DOWN || event.action == MotionEvent.ACTION_MOVE) {
            player.moveTo(event.x, event.y)
            return true
        }
        return super.onTouchEvent(event)
    }
}
