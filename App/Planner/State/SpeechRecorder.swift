import AVFoundation
import Foundation
import Speech

/// Диктовка по-русски на системном распознавании речи (SFSpeechRecognizer + AVAudioEngine).
/// Отдаёт живой текст текущего захода; долгие паузы между словами превращаются в переносы строк,
/// чтобы `DictationSplitter` делил задачи ещё и по ним.
@MainActor
@Observable
final class SpeechRecorder {
    enum Status: Equatable {
        case idle, listening, paused, denied, unavailable
        case failed(String)
    }

    private(set) var status: Status = .idle
    /// Текст текущего захода (с момента последнего старта).
    private(set) var liveText = ""
    /// Уровень сигнала 0…1 для волны.
    private(set) var level: Double = 0
    /// Система сама закрыла заход (лимит ~1 минута): текст отдаётся наружу, заход начинается заново.
    var onSegmentFinished: ((String) -> Void)?

    var isListening: Bool { status == .listening }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0

    /// Длина паузы, после которой начинается новая задача.
    private let pauseThreshold: TimeInterval = 1.1

    func start() async {
        guard await authorize() else {
            status = .denied
            return
        }
        guard let recognizer = recognizer, recognizer.isAvailable else {
            status = .unavailable
            return
        }
        do {
            try beginSession(with: recognizer)
            status = .listening
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Остановить запись; `liveText` остаётся до `clearLive()`.
    func pause() {
        endSession()
        if status == .listening { status = .paused }
    }

    func clearLive() {
        liveText = ""
    }

    func shutdown() {
        endSession()
        status = .idle
    }

    // MARK: - Разрешения

    private func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    // MARK: - Сессия

    private func beginSession(with recognizer: SFSpeechRecognizer) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = false
        self.request = request

        generation += 1
        let current = generation
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let power = Self.power(of: buffer)
            Task { @MainActor in self?.level = power }
        }
        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.handle(result: result, error: error)
            }
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            liveText = Self.text(from: result.bestTranscription, pause: pauseThreshold)
            if result.isFinal, status == .listening {
                // Лимит системы: закрываем заход, отдаём текст и начинаем новый.
                let finished = liveText
                endSession()
                liveText = ""
                if !finished.isEmpty { onSegmentFinished?(finished) }
                if let recognizer, recognizer.isAvailable {
                    try? beginSession(with: recognizer)
                } else {
                    status = .unavailable
                }
            }
            return
        }
        if error != nil, status == .listening {
            endSession()
            status = liveText.isEmpty ? .failed("Не удалось распознать речь") : .paused
        }
    }

    private func endSession() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        generation += 1
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Вспомогательное

    /// Текст из сегментов; пауза длиннее порога — перенос строки.
    static func text(from transcription: SFTranscription, pause: TimeInterval) -> String {
        var out = ""
        var previousEnd: TimeInterval?
        for segment in transcription.segments {
            if let previousEnd, segment.timestamp - previousEnd > pause {
                out += "\n"
            } else if !out.isEmpty {
                out += " "
            }
            out += segment.substring
            previousEnd = segment.timestamp + segment.duration
        }
        return out.isEmpty ? transcription.formattedString : out
    }

    private static func power(of buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count { sum += data[index] * data[index] }
        let rms = sqrt(sum / Float(count))
        return Double(min(1, rms * 6))
    }
}
