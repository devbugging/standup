import SwiftUI
import ServiceManagement

struct SetupView: View {
    @ObservedObject private var appState = AppState.shared
    @StateObject private var audioRecorder = AudioRecorder()
    @State private var currentStep = 0
    @State private var newProjectName = ""
    @State private var projectNames: [String] = []
    @State private var repoStatus: RepoStatus = .none
    @State private var setupError: String?
    @State private var isSettingUp = false

    enum RepoStatus {
        case none
        case existingValid
        case willCreate
    }

    private let totalSteps = 3

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .contentBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with step indicator
                setupHeader

                // Step content
                ScrollView {
                    VStack(spacing: 20) {
                        stepContent
                    }
                    .padding(28)
                }

                // Navigation buttons
                navigationBar
            }
        }
        .frame(minWidth: 500, minHeight: 700)
        .onAppear {
            // Pre-populate from existing settings if re-opening setup
            projectNames = appState.settings.projectNames
            if !appState.settings.repoPath.isEmpty {
                checkRepoStatus(appState.settings.repoPath)
            }
        }
    }

    // MARK: - Header

    private var setupHeader: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Setup")
                        .font(.system(size: 20, weight: .bold))
                    Text(stepSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Step \(currentStep + 1) of \(totalSteps)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * CGFloat(currentStep + 1) / CGFloat(totalSteps), height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private var stepSubtitle: String {
        switch currentStep {
        case 0: return "Tell us about yourself"
        case 1: return "Set up your standup repository"
        case 2: return "Configure your preferences"
        default: return ""
        }
    }

    // MARK: - Step Router

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0: profileStep
        case 1: repositoryStep
        case 2: preferencesStep
        default: EmptyView()
        }
    }

    // MARK: - Step 1: Profile & API Key

    private var profileStep: some View {
        VStack(spacing: 20) {
            settingsCard(title: "Profile", icon: "person.crop.circle") {
                VStack(spacing: 14) {
                    settingsField("Name", text: $appState.settings.userName, placeholder: "Your name")
                    settingsField("Roles", text: $appState.settings.userRoles, placeholder: "e.g. Development, Marketing")
                }
            }

            settingsCard(title: "OpenAI API Key", icon: "key") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Used for Whisper transcription and GPT note structuring.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    SecureField("sk-...", text: $appState.settings.openAIAPIKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, design: .monospaced))
                        .padding(10)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                        )

                    HStack(spacing: 8) {
                        Button(action: {
                            NSWorkspace.shared.open(URL(string: "https://platform.openai.com/api-keys")!)
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 10))
                                Text("Get API Key from OpenAI")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)

                        Spacer()
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text("Sign in to OpenAI, then create a new secret key. Paste it above.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Step 2: Repository Setup

    private var repositoryStep: some View {
        VStack(spacing: 20) {
            // Explanation card
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Text("What is this?")
                            .font(.system(size: 13, weight: .semibold))
                    }

                    Text("Daily Standup stores your updates in a local git repository. This repo contains all your daily standup notes and project information — it can also serve as context for other AI tools.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
            }

            // Folder selection
            settingsCard(title: "Repository Location", icon: "folder") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Choose where to create (or find) your standup repository.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField("/path/to/standup-repo", text: $appState.settings.repoPath)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(10)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                            .onChange(of: appState.settings.repoPath) { _, newValue in
                                checkRepoStatus(newValue)
                            }

                        Button(action: {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.canCreateDirectories = true
                            panel.allowsMultipleSelection = false
                            panel.prompt = "Select"
                            if panel.runModal() == .OK, let url = panel.url {
                                appState.settings.repoPath = url.path
                            }
                        }) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 13))
                                .frame(width: 34, height: 34)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }

                    // Repo status indicator
                    if !appState.settings.repoPath.isEmpty {
                        repoStatusBadge
                    }
                }
            }

            // Projects
            settingsCard(title: "Projects", icon: "rectangle.stack") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add the projects you work on. Each becomes a folder in the repository.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField("Project name", text: $newProjectName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5))
                            .padding(10)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                            .onSubmit { addProject() }

                        Button(action: addProject) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if !projectNames.isEmpty {
                        FlowLayoutView(items: projectNames) { name in
                            HStack(spacing: 4) {
                                Text(name)
                                    .font(.system(size: 11, weight: .medium))
                                Button(action: { removeProject(name) }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.08))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var repoStatusBadge: some View {
        switch repoStatus {
        case .existingValid:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 11))
                Text("Existing standup repository detected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            }
        case .willCreate:
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 11))
                Text("A new git repository will be created here")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.blue)
            }
        case .none:
            EmptyView()
        }
    }

    // MARK: - Step 3: Preferences

    private var preferencesStep: some View {
        VStack(spacing: 20) {
            settingsCard(title: "Daily Reminder", icon: "bell.badge") {
                HStack(spacing: 12) {
                    Text("Time")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    HStack(spacing: 4) {
                        Picker("", selection: $appState.settings.notificationHour) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(String(format: "%02d", h)).tag(h)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 64)

                        Text(":")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)

                        Picker("", selection: $appState.settings.notificationMinute) {
                            ForEach(0..<60, id: \.self) { m in
                                Text(String(format: "%02d", m)).tag(m)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 64)
                    }
                }
            }

            settingsCard(title: "Microphone", icon: "mic") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Input Device", selection: $appState.settings.selectedMicUID) {
                        Text("System Default").tag("")
                        ForEach(audioRecorder.availableDevices) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                    .labelsHidden()

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text("If recording is silent, try selecting a different device")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    Button(action: { audioRecorder.refreshDevices() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                            Text("Refresh Devices")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            settingsCard(title: "System", icon: "gearshape.2") {
                Toggle(isOn: $appState.settings.launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("Start Daily Standup automatically")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: appState.settings.launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        print("Launch at login error: \(error)")
                    }
                }
            }

            // Error display
            if let error = setupError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12))
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            if currentStep > 0 {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentStep -= 1
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Spacer()

            if currentStep < totalSteps - 1 {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentStep += 1
                    }
                }) {
                    HStack(spacing: 4) {
                        Text("Next")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canAdvanceFromCurrentStep)
            } else {
                Button(action: completeSetup) {
                    HStack(spacing: 6) {
                        if isSettingUp {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                        }
                        Text("Complete Setup")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSettingUp)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }

    // MARK: - Validation

    private var canAdvanceFromCurrentStep: Bool {
        switch currentStep {
        case 0:
            return !appState.settings.userName.trimmingCharacters(in: .whitespaces).isEmpty
                && !appState.settings.openAIAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
        case 1:
            return !appState.settings.repoPath.trimmingCharacters(in: .whitespaces).isEmpty
        default:
            return true
        }
    }

    // MARK: - Repo Check

    private func checkRepoStatus(_ path: String) {
        guard !path.trimmingCharacters(in: .whitespaces).isEmpty else {
            repoStatus = .none
            return
        }
        if GitService().isValidRepo(at: path) {
            repoStatus = .existingValid
            // Load existing projects
            let existing = MarkdownManager().scanProjects(repoPath: path)
            if !existing.isEmpty && projectNames.isEmpty {
                projectNames = existing
            }
        } else {
            repoStatus = .willCreate
        }
    }

    // MARK: - Project Management

    private func addProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !projectNames.contains(name) else { return }
        projectNames.append(name)
        newProjectName = ""
    }

    private func removeProject(_ name: String) {
        projectNames.removeAll { $0 == name }
    }

    // MARK: - Complete Setup

    private func completeSetup() {
        isSettingUp = true
        setupError = nil
        appState.settings.projectNames = projectNames

        Task {
            do {
                let repoPath = appState.settings.repoPath
                let git = GitService()

                if git.isValidRepo(at: repoPath) {
                    // Existing repo — just add any new project directories
                    try git.addProjects(projectNames, repoPath: repoPath)
                } else {
                    // Create new repo
                    try await git.initializeRepo(at: repoPath, projectNames: projectNames)
                }

                await MainActor.run {
                    appState.settings.setupCompleted = true
                    appState.save()
                    NotificationManager.shared.reschedule()
                    isSettingUp = false
                    NSApp.keyWindow?.close()
                }
            } catch {
                await MainActor.run {
                    setupError = error.localizedDescription
                    isSettingUp = false
                }
            }
        }
    }

    // MARK: - Card Builder

    private func settingsCard<Content: View>(
        title: String, icon: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }

            content()
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private func settingsField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        }
    }
}
