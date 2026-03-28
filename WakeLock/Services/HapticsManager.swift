import Foundation
import CoreHaptics
import UIKit
import AudioToolbox

/// Persistent haptic feedback engine for the alarm punishment system.
///
/// ## Phase design
/// | Phase   | When         | Pattern                          | Intensity |
/// |---------|--------------|----------------------------------|-----------|
/// | Phase 1 | Alarm fires  | Single buzz every 500 ms          | 0.65      |
/// | Phase 2 | 30 s elapsed | Double tap every 500 ms           | 0.85      |
/// | Phase 3 | 60 s elapsed | 5 rapid sharp hits every 700 ms   | 1.0       |
///
/// ## Persistence guarantees
/// 1. **Heartbeat timer** (every 3 s) — checks `isPlayerActive` flag and
///    rebuilds the player if it was stopped by anything.
/// 2. **Player `completionHandler`** — fires immediately when the engine stops
///    the player unexpectedly; triggers a restart.
/// 3. **Engine `resetHandler`** — rebuilds the engine + player after an
///    OS-level engine reset.
/// 4. **Engine `stoppedHandler`** — restarts for all stop reasons except
///    `.applicationSuspended` (background — haptics cannot run in background).
/// 5. **`UIApplication.didBecomeActiveNotification`** — restarts the moment
///    the app returns to the foreground after any background period.
///    This covers: volume-button press, notification banner, lock/unlock,
///    phone call return, Control Centre, and any other foreground→background cycle.
///
/// ## Volume buttons
/// CoreHaptics (`CHHapticEngine`) is completely independent of
/// `AVAudioSession.outputVolume`.  Pressing the volume buttons does NOT stop
/// the haptic engine — the buzz continues at full mechanical intensity even
/// when system volume reaches zero.
final class HapticsManager {

    static let shared = HapticsManager()
    private init() {
        prepareEngine()
        setupAppStateObservers()
    }

    // MARK: - Haptic phase tracking

    // Explicitly Equatable & Sendable so the conformance is nonisolated and
    // can be used inside Timer / NotificationCenter closures without triggering
    // Swift 6 "Main actor-isolated conformance in nonisolated context" errors.
    private enum HapticPhase: Equatable, Sendable { case idle, phase1, phase2, phase3 }
    private var currentPhase: HapticPhase = .idle

    // MARK: - Engine + player

    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?

    /// `true` while our player is actively running.
    /// Set to `false` by completionHandler, stoppedHandler, willResignActive,
    /// and our own stop() call.  Checked by the heartbeat timer.
    private var isPlayerActive = false

    // MARK: - Fallback (devices without CoreHaptics)

    private var fallbackTimer: Timer?

    // MARK: - Heartbeat

    private var heartbeatTimer: Timer?

    // =========================================================================
    // MARK: - Public API
    // =========================================================================

    /// Start immediately when the alarm fires (Phase 1).
    /// Medium urgency — single buzz every 500 ms.
    func startPhase1() {
        guard currentPhase == .idle else { return }   // don't downgrade an active phase
        currentPhase = .phase1
        activatePlayer()
    }

    /// Escalate to Phase 2 (called at 30 s by PunishmentEngine).
    /// Higher urgency — double tap every 500 ms.
    func startPhase2() {
        currentPhase = .phase2
        activatePlayer()
    }

    /// Escalate to Phase 3 (called at 60 s by PunishmentEngine).
    /// Maximum urgency — 5 rapid sharp hits every 700 ms.
    func startPhase3() {
        currentPhase = .phase3
        activatePlayer()
    }

    /// Stop all haptics and reset state.  Call when alarm is dismissed.
    func stop() {
        currentPhase   = .idle
        isPlayerActive = false

        heartbeatTimer?.invalidate(); heartbeatTimer = nil
        fallbackTimer?.invalidate();  fallbackTimer  = nil

        try? player?.stop(atTime: CHHapticTimeImmediate)  // player.stop(atTime:) throws
        player = nil
        engine?.stop()   // CHHapticEngine.stop() is non-throwing (completion-handler variant)
    }

    /// Restart haptics for the current phase without changing the phase.
    /// Called by `PunishmentEngine.restoreIfNeeded()` when the app returns
    /// to the foreground — this is the same recovery path as `didBecomeActive`.
    func ensureRunning() {
        guard currentPhase != .idle, !isPlayerActive else { return }
        activatePlayer()
    }

    // =========================================================================
    // MARK: - Private: activation
    // =========================================================================

    /// Build the pattern for `currentPhase`, start the engine, and play.
    private func activatePlayer() {
        guard currentPhase != .idle else { return }

        // Devices without a Taptic Engine fall back to a timer-driven vibration.
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            startFallbackVibration()
            return
        }

        ensureEngineStarted()

        guard let engine else { return }

        do {
            let pattern = try patternForCurrentPhase()

            // Stop any existing player before creating a new one
            try? player?.stop(atTime: CHHapticTimeImmediate)
            player = nil

            let newPlayer = try engine.makeAdvancedPlayer(with: pattern)
            newPlayer.loopEnabled = true

            // Set loop period so there's a natural pause between repetitions
            switch currentPhase {
            case .phase1: newPlayer.loopEnd = 0.5   // buzz + 300 ms silence
            case .phase2: newPlayer.loopEnd = 0.5   // double-tap + silence
            case .phase3: newPlayer.loopEnd = 0.7   // 5 hits + silence
            case .idle:   break
            }

            // Detect unexpected stops and auto-restart
            newPlayer.completionHandler = { [weak self] _ in
                guard let self, self.currentPhase != .idle else { return }
                self.isPlayerActive = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.activatePlayer()
                }
            }

            try newPlayer.start(atTime: CHHapticTimeImmediate)
            player         = newPlayer
            isPlayerActive = true
            startHeartbeat()

        } catch {
            print("[HapticsManager] Player start error: \(error)")
            startFallbackVibration()
        }
    }

    // =========================================================================
    // MARK: - Private: engine lifecycle
    // =========================================================================

    private func ensureEngineStarted() {
        if engine == nil { prepareEngine() }
        do {
            try engine?.start()
        } catch {
            print("[HapticsManager] Engine start error: \(error)")
        }
    }

    private func prepareEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
        } catch {
            print("[HapticsManager] Engine init error: \(error)")
            return
        }

        // Engine was reset by the OS (rare) — rebuild everything
        engine?.resetHandler = { [weak self] in
            guard let self else { return }
            print("[HapticsManager] Engine reset — rebuilding")
            self.isPlayerActive = false
            self.player         = nil
            do {
                try self.engine?.start()
            } catch {
                print("[HapticsManager] Engine restart after reset failed: \(error)")
                return
            }
            // Small delay for the engine to stabilise
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.activatePlayer()
            }
        }

        // Engine stopped — determine why and act accordingly
        engine?.stoppedHandler = { [weak self] reason in
            guard let self, self.currentPhase != .idle else { return }
            self.isPlayerActive = false
            self.player         = nil

            switch reason {
            case .applicationSuspended:
                // App went to background — haptics will restart via didBecomeActiveNotification.
                // Do NOT try to restart here; the engine cannot run while backgrounded.
                print("[HapticsManager] Engine suspended (background) — will restart on foreground")

            default:
                // All other reasons (audio interrupt, idle timeout, system error, etc.)
                // → restart after a brief delay.
                print("[HapticsManager] Engine stopped (\(reason)) — restarting")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.ensureEngineStarted()
                    self.activatePlayer()
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Private: heartbeat
    // =========================================================================

    /// Fires every 3 seconds as a last-resort check.
    /// If the player stopped for any reason that the completionHandler or
    /// stoppedHandler missed, the heartbeat catches it.
    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: 3.0,
            repeats: true
        ) { [weak self] _ in
            guard let self, self.currentPhase != .idle else { return }
            if !self.isPlayerActive {
                print("[HapticsManager] Heartbeat: player inactive — restarting")
                self.activatePlayer()
            }
        }
    }

    // =========================================================================
    // MARK: - Private: app-state observers
    // =========================================================================

    private func setupAppStateObservers() {
        let nc = NotificationCenter.default

        // App returned to foreground — restart immediately regardless of stop reason
        nc.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object:  nil,
            queue:   .main
        ) { [weak self] _ in
            guard let self, self.currentPhase != .idle else { return }
            print("[HapticsManager] App active — restoring haptics for phase \(self.currentPhase)")
            self.isPlayerActive = false
            self.player         = nil
            // Delay slightly to let AVAudioSession re-activate first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.activatePlayer()
            }
        }

        // App going to background — mark player as inactive so didBecomeActive
        // knows it needs to restart (don't stop the engine — let iOS do it)
        nc.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object:  nil,
            queue:   .main
        ) { [weak self] _ in
            self?.isPlayerActive = false
        }
    }

    // =========================================================================
    // MARK: - Private: haptic patterns
    // =========================================================================

    private func patternForCurrentPhase() throws -> CHHapticPattern {
        switch currentPhase {
        case .phase1: return try phase1Pattern()
        case .phase2: return try phase2Pattern()
        case .phase3: return try phase3Pattern()
        case .idle:   return try phase1Pattern()
        }
    }

    /// Phase 1 — single medium buzz (0.2 s on, 0.3 s off via loopEnd)
    private func phase1Pattern() throws -> CHHapticPattern {
        let event = CHHapticEvent(
            eventType:    .hapticContinuous,
            parameters:   [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.65),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.40)
            ],
            relativeTime: 0,
            duration:     0.2
        )
        return try CHHapticPattern(events: [event], parameters: [])
    }

    /// Phase 2 — double tap (two 0.12 s buzzes, 0.06 s apart; 0.26 s of silence via loopEnd)
    private func phase2Pattern() throws -> CHHapticPattern {
        let make: (Double) -> CHHapticEvent = { t in
            CHHapticEvent(
                eventType:    .hapticContinuous,
                parameters:   [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.85),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.70)
                ],
                relativeTime: t,
                duration:     0.12
            )
        }
        return try CHHapticPattern(events: [make(0.0), make(0.18)], parameters: [])
    }

    /// Phase 3 — 5 sharp transient hits 0.1 s apart; 0.2 s of silence via loopEnd
    private func phase3Pattern() throws -> CHHapticPattern {
        let events: [CHHapticEvent] = (0..<5).map { i in
            CHHapticEvent(
                eventType:    .hapticTransient,
                parameters:   [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                ],
                relativeTime: Double(i) * 0.1
            )
        }
        return try CHHapticPattern(events: events, parameters: [])
    }

    // =========================================================================
    // MARK: - Private: fallback vibration (no Taptic Engine)
    // =========================================================================

    private func startFallbackVibration() {
        fallbackTimer?.invalidate()
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

        let interval: TimeInterval
        switch currentPhase {
        case .phase1: interval = 0.8
        case .phase2: interval = 0.5
        case .phase3: interval = 0.3
        case .idle:   return
        }

        fallbackTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
}
