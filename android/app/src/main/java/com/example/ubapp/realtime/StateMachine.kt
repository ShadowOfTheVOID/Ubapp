package com.example.ubapp.realtime

abstract class State {
    open fun enter() {}
    open fun exit() {}
    open fun update(dt: Float) {}
}

class StateMachine(initial: State) {
    var current: State = initial
        private set

    init {
        initial.enter()
    }

    fun transition(to: State) {
        if (to === current) return
        current.exit()
        current = to
        to.enter()
    }

    fun update(dt: Float) {
        current.update(dt)
    }
}
