package com.example.ubapp.realtime

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class RealTimeActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(GameView(this))
    }
}
