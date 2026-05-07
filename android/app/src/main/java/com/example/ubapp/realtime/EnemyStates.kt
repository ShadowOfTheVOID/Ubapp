package com.example.ubapp.realtime

import android.graphics.Color
import kotlin.random.Random

private const val CHASE_RADIUS = 250f
private const val GIVE_UP_RADIUS = 400f

class WanderState(
    private val enemy: EnemyEntity,
    private val worldWidth: () -> Float,
    private val worldHeight: () -> Float
) : State() {
    var peer: ChaseState? = null
    private var pickTimer = 0f

    override fun enter() {
        enemy.sprite.setColor(Color.GRAY)
        enemy.agent.maxSpeed = 90f
        pickNewTarget()
    }

    override fun update(dt: Float) {
        pickTimer -= dt
        if (pickTimer <= 0f) pickNewTarget()

        val dx = enemy.target.x - enemy.sprite.x
        val dy = enemy.target.y - enemy.sprite.y
        if (dx * dx + dy * dy < CHASE_RADIUS * CHASE_RADIUS) {
            peer?.let { enemy.stateMachine.transition(it) }
        }
    }

    private fun pickNewTarget() {
        enemy.agent.targetX = Random.nextFloat() * worldWidth()
        enemy.agent.targetY = Random.nextFloat() * worldHeight()
        pickTimer = 1.5f + Random.nextFloat() * 1.5f
    }
}

class ChaseState(private val enemy: EnemyEntity) : State() {
    var peer: WanderState? = null

    override fun enter() {
        enemy.sprite.setColor(Color.RED)
        enemy.agent.maxSpeed = 170f
    }

    override fun update(dt: Float) {
        enemy.agent.targetX = enemy.target.x
        enemy.agent.targetY = enemy.target.y

        val dx = enemy.target.x - enemy.sprite.x
        val dy = enemy.target.y - enemy.sprite.y
        if (dx * dx + dy * dy > GIVE_UP_RADIUS * GIVE_UP_RADIUS) {
            peer?.let { enemy.stateMachine.transition(it) }
        }
    }
}
