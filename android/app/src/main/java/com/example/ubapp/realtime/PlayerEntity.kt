package com.example.ubapp.realtime

import android.graphics.Color

class PlayerEntity(x: Float, y: Float) {
    val entity = Entity()
    val sprite = SpriteComponent(x, y, radius = 22f, color = Color.parseColor("#3478F6"))
    val agent = AgentComponent(maxSpeed = 260f, maxAccel = 600f)

    init {
        entity.add(sprite).add(agent)
    }

    fun moveTo(x: Float, y: Float) {
        agent.targetX = x
        agent.targetY = y
    }
}
