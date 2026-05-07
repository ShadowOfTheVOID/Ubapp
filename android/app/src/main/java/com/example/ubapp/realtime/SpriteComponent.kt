package com.example.ubapp.realtime

import android.graphics.Canvas
import android.graphics.Paint

class SpriteComponent(
    var x: Float,
    var y: Float,
    val radius: Float,
    color: Int
) : Component() {
    private val paint = Paint().apply {
        this.color = color
        isAntiAlias = true
    }

    fun setColor(color: Int) {
        paint.color = color
    }

    override fun render(canvas: Canvas) {
        canvas.drawCircle(x, y, radius, paint)
    }
}
