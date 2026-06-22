/*
 * DicyaninARKitSession
 * Created by Hunter Harris on 04/03/2025
 * Copyright © 2025 Dicyanin Labs. All rights reserved.
 */

import RealityKit
import ARKit
import Combine

/// Errors that can occur during ARKit session management
public enum ARKitSessionError: Error {
    /// The device does not support hand tracking
    case handTrackingNotSupported
    /// The device does not support scene reconstruction
    case sceneReconstructionNotSupported
}

/// A shared manager for ARKit sessions that distributes hand tracking and
/// scene-reconstruction updates to multiple packages.
///
/// This class manages a single ARKit session and distributes updates to multiple
/// subscribers. It ensures that only one ARKit session is running at a time, even
/// when multiple packages need data from it. Apple recommends running a single
/// `ARKitSession` for all providers, so hand tracking and scene reconstruction are
/// hosted on the same session here.
///
/// Example usage:
/// ```swift
/// // Subscribe to hand tracking updates
/// let cancellable = ARKitSessionManager.shared.handTrackingUpdates
///     .sink { update in /* ... */ }
///
/// // Consume scene-reconstruction mesh anchor updates
/// Task {
///     for await update in ARKitSessionManager.shared.sceneReconstructionUpdates {
///         // update.event, update.anchor (a MeshAnchor)
///     }
/// }
///
/// // Start the session with the capabilities you need
/// try await ARKitSessionManager.shared.start(handTracking: true, sceneReconstruction: true)
/// ```
public class ARKitSessionManager {
    /// Shared instance of the session manager
    public static let shared = ARKitSessionManager()

    private var session = ARKitSession()
    private var handTracking = HandTrackingProvider()
    private var sceneReconstruction: SceneReconstructionProvider?

    private let handTrackingSubject = PassthroughSubject<HandAnchorUpdate, Never>()

    private let sceneReconstructionContinuation: AsyncStream<AnchorUpdate<MeshAnchor>>.Continuation

    /// Publisher that emits hand tracking updates.
    public var handTrackingUpdates: AnyPublisher<HandAnchorUpdate, Never> {
        handTrackingSubject.eraseToAnyPublisher()
    }

    /// Stream of scene-reconstruction mesh anchor updates.
    ///
    /// This is a single-consumer broadcast of the shared `SceneReconstructionProvider`.
    /// Iterate it from one place (e.g. a mesh tracker) and re-distribute as needed.
    public let sceneReconstructionUpdates: AsyncStream<AnchorUpdate<MeshAnchor>>

    private var isRunning = false
    private var subscribers = 0
    private var handTrackingEnabled = false
    private var sceneReconstructionEnabled = false

    /// Whether the current device supports hand tracking.
    public static var isHandTrackingSupported: Bool { HandTrackingProvider.isSupported }

    /// Whether the current device supports scene reconstruction.
    public static var isSceneReconstructionSupported: Bool { SceneReconstructionProvider.isSupported }

    private init() {
        let (stream, continuation) = AsyncStream<AnchorUpdate<MeshAnchor>>.makeStream(
            bufferingPolicy: .unbounded
        )
        sceneReconstructionUpdates = stream
        sceneReconstructionContinuation = continuation
    }

    /// Starts the ARKit session with the requested capabilities.
    ///
    /// Capabilities are additive: calling this again with a capability that isn't yet
    /// running re-runs the session with the union of all enabled providers. Calling it
    /// with already-running capabilities just increments the subscriber count.
    ///
    /// - Parameters:
    ///   - handTracking: Enable hand tracking. Defaults to `true` (backward compatible).
    ///   - sceneReconstruction: Enable scene reconstruction. Defaults to `false`.
    /// - Throws: `ARKitSessionError` if a requested capability is unsupported.
    public func start(handTracking enableHands: Bool = true,
                      sceneReconstruction enableScene: Bool = false) async throws {
        subscribers += 1

        var needsRun = false

        if enableHands && !handTrackingEnabled {
            guard HandTrackingProvider.isSupported else {
                throw ARKitSessionError.handTrackingNotSupported
            }
            handTrackingEnabled = true
            needsRun = true
        }

        if enableScene && !sceneReconstructionEnabled {
            guard SceneReconstructionProvider.isSupported else {
                throw ARKitSessionError.sceneReconstructionNotSupported
            }
            sceneReconstructionEnabled = true
            needsRun = true
        }

        guard needsRun else { return }

        var providers: [any DataProvider] = []

        if handTrackingEnabled {
            handTracking = HandTrackingProvider()
            providers.append(handTracking)
        }

        if sceneReconstructionEnabled {
            let provider = SceneReconstructionProvider(modes: [.classification])
            sceneReconstruction = provider
            providers.append(provider)
        }

        try await session.run(providers)
        isRunning = true

        if handTrackingEnabled {
            let provider = handTracking
            Task { await publishHandTrackingUpdates(provider) }
        }

        if sceneReconstructionEnabled, let provider = sceneReconstruction {
            Task { await publishSceneReconstructionUpdates(provider) }
        }
    }

    /// Stops the ARKit session if there are no more subscribers.
    public func stop() {
        subscribers -= 1

        if subscribers <= 0 {
            session.stop()
            isRunning = false
            subscribers = 0
            handTrackingEnabled = false
            sceneReconstructionEnabled = false
            sceneReconstruction = nil
        }
    }

    private func publishHandTrackingUpdates(_ provider: HandTrackingProvider) async {
        for await update in provider.anchorUpdates {
            guard update.anchor.isTracked else { continue }

            let handUpdate = HandAnchorUpdate(
                left: update.anchor.chirality == .left ? update.anchor : nil,
                right: update.anchor.chirality == .right ? update.anchor : nil
            )

            handTrackingSubject.send(handUpdate)
        }
    }

    private func publishSceneReconstructionUpdates(_ provider: SceneReconstructionProvider) async {
        for await update in provider.anchorUpdates {
            sceneReconstructionContinuation.yield(update)
        }
    }
}
