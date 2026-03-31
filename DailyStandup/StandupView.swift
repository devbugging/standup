import SwiftUI

// MARK: - Theme

enum Theme {
    static let cardRadius: CGFloat = 14
    static let cardPadding: CGFloat = 20

    static let gradient = LinearGradient(
        colors: [Color(nsColor: .controlAccentColor).opacity(0.08), .clear],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Main View

struct StandupView: View {
    @StateObject private var viewModel = StandupViewModel()
    @State private var phaseAppeared = false

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 0) {
                customTitleBar
                statusBar

                ScrollView {
                    VStack(spacing: 24) {
                        phaseContent
                            .id(viewModel.phase)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal: .opacity.combined(with: .move(edge: .leading))
                            ))
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 580, idealHeight: 680)
        .onAppear { viewModel.prepare() }
        .animation(.easeInOut(duration: 0.35), value: viewModel.phase)
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            VisualEffectBlur(material: .contentBackground, blendingMode: .behindWindow)
            Theme.gradient.ignoresSafeArea()
        }
    }

    // MARK: - Title Bar

    private var customTitleBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Daily Standup")
                    .font(.system(size: 14, weight: .semibold))
                Text(viewModel.formattedDate)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.phase == .ready {
                settingsButton
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var settingsButton: some View {
        Button(action: { WindowManager.shared.showSetup() }) {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status Bar

    @ViewBuilder
    private var statusBar: some View {
        if !viewModel.statusMessage.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text(viewModel.statusMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Phase Router

    @ViewBuilder
    private var phaseContent: some View {
        switch viewModel.phase {
        case .ready, .recording: readyPhase
        case .processing:  processingPhase
        case .review:      reviewPhase
        case .pushing:     pushingPhase
        case .done:        donePhase
        case .error(let m): errorPhase(m)
        }
    }

    // MARK: - Ready Phase

    private var isRecording: Bool {
        viewModel.phase == .recording
    }

    private var readyPhase: some View {
        VStack(spacing: 20) {
            // Instructions card
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Text("Recording Guide")
                            .font(.system(size: 13, weight: .semibold))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        instructionRow(1, "Describe what you worked on today", "Mention project names for auto-tagging")
                        instructionRow(2, "Share any blockers", "Issues preventing progress")
                        instructionRow(3, "Say \"todos\" for action items", "What still needs to be done")
                    }
                }
            }
            .opacity(isRecording ? 0.5 : 1.0)

            // Projects
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Text("Active Projects")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("\(viewModel.projects.count)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }

                    FlowLayoutView(items: viewModel.projects) { project in
                        Text(project)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.08))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
            }
            .opacity(isRecording ? 0.5 : 1.0)

            if !viewModel.recorder.permissionGranted {
                micPermissionWarning
            }

            Spacer(minLength: 8)

            // Record / Stop button
            if isRecording {
                RecordingIndicatorButton(
                    elapsedTime: viewModel.recorder.elapsedTime,
                    audioLevel: viewModel.recorder.audioLevel,
                    action: { viewModel.completeRecording() }
                )
            } else {
                RecordButton(action: { viewModel.startRecording() })
                    .disabled(!viewModel.recorder.permissionGranted)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isRecording)
    }

    private var micPermissionWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 14))
            Text("Microphone access needed. Enable in **System Settings > Privacy > Microphone**.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Processing Phase

    private var processingPhase: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 60)

            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.1), lineWidth: 4)
                    .frame(width: 64, height: 64)
                ProgressView()
                    .scaleEffect(1.4)
            }

            Text("Transcribing audio...")
                .font(.system(size: 16, weight: .semibold))

            Text("ElevenLabs is processing your recording")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer(minLength: 60)
        }
    }

    // MARK: - Review Phase

    private var reviewPhase: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Review & Edit")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }

            // Standup notes editor
            editorSection(
                title: "Standup Notes",
                icon: "list.bullet.clipboard",
                hint: "Format: - **Project:** What you did",
                text: $viewModel.standupText,
                minHeight: 140,
                maxHeight: 240
            )

            // Todo editor
            editorSection(
                title: "To Do Items",
                icon: "checklist",
                hint: "Format: Project: What needs to be done (one per line)",
                text: $viewModel.todoText,
                minHeight: 90,
                maxHeight: 180
            )

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                Button(action: { viewModel.reset() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Re-record")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(action: { viewModel.confirm() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                        Text("Confirm & Push")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private func editorSection(
        title: String, icon: String, hint: String,
        text: Binding<String>, minHeight: CGFloat, maxHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: text)
                .font(.system(size: 13, weight: .regular))
                .lineSpacing(4)
                .frame(minHeight: minHeight, maxHeight: maxHeight)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )

            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Pushing Phase

    private var pushingPhase: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 60)

            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.1), lineWidth: 4)
                    .frame(width: 64, height: 64)
                ProgressView()
                    .scaleEffect(1.4)
            }

            Text("Pushing to repository...")
                .font(.system(size: 16, weight: .semibold))

            Text(viewModel.statusMessage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer(minLength: 60)
        }
    }

    // MARK: - Done Phase

    private var donePhase: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 50)

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 88, height: 88)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: viewModel.phase)
            }

            Text("All done!")
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 4)

            Text("Standup committed and pushed successfully.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Spacer(minLength: 40)

            Button(action: { NSApp.keyWindow?.close() }) {
                Text("Close")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 120)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    // MARK: - Error Phase

    private func errorPhase(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)

            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
            }

            Text("Something went wrong")
                .font(.system(size: 17, weight: .semibold))

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .padding(.horizontal, 24)

            Spacer(minLength: 20)

            HStack(spacing: 10) {
                Button("Try Again") { viewModel.reset() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("Close") { NSApp.keyWindow?.close() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
    }

    // MARK: - Helpers

    private func instructionRow(_ number: Int, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Glass Card

struct GlassCard<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            )
    }
}

// MARK: - Record Button

struct RecordButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(isHovering ? 0.12 : 0.06))
                        .frame(width: 80, height: 80)
                        .scaleEffect(isHovering ? 1.1 : 1.0)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.red, Color.red.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 52, height: 52)
                        .shadow(color: .red.opacity(isHovering ? 0.5 : 0.3), radius: isHovering ? 16 : 10, y: 3)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }

                Text("Start Recording")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.2), value: isHovering)
    }
}

// MARK: - Recording Indicator Button

struct RecordingIndicatorButton: View {
    let elapsedTime: TimeInterval
    let audioLevel: Float
    let action: () -> Void
    @State private var isHovering = false
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                ZStack {
                    let level = CGFloat(audioLevel)

                    // Pulsing outer rings
                    ForEach(0..<2, id: \.self) { i in
                        Circle()
                            .stroke(Color.red.opacity(0.10 - Double(i) * 0.04), lineWidth: 2)
                            .frame(width: CGFloat(72 + i * 24), height: CGFloat(72 + i * 24))
                            .scaleEffect(1.0 + level * CGFloat(0.1 + Double(i) * 0.06))
                            .animation(.easeOut(duration: 0.15), value: level)
                    }

                    // Outer glow
                    Circle()
                        .fill(Color.red.opacity(isHovering ? 0.12 : 0.06))
                        .frame(width: 80, height: 80)
                        .scaleEffect(isHovering ? 1.1 : 1.0)

                    // Main button - stop square
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.red, Color.red.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 52, height: 52)
                        .shadow(color: .red.opacity(isHovering ? 0.5 : 0.3), radius: isHovering ? 16 : 10, y: 3)

                    Image(systemName: "stop.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 4) {
                    Text(formatTime(elapsedTime))
                        .font(.system(size: 22, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)

                    Text("Recording — tap to stop")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.2), value: isHovering)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Flow Layout

struct FlowLayoutView<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let items: Data
    let content: (Data.Element) -> Content

    @State private var totalHeight = CGFloat.zero

    var body: some View {
        GeometryReader { geometry in
            self.generateContent(in: geometry)
        }
        .frame(height: totalHeight)
    }

    private func generateContent(in geometry: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero

        return ZStack(alignment: .topLeading) {
            ForEach(Array(items.enumerated()), id: \.element) { _, item in
                content(item)
                    .padding(.trailing, 6)
                    .padding(.bottom, 6)
                    .alignmentGuide(.leading) { dimension in
                        if abs(width - dimension.width) > geometry.size.width {
                            width = 0
                            height -= dimension.height
                        }
                        let result = width
                        if item == items.last! {
                            width = 0
                        } else {
                            width -= dimension.width
                        }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item == items.last! {
                            height = 0
                        }
                        return result
                    }
            }
        }
        .background(viewHeightReader($totalHeight))
    }

    private func viewHeightReader(_ binding: Binding<CGFloat>) -> some View {
        GeometryReader { geometry -> Color in
            let rect = geometry.frame(in: .local)
            DispatchQueue.main.async {
                binding.wrappedValue = rect.size.height
            }
            return .clear
        }
    }
}

// MARK: - Visual Effect

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
