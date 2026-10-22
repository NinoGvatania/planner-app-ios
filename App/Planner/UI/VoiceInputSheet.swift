import PlannerCore
import SwiftUI

/// Голосовой ввод: сначала экран слушает всё подряд и показывает расшифровку, по галочке весь текст
/// разбирается на задачи прямо на устройстве (Apple Intelligence или правила), потом карточки можно
/// поправить и сохранить.
struct VoiceInputSheet: View {
    let onDone: ([DraftTask]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = SpeechRecorder()

    private enum Stage { case listening, processing, review }
    @State private var stage: Stage = .listening
    /// Законченные заходы распознавания.
    @State private var committed: [String] = []
    /// Текст, который можно поправить на паузе.
    @State private var editedTranscript = ""
    @State private var drafts: [DraftTask] = []
    @State private var editing: DraftTask?
    @State private var sourceNote = ""
    @FocusState private var transcriptFocused: Bool
    /// На паузе текст правят в редакторе только после тапа по нему: до этого он стоит как стоял
    /// (тот же кегль, та же прокрутка к концу), без прыжка.
    @State private var editingTranscript = false
    @State private var transcriptSelection: TextSelection?

    private var transcript: String {
        (committed + [recorder.liveText]).filter { !$0.isEmpty }.joined(separator: "\n")
    }
    private var isEmptyTranscript: Bool { transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// Что уйдёт в разбор по галочке: на паузе — поле правки, иначе — живая расшифровка.
    private var textToProcess: String { recorder.status == .paused ? editedTranscript : transcript }
    private var canProcess: Bool { !textToProcess.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var statusText: String {
        switch recorder.status {
        case .idle: return "Подключаю микрофон…"
        case .listening: return "Слушаю…"
        case .paused: return "Пауза — нажми на текст, чтобы поправить"
        case .denied: return "Нет доступа к микрофону или распознаванию речи"
        case .unavailable: return "Распознавание речи сейчас недоступно"
        case .failed(let message): return message
        }
    }

    var body: some View {
        ZStack {
            Tokens.background.ignoresSafeArea()
            RadialGradient(
                colors: [Tokens.accent.opacity(recorder.isListening ? 0.22 : 0.08), Color.clear],
                center: .bottom, startRadius: 20, endRadius: 520
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: recorder.isListening)

            VStack(spacing: 0) {
                topBar
                switch stage {
                case .listening:
                    transcriptArea
                    listeningControls
                case .processing:
                    Spacer()
                    ProgressView()
                        .controlSize(.large)
                        .tint(Tokens.accent)
                    Text("Разбираю на задачи…")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.top, 16)
                    Spacer()
                case .review:
                    reviewList
                    reviewControls
                }
            }
        }
        .foregroundStyle(Tokens.text)
        .task {
            recorder.onSegmentFinished = { text in
                committed.append(text)
            }
            await recorder.start()
        }
        .onDisappear { recorder.shutdown() }
        .onChange(of: recorder.status) { _, status in
            // Распознаватель сам ушёл в паузу (ошибка, обрыв сети): поле правки заполняем тем, что есть.
            if status == .paused, editedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                editedTranscript = transcript
            }
        }
        .sheet(item: $editing) { draft in
            DraftEditSheet(draft: Binding(
                get: { drafts.first { $0.id == draft.id } ?? draft },
                set: { updated in
                    if let index = drafts.firstIndex(where: { $0.id == draft.id }) { drafts[index] = updated }
                }
            ))
        }
    }

    // MARK: - Шапка

    private var topBar: some View {
        HStack {
            Button {
                recorder.shutdown()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                    .background(Tokens.cluster, in: Circle())
            }
            .accessibilityLabel("Отменить диктовку")
            Spacer()
            Text(stage == .review ? "Задачи" : "Диктовка")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Tokens.caption)
            Spacer()
            Color.clear.frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Слушаем

    /// Что видно в области текста: на паузе — то, что можно править, иначе — живая расшифровка.
    private var shownTranscript: String { recorder.status == .paused ? editedTranscript : transcript }

    private var transcriptArea: some View {
        Group {
            let paused = recorder.status == .paused
            // Фокус в редакторе — тоже правка: иначе после первой буквы в пустом поле редактор
            // сменился бы текстом и клавиатура закрылась.
            if paused && (editingTranscript || transcriptFocused || editedTranscript.isEmpty) {
                // Редактор с теми же кеглем, интерлиньяжем и полями, что у текста при записи:
                // 15 + 5 (поле строки UITextView) = 20 по горизонтали, 8 + 8 (отступ контейнера) = 16 сверху.
                TextEditor(text: $editedTranscript, selection: $transcriptSelection)
                    .focused($transcriptFocused)
                    .font(.system(size: 22, weight: .medium))
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 15)
                    .padding(.top, 8)
                    .task { transcriptFocused = editingTranscript }
                    .onChange(of: transcriptFocused) { _, focused in
                        if focused { editingTranscript = true }
                    }
            } else if shownTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyHint
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        Text(shownTranscript)
                            .font(.system(size: 22, weight: .medium))
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .onChange(of: shownTranscript) { _, _ in
                        withAnimation { proxy.scrollTo("end", anchor: .bottom) }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    // Тап на паузе — править: курсор в конце текста, там, где остановились.
                    guard paused else { return }
                    transcriptSelection = TextSelection(insertionPoint: editedTranscript.endIndex)
                    editingTranscript = true
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Text("Говори всё, что нужно сделать")
                .font(.system(size: 22, weight: .semibold))
                .multilineTextAlignment(.center)
            Text("Как угодно, с паузами и оговорками. По галочке я разберу текст на отдельные короткие задачи, пойму дни, время и «важно / срочно».")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Tokens.caption)
            if !ClaudeSettings.isEnabled {
                Text("Без Claude разбор идёт по правилам: точка, пауза, «а ещё», «потом», «и» между действиями. Свой ключ Claude — в «…» → «Настройки…».")
                    .font(.system(size: 12.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Tokens.muted)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listeningControls: some View {
        VStack(spacing: 10) {
            Text(statusText)
                .font(.system(size: 16, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 24)
            Text(recorder.status == .denied ? "Разреши в Настройках → Quick" : (recorder.isListening ? "Нажми паузу, чтобы поправить текст, или галочку, чтобы разобрать" : "Микрофон — продолжить, галочка — разобрать"))
                .font(.system(size: 13))
                .foregroundStyle(Tokens.caption)
                .multilineTextAlignment(.center)
                .frame(minHeight: 16)
                .padding(.horizontal, 24)
            HStack(spacing: 16) {
                Button {
                    if recorder.isListening {
                        pause()
                    } else {
                        resume()
                    }
                } label: {
                    Image(systemName: recorder.isListening ? "pause.fill" : "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 64, height: 64)
                        .background(Tokens.cluster, in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                }
                .disabled(recorder.status == .idle)
                .accessibilityLabel(recorder.isListening ? "Пауза" : "Продолжить диктовку")

                WaveformView(recorder: recorder)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)

                Button(action: process) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Tokens.onAccent)
                        .frame(width: 64, height: 64)
                        .background(canProcess ? Tokens.accent : Tokens.accent.opacity(0.35), in: Circle())
                }
                .disabled(!canProcess)
                .accessibilityLabel("Разобрать на задачи")
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    private func pause() {
        recorder.pause()
        // Итоговый текст придёт через onSegmentFinished чуть позже; поле заполняем тем, что есть,
        // и через полторы секунды подменяем полной версией, если пользователь ещё ничего не правил.
        let snapshot = transcript
        editedTranscript = snapshot
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            guard recorder.status == .paused, editedTranscript == snapshot else { return }
            let latest = committed.joined(separator: "\n")
            if latest.count > snapshot.count { editedTranscript = latest }
        }
    }

    private func resume() {
        // Правки на паузе становятся основой, дальше дописываем. Недоговорённый заход распознавателя
        // уже лежит в поле — второй раз его не принимаем.
        if recorder.status == .paused {
            recorder.discardPending()
            committed = editedTranscript.isEmpty ? [] : [editedTranscript]
        }
        transcriptFocused = false
        editingTranscript = false
        Task { await recorder.start() }
    }

    private func process() {
        let text = textToProcess
        recorder.shutdown()
        transcriptFocused = false
        editingTranscript = false
        stage = .processing
        Task { @MainActor in
            let result = await TaskExtractor.extract(text)
            // «Надиктовать ещё» добавляет к уже разобранным карточкам, а не заменяет их.
            drafts.append(contentsOf: result.drafts)
            switch result.source {
            case .claude(let model): sourceNote = "Разобрано Claude · " + ClaudeSettings.title(of: model)
            case .apple: sourceNote = "Разобрано Apple Intelligence на устройстве"
            case .rules(let reason): sourceNote = reason ?? "Разобрано правилами"
            }
            stage = .review
        }
    }

    // MARK: - Проверка

    private var reviewList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                Text(sourceNote)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Tokens.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                ForEach(drafts) { draft in
                    card(draft)
                }
                if drafts.isEmpty {
                    Text("Задач не нашлось. Вернись и надиктуй ещё.")
                        .font(.system(size: 15))
                        .foregroundStyle(Tokens.caption)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
    }

    private func card(_ draft: DraftTask) -> some View {
        let style = Quadrant(rawValue: draft.quadrantRaw)?.style ?? .unsorted
        return HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(style.dot)
                .frame(width: 12, height: 12)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(draft.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(3)
                HStack(spacing: 6) {
                    Text(draft.whenText)
                    if draft.quadrantRaw != 0, let quadrant = Quadrant(rawValue: draft.quadrantRaw) {
                        Text("· " + quadrant.name.lowercased())
                    }
                    if !draft.project.isEmpty {
                        Text("· #" + draft.project)
                    }
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Tokens.caption)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                drafts.removeAll { $0.id == draft.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.caption)
                    .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Удалить: " + draft.title)
        }
        .padding(.leading, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .background(Tokens.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { editing = draft }
    }

    private var reviewControls: some View {
        HStack(spacing: 16) {
            Button {
                // Ещё надиктовать: текущие карточки остаются, новый текст добавится к ним.
                committed = []
                editedTranscript = ""
                editingTranscript = false
                stage = .listening
                Task { await recorder.start() }
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 64, height: 64)
                    .background(Tokens.cluster, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }
            .accessibilityLabel("Надиктовать ещё")
            Text("\(drafts.count) " + DayMath.plural(drafts.count, "задача", "задачи", "задач"))
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
            Button {
                recorder.shutdown()
                onDone(drafts)
                dismiss()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Tokens.onAccent)
                    .frame(width: 64, height: 64)
                    .background(drafts.isEmpty ? Tokens.accent.opacity(0.35) : Tokens.accent, in: Circle())
            }
            .disabled(drafts.isEmpty)
            .accessibilityLabel("Сохранить задачи")
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }
}

/// Волна уровня сигнала: живёт отдельно, чтобы частые обновления уровня не перерисовывали текст.
private struct WaveformView: View {
    let recorder: SpeechRecorder
    @State private var levels: [Double] = Array(repeating: 0, count: 28)

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, value in
                Capsule()
                    .fill(recorder.isListening ? Tokens.accent : Tokens.muted)
                    .frame(width: 3, height: max(4, 4 + value * 30))
            }
        }
        .animation(.linear(duration: 0.08), value: levels)
        .onChange(of: recorder.level) { _, value in
            levels.removeFirst()
            levels.append(value)
        }
    }
}
