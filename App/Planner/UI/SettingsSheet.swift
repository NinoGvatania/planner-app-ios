import SwiftData
import SwiftUI

/// Настройки: экспорт в Календарь, ключ Claude API для умной диктовки (хранится в связке ключей) и модель.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var tasks: [PlannerTask]
    @State private var apiKey = ""
    @State private var saved = false
    @AppStorage(TaskExtractor.modelKey) private var model = TaskExtractor.defaultModel
    @AppStorage(CalendarSync.enabledKey) private var calendarExport = false
    @AppStorage(CalendarSync.calendarKey) private var calendarID = ""
    @State private var calendarAccess = CalendarSync.hasAccess
    @State private var calendarDenied = CalendarSync.isDenied
    @State private var calendars: [CalendarSync.CalendarChoice] = []
    @State private var syncNote = ""

    var body: some View {
        NavigationStack {
            Form {
                calendarSection
                Section {
                    SecureField("sk-ant-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 15, design: .monospaced))
                    Button(saved ? "Сохранено" : "Сохранить ключ") {
                        KeychainStore.write(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: TaskExtractor.apiKeyAccount)
                        saved = true
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines) == TaskExtractor.apiKey)
                    if TaskExtractor.hasKey {
                        Button("Удалить ключ", role: .destructive) {
                            KeychainStore.write("", for: TaskExtractor.apiKeyAccount)
                            apiKey = ""
                            saved = false
                        }
                    }
                } header: {
                    Text("Умная диктовка — Claude API")
                } footer: {
                    Text("С ключом надиктованный текст делится на задачи по смыслу, а формулировки чистятся от речевого мусора. Без ключа работают правила. Ключ хранится только в связке ключей этого iPhone и уходит только на api.anthropic.com. Ключ берётся в console.anthropic.com.")
                }
                Section("Модель") {
                    Picker("Модель", selection: $model) {
                        ForEach(TaskExtractor.models, id: \.id) { item in
                            Text(item.title).tag(item.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
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
                    Button("Готово") { dismiss() }
                }
            }
        }
        .tint(Tokens.accent)
        .presentationDetents([.large])
        .presentationBackground(Tokens.panel)
        .onAppear {
            apiKey = TaskExtractor.apiKey
            if calendarAccess { calendars = CalendarSync.writableCalendars() }
        }
        .onChange(of: apiKey) { _, _ in saved = false }
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
                    Text("Нет доступа к Календарю. Разреши полный доступ: Настройки iOS → Планировщик → Календари.")
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
        let count = await CalendarSync.syncNow(tasks)
        syncNote = "В календаре \(count) " + DayMath.plural(count, "событие", "события", "событий")
    }
}
