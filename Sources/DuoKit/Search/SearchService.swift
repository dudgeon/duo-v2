import DuoSearch
import Foundation
import PDFKit

/// The app's side of search (Phase M1): installs the model, registers PDF extraction, and keeps
/// the index up to date for every project in the workspace, in the background (SRCH L8).
public enum SearchSetup {
    /// PDF text for the index: one page per paragraph, so chunks stay within pages.
    public static func registerExtractors() {
        FileSource.extractors["pdf"] = { path in
            guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else { return nil }
            return (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n\n")
        }
    }
}

/// Background indexing for the live workspace. One pass at a time, recently changed projects
/// first, a pause between files, longer when the Mac is hot or in Low Power Mode (FR-7.3.3).
@MainActor
public final class SearchService {
    public static let shared = SearchService()
    public private(set) var lastStats: [String: IndexStats] = [:]
    private var running = false
    private var lastPass = Date.distantPast
    private var lastProjects: [String: URL] = [:]

    /// Called after each workspace refresh; starts a pass when the projects changed or a minute passed.
    /// `fileProjects`: the documented projects whose files are indexed; folder entries (sessions
    /// started somewhere without a project file, often `~`) contribute only their sessions (F-53).
    public func update(projects: [String: URL], fileProjects: Set<String>? = nil) {
        guard !running, projects != lastProjects || Date().timeIntervalSince(lastPass) > 60 else { return }
        running = true
        lastProjects = projects
        let bundled = Bundle.main.resourceURL?.appending(path: "search")
        Task.detached(priority: .utility) {
            let stats = await Self.pass(projects: projects, fileProjects: fileProjects ?? Set(projects.keys), bundled: bundled)
            await MainActor.run {
                self.lastStats = stats
                self.running = false
                self.lastPass = Date()
            }
        }
    }

    nonisolated static func pass(projects: [String: URL], fileProjects: Set<String>, bundled: URL?) async -> [String: IndexStats] {
        SearchSetup.registerExtractors()
        do {
            try await installModelIfNeeded(bundled: bundled)
            let embedder = try Embedder(use: .indexing)
            let index = try SearchIndex(readOnly: false)
            // Projects that left the workspace leave search (FR-7.1.1).
            for c in try index.coverage() where fileProjects.contains(c.project) == false && c.project != SearchIndex.unfiled { try index.removeProject(c.project) }
            let order = projects.filter { fileProjects.contains($0.key) && !ProtectedFolders.isHome($0.value) }.sorted { latest($0.value) > latest($1.value) }
            var out: [String: IndexStats] = [:]
            for (name, root) in order {
                out[name] = try await index.indexProject(name, root: root, embedder: embedder) {
                    let busy = ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState.rawValue >= 2
                    try? await Task.sleep(for: .milliseconds(busy ? 500 : 15))
                }
            }
            let claude = (ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")).appending(path: "projects")
            out["sessions"] = try await index.indexSessions(projects: projects, claudeProjects: claude, embedder: embedder,
                                                            archived: SessionArchive.purged()) {
                try? await Task.sleep(for: .milliseconds(ProcessInfo.processInfo.isLowPowerModeEnabled ? 500 : 15))
            }
            try index.vacuumContent()
            return out
        } catch {
            FileHandle.standardError.write(Data("search: \(error)\n".utf8))
            return [:]
        }
    }

    /// Compiles the bundled model into Duo's folder the first time, or when the bundle's changed.
    nonisolated static func installModelIfNeeded(bundled: URL?) async throws {
        guard let bundled, FileManager.default.fileExists(atPath: bundled.appending(path: "bge-small-fp16.mlpackage").path) else {
            throw SearchError("no search model in this build")
        }
        let stamp = SearchPaths.compiledModel.deletingLastPathComponent().appending(path: "PROVENANCE.json")
        let want = try? Data(contentsOf: bundled.appending(path: "PROVENANCE.json"))
        if FileManager.default.fileExists(atPath: SearchPaths.compiledModel.path), (try? Data(contentsOf: stamp)) == want { return }
        _ = try await Embedder.install(package: bundled.appending(path: "bge-small-fp16.mlpackage"), vocab: bundled.appending(path: "vocab.txt"))
        try want?.write(to: stamp)
    }

    nonisolated static func latest(_ root: URL) -> Date {
        (try? root.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
