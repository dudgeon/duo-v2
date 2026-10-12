import DuoSearch
import Foundation
import DuoControl
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
    private var engine: Engine?

    /// The embedder and the open index, made once and kept for the app's life (C-79).
    final class Engine: @unchecked Sendable {
        let embedder: Embedder
        let index: SearchIndex
        init() throws {
            embedder = try Embedder(use: .indexing)
            index = try SearchIndex(readOnly: false)
        }
    }
    /// A file already in the index is re-indexed once it has been quiet this long (seconds).
    nonisolated static let quietPeriod: TimeInterval = 180

    /// Called after each workspace refresh; starts a pass when the projects changed or a minute passed.
    /// Every folder on the map is searched: projects, and Claude folders (sessions or a CLAUDE.md,
    /// DL-103). The home folder and those above it never are (F-53); see `FileSource`.
    public func update(projects: [String: URL]) {
        guard !running, projects != lastProjects || Date().timeIntervalSince(lastPass) > 60 else { return }
        running = true
        lastProjects = projects
        let bundled = Bundle.main.resourceURL?.appending(path: "search")
        let kept = engine
        Task.detached(priority: .utility) {
            let (stats, used) = await Self.pass(projects: projects, bundled: bundled, engine: kept)
            await MainActor.run {
                if used != nil { self.engine = used }
                self.lastStats = stats
                self.running = false
                self.lastPass = Date()
            }
        }
    }

    /// After the index was moved aside (unreadable): build it again on the next pass.
    public func rebuild() {
        engine = nil
        lastProjects = [:]
        lastPass = .distantPast
    }

    nonisolated static func pass(projects: [String: URL], bundled: URL?, engine kept: Engine?) async -> ([String: IndexStats], Engine?) {
        SearchSetup.registerExtractors()
        let began = Date()
        do {
            try await installModelIfNeeded(bundled: bundled)
            let engine = try kept ?? Engine()
            let embedder = engine.embedder, index = engine.index
            var removedAny = false
            let order = projects.filter { !ProtectedFolders.neverFileRoot($0.value) }.sorted { latest($0.value) > latest($1.value) }
            // Projects that left the workspace leave search (FR-7.1.1).
            for c in try index.coverage() where order.contains(where: { $0.key == c.project }) == false && c.project != SearchIndex.unfiled { try index.removeProject(c.project); removedAny = true }
            let roots = order.map { $0.value.resolvingSymlinksInPath().path }
            var out: [String: IndexStats] = [:]
            for (name, root) in order {
                // A folder inside another (a project in a Claude folder, Home's projects) is its own.
                let path = root.resolvingSymlinksInPath().path
                let inner = Set(roots.filter { $0.hasPrefix(path + "/") })
                out[name] = try await index.indexProject(name, root: root, excluding: inner, embedder: embedder, quiet: quietPeriod) {
                    let busy = ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState.rawValue >= 2
                    try? await Task.sleep(for: .milliseconds(busy ? 500 : 15))
                }
            }
            let claude = (Env.value("CLAUDE_CONFIG_DIR").map { URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")).appending(path: "projects")
            out["sessions"] = try await index.indexSessions(projects: projects, claudeProjects: claude, embedder: embedder,
                                                            archived: SessionArchive.purged(), quiet: quietPeriod) {
                try? await Task.sleep(for: .milliseconds(ProcessInfo.processInfo.isLowPowerModeEnabled ? 500 : 15))
            }
            // Vectors are orphaned only when items left or were rewritten.
            if removedAny || out.values.contains(where: { $0.removed > 0 || $0.replaced > 0 }) { try index.vacuumContent() }
            let total = out.values.reduce(IndexStats()) { a, b in
                var a = a; a.changed += b.changed; a.embedded += b.embedded; a.chunks += b.chunks; a.deferred += b.deferred; return a
            }
            FileHandle.standardError.write(Data("search: pass \(total.changed) files changed, \(total.chunks) chunks (\(total.embedded) embedded), \(total.deferred) waiting, \(Int(Date().timeIntervalSince(began) * 1000)) ms\n".utf8))
            return (out, engine)
        } catch {
            FileHandle.standardError.write(Data("search: \(error)\n".utf8))
            return ([:], nil)
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
