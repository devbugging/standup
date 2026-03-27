import SwiftUI

// MARK: - View Model

enum TodoViewPhase: Equatable {
    case loading
    case loaded
    case empty
    case error(String)
}

@MainActor
class TodoViewModel: ObservableObject {
    @Published var phase: TodoViewPhase = .loading
    @Published var todos: [OrganizedTodo] = []
    @Published var summary: String = ""
    @Published var cachedTime: String = ""

    var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMM d"
        return fmt.string(from: Date())
    }

    /// Load from cache first (instant), then fall back to live fetch.
    func load() {
        // Try cache first
        if let cached = TodoCache.shared.loadCachedForToday() {
            applyCache(cached)
            return
        }

        // No cache — fetch live
        phase = .loading
        fetchLive()
    }

    /// Force refresh: re-processes from todo.md via OpenAI, ignoring cache.
    func refresh() {
        phase = .loading

        Task {
            do {
                let cached = try await TodoCache.shared.forceRefresh()
                applyCache(cached)
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }

    private func fetchLive() {
        Task {
            do {
                let cached = try await TodoCache.shared.forceRefresh()
                applyCache(cached)
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }

    private func applyCache(_ cached: CachedTodoData) {
        if cached.todos.isEmpty {
            phase = .empty
            return
        }

        todos = cached.todos.map {
            OrganizedTodo(project: $0.project, task: $0.task, priority: $0.priority)
        }
        summary = cached.summary

        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        cachedTime = fmt.string(from: cached.processedAt)

        phase = .loaded
    }
}

// MARK: - View

struct TodoView: View {
    @StateObject private var viewModel = TodoViewModel()

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .contentBackground, blendingMode: .behindWindow)
            Theme.gradient.ignoresSafeArea()

            VStack(spacing: 0) {
                titleBar

                switch viewModel.phase {
                case .loading:
                    loadingContent
                case .loaded:
                    loadedContent
                case .empty:
                    emptyContent
                case .error(let msg):
                    errorContent(msg)
                }
            }
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 400, idealHeight: 600)
        .onAppear { viewModel.load() }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "checklist")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Daily To-Do")
                    .font(.system(size: 14, weight: .semibold))
                Text(viewModel.formattedDate)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !viewModel.cachedTime.isEmpty && viewModel.phase == .loaded {
                Text("Updated \(viewModel.cachedTime)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            Button(action: { viewModel.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Re-process todos from file")
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Loading

    private var loadingContent: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.1), lineWidth: 4)
                    .frame(width: 56, height: 56)
                ProgressView()
                    .scaleEffect(1.3)
            }
            Text("Organizing your tasks...")
                .font(.system(size: 14, weight: .medium))
            Text("GPT is prioritizing and grouping your to-dos")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Loaded

    private var loadedContent: some View {
        VStack(spacing: 0) {
            // Summary card
            if !viewModel.summary.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                    Text(viewModel.summary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.orange.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    // Group by priority
                    let high = viewModel.todos.filter { $0.priority == "high" }
                    let medium = viewModel.todos.filter { $0.priority == "medium" }
                    let low = viewModel.todos.filter { $0.priority == "low" }

                    if !high.isEmpty {
                        prioritySection("Priority", items: high, color: .red)
                    }
                    if !medium.isEmpty {
                        prioritySection("Today", items: medium, color: .orange)
                    }
                    if !low.isEmpty {
                        prioritySection("Backlog", items: low, color: .secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private func prioritySection(_ title: String, items: [OrganizedTodo], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text("\(items.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 8)

            ForEach(items) { item in
                todoRow(item, accentColor: color)
            }
        }
    }

    private func todoRow(_ item: OrganizedTodo, accentColor: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .stroke(accentColor.opacity(0.4), lineWidth: 1.5)
                .frame(width: 16, height: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.task)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(3)

                Text(item.project)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.08), in: Capsule())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }

    // MARK: - Empty

    private var emptyContent: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green.opacity(0.6))
            Text("All clear!")
                .font(.system(size: 17, weight: .semibold))
            Text("No pending to-do items found.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Error

    private func errorContent(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Failed to load todos")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button("Retry") { viewModel.load() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Spacer()
        }
    }
}
