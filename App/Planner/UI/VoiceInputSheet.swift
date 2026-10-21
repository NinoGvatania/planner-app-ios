import PlannerCore
import SwiftUI

/// Голосовой ввод: говоришь всё подряд — задачи появляются карточками по мере распознавания.
/// Пауза делает карточки редактируемыми (тап — правка, крестик — удалить), «Ещё» продолжает диктовку,
/// «Готово» сохраняет всё. Распознавание — системное, по-русски.
struct VoiceInputSheet: View {
    let onDone: ([DraftTask]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = SpeechRecorder()
    /// Подтверждённые карточки (после паузы) — их можно править и удалять.
    @State private var drafts: [DraftTask] = []
    @State private var editing: DraftTask?
    @State private var levels: [Double] = Array(repeating: 0, count: 28)

    private var liveDrafts: [DraftTask] { DraftTask.drafts(from: recorder.liveText) }
    private var isEmpty: Bool { drafts.isEmpty && liveDrafts.isEmpty }

    private var statusText: String {
        switch recorder.status {
        case .idle: return "Подключаю микрофон…"
        case .listening: return "Слушаю…"
        case .paused: return "Пауза — можно поправить задачи"
        case .denied: return "Нет доступа к микрофону или распознаванию речи"
        case .unavailable: return "Распознавание речи сейчас недоступно"
        case .failed(let message): return message
        }
    }

    private var statusHint: String {
        switch recorder.status {
        case .listening: return "Говори всё, что нужно сделать — я разложу по задачам"
        case .paused: return "Нажми микрофон, чтобы добавить ещё"
        case .denied: return "Разреши в Настройках → Планировщик"
        default: return ""
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
                    Text("Диктовка")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tokens.caption)
                    Spacer()
                    Color.clear.frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(drafts) { draft in
                            card(draft, live: false)
                        }
                        ForEach(liveDrafts) { draft in
                            card(draft, live: true)
                        }
                        if isEmpty {
                            emptyHint
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 20)
                }
                .animation(.easeOut(duration: 0.2), value: drafts.count + liveDrafts.count)

                controls
            }
        }
        .foregroundStyle(Tokens.text)
        .task {
            recorder.onSegmentFinished = { text in
                drafts.append(contentsOf: DraftTask.drafts(from: text))
            }
            await recorder.start()
        }
        .onChange(of: recorder.level) { _, value in
            levels.removeFirst()
            levels.append(value)
        }
        .onDisappear { recorder.shutdown() }
        .sheet(item: $editing) { draft in
            DraftEditSheet(draft: Binding(
                get: { drafts.first { $0.id == draft.id } ?? draft },
                set: { updated in
                    if let index = drafts.firstIndex(where: { $0.id == draft.id }) { drafts[index] = updated }
                }
            ))
        }
    }

    // MARK: - Карточки

    private func card(_ draft: DraftTask, live: Bool) -> some View {
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
                .foregroundStyle(live ? Tokens.muted : Tokens.caption)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if live {
                Circle()
                    .fill(Tokens.accent)
                    .frame(width: 8, height: 8)
                    .padding(.top, 8)
                    .padding(.trailing, 8)
            } else {
                Button {
                    drafts.removeAll { $0.id == draft.id }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Tokens.caption)
                        .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                }
                .accessibilityLabel("Удалить: " + draft.title)
            }
        }
        .padding(.leading, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .background(live ? Tokens.panel.opacity(0.7) : Tokens.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(live ? Tokens.accent.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            if !live { editing = draft }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Text("Попробуй сказать")
                .font(.system(size: 13))
                .foregroundStyle(Tokens.muted)
            Text("«Позвонить маме. Завтра в 10 созвон, важно. Купить хлеб и молоко»")
                .font(.system(size: 20, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Tokens.accent)
            Text("Точка, пауза или «а ещё» — следующая задача. Слова «важно», «срочно», день и время понимаются как в быстром вводе.")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(Tokens.caption)
                .padding(.top, 6)
        }
        .padding(.horizontal, 12)
        .padding(.top, 120)
    }

    // MARK: - Управление

    private var controls: some View {
        VStack(spacing: 10) {
            Text(statusText)
                .font(.system(size: 16, weight: .semibold))
            Text(statusHint)
                .font(.system(size: 13))
                .foregroundStyle(Tokens.caption)
                .multilineTextAlignment(.center)
                .frame(minHeight: 16)
            HStack(spacing: 16) {
                Button {
                    if recorder.isListening {
                        pauseAndCommit()
                    } else {
                        Task { await recorder.start() }
                    }
                } label: {
                    Image(systemName: recorder.isListening ? "pause.fill" : "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 64, height: 64)
                        .background(Tokens.cluster, in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                }
                .accessibilityLabel(recorder.isListening ? "Пауза" : "Продолжить диктовку")

                waveform
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)

                Button(action: finish) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Tokens.onAccent)
                        .frame(width: 64, height: 64)
                        .background(isEmpty ? Tokens.accent.opacity(0.35) : Tokens.accent, in: Circle())
                }
                .disabled(isEmpty)
                .accessibilityLabel("Сохранить задачи")
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    private var waveform: some View {
        HStack(spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, value in
                Capsule()
                    .fill(recorder.isListening ? Tokens.accent : Tokens.muted)
                    .frame(width: 3, height: max(4, 4 + value * 30))
            }
        }
        .animation(.linear(duration: 0.08), value: levels)
    }

    private func pauseAndCommit() {
        recorder.pause()
        drafts.append(contentsOf: liveDrafts)
        recorder.clearLive()
    }

    private func finish() {
        if recorder.isListening { pauseAndCommit() }
        recorder.shutdown()
        onDone(drafts)
        dismiss()
    }
}
