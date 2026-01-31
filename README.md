# Smart-Watch-Alarm

Minimal watchOS app that works as a manual haptic sleep sensor. It is intended to be launched by Apple Shortcuts in a user-defined time window, keep the watch active via a HealthKit workout session, and react to wrist movement while the user sleeps.

## Status

Implemented:
- watchOS-only app scaffold
- HealthKit authorization flow
- Workout session lifecycle (Mind & Body)
- Main UI with a large STOP button and monitoring indicator

Planned (KAN-6/7/8):
- CoreMotion-based movement detection
- Haptic feedback loop with cooldown
- Manual stop logic that shuts down all sensors

## Requirements

- macOS with Xcode 15+
- watchOS 10+ (Apple Watch or watchOS Simulator)
- Apple Developer signing team configured in Xcode

## Setup & Run

1. Open `Smart-Watch-Alarm.xcodeproj` in Xcode.
2. Select a signing team for the `Smart-Watch-Alarm` target.
3. Build and run on an Apple Watch (or simulator).
4. On first launch, grant Health and Motion permissions.

The app starts monitoring immediately on launch. Use the STOP button to end the session.

## Tests

- Xcode: Product > Test
- CLI (example):
  - `xcodebuild test -project Smart-Watch-Alarm.xcodeproj -scheme Smart-Watch-AlarmTests -destination 'platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)'`

## Key Files

- `Smart-Watch-Alarm/SleepSessionManager.swift` — HealthKit authorization and workout session handling
- `Smart-Watch-Alarm/ContentView.swift` — main UI
- `Smart-Watch-Alarm/Info.plist` — privacy usage strings
- `Smart-Watch-AlarmTests/SleepSessionManagerTests.swift` — unit tests for auth flow

## Notes

- The app itself does not manage scheduling. Use Shortcuts to launch it inside your desired wake window.
- Motion detection and haptics are pending and will be added in the next stories.
