import AppKit
import SwiftUI

// MARK: - Apps Settings View

struct AppsSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var showAddApp = false
    @State private var showAutoCapitalizeSheet = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ứng dụng")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                    Text("Tùy biến hành vi gõ và độ tương thích cho từng phần mềm trên macOS.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.bottom, 4)

                // Chế độ tổng thể theo ứng dụng
                VStack(alignment: .leading, spacing: 6) {
                    SettingSectionHeader(title: "Chế độ ứng dụng")

                    VStack(spacing: 0) {
                        SettingToggleRow(
                            title: "Nhớ trạng thái theo app",
                            description: "Tự động ghi nhớ và chuyển đổi chế độ gõ tiếng Việt / tiếng Anh riêng cho từng cửa sổ đang mở.",
                            isOn: $appState.perAppModeEnabled
                        )

                        Divider().overlay(Theme.divider).padding(.leading, 14)

                        SettingToggleRow(
                            title: "Tắt phát hiện Spotlight / Raycast",
                            description: "Bỏ qua các panel tìm kiếm nổi để giảm sử dụng CPU và tối ưu hóa bộ nhớ RAM.",
                            isOn: $appState.disablePanelDetection
                        )

                        Divider().overlay(Theme.divider).padding(.leading, 14)

                        SettingToggleRow(
                            title: "Chế độ Remote Desktop",
                            description: "Bắt synthetic events ở session level khi gõ qua AnyDesk, RustDesk, TeamViewer.",
                            isOn: $appState.sessionTapMode
                        )
                    }
                    .flatCard()
                }

                // Loại trừ viết hoa đầu câu
                VStack(alignment: .leading, spacing: 6) {
                    SettingSectionHeader(title: "Viết hoa đầu câu")

                    VStack(spacing: 0) {
                        SettingRow(
                            title: "Danh sách ứng dụng loại trừ",
                            description: appState.autoCapitalizeExcludedApps.isEmpty
                                ? "Chưa có ứng dụng nào bị loại trừ khỏi tính năng tự viết hoa"
                                : "\(appState.autoCapitalizeExcludedApps.count) ứng dụng đang được loại trừ"
                        ) {
                            Button("Quản lý...") {
                                showAutoCapitalizeSheet = true
                            }
                            .buttonStyle(.bordered)
                            .tint(Theme.accent)
                        }
                    }
                    .flatCard()
                }

                // Cấu hình chi tiết từng ứng dụng
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        SettingSectionHeader(title: "Tùy chỉnh riêng cho từng phần mềm")
                        Spacer()
                        Button(action: { showAddApp = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                Text("Thêm ứng dụng")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(spacing: 0) {
                        if sortedProfiles.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "slider.horizontal.2.square")
                                    .font(.system(size: 28))
                                    .foregroundColor(Theme.textSecondary)
                                Text("Chưa có cấu hình riêng nào")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Theme.textPrimary)
                                Text("Nhấn \"Thêm ứng dụng\" ở góc phải để chỉnh độ trễ hoặc chế độ inject cho app bị lỗi.")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .padding(.horizontal, 16)
                        } else {
                            ForEach(Array(sortedProfiles.enumerated()), id: \.element.key) { index, entry in
                                if index > 0 {
                                    Divider().overlay(Theme.divider).padding(.leading, 14)
                                }
                                PerAppProfileRow(
                                    bundleId: entry.key,
                                    config: entry.value,
                                    onChange: { appState.perAppProfiles[entry.key] = $0 },
                                    onRemove: { appState.perAppProfiles.removeValue(forKey: entry.key) }
                                )
                            }
                        }
                    }
                    .flatCard()
                }

                Spacer(minLength: 10)
            }
            .padding(26)
        }
        .background(Theme.contentBackground)
        .sheet(isPresented: $showAddApp) {
            AppPickerSheet(existingBundleIds: Set(appState.perAppProfiles.keys)) { bundleId in
                appState.perAppProfiles[bundleId] = PerAppConfig.fromDetected(bundleId: bundleId)
            }
        }
        .sheet(isPresented: $showAutoCapitalizeSheet) {
            AutoCapitalizeExcludedAppsSheet(appState: appState)
        }
    }

    private var sortedProfiles: [(key: String, value: PerAppConfig)] {
        appState.perAppProfiles.sorted { $0.key < $1.key }
    }
}

// Backward compatibility alias
typealias AdvancedSettingsView = AppsSettingsView

// MARK: - Per-App Profile Row

struct PerAppProfileRow: View {
    let bundleId: String
    let config: PerAppConfig
    let onChange: (PerAppConfig) -> Void
    let onRemove: () -> Void
    @State private var removeHovered = false
    @State private var resetHovered = false

    private let labelWidth: CGFloat = 48
    private let labelFont = Font.system(size: 10)

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack(spacing: 8) {
                AppIconView(bundleId: bundleId)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(appName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                        if let hint = detectedHint {
                            Text(hint)
                                .font(.system(size: 9))
                                .foregroundColor(Theme.textSecondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Theme.textSecondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text(bundleId)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button(action: { onChange(PerAppConfig.fromDetected(bundleId: bundleId)) }) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(resetHovered ? Theme.accent : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .onHover { resetHovered = $0 }
                .help("Khôi phục mặc định")

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(removeHovered ? Theme.error : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .onHover { removeHovered = $0 }
                .help("Xóa khỏi danh sách tùy biến")
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            // Delay slider
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Độ trễ")
                        .font(labelFont)
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: labelWidth, alignment: .leading)
                    Slider(value: delaySliderBinding, in: 0 ... Double(DelayPreset.allCases.count - 1), step: 1)
                        .tint(Theme.accent)
                    Text(delayPresetName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(delayPresetColor)
                        .frame(width: 52, alignment: .trailing)
                }
                Text("Tăng độ trễ nếu ứng dụng phản hồi chậm hoặc bị nuốt ký tự")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.leading, labelWidth + 6)
            }
            .padding(.horizontal, 14)

            // Trạng thái bộ gõ & Kiểu inject
            HStack(spacing: 12) {
                profilePicker("Bộ gõ", selection: enabledBinding, width: 85) {
                    Text("Tự động").tag(0)
                    Text("Bật").tag(1)
                    Text("Tắt").tag(-1)
                }
                profilePicker("Kiểu Inject", selection: injectionBinding, width: 110) {
                    ForEach(InjectionOverride.allCases, id: \.rawValue) { Text($0.name).tag($0.rawValue) }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    private func profilePicker(_ label: String, selection: Binding<some Hashable>, width: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(labelFont)
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
            Picker("", selection: selection, content: content)
                .labelsHidden()
                .frame(width: width)
        }
    }

    // MARK: - Bindings & Helpers

    private var enabledBinding: Binding<Int> {
        Binding(
            get: { config.enabledState },
            set: { v in var c = config; c.enabledState = v; onChange(c) }
        )
    }

    private var injectionBinding: Binding<Int> {
        Binding(
            get: { config.injectionOverride },
            set: { v in var c = config; c.injectionOverride = v; onChange(c) }
        )
    }

    private var delaySliderBinding: Binding<Double> {
        Binding(
            get: { Double(config.delayPreset) },
            set: { val in var c = config; c.delayPreset = Int(val.rounded()); onChange(c) }
        )
    }

    private var delayPresetName: String {
        (DelayPreset(rawValue: config.delayPreset) ?? .none).name
    }

    private var delayPresetColor: Color {
        (DelayPreset(rawValue: config.delayPreset) ?? .none).color
    }

    private var detectedHint: String? {
        getDetectedDefault(for: bundleId)?.method
    }

    private var appName: String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleId })?
            .localizedName ?? bundleId.components(separatedBy: ".").last ?? bundleId
    }
}
