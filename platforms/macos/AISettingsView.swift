import SwiftUI

struct AISettingsView: View {
    @StateObject private var ollama = OllamaService.shared
    @State private var config = AIService.shared.loadConfig()
    @State private var acceptShortcut = AISettingsView.loadShortcut()
    @State private var toggleShortcut = AISettingsView.loadShortcut(key: GhostTextManager.toggleShortcutKey)
    @State private var recordingAccept = false
    @State private var recordingToggle = false
    @State private var modelToDelete: OllamaModelInfo?
    @AppStorage(GhostTextManager.displayModeKey) private var displayMode = "inline"
    @AppStorage(GhostTextManager.completionLengthKey) private var completionLength = "medium"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                aiToggle
                appearanceSection
                ollamaStatus
                modelSection
                shortcutSection
                privacySection
            }
            .padding(24)
        }
        .frame(minWidth: 620, minHeight: 620)
        .onAppear {
            config.providerType = .localOllama
            Task { await ollama.refresh() }
        }
        .onChange(of: config.isEnabled) { newValue in
            saveConfig()
            if !newValue { GhostTextManager.shared.dismiss() }
        }
        .onChange(of: config.model) { _ in saveConfig() }
        .onChange(of: acceptShortcut) { _ in saveShortcut(acceptShortcut, key: GhostTextManager.acceptShortcutKey) }
        .onChange(of: toggleShortcut) { _ in saveShortcut(toggleShortcut, key: GhostTextManager.toggleShortcutKey) }
        .alert("Xóa model Ollama?", isPresented: Binding(
            get: { modelToDelete != nil },
            set: { if !$0 { modelToDelete = nil } }
        ), presenting: modelToDelete) { model in
            Button("Xóa", role: .destructive) {
                Task { await ollama.delete(model: model.name) }
                modelToDelete = nil
            }
            Button("Hủy", role: .cancel) { modelToDelete = nil }
        } message: { model in
            Text("Model \(model.name) sẽ bị xóa khỏi Ollama trên máy này.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("AI Copilot")
                .font(.system(size: 24, weight: .semibold))
            Text("Gợi ý phần tiếp theo ngay trong ô đang gõ. Beta chỉ dùng model Ollama chạy trên máy.")
                .font(.system(size: 13))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
    }

    private var aiToggle: some View {
        SettingsCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bật gợi ý AI")
                        .font(.system(size: 14, weight: .medium))
                    Text("Bộ gõ tiếng Việt vẫn hoạt động khi AI tắt hoặc Ollama lỗi.")
                        .font(.system(size: 12))
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                }
                Spacer()
                Toggle("", isOn: $config.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hiển thị & Độ dài")
                .font(.system(size: 15, weight: .semibold))
            SettingsCard {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kiểu hiển thị")
                                .font(.system(size: 13, weight: .medium))
                            Text("Chữ mờ tự nhiên tại con trỏ hoặc thẻ nổi có phím Tab.")
                                .font(.system(size: 11))
                                .foregroundColor(Color(NSColor.secondaryLabelColor))
                        }
                        Spacer()
                        Picker("", selection: $displayMode) {
                            Text("Inline (Chữ mờ)").tag("inline")
                            Text("Pill (Thẻ nổi)").tag("pill")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Độ dài gợi ý")
                                .font(.system(size: 13, weight: .medium))
                            Text("Gợi ý ngắn phản hồi nhanh hơn; dài viết câu trọn vẹn hơn.")
                                .font(.system(size: 11))
                                .foregroundColor(Color(NSColor.secondaryLabelColor))
                        }
                        Spacer()
                        Picker("", selection: $completionLength) {
                            Text("Ngắn (1–3)").tag("short")
                            Text("Vừa (4–6)").tag("medium")
                            Text("Dài (7–10)").tag("long")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                }
            }
        }
    }

    private var ollamaStatus: some View {
        SettingsCard {
            HStack(spacing: 10) {
                Circle()
                    .fill(ollama.isReachable ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ollama.isReachable ? "Ollama đang chạy" : "Chưa kết nối Ollama")
                        .font(.system(size: 13, weight: .medium))
                    Text(ollama.isReachable ? "localhost:11434" : "Cài Ollama và mở daemon để tải model.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                }
                Spacer()
                Button("Làm mới") { Task { await ollama.refresh() } }
                    .buttonStyle(.bordered)
            }
            if let error = ollama.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Model autocomplete")
                .font(.system(size: 15, weight: .semibold))
            ForEach(ollama.recommendations) { recommendation in
                modelRow(recommendation)
            }
            if !ollama.selectableModels.isEmpty {
                Text("Model đã cài")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.top, 6)
                ForEach(ollama.selectableModels) { model in
                    installedModelRow(model)
                }
            }
            if ollama.models.contains(where: { !$0.isGenerative }) {
                Text("Model embedding chỉ dùng để tìm kiếm, không dùng được cho autocomplete.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
            }
        }
    }

    private func modelRow(_ recommendation: OllamaModelRecommendation) -> some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(recommendation.model).font(.system(size: 13, weight: .medium))
                        if config.model == recommendation.model {
                            Text("Đang chọn").font(.system(size: 10, weight: .medium)).foregroundColor(.accentColor)
                        }
                    }
                    Text(recommendation.title).font(.system(size: 12))
                    Text(recommendation.description).font(.system(size: 11)).foregroundColor(Color(NSColor.secondaryLabelColor))
                    Text(recommendation.memoryRequirement).font(.system(size: 10)).foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
                Spacer()
                if ollama.downloadingModel == recommendation.model {
                    VStack(spacing: 5) {
                        if let progress = ollama.downloadProgress {
                            ProgressView(value: progress).frame(width: 90)
                        } else {
                            ProgressView().frame(width: 90)
                        }
                        Button("Hủy") { ollama.cancelPull() }.buttonStyle(.borderless)
                    }
                } else if ollama.hasModel(recommendation.model) {
                    Button(config.model == recommendation.model ? "Đang dùng" : "Chọn") {
                        config.model = recommendation.model
                        saveConfig()
                    }
                    .buttonStyle(.bordered)
                    .disabled(config.model == recommendation.model)
                } else {
                    Button("Tải model") { ollama.pull(model: recommendation.model) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!ollama.isReachable || ollama.downloadingModel != nil)
                }
            }
        }
    }

    private func installedModelRow(_ model: OllamaModelInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.name).font(.system(size: 12, weight: .medium))
                Text(model.sizeDescription).font(.system(size: 10)).foregroundColor(Color(NSColor.secondaryLabelColor))
            }
            Spacer()
            Button(config.model == model.name ? "Đang dùng" : "Chọn") {
                config.model = model.name
                saveConfig()
            }
            .buttonStyle(.bordered)
            .disabled(config.model == model.name)
            Button(role: .destructive) {
                modelToDelete = model
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
        .cornerRadius(7)
    }

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Phím tắt AI")
                .font(.system(size: 15, weight: .semibold))
            SettingsCard {
                ShortcutRecorderRow(
                    shortcut: $acceptShortcut,
                    isRecording: $recordingAccept,
                    title: "Nhận gợi ý",
                    subtitle: "Chỉ chiếm phím khi có gợi ý hợp lệ"
                )
                Divider()
                ShortcutRecorderRow(
                    shortcut: $toggleShortcut,
                    isRecording: $recordingToggle,
                    title: "Bật/tắt AI",
                    subtitle: "Có thể tự ghi lại phím tắt riêng"
                )
            }
        }
    }

    private var privacySection: some View {
        SettingsCard {
            Label("AI chỉ đọc ngữ cảnh quanh con trỏ qua Accessibility. Trường mật khẩu và secure input bị bỏ qua.", systemImage: "lock.shield")
                .font(.system(size: 11))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
    }

    private func saveConfig() {
        config.providerType = .localOllama
        config.baseURL = AIProviderType.localOllama.defaultBaseURL
        AIService.shared.saveConfig(config)
    }

    private static func loadShortcut(key: String = GhostTextManager.acceptShortcutKey) -> KeyboardShortcut {
        guard let data = UserDefaults.standard.data(forKey: key),
              let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data)
        else {
            if key == GhostTextManager.toggleShortcutKey {
                return KeyboardShortcut(keyCode: 0x31, modifiers: CGEventFlags.maskControl.union(.maskAlternate).rawValue)
            }
            return KeyboardShortcut(keyCode: 0x30, modifiers: 0)
        }
        return shortcut
    }

    private func saveShortcut(_ shortcut: KeyboardShortcut, key: String) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private struct SettingsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.65))
            .cornerRadius(9)
    }
}
