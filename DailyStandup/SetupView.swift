import SwiftUI
import ServiceManagement

struct SetupView: View {
    @ObservedObject private var appState = AppState.shared
    @StateObject private var audioRecorder = AudioRecorder()
    @State private var currentStep = 0
    @State private var projectInfos: [ProjectInfo] = []
    @State private var repoStatus: RepoStatus = .none
    @State private var setupError: String?
    @State private var isSettingUp = false
    @State private var setupProgress: String?

    // New project form fields
    @State private var newName = ""
    @State private var newDescription = ""
    @State private var newRepoURL = ""
    @State private var newWebsiteURL = ""
    @State private var editingIndex: Int?

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
                setupHeader

                ScrollView {
                    VStack(spacing: 20) {
                        stepContent
                    }
                    .padding(28)
                }

                navigationBar
            }
        }
        .frame(minWidth: 520, minHeight: 700)
        .onAppear {
            projectInfos = appState.settings.projects
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
            // Repository location (merged with explanation)
            settingsCard(title: "Repository", icon: "folder") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Daily Standup stores your updates in a repository. This repo contains all your daily standup notes and project information — it can also serve as context for other AI tools.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)

                    HStack(spacing: 8) {
                        Text(appState.settings.repoPath.isEmpty ? "No folder selected" : appState.settings.repoPath)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(appState.settings.repoPath.isEmpty ? .tertiary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                            )

                        Button(action: {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.canCreateDirectories = true
                            panel.allowsMultipleSelection = false
                            panel.prompt = "Select"
                            if panel.runModal() == .OK, let url = panel.url {
                                appState.settings.repoPath = url.path
                                checkRepoStatus(url.path)
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 12))
                                Text("Choose Folder")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }

                    if !appState.settings.repoPath.isEmpty {
                        repoStatusBadge
                    }
                }
            }

            // Project form
            settingsCard(title: editingIndex != nil ? "Edit Project" : "New Project", icon: "rectangle.on.rectangle") {
                VStack(alignment: .leading, spacing: 10) {
                    settingsField("Name", text: $newName, placeholder: "Project name")

                    settingsField("Description", text: $newDescription, placeholder: "Short description (optional)")

                    settingsField("Repository", text: $newRepoURL, placeholder: "https://github.com/org/repo (optional)")

                    settingsField("Website", text: $newWebsiteURL, placeholder: "https://example.com (optional)")

                    HStack {
                        Spacer()
                        if editingIndex != nil {
                            Button("Cancel") {
                                clearProjectForm()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        Button(action: addOrUpdateProject) {
                            HStack(spacing: 4) {
                                Image(systemName: editingIndex != nil ? "checkmark" : "plus")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(editingIndex != nil ? "Update Project" : "Add Project")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(newName.trimmingCharacters(in: .whitespaces).isEmpty ? Color.accentColor.opacity(0.4) : Color.accentColor)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }

            // Project list
            if !projectInfos.isEmpty {
                settingsCard(title: "Projects (\(projectInfos.count))", icon: "rectangle.stack") {
                    VStack(spacing: 8) {
                        ForEach(Array(projectInfos.enumerated()), id: \.element.name) { index, project in
                            projectRow(project, index: index)
                        }
                    }
                }
            }
        }
    }

    private func projectRow(_ project: ProjectInfo, index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.system(size: 12.5, weight: .semibold))

                if !project.description.isEmpty {
                    Text(project.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 10) {
                    if !project.repoURL.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9))
                            Text("Repo")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.tertiary)
                    }
                    if !project.websiteURL.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "globe")
                                .font(.system(size: 9))
                            Text("Web")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Button(action: { startEditingProject(index) }) {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button(action: { projectInfos.remove(at: index) }) {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
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

            if let progress = setupProgress {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text(progress)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

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
            if projectInfos.isEmpty {
                let existing = MarkdownManager().scanProjects(repoPath: path)
                projectInfos = existing.map { ProjectInfo(name: $0) }
            }
        } else {
            repoStatus = .willCreate
        }
    }

    // MARK: - Project Management

    private func addOrUpdateProject() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let info = ProjectInfo(
            name: name,
            description: newDescription.trimmingCharacters(in: .whitespaces),
            repoURL: newRepoURL.trimmingCharacters(in: .whitespaces),
            websiteURL: newWebsiteURL.trimmingCharacters(in: .whitespaces)
        )

        if let idx = editingIndex {
            projectInfos[idx] = info
        } else {
            guard !projectInfos.contains(where: { $0.name == name }) else { return }
            projectInfos.append(info)
        }

        clearProjectForm()
    }

    private func startEditingProject(_ index: Int) {
        let project = projectInfos[index]
        newName = project.name
        newDescription = project.description
        newRepoURL = project.repoURL
        newWebsiteURL = project.websiteURL
        editingIndex = index
    }

    private func clearProjectForm() {
        newName = ""
        newDescription = ""
        newRepoURL = ""
        newWebsiteURL = ""
        editingIndex = nil
    }

    // MARK: - Complete Setup

    private func completeSetup() {
        isSettingUp = true
        setupError = nil
        appState.settings.projects = projectInfos

        Task {
            do {
                let repoPath = appState.settings.repoPath
                let git = GitService()
                let projectNames = projectInfos.map { $0.name }

                if git.isValidRepo(at: repoPath) {
                    try git.addProjects(projectNames, repoPath: repoPath)
                } else {
                    await MainActor.run { setupProgress = "Creating repository..." }
                    try await git.initializeRepo(at: repoPath, projectNames: projectNames)
                }

                // Generate metadata.json and project.md for each project
                let apiKey = appState.settings.openAIAPIKey
                for (i, project) in projectInfos.enumerated() {
                    await MainActor.run {
                        setupProgress = "Setting up \(project.name) (\(i + 1)/\(projectInfos.count))..."
                    }
                    try await ProjectSetupService.generateProjectFiles(
                        project: project,
                        repoPath: repoPath,
                        apiKey: apiKey
                    )
                }

                // Commit the generated project files
                await MainActor.run { setupProgress = "Committing project files..." }
                _ = try await git.run(["add", "."], in: repoPath)
                // Only commit if there are staged changes
                let status = try await git.run(["status", "--porcelain"], in: repoPath)
                if !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    _ = try await git.run(["commit", "-m", "Add project metadata and descriptions"], in: repoPath)
                }

                await MainActor.run {
                    appState.settings.setupCompleted = true
                    appState.save()
                    NotificationManager.shared.reschedule()
                    isSettingUp = false
                    setupProgress = nil
                    NSApp.keyWindow?.close()
                }
            } catch {
                await MainActor.run {
                    setupError = error.localizedDescription
                    isSettingUp = false
                    setupProgress = nil
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
