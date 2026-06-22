# DicyaninARKitSession

A Swift package that provides a shared ARKit session manager for hand tracking and scene reconstruction in visionOS applications.

## Overview

DicyaninARKitSession manages a single ARKit session and distributes hand tracking and scene-reconstruction updates to multiple subscribers. It ensures that only one ARKit session is running at a time — the pattern Apple recommends — even when multiple packages need data from it.

## Requirements

- visionOS 1.0+
- Swift 5.9+

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/hunterh37/DicyaninARKitSession.git", from: "0.0.1")
]


## Usage

```swift
import DicyaninARKitSession

// Subscribe to hand tracking updates
let cancellable = ARKitSessionManager.shared.handTrackingUpdates
    .sink { update in
        // Handle hand tracking update
        if let leftHand = update.left {
            // Process left hand data
        }
        if let rightHand = update.right {
            // Process right hand data
        }
    }

// Start the session (hand tracking only — backward compatible default)
try await ARKitSessionManager.shared.start()

// Stop the session when done
ARKitSessionManager.shared.stop()
```

### Scene reconstruction

The shared session can also host a `SceneReconstructionProvider` (mesh of the real
room) on the same `ARKitSession`. Enable it via `start(...)` and consume mesh anchor
updates from the `sceneReconstructionUpdates` async stream:

```swift
import DicyaninARKitSession
import ARKit

// Consume mesh anchor updates (single consumer — re-distribute as needed)
Task {
    for await update in ARKitSessionManager.shared.sceneReconstructionUpdates {
        switch update.event {
        case .added, .updated: handle(update.anchor)   // a MeshAnchor
        case .removed:         remove(update.anchor)
        }
    }
}

// Start with both capabilities (each is optional)
try await ARKitSessionManager.shared.start(handTracking: true, sceneReconstruction: true)

// Capability support checks
ARKitSessionManager.isHandTrackingSupported
ARKitSessionManager.isSceneReconstructionSupported
```

> Tip: [DicyaninSceneReconstruction](https://github.com/hunterh37/DicyaninSceneReconstruction)
> builds on this stream to maintain tracked mesh entities with colliders and floor raycasts.

## License

Copyright © 2025 Dicyanin Labs. All rights reserved. 
