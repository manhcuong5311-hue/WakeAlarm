import Foundation
import AVFoundation
import AudioToolbox
import MediaPlayer
import UIKit
import Combine

/// Dual-layer persistent alarm audio engine.
///
/// ## Persistence layers (innermost → outermost)
/// 1. **AVAudioSession `.playback`** — ignores the silent/ring switch; keeps process alive
///    in background-audio class.
/// 2. **Dual AVAudioPlayer** — primary (alarm.caf) + secondary (alarm_aggressive.caf)
///    both looping, both independently restarted by the enforcement timer.
/// 3. **Volume enforcement timer** (every 2 s) — resets software `player.volume` to the
///    target and restarts any player that stopped unexpectedly.
/// 4. **System-volume enforcement** — KVO on `AVAudioSession.outputVolume`.  If the
///    user holds volume-down below 15%, an off-screen `MPVolumeView` slider pushes
///    it back to 60%.  Uses a debounce flag to avoid KVO feedback loops.
/// 5. **Interruption observer** — restarts on `.ended` regardless of `shouldResume`.
/// 6. **Route-change observer** — recovers on headphone/BT disconnect AND connect.
/// 7. **Media-services reset** — full reinit.
/// 8. **Low Power Mode observer** — calls `ensurePlaying()` when LPM toggles.
/// 9. **`UIBackgroundTask`** — requests an extra ~30 s of CPU time so the engine
///    survives brief audio interruptions that would otherwise cause suspension.
/// 10. **Keepalive** — silent loop keeps the process in background-audio class
///     while any alarm is armed, so `startAlarm()` has zero cold-start gap.
final class AudioManager: ObservableObject {

    static let shared = AudioManager()
    private init() {
        setupSessionObservers()
        setupSystemObservers()
    }

    // MARK: - Published state

    @Published private(set) var isAlarmPlaying = false

    // MARK: - Players

    private var primaryPlayer: AVAudioPlayer?     // alarm.caf          — main layer
    private var secondaryPlayer: AVAudioPlayer?   // alarm_aggressive   — ambient layer
    private var keepalivePlayer: AVAudioPlayer?   // alarm.caf vol=0    — process keepalive

    // MARK: - Timers

    private var rampTimer: Timer?
    private var enforcementTimer: Timer?

    // MARK: - Target volumes

    private var primaryTarget: Float   = 0.85
    private var secondaryTarget: Float = 0.25

    // MARK: - Session

    private var sessionActive = false

    // MARK: - System-volume enforcement

    private var systemVolumeView: MPVolumeView?
    private var volumeObservation: NSKeyValueObservation?
    private var isRestoringVolume = false   // debounce flag

    // MARK: - Background task

    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // =========================================================================
    // MARK: - Keepalive
    // =========================================================================

    func startKeepalive() {
        guard keepalivePlayer == nil, !isAlarmPlaying else { return }
        activateSession()
        guard let url = soundURL("alarm") else { return }
        do {
            keepalivePlayer = try AVAudioPlayer(contentsOf: url)
            keepalivePlayer?.numberOfLoops = -1
            keepalivePlayer?.volume        = 0
            keepalivePlayer?.prepareToPlay()
            keepalivePlayer?.play()
        } catch {
            print("[AudioManager] Keepalive error: \(error)")
        }
    }

    func stopKeepalive() {
        keepalivePlayer?.stop()
        keepalivePlayer = nil
        if !isAlarmPlaying { deactivateSession() }
    }

    // =========================================================================
    // MARK: - Alarm start
    // =========================================================================

    func startAlarm() {
        guard !isAlarmPlaying else {
            ensurePlaying()
            return
        }

        activateSession()
        primaryTarget   = 0.85
        secondaryTarget = 0.25

        // Reuse keepalive player for a seamless, gap-free handoff
        if let kp = keepalivePlayer {
            kp.volume      = primaryTarget
            primaryPlayer  = kp
            keepalivePlayer = nil
        } else {
            startPrimary(volume: primaryTarget)
        }

        // Secondary layer offset 9 s to create a richer, layered texture
        startSecondary(volume: secondaryTarget, offset: 9.0)

        isAlarmPlaying = true
        startEnforcementTimer()
        beginBackgroundTask()
        startVolumeEnforcement()
    }

    // =========================================================================
    // MARK: - Escalation (called by PunishmentEngine)
    // =========================================================================

    func rampToMax() {
        guard isAlarmPlaying else { return }
        secondaryTarget = 0.65
        primaryTarget   = 1.0
        animateToTarget(player: primaryPlayer,   target: primaryTarget)
        animateToTarget(player: secondaryPlayer, target: secondaryTarget)
    }

    func startAggressiveLayer() {
        guard isAlarmPlaying else { return }
        primaryTarget   = 1.0
        secondaryTarget = 1.0
        primaryPlayer?.volume   = 1.0
        secondaryPlayer?.volume = 1.0
    }

    // =========================================================================
    // MARK: - Recovery
    // =========================================================================

    /// Ensure both audio layers are playing.  Safe to call from any state.
    func ensurePlaying() {
        guard isAlarmPlaying else { return }
        activateSession()

        if let p = primaryPlayer {
            p.volume = primaryTarget
            if !p.isPlaying { p.play() }
        } else {
            startPrimary(volume: primaryTarget)
        }

        if let s = secondaryPlayer {
            s.volume = secondaryTarget
            if !s.isPlaying { s.play() }
        } else {
            startSecondary(volume: secondaryTarget, offset: 0)
        }
    }

    // =========================================================================
    // MARK: - Stop
    // =========================================================================

    func stopAlarm() {
        isAlarmPlaying  = false
        primaryTarget   = 0.85
        secondaryTarget = 0.25

        enforcementTimer?.invalidate(); enforcementTimer = nil
        rampTimer?.invalidate();        rampTimer        = nil

        primaryPlayer?.stop();   primaryPlayer   = nil
        secondaryPlayer?.stop(); secondaryPlayer = nil

        stopVolumeEnforcement()
        endBackgroundTask()

        // Re-arm keepalive if any alarm is still enabled
        if AlarmManager.shared.alarms.contains(where: { $0.isEnabled }) {
            startKeepalive()
        } else {
            deactivateSession()
        }
    }

    // =========================================================================
    // MARK: - Private: player construction
    // =========================================================================

    private func startPrimary(volume: Float) {
        guard let url = soundURL("alarm") else {
            AudioServicesPlaySystemSound(1005)
            return
        }
        do {
            primaryPlayer = try AVAudioPlayer(contentsOf: url)
            primaryPlayer?.numberOfLoops = -1
            primaryPlayer?.volume        = volume
            primaryPlayer?.prepareToPlay()
            primaryPlayer?.play()
        } catch {
            print("[AudioManager] Primary play error: \(error)")
        }
    }

    private func startSecondary(volume: Float, offset: TimeInterval) {
        guard let url = soundURL("alarm_aggressive") ?? soundURL("alarm") else { return }
        do {
            secondaryPlayer = try AVAudioPlayer(contentsOf: url)
            secondaryPlayer?.numberOfLoops  = -1
            secondaryPlayer?.volume         = volume
            secondaryPlayer?.currentTime    = offset
            secondaryPlayer?.prepareToPlay()
            secondaryPlayer?.play()
        } catch {
            print("[AudioManager] Secondary play error: \(error)")
        }
    }

    // =========================================================================
    // MARK: - Private: volume ramp
    // =========================================================================

    private func animateToTarget(player: AVAudioPlayer?, target: Float) {
        guard let player else { return }
        var v = player.volume
        rampTimer?.invalidate()
        rampTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] t in
            guard self != nil else { t.invalidate(); return }
            v = min(v + 0.05, target)
            player.volume = v
            if v >= target { t.invalidate() }
        }
    }

    // =========================================================================
    // MARK: - Private: enforcement timer
    // =========================================================================

    private func startEnforcementTimer() {
        enforcementTimer?.invalidate()
        enforcementTimer = Timer.scheduledTimer(
            withTimeInterval: 2.0,
            repeats: true
        ) { [weak self] _ in
            self?.enforcePlayback()
        }
    }

    private func enforcePlayback() {
        guard isAlarmPlaying else { return }

        primaryPlayer?.volume   = primaryTarget
        secondaryPlayer?.volume = secondaryTarget

        if let p = primaryPlayer, !p.isPlaying {
            activateSession()
            p.play()
        }
        if let s = secondaryPlayer, !s.isPlaying {
            s.play()
        }
    }

    // =========================================================================
    // MARK: - Private: system-volume enforcement (MPVolumeView + KVO)
    // =========================================================================

    private func startVolumeEnforcement() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.attachVolumeViewIfNeeded()
            // Brief delay so the view is fully in the hierarchy before KVO fires
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.startVolumeKVO()
            }
        }
    }

    private func stopVolumeEnforcement() {
        volumeObservation?.invalidate()
        volumeObservation  = nil
        isRestoringVolume  = false
        DispatchQueue.main.async { [weak self] in
            self?.systemVolumeView?.removeFromSuperview()
            self?.systemVolumeView = nil
        }
    }

    /// Add an off-screen `MPVolumeView` to the key window.
    /// This is the only public API that lets us programmatically set system volume.
    private func attachVolumeViewIfNeeded() {
        guard systemVolumeView?.superview == nil else { return }

        let v = MPVolumeView(frame: CGRect(x: -300, y: -300, width: 100, height: 100))
        v.alpha      = 0.001    // invisible but participates in the responder chain
        v.isHidden   = false
        systemVolumeView = v

        // Find the active key window
        let window = UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
            ?? UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first

        window?.addSubview(v)
    }

    /// KVO observer: when system volume drops below 15% while the alarm is
    /// ringing, restore it to 60%.  Uses `isRestoringVolume` flag to prevent
    /// the KVO from firing in a feedback loop.
    private func startVolumeKVO() {
        volumeObservation?.invalidate()
        volumeObservation = AVAudioSession.sharedInstance().observe(
            \.outputVolume,
            options: [.new]
        ) { [weak self] _, change in
            guard let self,
                  self.isAlarmPlaying,
                  !self.isRestoringVolume else { return }

            let vol = change.newValue ?? 0
            if vol < 0.15 {
                self.isRestoringVolume = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.setSystemVolume(0.6)
                    // Release debounce after 1 s so the next legitimate change is observed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.isRestoringVolume = false
                    }
                }
            }
        }
    }

    private func setSystemVolume(_ volume: Float) {
        guard let slider = systemVolumeView?
            .subviews
            .first(where: { $0 is UISlider }) as? UISlider
        else { return }
        slider.value = volume
    }

    // =========================================================================
    // MARK: - Private: background task
    // =========================================================================

    /// Request ~30 s of extra background CPU time so the audio session survives
    /// brief interruptions (incoming call answer, Siri, etc.) that would otherwise
    /// cause iOS to suspend the process.
    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(
            withName: "WakeLock.AlarmRing"
        ) { [weak self] in
            // Expiry: background time exhausted — end gracefully.
            // AVAudioSession keeps us alive via background audio mode; this task
            // is belt-and-suspenders for non-audio-interrupted scenarios.
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    // =========================================================================
    // MARK: - Private: system observers (LPM, session)
    // =========================================================================

    private func setupSystemObservers() {
        // Low Power Mode toggle — timers may fire less frequently; re-verify playback
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isAlarmPlaying else { return }
            print("[AudioManager] Power state changed — ensuring playback")
            self.ensurePlaying()
        }
    }

    private func setupSessionObservers() {
        let nc = NotificationCenter.default

        // ── Interruption (phone calls, Siri, FaceTime, etc.) ─────────────────
        nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object:  AVAudioSession.sharedInstance(),
            queue:   .main
        ) { [weak self] n in self?.handleInterruption(n) }

        // ── Route change (device plug/unplug, BT connect/disconnect) ─────────
        nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object:  AVAudioSession.sharedInstance(),
            queue:   .main
        ) { [weak self] n in self?.handleRouteChange(n) }

        // ── Media services reset (rare daemon crash) ──────────────────────────
        nc.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object:  nil,
            queue:   .main
        ) { [weak self] _ in self?.handleMediaServicesReset() }
    }

    // =========================================================================
    // MARK: - Private: interruption handler
    // =========================================================================

    private func handleInterruption(_ notification: Notification) {
        guard let info    = notification.userInfo,
              let typeVal = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type    = AVAudioSession.InterruptionType(rawValue: typeVal) else { return }

        switch type {
        case .began:
            print("[AudioManager] Interruption began")

        case .ended:
            // Always attempt to resume, even if `shouldResume` is absent.
            // An alarm must keep ringing after a phone call ends, regardless of
            // what the OS recommends.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.ensurePlaying()
            }

        @unknown default: break
        }
    }

    // =========================================================================
    // MARK: - Private: route-change handler
    // =========================================================================

    private func handleRouteChange(_ notification: Notification) {
        guard isAlarmPlaying,
              let info      = notification.userInfo,
              let reasonVal = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason    = AVAudioSession.RouteChangeReason(rawValue: reasonVal) else { return }

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged or BT speaker/headphones disconnected.
            // iOS pauses playback; restart it on the built-in speaker.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.ensurePlaying()
            }

        case .newDeviceAvailable:
            // BT speaker or headphones connected while alarm is ringing.
            // iOS may pause and re-route; ensure playback continues on the new device.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.ensurePlaying()
            }

        case .categoryChange:
            // Another app changed the session category under us — reactivate.
            sessionActive = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.ensurePlaying()
            }

        case .wakeFromSleep:
            // Device woke from deep sleep — verify audio is still playing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.ensurePlaying()
            }

        default: break
        }
    }

    // =========================================================================
    // MARK: - Private: media-services reset
    // =========================================================================

    private func handleMediaServicesReset() {
        // All players and sessions are completely invalid after a daemon reset.
        sessionActive   = false
        primaryPlayer   = nil
        secondaryPlayer = nil
        keepalivePlayer = nil

        if isAlarmPlaying {
            isAlarmPlaying = false  // clear guard so startAlarm() runs fully
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startAlarm()
            }
        }
    }

    // =========================================================================
    // MARK: - Private: session
    // =========================================================================

    private func activateSession() {
        guard !sessionActive else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .default, options: [.duckOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
            sessionActive = true
        } catch {
            print("[AudioManager] Session activate error: \(error)")
        }
    }

    private func deactivateSession() {
        guard sessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
        sessionActive = false
    }

    // =========================================================================
    // MARK: - Private: sound-file lookup
    // =========================================================================

    private func soundURL(_ name: String) -> URL? {
        for ext in ["caf", "m4a", "wav", "mp3"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        }
        let path = "/System/Library/Audio/UISounds/alarm.caf"
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
}
