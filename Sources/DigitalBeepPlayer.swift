import AVFoundation
import Foundation

/// Synthetic classic digital alarm: short square-wave beeps with a pause between pairs.
/// Volume ramps from near-silent to the user-chosen level over `rampDuration`.
final class DigitalBeepPlayer {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var startedAt: Date?
    private var isPlaying = false
    private let lock = NSLock()
    private var _userVolume: Float = 0.85

    /// Seconds from first beep to full volume.
    var rampDuration: TimeInterval = 30

    /// User volume (0...1). Applied live while ringing.
    var userVolume: Float {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _userVolume
        }
        set {
            let clamped = min(1, max(0.05, newValue))
            lock.lock()
            _userVolume = clamped
            lock.unlock()
            if isPlaying {
                engine.mainMixerNode.outputVolume = 1.0
            }
        }
    }

    private let beepFrequency: Double = 1000
    private let beepOnDuration: Double = 0.12
    private let beepGapDuration: Double = 0.08
    private let pairGapDuration: Double = 0.55
    /// Synthetic sample peak before user volume (keep high so slider can get loud).
    private let samplePeak: Float = 0.95

    func start() {
        stop()

        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard sampleRate > 0 else { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            return
        }

        let onDur = beepOnDuration
        let gapDur = beepGapDuration
        let cycle = onDur + gapDur + onDur + pairGapDuration
        let freq = beepFrequency
        let ramp = rampDuration
        let peak = samplePeak

        var sampleTime: Double = 0
        let start = Date()
        startedAt = start

        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let data = abl[0].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }

            let userVol = self?.userVolume ?? 0.85
            let elapsed = Date().timeIntervalSince(start)
            let rampProgress = min(1.0, max(0.0, elapsed / ramp))
            let eased = rampProgress * rampProgress
            let volume = Float(eased) * peak * userVol

            for frame in 0..<Int(frameCount) {
                let t = sampleTime / sampleRate
                let phaseInCycle = t.truncatingRemainder(dividingBy: cycle)

                let inFirstBeep = phaseInCycle < onDur
                let inSecondBeep = phaseInCycle >= (onDur + gapDur)
                    && phaseInCycle < (onDur + gapDur + onDur)

                if inFirstBeep || inSecondBeep {
                    let phase = 2.0 * Double.pi * freq * t
                    data[frame] = (sin(phase) >= 0 ? volume : -volume)
                } else {
                    data[frame] = 0
                }
                sampleTime += 1
            }

            return noErr
        }

        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1.0

        do {
            try engine.start()
            isPlaying = true
        } catch {
            stop()
        }
    }

    func stop() {
        if isPlaying {
            engine.stop()
        }
        if let node = sourceNode {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
        }
        sourceNode = nil
        startedAt = nil
        isPlaying = false
    }

    var currentlyPlaying: Bool { isPlaying }
}
