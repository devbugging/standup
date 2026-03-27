import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject private var appState = AppState.shared
    @StateObject private var audioRecorder = AudioRecorder()
    @State private var showingSaved = false

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .contentBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Settings")
                                .font(.system(size: 20, weight: .bold))
                            Text("Configure your standup preferences")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 4)

                    // Profile
                    settingsCard(title: "Profile", icon: "person.crop.circle") {
                        VStack(spacing: 14) {
                            settingsField("Name", text: $appState.settings.userName, placeholder: "Your name")
                            settingsField("Roles", text: $appState.settings.userRoles, placeholder: "e.g. Development, Marketing")
                        }
                    }

                    // API Key
                    settingsCard(title: "OpenAI", icon: "key") {
                        apiKeyField(
                            label: "API Key",
                            sublabel: "Whisper transcription + GPT note structuring",
                            placeholder: "sk-...",
                            text: $appState.settings.openAIAPIKey
                        )
                    }

                    // Microphone
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

                    // Notification
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

                    // Repository
                    settingsCard(title: "Repository", icon: "folder") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Projects Path")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                TextField("/path/to/projects", text: $appState.settings.repoPath)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, design: .monospaced))
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
                                    panel.allowsMultipleSelection = false
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
                        }
                    }

                    // System
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

                    // Save button
                    HStack {
                        Spacer()

                        if showingSaved {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Saved")
                                    .foregroundStyle(.green)
                            }
                            .font(.system(size: 12, weight: .medium))
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }

                        Button(action: {
                            appState.save()
                            NotificationManager.shared.scheduleDailyReminder(
                                hour: appState.settings.notificationHour,
                                minute: appState.settings.notificationMinute
                            )
                            withAnimation(.easeOut(duration: 0.2)) {
                                showingSaved = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { showingSaved = false }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Save & Update")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
                .padding(28)
            }
        }
        .frame(minWidth: 460, minHeight: 540)
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

    private func apiKeyField(label: String, sublabel: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                Text(sublabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            SecureField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, design: .monospaced))
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        }
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
