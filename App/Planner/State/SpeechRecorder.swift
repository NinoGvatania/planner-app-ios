import AVFoundation
import Foundation
import QuartzCore
import Speech

/// Диктовка по-русски на системном распознавании речи (SFSpeechRecognizer + AVAudioEngine).
/// Отдаёт живой текст текущего захода; долгие паузы между словами превращаются в переносы строк,
/// чтобы `DictationSplitter` делил задачи ещё и по ним. Законченный заход (пауза, лимит системы,
/// ошибка) отдаётся целиком через `onSegmentFinished`.
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
    /// Заход закончен (пауза, лимит ~1 минута, ошибка): текст отдаётся наружу целиком.
    var onSegmentFinished: ((String) -> Void)?

    var isListening: Bool { status == .listening }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var isStarting = false
    /// Ждём итоговый результат после паузы (task.finish()), чтобы не потерять последние слова.
    private var awaitingFinal = false
    private var finalTimeout: Task<Void, Never>?

    /// Пауза между словами, после которой в тексте ставится перенос строки — подсказка для разбора.
    /// Короткие заминки внутри фразы (до трёх секунд) текст не делят.
    private let pauseThreshold: TimeInterval = 3.0
    /// Уровень сигнала, выше которого считаем, что человек говорит.
    private let voiceThreshold: Double = 0.08

    /// Сырой текст распознавателя и тот же текст с переносами по таймкодам сегментов.
    private var rawText = ""
    private var segmentText = ""
    /// Границы задач по паузам в звуке: после скольких слов была тишина дольше порога.
    private var breaks: [Int] = []
    private var lastVoiced: TimeInterval = 0

    func start() async {
        guard !isStarting, status != .listening else { return }
        isStarting = true
        defer { isStarting = false }
        guard await authorize() else {
            status = .denied
            return
        }
        guard let recognizer = recognizer, recognizer.isAvailable else {
            status = .unavailable
            return
        }
        finishPendingSegment()
        do {
            try beginSession(with: recognizer)
            status = .listening
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Пауза: звук останавливается, распознаватель дорабатывает последние слова и отдаёт заход целиком.
    func pause() {
        guard status == .listening else { return }
        status = .paused
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        level = 0
        request?.endAudio()
        if task != nil {
            awaitingFinal = true
            task?.finish()
            finalTimeout?.cancel()
            finalTimeout = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                if !Task.isCancelled { finishPendingSegment() }
            }
        } else {
            finishPendingSegment()
        }
    }

    /// Закрыть всё и забыть недоговорённый текст: экран уже забрал его из `liveText`/`onSegmentFinished`.
    /// Иначе следующий `start()` отдал бы его второй раз (дубли карточек после «Надиктовать ещё»).
    func shutdown() {
        discardPending()
        status = .idle
    }

    /// Забыть недоговорённый заход без передачи наружу (на паузе текст уже лежит в поле правки).
    func discardPending() {
        finalTimeout?.cancel()
        finalTimeout = nil
        awaitingFinal = false
        endSession()
        liveText = ""
        rawText = ""
        segmentText = ""
        breaks = []
        lastVoiced = 0
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
        rawText = ""
        segmentText = ""
        breaks = []
        lastVoiced = 0
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let power = Self.power(of: buffer)
            let time = CACurrentMediaTime()
            Task { @MainActor in self?.audioLevel(power, at: time) }
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

    /// Уровень сигнала для волны. Паузы в звуке задачи больше не делят: это резало фразы на куски.
    private func audioLevel(_ power: Double, at time: TimeInterval) {
        if abs(level - power) > 0.02 { level = power }
        if power > voiceThreshold { lastVoiced = time }
    }

    /// Живой текст: сырой текст распознавателя с переносами только по долгим паузам между сегментами.
    private func composeLiveText() {
        liveText = segmentText.isEmpty ? rawText : segmentText
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            rawText = result.bestTranscription.formattedString
            segmentText = Self.text(from: result.bestTranscription, pause: pauseThreshold)
            composeLiveText()
            if result.isFinal {
                if status == .listening {
                    // Лимит системы: закрываем заход, отдаём текст и начинаем новый.
                    finishPendingSegment()
                    if let recognizer, recognizer.isAvailable {
                        do {
                            try beginSession(with: recognizer)
                        } catch {
                            status = .failed(error.localizedDescription)
                        }
                    } else {
                        status = .unavailable
                    }
                } else {
                    finishPendingSegment()
                }
            }
            return
        }
        if error != nil {
            let wasListening = status == .listening
            let hadText = !liveText.isEmpty
            finishPendingSegment()
            if wasListening {
                status = hadText ? .paused : .failed("Не удалось распознать речь")
            }
        }
    }

    /// Отдать текст текущего захода наружу и закрыть сессию.
    private func finishPendingSegment() {
        finalTimeout?.cancel()
        finalTimeout = nil
        awaitingFinal = false
        let finished = liveText
        endSession()
        liveText = ""
        rawText = ""
        segmentText = ""
        breaks = []
        lastVoiced = 0
        if !finished.isEmpty { onSegmentFinished?(finished) }
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
