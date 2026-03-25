---
name: Basket Trainer App
description: Basketball training app for Garmin Forerunner 255 + iPhone, tracks shots made/missed
type: project
---

Building a basketball shot tracker app with two components:
- Garmin Forerunner 255 app (Monkey C / Connect IQ SDK)
- iPhone companion app (SwiftUI, iOS 16+)

**Why:** User wants to track free throws and 3-point shots during practice, marking each shot as made or missed, with stats history on iPhone.

**How to apply:** The watch app works standalone (configure exercise + shot count directly on watch). iPhone app receives data via Garmin Connect IQ Mobile SDK over Bluetooth. Stats are stored in UserDefaults via SessionStore.

Key files:
- garmin-app/source/ — all Monkey C watch code
- ios-app/BasketTrainer/ — all Swift iPhone code
- SETUP.md — full step-by-step setup guide

App UUID (both apps must match): a3d5e7f9-1b2c-4d6e-8f0a-2b4c6d8e0f1a

Exercise types (0-8): freethrow, threeCenter, threeRight45, threeLeft45, threeCornerR, threeCornerL, midCenter, midRight, midLeft

Watch button mapping during workout: UP = made ✅, DOWN = missed ❌, BACK = cancel, START = confirm on summary screen.
