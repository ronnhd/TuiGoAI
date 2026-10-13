import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Sound Manager

class SoundManager {
    static let shared = SoundManager()

    private let enableSound: NSSound?
    private let disableSound: NSSound?
    private var currentSound: NSSound?

    private init() {
        enableSound = NSSound(named: NSSound.Name("Tink"))
        disableSound = NSSound(named: NSSound.Name("Pop"))
    }

    func playToggleSound(enabled: Bool) {
        guard AppState.shared.soundEnabled else { return }
        currentSound?.stop()
        let sound = enabled ? enableSound : disableSound
        currentSound = sound
        sound?.play()
    }
}

// MARK: - Navigation Pages

enum NavigationPage: String, CaseIterable {
    case overview = "Tổng quan"
    case typing = "Bộ gõ"
    case ai = "AI Copilot"
    case apps = "Ứng dụng"
    case about = "Giới thiệu"

    var icon: String {
        switch self {
        case .overview: "slider.horizontal.3"
        case .typing: "keyboard"
        case .ai: "wand.and.stars"
        case .apps: "macwindow"
        case .about: "info.circle"
        }
    }
}

// MARK: - App State

class AppState: ObservableObject {
    static let shared = AppState()

    private var isSilentUpdate = false
    private var cancellables = Set<AnyCancellable>()

    @Published var isEnabled: Bool {
        didSet {
            RustBridge.setEnabled(isEnabled)
            guard !isSilentUpdate else { return }

            if perAppModeEnabled {
                if let bundleId = PerAppModeManager.shared.getCurrentBundleId() {
                    savePerAppMode(bundleId: bundleId, enabled: isEnabled)
                } else if let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
                    savePerAppMode(bundleId: bundleId, enabled: isEnabled)
                }
            } else {
                UserDefaults.standard.set(isEnabled, forKey: SettingsKey.enabled)
            }
        }
    }

    @Published private(set) var isSecureInputBlocked = false
    @Published private(set) var secureInputHolderName: String?

    var shouldShowSecureInputWarning: Bool {
        SecureInputPresentation.shouldShow(
            engineEnabled: isEnabled,
            inputSourceAllowed: InputSourceObserver.shared.isAllowedInputSource,
            secureInputBlocked: isSecureInputBlocked
        )
    }

    func setSecureInputBlocked(_ blocked: Bool, holderName: String? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.setSecureInputBlocked(blocked, holderName: holderName) }
            return
        }
        secureInputHolderName = blocked ? holderName : nil
        guard isSecureInputBlocked != blocked else { return }
        isSecureInputBlocked = blocked
    }

    @Published var currentMethod: InputMode {
        didSet {
            RustBridge.setMethod(currentMethod.rawValue)
            guard !isSilentUpdate else { return }
            UserDefaults.standard.set(currentMethod.rawValue, forKey: SettingsKey.method)
        }
    }

    @Published var perAppModeEnabled: Bool = true {
        didSet { UserDefaults.standard.set(perAppModeEnabled, forKey: SettingsKey.perAppMode) }
    }

    @Published var autoWShortcut: Bool = true {
        didSet {
            UserDefaults.standard.set(autoWShortcut, forKey: SettingsKey.autoWShortcut)
            RustBridge.setSkipWShortcut(!autoWShortcut)
        }
    }

    @Published var bracketShortcut: Bool = false {
        didSet {
            UserDefaults.standard.set(bracketShortcut, forKey: SettingsKey.bracketShortcut)
            RustBridge.setBracketShortcut(bracketShortcut)
        }
    }

    @Published var restoreShortcutEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(restoreShortcutEnabled, forKey: SettingsKey.restoreShortcutEnabled)
            RustBridge.setRestoreShortcutEnabled(restoreShortcutEnabled)
        }
    }

    @Published var modernTone: Bool = true {
        didSet {
            UserDefaults.standard.set(modernTone, forKey: SettingsKey.modernTone)
            RustBridge.setModernTone(modernTone)
        }
    }

    @Published var englishAutoRestore: Bool = false {
        didSet {
            UserDefaults.standard.set(englishAutoRestore, forKey: SettingsKey.englishAutoRestore)
            RustBridge.setEnglishAutoRestore(englishAutoRestore)
        }
    }

    @Published var autoCapitalize: Bool = false {
        didSet {
            UserDefaults.standard.set(autoCapitalize, forKey: SettingsKey.autoCapitalize)
            updateAutoCapitalizeEngine()
        }
    }

    @Published var autoCapitalizeExcludedApps: Set<String> = [] {
        didSet {
            let array = Array(autoCapitalizeExcludedApps)
            UserDefaults.standard.set(array, forKey: SettingsKey.autoCapitalizeExcludedApps)
            updateAutoCapitalizeEngine()
        }
    }

    @Published var soundEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(soundEnabled, forKey: SettingsKey.soundEnabled)
        }
    }

    @Published var allowForeignConsonants: Bool = false {
        didSet {
            UserDefaults.standard.set(allowForeignConsonants, forKey: SettingsKey.allowForeignConsonants)
            RustBridge.setAllowForeignConsonants(allowForeignConsonants)
        }
    }

    @Published var toggleShortcut: KeyboardShortcut {
        didSet {
            toggleShortcut.save()
            NotificationCenter.default.post(name: .shortcutChanged, object: toggleShortcut)
        }
    }

    @Published var restoreShortcut: KeyboardShortcut {
        didSet {
            restoreShortcut.saveAsRestoreShortcut()
            NotificationCenter.default.post(name: .restoreShortcutChanged, object: restoreShortcut)
        }
    }

    @Published var secondaryToggleShortcut: KeyboardShortcut {
        didSet {
            secondaryToggleShortcut.saveAsSecondaryToggle()
            NotificationCenter.default.post(name: .secondaryShortcutChanged, object: nil)
        }
    }

    @Published var secondaryToggleShortcutEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(secondaryToggleShortcutEnabled, forKey: SettingsKey.secondaryToggleShortcutEnabled)
            NotificationCenter.default.post(name: .secondaryShortcutChanged, object: nil)
        }
    }

    @Published var advancedMode: Bool = true {
        didSet {
            UserDefaults.standard.set(advancedMode, forKey: SettingsKey.advancedMode)
        }
    }

    @Published var disablePanelDetection: Bool = false {
        didSet {
            UserDefaults.standard.set(disablePanelDetection, forKey: SettingsKey.disablePanelDetection)
        }
    }

    @Published var restartOnClose: Bool = false {
        didSet {
            UserDefaults.standard.set(restartOnClose, forKey: SettingsKey.restartOnClose)
        }
    }

    @Published var sessionTapMode: Bool = false {
        didSet {
            UserDefaults.standard.set(sessionTapMode, forKey: SettingsKey.sessionTapMode)
            guard !isSilentUpdate else { return }
            KeyboardHookManager.shared.restart()
        }
    }

    @Published var perAppProfiles: [String: PerAppConfig] = [:] {
        didSet {
            if let data = try? JSONEncoder().encode(perAppProfiles) {
                UserDefaults.standard.set(data, forKey: SettingsKey.perAppProfiles)
            }
            clearDetectionCache()
        }
    }

    @Published var shortcuts: [ShortcutItem] = []
    @Published var isLaunchAtLoginEnabled: Bool = false
    @Published var requiresManualLaunchAtLogin: Bool = false

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: SettingsKey.enabled)
        currentMethod = InputMode(rawValue: defaults.integer(forKey: SettingsKey.method)) ?? .telex
        toggleShortcut = KeyboardShortcut.load()
        restoreShortcut = KeyboardShortcut.loadRestoreShortcut()
        secondaryToggleShortcut = KeyboardShortcut.loadSecondaryToggle()
        secondaryToggleShortcutEnabled = defaults.bool(forKey: SettingsKey.secondaryToggleShortcutEnabled)
        perAppModeEnabled = defaults.bool(forKey: SettingsKey.perAppMode)
        autoWShortcut = defaults.bool(forKey: SettingsKey.autoWShortcut)
        bracketShortcut = defaults.bool(forKey: SettingsKey.bracketShortcut)
        restoreShortcutEnabled = defaults.bool(forKey: SettingsKey.restoreShortcutEnabled)
        modernTone = defaults.bool(forKey: SettingsKey.modernTone)
        englishAutoRestore = defaults.bool(forKey: SettingsKey.englishAutoRestore)
        autoCapitalize = defaults.bool(forKey: SettingsKey.autoCapitalize)
        if let excludedApps = defaults.stringArray(forKey: SettingsKey.autoCapitalizeExcludedApps) {
            autoCapitalizeExcludedApps = Set(excludedApps)
        }
        soundEnabled = defaults.bool(forKey: SettingsKey.soundEnabled)
        allowForeignConsonants = defaults.bool(forKey: SettingsKey.allowForeignConsonants)
        advancedMode = true
        disablePanelDetection = defaults.bool(forKey: SettingsKey.disablePanelDetection)
        restartOnClose = defaults.bool(forKey: SettingsKey.restartOnClose)
        isSilentUpdate = true
        sessionTapMode = defaults.bool(forKey: SettingsKey.sessionTapMode)
        isSilentUpdate = false
        if let data = defaults.data(forKey: SettingsKey.perAppProfiles),
           let profiles = try? JSONDecoder().decode([String: PerAppConfig].self, from: data)
        {
            perAppProfiles = profiles
        }

        syncAllToEngine()
        loadShortcuts()
        setupObservers()
        setupLaunchAtLoginMonitoring()
    }

    private func syncAllToEngine() {
        RustBridge.setEnabled(isEnabled)
        RustBridge.setMethod(currentMethod.rawValue)
        RustBridge.setSkipWShortcut(!autoWShortcut)
        RustBridge.setBracketShortcut(bracketShortcut)
        RustBridge.setRestoreShortcutEnabled(restoreShortcutEnabled)
        RustBridge.setModernTone(modernTone)
        RustBridge.setEnglishAutoRestore(englishAutoRestore)
        updateAutoCapitalizeEngine()
        RustBridge.setAllowForeignConsonants(allowForeignConsonants)
    }

    func updateAutoCapitalizeEngine() {
        let currentBundleId = PerAppModeManager.shared.getCurrentBundleId()
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let isExcluded = currentBundleId.map { autoCapitalizeExcludedApps.contains($0) } ?? false
        RustBridge.setAutoCapitalize(autoCapitalize && !isExcluded)
    }

    func isAppExcludedFromAutoCapitalize(_ bundleId: String) -> Bool {
        autoCapitalizeExcludedApps.contains(bundleId)
    }

    func excludeAppFromAutoCapitalize(_ bundleId: String) {
        autoCapitalizeExcludedApps.insert(bundleId)
    }

    func includeAppInAutoCapitalize(_ bundleId: String) {
        autoCapitalizeExcludedApps.remove(bundleId)
    }

    private var profileSavedEnabled: Bool?

    func applyPerAppProfile(bundleId: String) {
        guard let profile = perAppProfiles[bundleId] else {
            restoreProfileDefaults()
            return
        }

        guard profile.enabledState != 0 else {
            restoreProfileDefaults()
            return
        }

        if profile.enabledState == -1 {
            if profileSavedEnabled == nil {
                profileSavedEnabled = isEnabled
            }
            RustBridge.setEnabled(false)
            setEnabledSilently(false)
            return
        }

        if profile.enabledState == 1 {
            if profileSavedEnabled == nil {
                profileSavedEnabled = isEnabled
            }
            RustBridge.setEnabled(true)
            setEnabledSilently(true)
        }
    }

    private func restoreProfileDefaults() {
        if profileSavedEnabled != nil {
            profileSavedEnabled = nil
            let ground = UserDefaults.standard.bool(forKey: SettingsKey.enabled)
            RustBridge.setEnabled(ground)
            setEnabledSilently(ground)
        }
    }

    private func loadShortcuts() {
        if let data = UserDefaults.standard.data(forKey: SettingsKey.shortcuts),
           let saved = try? JSONDecoder().decode([ShortcutItem].self, from: data)
        {
            shortcuts = saved
        } else {
            shortcuts = [
                ShortcutItem(key: "vn", value: "Việt Nam", isEnabled: false),
                ShortcutItem(key: "hn", value: "Hà Nội", isEnabled: false),
                ShortcutItem(key: "hcm", value: "Hồ Chí Minh", isEnabled: false),
                ShortcutItem(key: "tphcm", value: "Thành phố Hồ Chí Minh", isEnabled: false),
            ]
        }
    }

    private func setupObservers() {
        NotificationCenter.default.publisher(for: .inputSourceChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $shortcuts
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] shortcuts in
                let validShortcuts = shortcuts.filter { !$0.key.isEmpty && !$0.value.isEmpty }
                self?.syncShortcutsToEngine(validShortcuts)
                if let data = try? JSONEncoder().encode(shortcuts) {
                    UserDefaults.standard.set(data, forKey: SettingsKey.shortcuts)
                }
            }
            .store(in: &cancellables)
    }

    private func setupLaunchAtLoginMonitoring() {
        isLaunchAtLoginEnabled = LaunchAtLoginManager.shared.isEnabled
        let userDisabled = UserDefaults.standard.bool(forKey: SettingsKey.launchAtLoginUserDisabled)
        if !userDisabled, !isLaunchAtLoginEnabled {
            autoEnableLaunchAtLogin()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshLaunchAtLoginStatus()
        }
    }

    private func autoEnableLaunchAtLogin() {
        do {
            try LaunchAtLoginManager.shared.enable()
            refreshLaunchAtLoginStatus()
            requiresManualLaunchAtLogin = false
        } catch {
            requiresManualLaunchAtLogin = true
        }
    }

    func refreshLaunchAtLoginStatus() {
        let newStatus = LaunchAtLoginManager.shared.isEnabled
        if newStatus != isLaunchAtLoginEnabled {
            isLaunchAtLoginEnabled = newStatus
        }
        if isLaunchAtLoginEnabled {
            requiresManualLaunchAtLogin = false
        }
    }

    func enableLaunchAtLogin() {
        do {
            try LaunchAtLoginManager.shared.enable()
            refreshLaunchAtLoginStatus()
            requiresManualLaunchAtLogin = false
            UserDefaults.standard.set(false, forKey: SettingsKey.launchAtLoginUserDisabled)
        } catch {
            requiresManualLaunchAtLogin = true
            openLoginItemsSettings()
        }
    }

    func disableLaunchAtLogin() {
        do {
            try LaunchAtLoginManager.shared.disable()
            refreshLaunchAtLoginStatus()
            UserDefaults.standard.set(true, forKey: SettingsKey.launchAtLoginUserDisabled)
        } catch {
            openLoginItemsSettings()
        }
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        if enabled {
            enableLaunchAtLogin()
        } else {
            disableLaunchAtLogin()
        }
    }

    func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func savePerAppMode(bundleId: String, enabled: Bool) {
        var modes = UserDefaults.standard.dictionary(forKey: SettingsKey.perAppModes) as? [String: Bool] ?? [:]
        modes[bundleId] = enabled
        UserDefaults.standard.set(modes, forKey: SettingsKey.perAppModes)
    }

    func getPerAppMode(bundleId: String) -> Bool {
        let modes = UserDefaults.standard.dictionary(forKey: SettingsKey.perAppModes) as? [String: Bool] ?? [:]
        return modes[bundleId] ?? true
    }

    func hasPerAppMode(bundleId: String) -> Bool {
        let modes = UserDefaults.standard.dictionary(forKey: SettingsKey.perAppModes) as? [String: Bool] ?? [:]
        return modes[bundleId] != nil
    }

    func setEnabledSilently(_ enabled: Bool) {
        isSilentUpdate = true
        isEnabled = enabled
        isSilentUpdate = false
    }

    func toggle() {
        isEnabled.toggle()
    }

    func setMethod(_ method: InputMode) {
        currentMethod = method
    }

    func syncShortcutsToEngine(_ validShortcuts: [ShortcutItem]? = nil) {
        let toSync = validShortcuts ?? shortcuts.filter { !$0.key.isEmpty && !$0.value.isEmpty }
        RustBridge.syncShortcuts(toSync.map { ($0.key, $0.value, $0.isEnabled) })
    }

    func exportShortcuts() -> String {
        var lines = [";TuiGoAI - Bảng gõ tắt"]
        for shortcut in shortcuts where !shortcut.key.isEmpty {
            let escapedValue = shortcut.value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            lines.append("\(shortcut.key):\(escapedValue)")
        }
        return lines.joined(separator: "\n")
    }

    func importShortcuts(from content: String) -> Int {
        let lines = content.components(separatedBy: .newlines)
        var imported = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix(";"),
                  let colonIndex = trimmed.firstIndex(of: ":") else { continue }
            let trigger = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            guard !trigger.isEmpty else { continue }
            let replacement = Self.unescapeShortcutValue(rawValue)
            if let idx = shortcuts.firstIndex(where: { $0.key == trigger }) {
                shortcuts[idx].value = replacement
                shortcuts[idx].isEnabled = true
            } else {
                shortcuts.append(ShortcutItem(key: trigger, value: replacement, isEnabled: true))
            }
            imported += 1
        }
        return imported
    }

    private static func unescapeShortcutValue(_ value: String) -> String {
        var result = ""
        var chars = value.makeIterator()
        while let ch = chars.next() {
            if ch == "\\" {
                if let next = chars.next() {
                    switch next {
                    case "n": result.append("\n")
                    case "r": result.append("\r")
                    case "\\": result.append("\\")
                    default: result.append("\\"); result.append(next)
                    }
                } else {
                    result.append("\\")
                }
            } else {
                result.append(ch)
            }
        }
        return result
    }
}

// MARK: - Models

struct ShortcutItem: Identifiable, Codable {
    var id = UUID()
    var key: String
    var value: String
    var isEnabled: Bool = true
}

// MARK: - Main Settings View

struct MainSettingsView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var selectedPage: NavigationPage = .overview

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            ZStack {
                Theme.sidebar
                sidebar
            }
            .frame(width: 195)
            .overlay(
                Rectangle()
                    .fill(Theme.divider)
                    .frame(width: 0.8),
                alignment: .trailing
            )

            // Content
            ZStack {
                Theme.contentBackground
                content
            }
        }
        .ignoresSafeArea()
        .frame(width: 820, height: 690)
        .tint(Theme.accent)
        .onReceive(NotificationCenter.default.publisher(for: .showSettingsPage)) { notification in
            if let page = notification.object as? NavigationPage {
                selectedPage = page
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Brand header
            VStack(spacing: 10) {
                Image(nsImage: AppMetadata.logo)
                    .resizable()
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Theme.divider, lineWidth: 0.8)
                    )

                Text(AppMetadata.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Theme.textPrimary)

                UpdateBadgeView()
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            // Navigation tabs
            VStack(spacing: 3) {
                ForEach(NavigationPage.allCases, id: \.self) { page in
                    NavButton(page: page, isSelected: selectedPage == page) {
                        selectedPage = page
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()
        }
    }

    // MARK: - Content Router

    @ViewBuilder
    private var content: some View {
        switch selectedPage {
        case .overview:
            OverviewPageView(appState: appState)
        case .typing:
            TypingPageView(appState: appState)
        case .ai:
            AISettingsView()
        case .apps:
            AppsSettingsView(appState: appState)
        case .about:
            AboutPageView(appState: appState)
        }
    }
}

// MARK: - Nav Button

struct NavButton: View {
    let page: NavigationPage
    let isSelected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: page.icon)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? Theme.accent : Theme.textSecondary)
                .frame(width: 18)

            Text(page.rawValue)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Theme.card : (hovered ? Theme.rowHover : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Theme.divider : Color.clear, lineWidth: 0.8)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.accent)
                    .frame(width: 3, height: 16)
                    .padding(.leading, 3)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { action() }
    }
}

// MARK: - Update Badge View

struct UpdateBadgeView: View {
    @ObservedObject private var updateManager = UpdateManager.shared
    @State private var hovered = false
    @State private var rotation: Double = 0

    var body: some View {
        HStack(spacing: 4) {
            Text("v\(AppMetadata.version)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSecondary)

            if updateManager.isChecking {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textSecondary)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { rotation = 360 }
                    }
                    .onDisappear { rotation = 0 }
            } else if updateManager.isReadyToInstall {
                Image(systemName: "arrow.uturn.forward.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.warning)
            } else if updateManager.updateAvailable {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.accent)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.success)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(
            Capsule()
                .fill(Theme.card)
        )
        .overlay(
            Capsule()
                .stroke(Theme.divider, lineWidth: 0.8)
        )
        .onHover { h in hovered = h }
        .onTapGesture {
            if updateManager.isReadyToInstall {
                updateManager.restartToUpdate()
            } else {
                updateManager.checkForUpdatesManually()
            }
        }
    }
}

// MARK: - Tab 1: Overview Page View

struct OverviewPageView: View {
    @ObservedObject var appState: AppState
    @StateObject private var ollama = OllamaService.shared
    @State private var aiConfig = AIService.shared.loadConfig()
    @State private var isRecordingToggle = false
    @State private var isRecordingAIToggle = false
    @State private var isRecordingAccept = false
    @State private var aiToggleShortcut = OverviewPageView.loadAIToggleShortcut()
    @State private var aiAcceptShortcut = OverviewPageView.loadAIAcceptShortcut()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tổng quan")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                    Text("Xem nhanh trạng thái hoạt động và các phím tắt chính của TuiGoAI.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.bottom, 4)

                // Secure Input warning if blocked
                if appState.shouldShowSecureInputWarning {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bộ gõ đang tạm dừng")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)
                            Text(SecureInputPresentation.warningMessage(holderName: appState.secureInputHolderName))
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.warning.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.warning.opacity(0.35), lineWidth: 0.8)
                    )
                }

                // Trạng thái hoạt động
                VStack(alignment: .leading, spacing: 6) {
                    SettingSectionHeader(title: "Trạng thái hoạt động")

                    VStack(spacing: 0) {
                        SettingToggleRow(
                            title: "Bộ gõ tiếng Việt",
                            description: "Xử lý Telex/VNI bằng lõi Rust độc lập, độ trễ tiệm cận 0ms",
                            isOn: $appState.isEnabled
                        )

                        Divider().overlay(Theme.divider).padding(.leading, 14)

                        SettingRow(
                            title: "AI Copilot",
                            description: "Gợi ý hoàn thành câu trực tiếp tại vị trí con trỏ văn bản"
                        ) {
                            Toggle("", isOn: Binding(
                                get: { aiConfig.isEnabled },
                                set: { newValue in
                                    aiConfig.isEnabled = newValue
                                    AIService.shared.saveConfig(aiConfig)
                                    if !newValue { GhostTextManager.shared.dismiss() }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(Theme.accent)
                        }

                        Divider().overlay(Theme.divider).padding(.leading, 14)

                        SettingRow(
                            title: "Dịch vụ Ollama",
                            description: ollama.isReachable ? "localhost:11434 · Sẵn sàng sinh văn bản" : "Chưa kết nối Ollama trên máy"
                        ) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(ollama.isReachable ? Theme.success : Theme.warning)
                                    .frame(width: 8, height: 8)

                                Text(ollama.isReachable ? "Đang chạy" : "Chưa bật")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(ollama.isReachable ? Theme.success : Theme.warning)

                                Button("Làm mới") {
                                    Task { await ollama.refresh() }
                                }
                                .buttonStyle(.bordered)
                                .tint(Theme.accent)
                            }
                        }
                    }
                    .flatCard()
                }

                // Phím tắt chính
                VStack(alignment: .leading, spacing: 6) {
                    SettingSectionHeader(title: "Phím tắt chính")

                    VStack(spacing: 0) {
                        ShortcutRecorderRow(
                            shortcut: $appState.toggleShortcut,
                            isRecording: $isRecordingToggle,
                            title: "Bật / tắt bộ gõ",
                            subtitle: "Chuyển nhanh giữa chế độ gõ tiếng Việt và tiếng Anh"
                        )

                        Divider().overlay(Theme.divider).padding(.leading, 14)

                        ShortcutRecorderRow(
                            shortcut: $aiToggleShortcut,
                            isRecording: $isRecordingAIToggle,
                            title: "Bật / tắt AI Copilot",
                            subtitle: "Tạm ngưng hoặc kích hoạt lại gợi ý inline của AI"
                        )

                        Divider().overlay(Theme.divider).padding(.leading, 14)

                        ShortcutRecorderRow(
                            shortcut: $aiAcceptShortcut,
                            isRecording: $isRecordingAccept,
                            title: "Nhận gợi ý AI",
                            subtitle: "Chấp nhận và chèn câu gợi ý của AI vào văn bản (mặc định Tab)"
                        )
                    }
                    .flatCard()
                }

                // Hệ thống
                VStack(alignment: .leading, spacing: 6) {
                    SettingSectionHeader(title: "Hệ thống")

                    VStack(spacing: 0) {
                        SettingToggleRow(
                            title: "Khởi động cùng macOS",
                            description: "Tự động chạy TuiGoAI trong thanh menu khi mở máy",
                            isOn: Binding(
                                get: { appState.isLaunchAtLoginEnabled },
                                set: { appState.toggleLaunchAtLogin($0) }
                            )
                        )
                    }
                    .flatCard()
                }

                Spacer(minLength: 10)
            }
            .padding(26)
        }
        .background(Theme.contentBackground)
        .onAppear {
            aiConfig = AIService.shared.loadConfig()
            Task { await ollama.refresh() }
        }
        .onChange(of: aiToggleShortcut) { shortcut in
            if let data = try? JSONEncoder().encode(shortcut) {
                UserDefaults.standard.set(data, forKey: GhostTextManager.toggleShortcutKey)
            }
        }
        .onChange(of: aiAcceptShortcut) { shortcut in
            if let data = try? JSONEncoder().encode(shortcut) {
                UserDefaults.standard.set(data, forKey: GhostTextManager.acceptShortcutKey)
            }
        }
    }

    private static func loadAIToggleShortcut() -> KeyboardShortcut {
        guard let data = UserDefaults.standard.data(forKey: GhostTextManager.toggleShortcutKey),
              let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data)
        else {
            return KeyboardShortcut(keyCode: 0x31, modifiers: CGEventFlags.maskControl.union(.maskAlternate).rawValue)
        }
        return shortcut
    }

    private static func loadAIAcceptShortcut() -> KeyboardShortcut {
        guard let data = UserDefaults.standard.data(forKey: GhostTextManager.acceptShortcutKey),
              let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data)
        else {
            return KeyboardShortcut(keyCode: 0x30, modifiers: 0)
        }
        return shortcut
    }
}

// MARK: - Tab 2: Typing Page View

struct TypingPageView: View {
    @ObservedObject var appState: AppState
    @State private var isRecordingSecondary = false
    @State private var isRecordingRestore = false
    @State private var showShortcutsSheet = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bộ gõ")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                    Text("Cấu hình kiểu gõ, quy tắc xử lý dấu tiếng Việt và danh sách từ gõ tắt.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.bottom, 4)

                // Kiểu gõ & Phục hồi
                VStack(alignment: .leading, spacing: 6) {
                    SettingSectionHeader(title: "Kiểu gõ & Phục hồi")

                    VStack(spacing: 0) {
                        SettingRow(
                            title: "Kiểu gõ",
                            description: "Chọn phương thức bỏ dấu tiếng Việt tiêu chuẩn"
                        ) {
                            Picker("", selection: $appState.currentMethod) {
                                ForEach(InputMode.allCases, id: \.self) {
                                    Text($0.name).tag($0)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 100)
                        }

                        if appState.currentMethod == .telex {
                            Divider().overlay(Theme.divider).padding(.leading, 14)

                            SettingToggleRow(
                                title: "Gõ W thành Ư",
                                description: "Gõ phím w để tạo ký tự ư khi đứng riêng hoặc đầu từ",
                                indented: true,
                                isOn: $appState.autoWShortcut
                            )

                            Divider().overlay(Theme.divider).padding(.leading, 14)

                            SettingToggleRow(
                                title: "Gõ [ ] thành Ơ Ư",
                                description: "Dùng phím mở và đóng ngoặc vuông để gõ chữ ơ và ư",
                                indented: true,
                                isOn: $appState.bracketShortcut
                            )

                            Divider().overlay(Theme.divider).padding(.leading, 14)

                            SettingToggleRow(
                                title: "Tự khôi phục tiếng Anh",
                                description: "Tự động hoàn lại từ tiếng Anh khi nhấn Space mà không nuốt phím",
                                indented: true,
                                isOn: $appState.englishAutoRestore
                            )
                        }
                    }
                    .flatCard()
                }

                // Quy tắc chính tả
                VStack(alignment: .leading, spacing: 6) {
                    SettingSectionHeader(title: "Quy tắc chính tả")

                    VStack(spacing: 0) {
                        SettingToggleRow(
                            title: "Đặt dấu kiểu mới",
                            description: "Đặt dấu thanh ở âm chính mới: oà thay vì òa, uý thay vì úy",
                            isOn: $appState.modernTone
                        )

                        Divider().overlay(Theme.divider).padding(.leading, 14)

                        SettingToggleRow(
                            title: "Cho phép phụ âm ngoại",
                            description: "Chấp nhận các chữ cái z, w, j, f ở đầu từ mà không làm mất dấu",
                            isOn: $appState.allowForeignConsonants
                        )

                        Divider().overlay(Theme.divider).padding(.leading, 14)

                        SettingToggleRow(
                            title: "Tự viết hoa đầu câu",
                            description: "Tự động viết hoa chữ cái đầu tiên sau dấu chấm câu",
                            isOn: $appState.autoCapitalize
                        )
                    }
                    .flatCard()
                }

                // Phím tắt bổ trợ & Âm thanh
                VStack(alignment: .leading, spacing: 6) {
                    SettingSectionHeader(title: "Phím tắt bổ trợ & Âm thanh")

                    VStack(spacing: 0) {
                        ShortcutRecorderRow(
                            shortcut: $appState.secondaryToggleShortcut,
                            isRecording: $isRecordingSecondary,
                            title: "Phím tắt bật / tắt thứ hai",
                            subtitle: "Hữu ích khi dùng bàn phím ngoài không có phím fn",
                            isEnabled: $appState.secondaryToggleShortcutEnabled,
                            duplicateOf: appState.toggleShortcut
                        )

                        Divider().overlay(Theme.divider).padding(.leading, 14)

                        RestoreShortcutRecorderRow(
                            shortcut: $appState.restoreShortcut,
                            isEnabled: $appState.restoreShortcutEnabled,
                            isRecording: $isRecordingRestore
                        )

                        Divider().overlay(Theme.divider).padding(.leading, 14)

                        SettingToggleRow(
                            title: "Âm thanh khi bật / tắt",
                            description: "Phát âm thanh phản hồi nhẹ khi chuyển trạng thái bộ gõ",
                            isOn: $appState.soundEnabled
                        )
                    }
                    .flatCard()
                }

                // Bảng từ gõ tắt
                VStack(alignment: .leading, spacing: 6) {
                    SettingSectionHeader(title: "Từ gõ tắt")

                    VStack(spacing: 0) {
                        SettingRow(
                            title: "Bảng từ gõ tắt",
                            description: appState.shortcuts.isEmpty
                                ? "Chưa có từ viết tắt nào được thiết lập"
                                : "\(appState.shortcuts.filter(\.isEnabled).count) / \(appState.shortcuts.count) từ gõ tắt đang được kích hoạt"
                        ) {
                            Button("Quản lý bảng gõ tắt...") {
                                showShortcutsSheet = true
                            }
                            .buttonStyle(.bordered)
                            .tint(Theme.accent)
                        }
                    }
                    .flatCard()
                }

                Spacer(minLength: 10)
            }
            .padding(26)
        }
        .background(Theme.contentBackground)
        .sheet(isPresented: $showShortcutsSheet) {
            ShortcutsSheet(appState: appState)
        }
    }
}

// MARK: - Tab 5: About Page View

struct AboutPageView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var updateManager = UpdateManager.shared
    @State private var logEnabled = FileManager.default.fileExists(atPath: "/tmp/gonhanh_debug.log") || FileManager.default.fileExists(atPath: "/tmp/tuigoai_debug.log")

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Giới thiệu")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                    Text("Thông tin phiên bản, bản quyền và chẩn đoán hệ thống.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.bottom, 4)

                // Thẻ thông tin ứng dụng trung tâm
                VStack(spacing: 14) {
                    Image(nsImage: AppMetadata.logo)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(Theme.divider, lineWidth: 0.8)
                        )

                    VStack(spacing: 3) {
                        Text(AppMetadata.name)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Theme.textPrimary)

                        Text("Phiên bản v\(AppMetadata.version) (Build \(AppMetadata.buildNumber))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.textSecondary)

                        Text("Bộ gõ tiếng Việt hiện đại tích hợp AI Copilot cho macOS")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                            .padding(.top, 2)
                    }

                    // Links
                    HStack(spacing: 12) {
                        if let repoURL = URL(string: AppMetadata.repository) {
                            Link(destination: repoURL) {
                                Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .tint(Theme.accent)
                        }

                        if let issuesURL = URL(string: AppMetadata.issuesURL) {
                            Link(destination: issuesURL) {
                                Label("Báo lỗi", systemImage: "ant")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .tint(Theme.accent)
                        }

                        if let authorURL = URL(string: AppMetadata.authorLinkedin) {
                            Link(destination: authorURL) {
                                Label("Tác giả: Ron Ng", systemImage: "person")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .tint(Theme.accent)
                        }
                    }
                    .padding(.top, 4)

                    Divider().overlay(Theme.divider).padding(.horizontal, 20)

                    // Acknowledgments
                    VStack(spacing: 2) {
                        Text("Kế thừa nền tảng từ GoNhanh (Kha Phan, BSD-3-Clause)")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textSecondary)
                        Text("Thuật toán Autocomplete tham khảo từ KeyType (Xi Nai Lai, MIT License)")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textSecondary)
                        Text("Phát hành dưới giấy phép mã nguồn mở BSD-3-Clause")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .padding(.horizontal, 16)
                .flatCard()

                // Cập nhật ứng dụng
                VStack(alignment: .leading, spacing: 6) {
                    SettingSectionHeader(title: "Cập nhật ứng dụng")

                    VStack(spacing: 0) {
                        SettingRow(
                            title: "Kiểm tra phiên bản mới",
                            description: updateManager.updateAvailable
                                ? "Đã có bản cập nhật mới sẵn sàng tải về"
                                : "TuiGoAI tự động kiểm tra bản phát hành mới định kỳ"
                        ) {
                            Button(updateManager.isReadyToInstall ? "Khởi động lại để cập nhật" : "Kiểm tra ngay") {
                                if updateManager.isReadyToInstall {
                                    updateManager.restartToUpdate()
                                } else {
                                    updateManager.checkForUpdatesManually()
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(Theme.accent)
                        }
                    }
                    .flatCard()
                }

                // Chẩn đoán & Bộ nhớ
                VStack(alignment: .leading, spacing: 6) {
                    SettingSectionHeader(title: "Chẩn đoán & Hiệu năng")

                    VStack(spacing: 0) {
                        SettingRow(
                            title: "Ghi log chẩn đoán (Debug Log)",
                            description: "Ghi nhật ký chi tiết xử lý phím vào /tmp/tuigoai_debug.log"
                        ) {
                            LogToggleButton(isEnabled: $logEnabled)
                        }

                        Divider().overlay(Theme.divider).padding(.leading, 14)

                        SettingToggleRow(
                            title: "Khởi động lại khi đóng cài đặt",
                            description: "Tự động giải phóng RAM của cửa sổ cài đặt sau khi đóng",
                            isOn: $appState.restartOnClose
                        )

                        if logEnabled {
                            Divider().overlay(Theme.divider).padding(.leading, 14)
                            LogViewerSection()
                        }
                    }
                    .flatCard()
                }

                Spacer(minLength: 10)
            }
            .padding(26)
        }
        .background(Theme.contentBackground)
    }
}

// MARK: - Shortcuts Sheet

struct ShortcutsSheet: View {
    @ObservedObject var appState: AppState

    @State private var formKey: String = ""
    @State private var formValue: String = ""
    @State private var editingId: UUID? = nil
    @State private var selectedIds: Set<UUID> = []

    private var isEditing: Bool {
        editingId != nil
    }

    private var canSave: Bool {
        !formKey.isEmpty && !formValue.isEmpty
    }

    private var subtitle: String {
        let enabled = appState.shortcuts.filter(\.isEnabled).count
        let total = appState.shortcuts.count
        return "\(total) mục · \(enabled) đang bật"
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader("Bảng gõ tắt", subtitle: subtitle)
            Divider().overlay(Theme.divider)
            formSection
            Divider().overlay(Theme.divider)
            tableContent
            Divider().overlay(Theme.divider)
            SheetToolbar {
                Button(action: importShortcuts) {
                    Label("Nhập", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)

                Button(action: exportShortcuts) {
                    Label("Xuất", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
                .disabled(appState.shortcuts.isEmpty)
            }
        }
        .frame(width: 480, height: 420)
        .background(Theme.contentBackground)
    }

    private var formSection: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Viết tắt").font(.system(size: 11, weight: .medium)).foregroundColor(Theme.textSecondary)
                    TextField("vd: tphcm", text: $formKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("Nội dung").font(.system(size: 11, weight: .medium)).foregroundColor(Theme.textSecondary)
                        Text("(⌥↩ xuống dòng)").font(.system(size: 10)).foregroundColor(Theme.textSecondary)
                    }
                    TextEditor(text: $formValue)
                        .font(.system(size: 13))
                        .frame(height: 44)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.divider, lineWidth: 0.8))
                        .overlay(alignment: .topLeading) {
                            if formValue.isEmpty {
                                Text("vd: Thành phố Hồ Chí Minh")
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.textSecondary.opacity(0.6))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }

            HStack(spacing: 8) {
                if isEditing {
                    Button("Huỷ") { clearForm() }
                    Button("Xoá", role: .destructive) { deleteSelected() }
                        .foregroundColor(Theme.error)
                }
                Spacer()
                Button(isEditing ? "Cập nhật" : "Thêm") { saveForm() }
                    .disabled(!canSave)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .foregroundColor(Theme.textOnAccent)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.card.opacity(0.5))
    }

    @ViewBuilder
    private var tableContent: some View {
        if appState.shortcuts.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "text.badge.plus").font(.system(size: 32)).foregroundColor(Theme.textSecondary)
                Text("Chưa có từ viết tắt").font(.system(size: 13, weight: .medium)).foregroundColor(Theme.textPrimary)
                Text("Điền biểu mẫu ở trên để thêm từ mới").font(.system(size: 11)).foregroundColor(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(appState.shortcuts, selection: $selectedIds) {
                TableColumn("") { item in
                    Toggle("", isOn: Binding(
                        get: { item.isEnabled },
                        set: { newValue in
                            if let idx = appState.shortcuts.firstIndex(where: { $0.id == item.id }) {
                                appState.shortcuts[idx].isEnabled = newValue
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .tint(Theme.accent)
                    .labelsHidden()
                }
                .width(24)

                TableColumn("Viết tắt") { item in
                    Text(item.key)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(item.isEnabled ? Theme.textPrimary : Theme.textSecondary)
                }
                .width(min: 80, ideal: 100, max: 140)

                TableColumn("Nội dung") { item in
                    Text(item.value.contains("\n") ? item.value.replacingOccurrences(of: "\n", with: " ↵ ") : item.value)
                        .font(.system(size: 12))
                        .foregroundColor(item.isEnabled ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                }

                TableColumn("") { item in
                    DeleteButton { deleteItem(item.id) }
                }
                .width(28)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .onDeleteCommand { deleteSelected() }
            .onChange(of: selectedIds) { newSelection in
                if newSelection.count == 1, let id = newSelection.first,
                   let item = appState.shortcuts.first(where: { $0.id == id })
                {
                    selectItem(item)
                } else {
                    clearForm()
                }
            }
        }
    }

    private func selectItem(_ item: ShortcutItem) {
        editingId = item.id
        formKey = item.key
        formValue = item.value
    }

    private func clearForm() {
        editingId = nil
        formKey = ""
        formValue = ""
    }

    private func saveForm() {
        if let id = editingId, let idx = appState.shortcuts.firstIndex(where: { $0.id == id }) {
            appState.shortcuts[idx].key = formKey
            appState.shortcuts[idx].value = formValue
        } else {
            appState.shortcuts.append(ShortcutItem(key: formKey, value: formValue, isEnabled: true))
        }
        clearForm()
    }

    private func deleteSelected() {
        guard !selectedIds.isEmpty else { return }
        appState.shortcuts.removeAll { selectedIds.contains($0.id) }
        selectedIds.removeAll()
        clearForm()
    }

    private func deleteItem(_ id: UUID) {
        appState.shortcuts.removeAll { $0.id == id }
        if editingId == id {
            clearForm()
        }
        selectedIds.remove(id)
    }

    private func importShortcuts() {
        DispatchQueue.main.async { [weak appState] in
            let panel = NSOpenPanel()
            panel.title = "Nhập bảng gõ tắt"
            panel.allowedContentTypes = [.plainText]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
                    DispatchQueue.main.async {
                        _ = appState?.importShortcuts(from: content)
                    }
                }
            }
        }
    }

    private func exportShortcuts() {
        DispatchQueue.main.async { [weak appState] in
            let panel = NSSavePanel()
            panel.title = "Xuất bảng gõ tắt"
            panel.nameFieldStringValue = "tuigoai-shortcuts.txt"
            panel.allowedContentTypes = [.plainText]
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    let content = appState?.exportShortcuts() ?? ""
                    try? content.write(to: url, atomically: true, encoding: .utf8)
                }
            }
        }
    }
}

// MARK: - Shortcut Recorder Row

private let systemShortcuts: Set<String> = [
    "⌘Space", "⌘⇥", "⌘Q", "⌘W", "⌘H", "⌘M",
    "⌘⇧3", "⌘⇧4", "⌘⇧5",
    "⌃↑", "⌃↓", "⌃←", "⌃→",
]

struct ShortcutRecorderRow: View {
    @Binding var shortcut: KeyboardShortcut
    @Binding var isRecording: Bool
    var title = "Bật / tắt bộ gõ"
    var subtitle = "Nhấn để thu phím tắt mới"
    var isEnabled: Binding<Bool>?
    var duplicateOf: KeyboardShortcut?
    @State private var hovered = false
    @State private var recordedObserver: NSObjectProtocol?
    @State private var cancelledObserver: NSObjectProtocol?
    @State private var windowObserver: NSObjectProtocol?

    private var enabled: Bool { isEnabled?.wrappedValue ?? true }

    private var conflictMessage: String? {
        if let other = duplicateOf, other == shortcut {
            return "Trùng với phím tắt chính"
        }
        if systemShortcuts.contains(shortcut.displayParts.joined()) {
            return "Phím tắt có thể xung đột với macOS"
        }
        return nil
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            HStack(spacing: 8) {
                shortcutDisplay

                if let isEnabled {
                    Toggle("", isOn: isEnabled)
                        .toggleStyle(.switch)
                        .tint(Theme.accent)
                        .labelsHidden()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background((hovered || isRecording) ? Theme.rowHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovered = enabled && $0 }
        .onTapGesture {
            guard enabled else { return }
            isRecording ? stopRecording() : startRecording()
        }
        .onDisappear { stopRecording() }
        .onChange(of: enabled) { _ in
            if isRecording { stopRecording() }
        }
    }

    private var shortcutDisplay: some View {
        HStack(spacing: 4) {
            if isRecording {
                Text("Nhấn phím...")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Theme.accent, lineWidth: 1.2)
                    )
            } else {
                ForEach(shortcut.displayParts, id: \.self) {
                    FlatKeyCap(text: $0)
                }
                if let conflictMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.warning)
                        .help(conflictMessage)
                }
            }
        }
        .opacity(enabled ? 1.0 : 0.45)
    }

    private func startRecording() {
        isRecording = true
        recordedObserver = NotificationCenter.default.addObserver(forName: .shortcutRecorded, object: nil, queue: .main) { notification in
            if let captured = notification.object as? KeyboardShortcut {
                shortcut = captured
            }
            stopRecording()
        }
        cancelledObserver = NotificationCenter.default.addObserver(forName: .shortcutRecordingCancelled, object: nil, queue: .main) { _ in stopRecording() }
        windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { _ in stopRecording() }
        startShortcutRecording()
    }

    private func stopRecording() {
        stopShortcutRecording()
        [recordedObserver, cancelledObserver, windowObserver].compactMap { $0 }.forEach { NotificationCenter.default.removeObserver($0) }
        recordedObserver = nil
        cancelledObserver = nil
        windowObserver = nil
        isRecording = false
    }
}

// MARK: - Restore Shortcut Recorder Row

struct RestoreShortcutRecorderRow: View {
    @Binding var shortcut: KeyboardShortcut
    @Binding var isEnabled: Bool
    @Binding var isRecording: Bool
    @State private var hovered = false
    @State private var recordedObserver: NSObjectProtocol?
    @State private var cancelledObserver: NSObjectProtocol?
    @State private var windowObserver: NSObjectProtocol?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Hoàn tác dấu vừa gõ")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Text("Phục hồi chuỗi ký tự ban đầu khi gõ nhầm dấu (mặc định Esc)")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            HStack(spacing: 8) {
                shortcutDisplay

                Toggle("", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                    .labelsHidden()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background((hovered || isRecording) ? Theme.rowHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovered = isEnabled && $0 }
        .onTapGesture {
            guard isEnabled else { return }
            isRecording ? stopRecording() : startRecording()
        }
        .onDisappear { stopRecording() }
        .onChange(of: isEnabled) { _ in
            if isRecording { stopRecording() }
        }
    }

    private var shortcutDisplay: some View {
        HStack(spacing: 4) {
            if isRecording {
                Text("Nhấn phím...")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Theme.accent, lineWidth: 1.2)
                    )
            } else {
                ForEach(shortcut.displayParts, id: \.self) {
                    FlatKeyCap(text: $0)
                }
            }
        }
        .opacity(isEnabled ? 1.0 : 0.45)
    }

    private func startRecording() {
        isRecording = true
        recordedObserver = NotificationCenter.default.addObserver(forName: .shortcutRecorded, object: nil, queue: .main) { notification in
            if let captured = notification.object as? KeyboardShortcut {
                shortcut = captured
            }
            stopRecording()
        }
        cancelledObserver = NotificationCenter.default.addObserver(forName: .shortcutRecordingCancelled, object: nil, queue: .main) { _ in stopRecording() }
        windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { _ in stopRecording() }
        startRestoreShortcutRecording()
    }

    private func stopRecording() {
        stopShortcutRecording()
        [recordedObserver, cancelledObserver, windowObserver].compactMap { $0 }.forEach { NotificationCenter.default.removeObserver($0) }
        recordedObserver = nil
        cancelledObserver = nil
        windowObserver = nil
        isRecording = false
    }
}

// MARK: - Auto Capitalize Excluded Apps Sheet

struct AutoCapitalizeExcludedAppsSheet: View {
    @ObservedObject var appState: AppState
    @State private var allApps: [AppToggleItem] = []

    private var subtitle: String {
        let count = appState.autoCapitalizeExcludedApps.count
        return count == 0 ? "Chưa có ứng dụng nào" : "\(count) ứng dụng đang loại trừ"
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader("Loại trừ viết hoa đầu câu", subtitle: subtitle)
            Divider().overlay(Theme.divider)

            if allApps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "app.badge.checkmark")
                        .font(.system(size: 28))
                        .foregroundColor(Theme.textSecondary)
                    Text("Không tìm thấy ứng dụng đang mở")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(allApps, id: \.bundleId) { app in
                        AppToggleRow(
                            name: app.name,
                            icon: app.icon,
                            isExcluded: appState.autoCapitalizeExcludedApps.contains(app.bundleId)
                        ) { isExcluded in
                            if isExcluded {
                                appState.excludeAppFromAutoCapitalize(app.bundleId)
                            } else {
                                appState.includeAppInAutoCapitalize(app.bundleId)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider().overlay(Theme.divider)
            SheetToolbar()
        }
        .frame(width: 460, height: 400)
        .background(Theme.contentBackground)
        .onAppear { loadApps() }
    }

    private func loadApps() {
        let excluded = appState.autoCapitalizeExcludedApps

        var apps: [AppToggleItem] = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppToggleItem? in
                guard let bundleId = app.bundleIdentifier,
                      bundleId != Bundle.main.bundleIdentifier else { return nil }
                return AppToggleItem(
                    bundleId: bundleId,
                    name: app.localizedName ?? bundleId,
                    icon: app.icon
                )
            }

        for bundleId in excluded where !apps.contains(where: { $0.bundleId == bundleId }) {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
            let name = running?.localizedName ?? bundleId.components(separatedBy: ".").last ?? bundleId
            apps.append(AppToggleItem(bundleId: bundleId, name: name, icon: running?.icon))
        }

        allApps = apps.sorted { a, b in
            let aExcluded = excluded.contains(a.bundleId)
            let bExcluded = excluded.contains(b.bundleId)
            if aExcluded != bExcluded {
                return aExcluded
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

struct AppToggleItem {
    let bundleId: String
    let name: String
    let icon: NSImage?
}

struct AppToggleRow: View {
    let name: String
    let icon: NSImage?
    let isExcluded: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .frame(width: 26, height: 26)

            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)

            Spacer()

            Toggle("", isOn: Binding(
                get: { isExcluded },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .tint(Theme.accent)
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Sheet Common Components

struct SheetHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Theme.sidebar)
    }
}

struct SheetToolbar<Actions: View>: View {
    @Environment(\.dismiss) private var dismiss
    let actions: Actions?

    init(@ViewBuilder actions: () -> Actions) {
        self.actions = actions()
    }

    init() where Actions == EmptyView {
        actions = nil
    }

    var body: some View {
        HStack(spacing: 12) {
            if let actions {
                actions
            }
            Spacer()
            Button("Xong") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .foregroundColor(Theme.textOnAccent)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.sidebar)
    }
}

struct DeleteButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 11))
                .foregroundColor(hovered ? Theme.error : Theme.textSecondary)
        }
        .buttonStyle(.borderless)
        .onHover { hovered = $0 }
        .help("Xoá")
    }
}
