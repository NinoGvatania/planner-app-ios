import SwiftData
import SwiftUI

/// Настройки: напоминания, экспорт в Календарь, состояние умного разбора диктовки (на устройстве), сборка.
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
                calendarSection
                Section {
                    LabeledContent("Умный разбор", value: OnDeviceExtractor.status == .available ? "Apple Intelligence" : "правила")
                    Text(OnDeviceExtractor.status.note)
                        .font(.footnote)
                        .foregroundStyle(Tokens.caption)
                } header: {
                    Text("Диктовка")
                } footer: {
                    Text("Надиктованный текст разбирается на задачи прямо на iPhone, в сеть ничего не уходит. Если Apple Intelligence доступен и понимает русский, делит по смыслу и чистит формулировки; иначе работают правила: точки, паузы, «а ещё», «потом», союз «и» между действиями, чистка речевого мусора.")
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
