import SwiftUI

/// Настройки: ключ Claude API для умной диктовки (хранится в связке ключей) и модель.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var saved = false
    @AppStorage(TaskExtractor.modelKey) private var model = TaskExtractor.defaultModel

    var body: some View {
        NavigationStack {
            Form {
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
        .onAppear { apiKey = TaskExtractor.apiKey }
        .onChange(of: apiKey) { _, _ in saved = false }
    }
}
