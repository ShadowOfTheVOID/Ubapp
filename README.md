# Ubapp

iPhone game scaffold built on **SpriteKit + GameplayKit**, with three modes wired up:

- **Real-time** — entity/component scene with steering agents (`GKAgent2D`) and a state machine (`GKStateMachine`) that flips enemies between Wander and Chase.
- **Turn-based** — tic-tac-toe driven by `GKGameModel` + `GKMinmaxStrategist` (depth-6 minimax AI).
- **Social** — Game Center sign-in and dashboard via `GKLocalPlayer` and `GKGameCenterViewController`, plus a `GKLeaderboard.submitScore` helper.

## Open in Xcode

Open `Ubapp.xcodeproj` in Xcode 15+, select an iPhone simulator, and run.

Default target: iOS 16, iPhone + iPad. Bundle id: `com.example.Ubapp` (change in the target's Signing & Capabilities).

## Structure

```
Ubapp/
├── AppDelegate.swift             # auth + scene config
├── SceneDelegate.swift           # window root
├── MainMenuViewController.swift  # 3 mode buttons
├── GameViewController.swift      # hosts SpriteKit scenes
├── RealTime/
│   ├── RealTimeScene.swift       # SKScene driving entities each frame
│   ├── PlayerEntity.swift        # tap-to-move via GKBehavior seek goal
│   ├── EnemyEntity.swift         # owns a GKStateMachine
│   ├── EnemyStateMachine.swift   # WanderState / ChaseState
│   ├── SpriteComponent.swift     # GKComponent wrapping SKShapeNode
│   └── AgentComponent.swift      # GKAgent2D bridged to its sprite
├── TurnBased/
│   ├── TicTacToeModel.swift      # GKGameModel + Move + Player
│   └── TurnBasedViewController.swift  # 3x3 board UI, AI on background queue
└── Social/
    └── GameCenterManager.swift   # auth + dashboard + score submit
```

## Game Center

To actually use leaderboards/achievements you need to:

1. Add the **Game Center** capability under Signing & Capabilities.
2. Configure a leaderboard ID in App Store Connect, then pass it to `GameCenterManager.shared.submit(score:leaderboard:)`.
3. Sign in to Game Center on the device/simulator.
