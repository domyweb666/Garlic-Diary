import AVFoundation
import Foundation
import Observation
import Speech

/// 用說的：SFSpeechRecognizer（zh-TW）。任何失敗都退回同一句提示：改用鍵盤上的麥克風。
@Observable final class SpeechService {
    var isRecording = false
    var lastError: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))
    private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var onText: ((String) -> Void)?
    @ObservationIgnored private var base = ""
    @ObservationIgnored private var engineStarted = false
    @ObservationIgnored private var gotText = false

    static let fallbackHint = "收音沒成功，可以改用鍵盤上的麥克風"

    var supported: Bool { recognizer != nil }

    /// 按一下開始、再按一下結束。base 是欄位裡已經有的字，辨識結果接在後面。
    func toggle(base: String, onText: @escaping (String) -> Void) {
        if isRecording {
            finish()
            return
        }
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        self.base = trimmed.isEmpty ? "" : trimmed + " "
        self.onText = onText
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                guard status == .authorized else {
                    self.fail("沒有語音辨識權限。到 iPhone「設定」→「蒜數」打開，或改用鍵盤上的麥克風")
                    return
                }
                AVAudioApplication.requestRecordPermission { ok in
                    DispatchQueue.main.async {
                        guard ok else {
                            self.fail("沒有麥克風權限。到 iPhone「設定」→「蒜數」打開，或改用鍵盤上的麥克風")
                            return
                        }
                        self.begin()
                    }
                }
            }
        }
    }

    func finish() {
        guard isRecording else { return }
        isRecording = false
        request?.endAudio()
        if engineStarted {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            engineStarted = false
        }
        // 最後一段結果通常一秒內到；沒到就收掉
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.request != nil else { return }
            self.cleanup()
        }
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable else {
            fail("這支手機現在不能語音辨識，改用鍵盤上的麥克風")
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            fail(Self.fallbackHint)
            return
        }
        Feedback.shared.sessionBusy = true
        gotText = false
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engineStarted = false
            cleanup()
            fail(Self.fallbackHint)
            return
        }
        engineStarted = true
        isRecording = true
        lastError = nil
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if !text.isEmpty { self.gotText = true }
                    self.onText?(self.base + text)
                    if result.isFinal { self.cleanup() }
                }
                if error != nil {
                    // 已經收完的尾巴（cancel 之類）不理
                    guard self.request != nil else { return }
                    let hadText = self.gotText
                    self.cleanup()
                    if !hadText { self.fail(Self.fallbackHint) }
                }
            }
        }
    }

    private func cleanup() {
        guard request != nil || engineStarted || task != nil else { return }
        let t = task
        task = nil
        request = nil
        if engineStarted {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            engineStarted = false
        }
        t?.cancel()
        isRecording = false
        Feedback.shared.sessionBusy = false
        let s = AVAudioSession.sharedInstance()
        try? s.setActive(false, options: .notifyOthersOnDeactivation)
        try? s.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    }

    private func fail(_ msg: String) {
        isRecording = false
        lastError = msg
    }
}
