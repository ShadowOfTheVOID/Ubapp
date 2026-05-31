package com.example.jamboree

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import com.example.jamboree.ads.ConsentManager
import com.example.jamboree.menu.MainMenu

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Handles GDPR/CCPA consent form if required, then initialises MobileAds.
        ConsentManager.initialize(this)
        setContent {
            MaterialTheme {
                Surface { MainMenu() }
            }
        }
    }
}
