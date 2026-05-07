package com.example.ubapp.realtime

import android.graphics.Color

class EnemyEntity(
    x: Float,
    y: Float,
    val target: SpriteComponent,
    private val worldWidth: () -> Float,
    private val worldHeight: () -> Float
) {
    val entity = Entity()
    val sprite = SpriteComponent(x, y, radius = 16f, color = Color.GRAY)
    val agent = AgentComponent(maxSpeed = 140f, maxAccel = 280f)

    val stateMachine: StateMachine

    init {
        entity.add(sprite).add(agent)
        val wander = WanderState(this, worldWidth, worldHeight)
        val chase = ChaseState(this)
        stateMachine = StateMachine(wander)
        wander.peer = chase
        chase.peer = wander
    }

    fun update(dt: Float) {
        stateMachine.update(dt)
        entity.update(dt)
    }
}
