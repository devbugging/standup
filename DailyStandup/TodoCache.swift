import Foundation

struct CachedTodoData: Codable {
    let date: String
    let todos: [CachedTodo]
    let summary: String
    let processedAt: Date
}

struct CachedTodo: Codable, Identifiable {
    let project: String
    let task: String
    let priority: String
    var id: String { "\(project):\(task)" }
}

/// Caches the daily organized todos to disk so the view opens instantly.
/// Refreshes once per day on app launch or wake from sleep.
class TodoCache {
    static let shared = TodoCache()

    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.dailystandup.app", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("daily_todos.json")
    }()

    private let openai = OpenAIService()
    private let markdown = MarkdownManager()

    private var isProcessing = false

    // MARK: - Read cache

    func loadCached() -> CachedTodoData? {
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode(CachedTodoData.self, from: data) else {
            return nil
        }
        return cached
    }

    func loadCachedForToday() -> CachedTodoData? {
        guard let cached = loadCached(), cached.date == todayString() else {
            return nil
        }
        return cached
    }

    // MARK: - Write cache

    private func save(_ data: CachedTodoData) {
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: cacheURL)
        }
    }

    // MARK: - Process & cache

    /// Processes todos in the background if today's cache doesn't exist yet.
    /// Safe to call multiple times — skips if already processing or cache is fresh.
    func refreshIfNeeded() {
        guard !isProcessing else { return }
        guard AppState.shared.isConfigured else { return }

        // Skip if already cached for today
        if loadCachedForToday() != nil { return }

        isProcessing = true

        Task {
            defer { isProcessing = false }

            do {
                let settings = AppState.shared.settings
                let projects = markdown.scanProjects(repoPath: settings.repoPath)
                let rawItems = markdown.readPendingTodos(
                    repoPath: settings.repoPath,
                    userName: settings.userName
                )

                guard !rawItems.isEmpty else {
                    let empty = CachedTodoData(
                        date: todayString(),
                        todos: [],
                        summary: "",
                        processedAt: Date()
                    )
                    save(empty)
                    return
                }

                let result = try await openai.organizeTodos(
                    rawItems: rawItems,
                    projects: projects,
                    userName: settings.userName
                )

                let cached = CachedTodoData(
                    date: todayString(),
                    todos: result.todos.map { CachedTodo(project: $0.project, task: $0.task, priority: $0.priority) },
                    summary: result.summary,
                    processedAt: Date()
                )
                save(cached)
            } catch {
                print("TodoCache: failed to process — \(error.localizedDescription)")
            }
        }
    }

    /// Force refresh regardless of cache state.
    func forceRefresh() async throws -> CachedTodoData {
        let settings = AppState.shared.settings
        let projects = markdown.scanProjects(repoPath: settings.repoPath)
        let rawItems = markdown.readPendingTodos(
            repoPath: settings.repoPath,
            userName: settings.userName
        )

        guard !rawItems.isEmpty else {
            let empty = CachedTodoData(
                date: todayString(),
                todos: [],
                summary: "",
                processedAt: Date()
            )
            save(empty)
            return empty
        }

        let result = try await openai.organizeTodos(
            rawItems: rawItems,
            projects: projects,
            userName: settings.userName
        )

        let cached = CachedTodoData(
            date: todayString(),
            todos: result.todos.map { CachedTodo(project: $0.project, task: $0.task, priority: $0.priority) },
            summary: result.summary,
            processedAt: Date()
        )
        save(cached)
        return cached
    }

    /// Invalidate today's cache so the next open or refreshIfNeeded re-processes.
    func invalidate() {
        try? FileManager.default.removeItem(at: cacheURL)
    }

    // MARK: - Helpers

    private func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}
