import PlannerCore
import SwiftUI

/// Чат с ассистентом по задачам (Claude). Открывается микрофоном и сразу слушает. Надиктовал или написал —
/// отправил; ассистент отвечает коротко и показывает карточки задач с номерами и кнопкой «Добавить».
/// Пока не нажал «Добавить», в календаре ничего не меняется: можно попросить «поправь первую и третью,
/// добавь ещё одну» — придёт исправленный список, прежний станет неактивным. Карточки можно и поправить
/// руками (тап) или убрать (крестик) — ассистент видит список уже с этими правками.
struct AssistantChatView: View {
    /// Добавить задачи в календарь и бэклог (экран чата остаётся открытым).
    let onAdd: ([DraftTask]) -> Void
    var vocabulary = DictationVocabulary()
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = SpeechRecorder()

    private struct Message: Identifiable {
        enum Role { case user, assistant, error }
        enum Proposal { case none, active, added, superseded }
        let id = UUID()
        let role: Role
        var text: String
        var drafts: [DraftTask] = []
        var proposal: Proposal = .none
    }

    /// Какую карточку правят: сообщение и задача в нём.
    private struct EditTarget: Identifiable {
        let messageID: UUID
        let draftID: UUID
        var id: UUID { draftID }
    }

    @State private var messages: [Message] = []
    /// Текст в поле ввода; надиктованные заходы дописываются сюда.
    @State private var composer = ""
    @State private var busy = false
    @State private var editing: EditTarget?
    @State private var confirmClose = false
    @FocusState private var composerFocused: Bool

    /// Что уйдёт по стрелке: написанное плюс недоговорённое распознавателем.
    private var outgoing: String {
        [composer, recorder.liveText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
    private var canSend: Bool { !busy && !outgoing.isEmpty }
    private var activeIndex: Int? { messages.lastIndex { $0.proposal == .active } }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if messages.isEmpty { emptyHint }
                        ForEach(messages) { message in
                            row(message)
                        }
                        if busy { typing }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("end", anchor: .bottom) }
                }
                .onChange(of: busy) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
            composerBar
        }
        .background(Tokens.background.ignoresSafeArea())
        .foregroundStyle(Tokens.text)
        .task {
            recorder.onSegmentFinished = { text in
                let piece = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !piece.isEmpty else { return }
                composer = composer.isEmpty ? piece : composer + " " + piece
            }
            // Открыли микрофоном — сразу слушаем.
            await recorder.start()
        }
        .onDisappear { recorder.shutdown() }
        .sheet(item: $editing) { target in
            DraftEditSheet(draft: Binding(
                get: {
                    messages.first { $0.id == target.messageID }?.drafts.first { $0.id == target.draftID }
                        ?? DraftTask(parsed: ParsedTask(title: "", dayOffset: nil, start: nil, duration: 30, quadrant: nil, project: nil))
                },
                set: { updated in
                    guard let m = messages.firstIndex(where: { $0.id == target.messageID }),
                          let d = messages[m].drafts.firstIndex(where: { $0.id == target.draftID }) else { return }
                    messages[m].drafts[d] = updated
                }
            ))
        }
        .confirmationDialog("Задачи ещё не добавлены", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Добавить и закрыть") {
                if let index = activeIndex { add(at: index) }
                close()
            }
            Button("Закрыть без добавления", role: .destructive) { close() }
            Button("Остаться", role: .cancel) {}
        }
    }

    // MARK: - Шапка

    private var topBar: some View {
        HStack {
            Button {
                if let index = activeIndex, !messages[index].drafts.isEmpty {
                    confirmClose = true
                } else {
                    close()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                    .background(Tokens.cluster, in: Circle())
            }
            .accessibilityLabel("Закрыть ассистента")
            Spacer()
            VStack(spacing: 1) {
                Text("Ассистент")
                    .font(.system(size: 15, weight: .semibold))
                Text("Claude · " + ClaudeSettings.title(of: ClaudeSettings.model))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Tokens.muted)
            }
            Spacer()
            Color.clear.frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func close() {
        recorder.shutdown()
        dismiss()
    }

    // MARK: - Сообщения

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Надиктуй или напиши, что нужно сделать")
                .font(.system(size: 20, weight: .semibold))
            Text("Я соберу список задач — проверь и нажми «Добавить». Пока не нажал, в календаре ничего не меняется. Можно поправлять словами: «вторую на завтра в 10», «третью убери», «добавь ещё купить хлеб».")
                .font(.system(size: 14))
                .foregroundStyle(Tokens.caption)
        }
        .padding(.top, 24)
    }

    @ViewBuilder
    private func row(_ message: Message) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .font(.system(size: 15))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Tokens.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .textSelection(.enabled)
            }
        case .assistant:
            assistantRow(message)
        case .error:
            VStack(alignment: .leading, spacing: 6) {
                Text(message.text)
                    .font(.system(size: 14))
                    .foregroundStyle(Tokens.overdue)
                Button("Повторить", action: retry)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Tokens.accent)
                    .frame(minHeight: Tokens.hitTarget)
                    .disabled(busy)
            }
        }
    }

    private func assistantRow(_ message: Message) -> some View {
        let active = message.proposal == .active
        return VStack(alignment: .leading, spacing: 8) {
            if !message.text.isEmpty {
                Text(message.text)
                    .font(.system(size: 15))
                    .textSelection(.enabled)
            }
            if !message.drafts.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(message.drafts.enumerated()), id: \.element.id) { index, draft in
                        card(draft, number: index + 1, messageID: message.id, active: active)
                    }
                }
                .opacity(active || message.proposal == .added ? 1 : 0.45)
            }
            switch message.proposal {
            case .active where !message.drafts.isEmpty:
                Button {
                    if let index = messages.firstIndex(where: { $0.id == message.id }) { add(at: index) }
                } label: {
                    Text("Добавить " + "\(message.drafts.count) " + DayMath.plural(message.drafts.count, "задачу", "задачи", "задач"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tokens.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Tokens.accent, in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Добавить задачи в календарь")
            case .added:
                Label("Добавлено", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.accent)
            case .superseded:
                Text("Заменено новым вариантом ниже")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Tokens.muted)
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card(_ draft: DraftTask, number: Int, messageID: UUID, active: Bool) -> some View {
        let style = Quadrant(rawValue: draft.quadrantRaw)?.style ?? .unsorted
        return HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Tokens.background)
                .frame(width: 20, height: 20)
                .background(style.dot, in: Circle())
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(draft.title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .lineLimit(3)
                if !draft.notes.isEmpty {
                    Text(draft.notes)
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.text.opacity(0.75))
                        .lineLimit(4)
                }
                HStack(spacing: 6) {
                    Text(draft.whenText)
                    if draft.quadrantRaw != 0, let quadrant = Quadrant(rawValue: draft.quadrantRaw) {
                        Text("· " + quadrant.name.lowercased())
                    }
                    if !draft.project.isEmpty {
                        Text("· #" + draft.project)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Tokens.caption)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if active {
                Button {
                    guard let m = messages.firstIndex(where: { $0.id == messageID }) else { return }
                    withAnimation(.easeOut(duration: 0.2)) { messages[m].drafts.removeAll { $0.id == draft.id } }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tokens.caption)
                        .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Убрать: " + draft.title)
            }
        }
        .padding(.leading, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 52)
        .background(Tokens.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            guard active else { return }
            editing = EditTarget(messageID: messageID, draftID: draft.id)
        }
    }

    private var typing: some View {
        HStack(spacing: 8) {
            ProgressView().tint(Tokens.accent)
            Text("Думаю…")
                .font(.system(size: 14))
                .foregroundStyle(Tokens.caption)
        }
        .frame(minHeight: Tokens.hitTarget)
    }

    // MARK: - Ввод

    private var composerBar: some View {
        VStack(spacing: 6) {
            if let note = recorderNote {
                Text(note)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Tokens.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    TextField("Напиши или надиктуй…", text: $composer, axis: .vertical)
                        .focused($composerFocused)
                        .lineLimit(1...6)
                        .font(.system(size: 15))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .opacity(recorder.isListening ? 0 : 1)
                    if recorder.isListening {
                        // Пока слушаю — поле показывает уже сказанное и то, что распознаётся сейчас.
                        Text(outgoing.isEmpty ? "Слушаю…" : outgoing)
                            .font(.system(size: 15))
                            .foregroundStyle(outgoing.isEmpty ? Tokens.muted : Tokens.text)
                            .lineLimit(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }
                }
                .frame(minHeight: Tokens.hitTarget)
                .glassEffect(.regular.tint(Tokens.field.opacity(0.5)), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                Button(action: toggleListening) {
                    Image(systemName: recorder.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                        .glassEffect(.regular.tint((recorder.isListening ? Tokens.overdueBadge : Tokens.cluster).opacity(0.8)).interactive(), in: Circle())
                        .foregroundStyle(Tokens.text)
                }
                .accessibilityLabel(recorder.isListening ? "Остановить диктовку" : "Надиктовать")

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                        .glassEffect(.regular.tint(Tokens.accent.opacity(canSend ? 0.85 : 0.3)).interactive(), in: Circle())
                        .foregroundStyle(Tokens.onAccent)
                }
                .disabled(!canSend)
                .accessibilityLabel("Отправить")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var recorderNote: String? {
        switch recorder.status {
        case .denied: return "Нет доступа к микрофону или распознаванию — можно писать текстом"
        case .unavailable: return "Распознавание речи сейчас недоступно — можно писать текстом"
        case .failed(let message): return message
        default: return nil
        }
    }

    private func toggleListening() {
        if recorder.isListening {
            // Последний заход распознаватель допишет в поле сам (onSegmentFinished).
            recorder.pause()
        } else {
            composerFocused = false
            Task { await recorder.start() }
        }
    }

    // MARK: - Разговор

    private func send() {
        let text = outgoing
        guard !text.isEmpty, !busy else { return }
        // Сказанное уже в `text`: недоговорённый заход распознавателя второй раз не нужен.
        recorder.shutdown()
        composer = ""
        composerFocused = false
        messages.append(Message(role: .user, text: text))
        requestReply()
    }

    /// Ошибка сети или ключа — ещё раз по той же истории.
    private func retry() {
        messages.removeAll { $0.role == .error }
        requestReply()
    }

    private func requestReply() {
        let turns: [ClaudeAssistant.Turn] = messages.compactMap { message in
            switch message.role {
            case .user: return ClaudeAssistant.Turn(role: .user, text: message.text)
            case .assistant:
                return ClaudeAssistant.Turn(role: .assistant, text: message.text, tasks: message.drafts,
                                            added: message.proposal == .added)
            case .error: return nil
            }
        }
        busy = true
        Task { @MainActor in
            do {
                let result = try await ClaudeAssistant.reply(
                    to: turns, apiKey: ClaudeSettings.apiKey, model: ClaudeSettings.model, vocabulary: vocabulary
                )
                // Новый список заменяет прежний недобавленный — добавить можно только последний.
                for index in messages.indices where messages[index].proposal == .active {
                    messages[index].proposal = .superseded
                }
                let reply = result.reply.isEmpty && result.drafts.isEmpty ? "Задач не нашёл — скажи иначе?" : result.reply
                messages.append(Message(role: .assistant, text: reply, drafts: result.drafts,
                                        proposal: result.drafts.isEmpty ? .none : .active))
            } catch {
                messages.append(Message(role: .error, text: ClaudeExtractor.message(for: error)))
            }
            busy = false
        }
    }

    private func add(at index: Int) {
        guard messages.indices.contains(index), messages[index].proposal == .active, !messages[index].drafts.isEmpty else { return }
        onAdd(messages[index].drafts)
        messages[index].proposal = .added
    }
}
