import AVFoundation
import UIKit

private enum Wave {
    case sine
    case triangle
}

private struct Tone {
    let f0: Double
    let f1: Double
    let dur: Double
    let vol: Double
    let wave: Wave
    let at: Double
}

/// 回饋：觸覺為主，聲音為輔。四個聲音對應網頁版的 tick／seed／thud／done。
/// 聲音走 .ambient，會跟著靜音鍵；觸覺不會。
final class Feedback {
    static let shared = Feedback()

    var soundOn = true
    var hapticsOn = true
    /// 語音收音期間 audio session 歸 SpeechService 管，這裡不碰類別
    var sessionBusy = false

    private let engine = AVAudioEngine()
    private let format: AVAudioFormat? = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
    private var nodes: [String: AVAudioPlayerNode] = [:]
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var ready = false

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let notify = UINotificationFeedbackGenerator()

    private init() {}

    func warmUp() {
        light.prepare()
        soft.prepare()
        rigid.prepare()
        notify.prepare()
    }

    /// 點一下選項、碰一顆蒜
    func tick() {
        if hapticsOn { light.impactOccurred() }
        play("tick")
    }

    /// 記下一句，長一條根
    func seed() {
        if hapticsOn { soft.impactOccurred() }
        play("seed")
    }

    /// 一顆落到籃子裡；v 是落地速度
    func thud(_ v: Double) {
        let vol = min(0.16, 0.04 + v * 0.02) / 0.16
        if hapticsOn { rigid.impactOccurred(intensity: CGFloat(0.35 + vol * 0.65)) }
        play("thud", volume: Float(vol))
    }

    /// 三瓣都剝完、對帳完成
    func done() {
        if hapticsOn { notify.notificationOccurred(.success) }
        play("done")
    }

    // MARK: - 聲音

    private func setup() {
        guard !ready, let format else { return }
        ready = true
        buffers["tick"] = render([Tone(f0: 900, f1: 620, dur: 0.07, vol: 0.05, wave: .triangle, at: 0)], format: format)
        buffers["seed"] = render([Tone(f0: 1300, f1: 1700, dur: 0.09, vol: 0.04, wave: .sine, at: 0)], format: format)
        buffers["thud"] = render([Tone(f0: 170, f1: 62, dur: 0.16, vol: 0.16, wave: .sine, at: 0)], format: format)
        buffers["done"] = render([Tone(f0: 520, f1: 780, dur: 0.18, vol: 0.06, wave: .sine, at: 0),
                                  Tone(f0: 780, f1: 1040, dur: 0.2, vol: 0.05, wave: .sine, at: 0.11)], format: format)
        for key in buffers.keys {
            let n = AVAudioPlayerNode()
            engine.attach(n)
            engine.connect(n, to: engine.mainMixerNode, format: format)
            nodes[key] = n
        }
        engine.prepare()
    }

    /// 先把音算好放進 buffer，播的時候不用即時合成
    private func render(_ tones: [Tone], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        let total = (tones.map { $0.at + $0.dur }.max() ?? 0.1) + 0.03
        let frames = AVAudioFrameCount(total * sr)
        guard frames > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let ch = buf.floatChannelData else { return nil }
        buf.frameLength = frames
        let out = ch[0]
        let count = Int(frames)
        for i in 0..<count { out[i] = 0 }
        for t in tones {
            var phase = 0.0
            let start = Int(t.at * sr)
            let n = Int(t.dur * sr)
            for i in 0..<n {
                let tt = Double(i) / sr
                let f = t.f0 * pow(t.f1 / t.f0, tt / t.dur)
                phase += f / sr
                if phase >= 1 { phase -= floor(phase) }
                let wave: Double = t.wave == .sine ? sin(phase * 2 * Double.pi) : (4 * abs(phase - 0.5) - 1)
                let env: Double = tt < 0.008
                    ? tt / 0.008
                    : pow(0.0001, (tt - 0.008) / max(t.dur - 0.008, 0.001))
                let idx = start + i
                if idx < count { out[idx] += Float(wave * env * t.vol * 2.0) }
            }
        }
        return buf
    }

    private func play(_ key: String, volume: Float = 1) {
        guard soundOn else { return }
        setup()
        guard let node = nodes[key], let buf = buffers[key] else { return }
        do {
            if !engine.isRunning {
                if !sessionBusy {
                    try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                    try AVAudioSession.sharedInstance().setActive(true)
                }
                try engine.start()
            }
            node.volume = volume
            if !node.isPlaying { node.play() }
            node.scheduleBuffer(buf, at: nil, options: [.interrupts], completionHandler: nil)
        } catch {
            // 聲音播不出來就算了，觸覺已經給過
        }
    }
}
