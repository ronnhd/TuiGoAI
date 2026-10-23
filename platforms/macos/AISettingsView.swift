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
    @AppStorage(GhostTextManager.clipboardContextEnabledKey) private var clipboardContextEnabled = true
    @AppStorage(FixNowManager.fixNowEnabledKey) private var fixNowEnabled = true
    @AppStorage(FixNowManager.fixNowTapKeyCodeKey) private var fixNowTapKeyCode = 54
    @AppStorage(FixNowManager.fixNowWindowKey) private var fixNowWindow = 800

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Copilot")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                    Text("Gợi ý phần tiếp theo ngay trong ô đang gõ. Sử dụng mô hình Ollama chạy trực tiếp trên máy.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.bottom, 4)

                // Toggle Kích hoạt AI
                VStack(spacing: 0) {
                    SettingToggleRow(
                        title: "Bật gợi ý AI",
                        description: "Bộ gõ tiếng Việt vẫn hoạt động bình thường khi AI tắt hoặc Ollama chưa kết nối.",
                        isOn: $config.isEnabled
                    )
                }
                .flatCard()

                // Kiểu hiển thị & Độ dài
                VStack(alignment: .leading, spacing: 6) {
                    SettingSectionHeader(title: "Hiển thị & Độ dài")

                    VStack(spacing: 0) {
                        SettingRow(
                            title: "Kiểu hiển thị",
                            description: "Chữ mờ tự nhiên tại vị trí con trỏ hoặc thẻ nổi kèm phím Tab"
                        ) {
                            Picker("", selection: $displayMode) {
                                Text("Inline (Chữ mờ)").tag("inline")
                                Text("Pill (Thẻ nổi)").tag("pill")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 210)
                        }

                        Divider().overlay(Theme.divider).padding(.leading, 14)

                        SettingRow(
                            title: "Độ dài gợi ý",
                            description: "Ngắn (1–3 từ) · Vừa (4–6 từ) · Dài (7–10 từ)"
                        ) {
                            Picker("", selection: $completionLength) {
                                Text("Ngắn").tag("short")
                                Text("Vừa").tag("medium")
                                Text("Dài").tag("long")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 175)
                        }

                        Divider().overlay(Theme.divider).padding(.leading, 14)

                        SettingToggleRow(
                            title: "Ngữ cảnh Clipboard",
                            description: "Sử dụng liên kết, tên hoặc văn bản ngắn vừa sao chép để tăng độ chính xác khi gợi ý.",
                            isOn: $clipboardContextEnabled
                        )
                    }
                    .flatCard()
                }

                // Trạng thái kết nối Ollama
                VStack(alignment: .leading, spacing: 6) {
                    SettingSectionHeader(title: "Dịch vụ AI Nội bộ")

                    VStack(spacing: 0) {
                        SettingRow(
                            title: ollama.isReachable ? "Ollama đang hoạt động" : "Chưa kết nối Ollama",
                            description: ollama.isReachable ? "Kết nối cục bộ: localhost:11434" : "Cài đặt Ollama và mở daemon trên máy để sử dụng tính năng gợi ý."
                        ) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(ollama.isReachable ? Theme.success : Theme.warning)
                                    .frame(width: 8, height: 8)

                                Button("Làm mới") {
                                    Task { await ollama.refresh() }
                                }
                                .buttonStyle(.bordered)
                                .tint(Theme.accent)
                            }
                        }

                        if let error = ollama.errorMessage {
                            Divider().overlay(Theme.divider).padding(.leading, 14)
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.warning)
                                Text(error)
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.warning)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                    }
                    .flatCard()
                }

                // Danh sách Model
                VStack(alignment: .leading, spacing: 6) {
                    SettingSectionHeader(title: "Mô hình Autocomplete")

                    VStack(spacing: 10) {
                        ForEach(ollama.recommendations) { recommendation in
                            modelRecommendationRow(recommendation)
                        }
                    }

                    if !ollama.selectableModels.isEmpty {
                        Text("MÔ HÌNH ĐÃ CÀI")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                            .padding(.top, 8)
                            .padding(.leading, 4)

                        VStack(spacing: 0) {
                            ForEach(Array(ollama.selectableModels.enumerated()), id: \.element.id) { index, model in
                                if index > 0 {
                                    Divider().overlay(Theme.divider).padding(.leading, 14)
                                }
                                installedModelRow(model)
                            }
                        }
                        .flatCard()
                    }

                    if ollama.models.contains(where: { !$0.isGenerative }) {
                        Text("Lưu ý: Mô hình embedding chỉ dùng cho tìm kiếm, không thể dùng cho autocomplete.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                            .padding(.leading, 4)
                            .padding(.top, 2)
                    }
                }

                // Phím tắt AI
                VStack(alignment: .leading, spacing: 6) {
                    SettingSectionHeader(title: "Phím tắt AI")

                    VStack(spacing: 0) {
                        ShortcutRecorderRow(
                            shortcut: $acceptShortcut,
                            isRecording: $recordingAccept,
                            title: "Nhận gợi ý",
                            subtitle: "Chỉ chiếm phím khi có câu gợi ý hợp lệ (mặc định Tab)"
                        )

                        Divider().overlay(Theme.divider).padding(.leading, 14)

                        ShortcutRecorderRow(
                            shortcut: $toggleShortcut,
                            isRecording: $recordingToggle,
                            title: "Bật / tắt AI Copilot",
                            subtitle: "Phím tắt chuyển nhanh trạng thái hoạt động của AI"
                        )
                    }
                    .flatCard()
                }

                // FixNow: sửa THEO câu tại chỗ
                VStack(alignment: .leading, spacing: 6) {
                    SettingSectionHeader(title: "FixNow")

                    VStack(spacing: 0) {
                        SettingToggleRow(
                            title: "Bật FixNow",
                            description: "Double-tap phím để sửa chính tả, ngữ pháp, dấu câu ngay trong ô đang gõ, giữ nguyên giọng văn.",
                            isOn: $fixNowEnabled
                        )

                        Divider().overlay(Theme.divider).padding(.leading, 14)

                        SettingRow(
                            title: "Phím double-tap",
                            description: "Nhấn hai lần liên tiếp phím này để sửa các câu gần nhất trước con trỏ"
                        ) {
                            Picker("", selection: $fixNowTapKeyCode) {
                                ForEach(FixNowManager.tapKeyOptions, id: \.keyCode) { option in
                                    Text(verbatim: option.label).tag(Int(option.keyCode))
                                }
                            }
                            .labelsHidden()
                            .frame(width: 175)
                        }

                        Divider().overlay(Theme.divider).padding(.leading, 14)

                        SettingRow(
                            title: "Phạm vi câu",
                            description: "Số ký tự tối đa trước con trỏ được lấy để sửa. Ngắn sửa nhanh hơn."
                        ) {
                            Picker("", selection: $fixNowWindow) {
                                Text("Ngắn (500)").tag(500)
                                Text("Vừa (800)").tag(800)
                                Text("Dài (2000)").tag(2000)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 210)
                        }

                        Divider().overlay(Theme.divider).padding(.leading, 14)

                        SettingRow(
                            title: "Trạng thái gần nhất",
                            description: FixNowManager.shared.lastStatus
                        ) {
                            EmptyView()
                        }
                    }
                    .flatCard()
                }

                // Quyền riêng tư & Bảo mật
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Quyền riêng tư & Bảo mật")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)
                            Text("AI chỉ đọc ngữ cảnh ký tự xung quanh con trỏ thông qua Accessibility API trên máy của bạn. Toàn bộ quá trình diễn ra offline với Ollama. Các trường nhập mật khẩu và secure input tự động được bỏ qua hoàn toàn.")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                                .lineSpacing(2)
                        }
                    }
                    .padding(14)
                }
                .flatCard()

                Spacer(minLength: 10)
            }
            .padding(26)
        }
        .background(Theme.contentBackground)
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

    // MARK: - Row Builders

    private func modelRecommendationRow(_ recommendation: OllamaModelRecommendation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(recommendation.model)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)

                    if config.model == recommendation.model {
                        Text("Đang chọn")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Theme.accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                Text(recommendation.title)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textPrimary)

                Text(recommendation.description)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)

                Text(recommendation.memoryRequirement)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.top, 1)
            }

            Spacer()

            if ollama.downloadingModel == recommendation.model {
                VStack(spacing: 6) {
                    if let progress = ollama.downloadProgress {
                        ProgressView(value: progress).frame(width: 90)
                    } else {
                        ProgressView().frame(width: 90)
                    }
                    Button("Hủy") { ollama.cancelPull() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.error)
                }
            } else if ollama.hasModel(recommendation.model) {
                Button(config.model == recommendation.model ? "Đang dùng" : "Chọn") {
                    config.model = recommendation.model
                    saveConfig()
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
                .disabled(config.model == recommendation.model)
            } else {
                Button("Tải model") {
                    ollama.pull(model: recommendation.model)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .foregroundColor(Theme.textOnAccent)
                .disabled(!ollama.isReachable || ollama.downloadingModel != nil)
            }
        }
        .padding(14)
        .flatCard()
    }

    private func installedModelRow(_ model: OllamaModelInfo) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textPrimary)

                Text(model.sizeDescription)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            Button(config.model == model.name ? "Đang dùng" : "Chọn") {
                config.model = model.name
                saveConfig()
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .disabled(config.model == model.name)

            Button(role: .destructive) {
                modelToDelete = model
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
            .buttonStyle(.borderless)
            .help("Xóa model này khỏi Ollama")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

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
