package com.example.ubapp.realtime

import android.graphics.Canvas

abstract class Component {
    var entity: Entity? = null
    open fun update(dt: Float) {}
    open fun render(canvas: Canvas) {}
}

class Entity {
    private val components = mutableListOf<Component>()

    fun add(component: Component): Entity {
        component.entity = this
        components += component
        return this
    }

    inline fun <reified T : Component> get(): T? =
        componentList().firstOrNull { it is T } as T?

    fun componentList(): List<Component> = components

    fun update(dt: Float) {
        for (c in components) c.update(dt)
    }

    fun render(canvas: Canvas) {
        for (c in components) c.render(canvas)
    }
}
