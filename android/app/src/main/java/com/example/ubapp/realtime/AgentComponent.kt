package com.example.ubapp.realtime

import kotlin.math.sqrt

class AgentComponent(
    var maxSpeed: Float = 200f,
    var maxAccel: Float = 400f
) : Component() {
    var vx = 0f
    var vy = 0f
    var targetX: Float? = null
    var targetY: Float? = null

    override fun update(dt: Float) {
        val sprite = entity?.get<SpriteComponent>() ?: return
        val tx = targetX
        val ty = targetY
        if (tx == null || ty == null) {
            sprite.x += vx * dt
            sprite.y += vy * dt
            return
        }
        val dx = tx - sprite.x
        val dy = ty - sprite.y
        val dist = sqrt(dx * dx + dy * dy)
        if (dist < 1f) {
            vx = 0f
            vy = 0f
            return
        }
        val desiredX = dx / dist * maxSpeed
        val desiredY = dy / dist * maxSpeed
        vx += clamp(desiredX - vx, -maxAccel * dt, maxAccel * dt)
        vy += clamp(desiredY - vy, -maxAccel * dt, maxAccel * dt)
        sprite.x += vx * dt
        sprite.y += vy * dt
    }

    private fun clamp(v: Float, lo: Float, hi: Float): Float =
        if (v < lo) lo else if (v > hi) hi else v
}
