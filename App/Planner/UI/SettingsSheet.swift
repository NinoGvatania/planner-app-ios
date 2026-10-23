import SwiftData
import SwiftUI

/// Настройки: напоминания, экспорт в Календарь, разбор диктовки (Claude по своему ключу, Apple Intelligence,
/// правила), сборка.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var tasks: [PlannerTask]
    @AppStorage(NotificationScheduler.leadKey) private var reminderLead = 0
    @AppStorage(CalendarSync.enabledKey) private var calendarExport = false
    @AppStorage(CalendarSync.calendarKey) private var calendarID = ""
    @State private var calendarAccess = CalendarSync.hasAccess
    @State private var calendarDenied = CalendarSync.isDenied
    @State private var calendars: [CalendarSync.CalendarChoice] = []
    @State private var syncNote = ""
    @AppStorage(ClaudeSettings.enabledKey) private var claudeEnabled = true
    @AppStorage(ClaudeSettings.modelKey) private var claudeModel = ClaudeSettings.defaultModel
    @AppStorage(BacklogSettings.reopenKey) private var backlogReopens = true
    /// Ключ в поле ввода (сохраняется в связку ключей кнопкой).
    @State private var claudeKey = ""
    @State private var claudeHasKey = ClaudeSettings.hasKey
    @State private var claudeNote = ""
    @State private var claudeChecking = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Напоминания о задачах") {
                    Picker("Напоминать", selection: $reminderLead) {
                        ForEach(NotificationScheduler.leadOptions, id: \.minutes) { option in
                            Text(option.title).tag(option.minutes)
                        }
                    }
                }
                Section {
                    Picker("После переноса", selection: $backlogReopens) {
                        Text("Раскрыть снова").tag(true)
                        Text("Оставить свёрнутым").tag(false)
                    }
                } header: {
                    Text("Бэклог")
                } footer: {
                    Text("Когда тянешь задачу, раскрытый бэклог сворачивается, чтобы не закрывать календарь. После того как отпустил — раскрывается снова или остаётся свёрнутым, пока не нажмёшь на него сам.")
                }
                calendarSection
                claudeSection
                Section {
                    LabeledContent("Сейчас разбирает", value: engineTitle)
                    Text(OnDeviceExtractor.status.note)
                        .font(.footnote)
                        .foregroundStyle(Tokens.caption)
                } header: {
                    Text("Диктовка")
                } footer: {
                    Text("По порядку: Claude (если ключ задан и включён), Apple Intelligence на iPhone, правила — точки, паузы, «а ещё», «потом», союз «и» между действиями, чистка речевого мусора. Почему не сработала модель, видно на экране разбора.")
                }
                Section {
                    LabeledContent("Сборка", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tokens.panel)
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        // Вставленный, но не сохранённый ключ не теряется.
                        saveClaudeKey()
                        dismiss()
                    }
                }
            }
        }
        .tint(Tokens.accent)
        .presentationDetents([.large])
        .presentationBackground(Tokens.panel)
        .onDisappear {
            // Закрыли лист свайпом — вставленный ключ всё равно сохраняется.
            saveClaudeKey()
        }
        .onAppear {
            if calendarAccess { calendars = CalendarSync.writableCalendars() }
        }
        .onChange(of: calendarExport) { _, on in
            Task {
                if on {
                    let granted = await CalendarSync.requestAccess()
                    calendarAccess = granted
                    calendarDenied = !granted
                    guard granted else { return }
                    calendars = CalendarSync.writableCalendars()
                    await syncCalendarNow()
                } else {
                    await CalendarSync.clear()
                    syncNote = ""
                }
            }
        }
        .onChange(of: calendarID) { _, _ in
            Task { await syncCalendarNow() }
        }
        .onChange(of: reminderLead) { _, _ in NotificationScheduler.sync(tasks) }
    }

    // MARK: - Claude

    private var engineTitle: String {
        if claudeHasKey && claudeEnabled { return "Claude · " + ClaudeSettings.title(of: claudeModel) }
        return OnDeviceExtractor.status == .available ? "Apple Intelligence, если iOS не откажет, иначе правила" : "правила"
    }

    private var claudeSection: some View {
        Section {
            Toggle("Разбирать через Claude", isOn: Binding(
                get: { claudeHasKey && claudeEnabled },
                set: { claudeEnabled = $0 }
            ))
            .disabled(!claudeHasKey)
            SecureField(claudeHasKey ? "Ключ сохранён · ввести новый" : "Ключ API: sk-ant-…", text: $claudeKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15, design: .monospaced))
                .submitLabel(.done)
                .onSubmit(saveClaudeKey)
            if !claudeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Сохранить ключ", action: saveClaudeKey)
            }
            Picker("Модель", selection: $claudeModel) {
                ForEach(ClaudeSettings.models, id: \.id) { item in
                    Text(item.title).tag(item.id)
                }
            }
            if claudeHasKey {
                Button(claudeChecking ? "Проверяю…" : "Проверить ключ") {
                    claudeChecking = true
                    claudeNote = ""
                    Task {
                        claudeNote = await ClaudeExtractor.check(apiKey: ClaudeSettings.apiKey, model: claudeModel)
                        claudeChecking = false
                    }
                }
                .disabled(claudeChecking)
                Button("Удалить ключ", role: .destructive) {
                    KeychainStore.write("", for: ClaudeSettings.keyAccount)
                    claudeHasKey = false
                    claudeKey = ""
                    claudeNote = "Ключ удалён"
                }
            }
            if !claudeNote.isEmpty {
                Text(claudeNote)
                    .font(.footnote)
                    .foregroundStyle(Tokens.caption)
            }
        } header: {
            Text("Claude — свой ключ API")
        } footer: {
            Text("Ключ создаётся на console.anthropic.com → API Keys (нужен пополненный баланс; подписка Claude Pro/Max для API не подходит). Хранится только в связке ключей этого iPhone. Надиктованный текст уходит на api.anthropic.com только при разборе диктовки. Цена диктовки: Haiku — доли цента, Sonnet — около цента, Opus — пара центов. Без сети или при ошибке разбор идёт дальше по порядку.")
        }
    }

    private func saveClaudeKey() {
        let key = claudeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        KeychainStore.write(key, for: ClaudeSettings.keyAccount)
        claudeHasKey = ClaudeSettings.hasKey
        claudeKey = ""
        claudeEnabled = true
        claudeNote = claudeHasKey ? "Ключ сохранён — нажми «Проверить ключ»" : "Не удалось сохранить ключ"
    }

    // MARK: - Календарь

    private var calendarSection: some View {
        Section {
            Toggle("Задачи в Календаре", isOn: $calendarExport)
            if calendarExport {
                if calendarAccess {
                    Picker("Календарь", selection: $calendarID) {
                        Text("Новый «Quick»").tag("")
                        ForEach(calendars) { choice in
                            Text(choice.source.isEmpty ? choice.title : choice.source + " · " + choice.title).tag(choice.id)
                        }
                    }
                    Button("Синхронизировать сейчас") {
                        Task { await syncCalendarNow() }
                    }
                    if !syncNote.isEmpty {
                        Text(syncNote)
                            .font(.footnote)
                            .foregroundStyle(Tokens.caption)
                    }
                } else if calendarDenied {
                    Text("Нет доступа к Календарю. Разреши полный доступ: Настройки iOS → Quick → Календари.")
                        .font(.footnote)
                        .foregroundStyle(Tokens.overdue)
                } else {
                    Text("Запрашиваю доступ к Календарю…")
                        .font(.footnote)
                        .foregroundStyle(Tokens.caption)
                }
            }
        } header: {
            Text("Календарь Apple и Google")
        } footer: {
            Text("Задачи с датой уходят событиями в выбранный календарь: с временем — по времени, без — на весь день. Сделанные и бэклог не попадают, правки и удаления подхватываются. Google: подключи аккаунт Google в Настройках iOS → Календарь и выбери его календарь здесь.")
        }
    }

    private func syncCalendarNow() async {
        guard calendarExport, CalendarSync.hasAccess else { return }
        guard let count = await CalendarSync.syncNow(tasks) else {
            syncNote = "Не удалось создать календарь «Quick» — выбери в списке существующий календарь"
            return
        }
        syncNote = "В календаре \(count) " + DayMath.plural(count, "событие", "события", "событий")
    }
}
