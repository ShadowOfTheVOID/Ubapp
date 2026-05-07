package com.example.ubapp

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.example.ubapp.realtime.RealTimeActivity
import com.example.ubapp.social.SocialActivity
import com.example.ubapp.turnbased.TurnBasedActivity
import com.google.android.material.button.MaterialButton

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        findViewById<MaterialButton>(R.id.btnRealTime).setOnClickListener {
            startActivity(Intent(this, RealTimeActivity::class.java))
        }
        findViewById<MaterialButton>(R.id.btnTurnBased).setOnClickListener {
            startActivity(Intent(this, TurnBasedActivity::class.java))
        }
        findViewById<MaterialButton>(R.id.btnSocial).setOnClickListener {
            startActivity(Intent(this, SocialActivity::class.java))
        }
    }
}
