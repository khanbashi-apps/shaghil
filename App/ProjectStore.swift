import Foundation
import SwiftUI
import WidgetKit

struct Project: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var created: Date
    var modified: Date
    var iconEmoji: String
    var iconColorHex: String
    var files: [String]          // ordered file names
    var activeFile: String

    var mainFile: String {
        if files.contains("index.html") { return "index.html" }
        return files.first ?? "index.html"
    }

    var language: CodeLanguage { CodeLanguage.from(fileName: mainFile) }

    var summary: ProjectSummary {
        ProjectSummary(id: id, name: name, language: language, modified: modified,
                       iconEmoji: iconEmoji, iconColorHex: iconColorHex)
    }
}

struct Snapshot: Codable, Identifiable, Hashable {
    var id: String
    var date: Date
    var reason: String
    var files: [String: String]

    var totalLines: Int {
        files.values.reduce(0) { $0 + $1.components(separatedBy: "\n").count }
    }
}

final class ProjectStore: ObservableObject {
    static let shared = ProjectStore()

    @Published private(set) var projects: [Project] = []

    private let fm = FileManager.default
    private let maxSnapshots = 60

    static let iconColors = ["#6340DC", "#E8573A", "#2F9E74", "#2F7BEF", "#E0A100", "#D6337A", "#14213D", "#00A6A6"]
    static let iconEmojis = ["⚡️", "🚀", "🧩", "📊", "🗒️", "🎯", "🧮", "🌙", "☀️", "🎨", "🕹️", "📿", "🕌", "🛒", "💡", "⏱️"]

    init() { load() }

    // MARK: paths

    func dir(_ id: String) -> URL { SharedStore.projectsURL.appendingPathComponent(id, isDirectory: true) }
    func filesDir(_ id: String) -> URL { dir(id).appendingPathComponent("files", isDirectory: true) }
    func historyDir(_ id: String) -> URL { dir(id).appendingPathComponent("history", isDirectory: true) }
    private func metaURL(_ id: String) -> URL { dir(id).appendingPathComponent("meta.json") }

    // MARK: load / save

    func load() {
        let ids = (try? fm.contentsOfDirectory(atPath: SharedStore.projectsURL.path)) ?? []
        var list: [Project] = []
        for id in ids {
            if let data = try? Data(contentsOf: metaURL(id)),
               let p = try? SharedStore.decoder.decode(Project.self, from: data) {
                list.append(p)
            }
        }
        projects = list.sorted { $0.modified > $1.modified }
        syncIndex()
    }

    private func saveMeta(_ p: Project) {
        try? fm.createDirectory(at: dir(p.id), withIntermediateDirectories: true)
        if let data = try? SharedStore.encoder.encode(p) {
            try? data.write(to: metaURL(p.id), options: .atomic)
        }
        if let i = projects.firstIndex(where: { $0.id == p.id }) {
            projects[i] = p
        } else {
            projects.append(p)
        }
        projects.sort { $0.modified > $1.modified }
        syncIndex()
    }

    func syncIndex() {
        SharedStore.saveIndex(projects.map(\.summary))
        WidgetCenter.shared.reloadAllTimelines()
    }

    func project(_ id: String) -> Project? { projects.first { $0.id == id } }

    // MARK: create

    @discardableResult
    func create(code: String, name: String? = nil, language: CodeLanguage? = nil) -> Project {
        let lang = language ?? Detector.detect(code)
        let base = name ?? Detector.suggestName(for: code, language: lang)
        let finalName = uniqueName(base, language: lang)
        let id = UUID().uuidString.lowercased()
        let fileName = lang.mainFileName
        let p = Project(id: id, name: finalName, created: Date(), modified: Date(),
                        iconEmoji: ProjectStore.iconEmojis.randomElement() ?? "⚡️",
                        iconColorHex: ProjectStore.iconColors.randomElement() ?? "#6340DC",
                        files: [fileName], activeFile: fileName)
        try? fm.createDirectory(at: filesDir(id), withIntermediateDirectories: true)
        try? fm.createDirectory(at: historyDir(id), withIntermediateDirectories: true)
        try? code.write(to: filesDir(id).appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        saveMeta(p)
        snapshot(p, reason: "النسخة الأولى")
        return p
    }

    func uniqueName(_ base: String, language: CodeLanguage, excluding id: String? = nil) -> String {
        let names = Set(projects.filter { $0.id != id }.map(\.name))
        if !names.contains(base) { return base }
        let f = DateFormatter(); f.dateFormat = "HHmm"; f.locale = Locale(identifier: "en_US_POSIX")
        let withTime = "\(base)_\(f.string(from: Date()))"
        if !names.contains(withTime) { return withTime }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    // MARK: files

    func read(_ file: String, in id: String) -> String {
        (try? String(contentsOf: filesDir(id).appendingPathComponent(file), encoding: .utf8)) ?? ""
    }

    func allFiles(_ p: Project) -> [String: String] {
        var d: [String: String] = [:]
        for f in p.files { d[f] = read(f, in: p.id) }
        return d
    }

    /// Writes a file. When `snapshotReason` is given a snapshot of the previous state is taken first.
    /// Otherwise an automatic snapshot is taken when the change is large or the last one is old.
    func write(_ content: String, file: String, in id: String, snapshotReason: String? = nil) {
        guard var p = project(id) else { return }
        let old = read(file, in: id)
        if old == content { return }
        if let reason = snapshotReason {
            snapshot(p, reason: reason)
        } else if shouldAutoSnapshot(p, file: file, old: old, new: content) {
            snapshot(p, reason: "حفظ تلقائي")
        }
        try? content.write(to: filesDir(id).appendingPathComponent(file), atomically: true, encoding: .utf8)
        p.modified = Date()
        saveMeta(p)
    }

    private func shouldAutoSnapshot(_ p: Project, file: String, old: String, new: String) -> Bool {
        guard let last = snapshots(p).first else { return true }
        let lastContent = last.files[file] ?? ""
        if lastContent == old { return false }               // previous state already saved
        let age = Date().timeIntervalSince(last.date)
        let jump = abs(new.count - old.count)
        return age > 300 || jump > 250
    }

    func addFile(_ name: String, content: String = "", to id: String) -> Bool {
        guard var p = project(id) else { return false }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !clean.isEmpty, !p.files.contains(clean) else { return false }
        try? content.write(to: filesDir(id).appendingPathComponent(clean), atomically: true, encoding: .utf8)
        p.files.append(clean)
        p.activeFile = clean
        p.modified = Date()
        saveMeta(p)
        return true
    }

    func renameFile(_ old: String, to new: String, in id: String) -> Bool {
        guard var p = project(id), let i = p.files.firstIndex(of: old) else { return false }
        let clean = new.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !clean.isEmpty, !p.files.contains(clean) else { return false }
        try? fm.moveItem(at: filesDir(id).appendingPathComponent(old), to: filesDir(id).appendingPathComponent(clean))
        p.files[i] = clean
        if p.activeFile == old { p.activeFile = clean }
        p.modified = Date()
        saveMeta(p)
        return true
    }

    func deleteFile(_ name: String, in id: String) {
        guard var p = project(id), p.files.count > 1 else { return }
        snapshot(p, reason: "قبل حذف \(name)")
        try? fm.removeItem(at: filesDir(id).appendingPathComponent(name))
        p.files.removeAll { $0 == name }
        if p.activeFile == name { p.activeFile = p.files.first ?? "" }
        p.modified = Date()
        saveMeta(p)
    }

    func setActiveFile(_ name: String, in id: String) {
        guard var p = project(id), p.activeFile != name else { return }
        p.activeFile = name
        saveMeta(p)
    }

    // MARK: project edits

    func rename(_ id: String, to name: String) {
        guard var p = project(id) else { return }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        p.name = n
        p.modified = Date()
        saveMeta(p)
    }

    func setIcon(_ id: String, emoji: String, colorHex: String) {
        guard var p = project(id) else { return }
        p.iconEmoji = emoji
        p.iconColorHex = colorHex
        saveMeta(p)
    }

    func delete(_ id: String) {
        try? fm.removeItem(at: dir(id))
        try? fm.removeItem(at: SharedStore.widgetURL.appendingPathComponent("\(id).json"))
        projects.removeAll { $0.id == id }
        syncIndex()
    }

    func duplicate(_ id: String) {
        guard let p = project(id) else { return }
        let files = allFiles(p)
        let newID = UUID().uuidString.lowercased()
        try? fm.createDirectory(at: filesDir(newID), withIntermediateDirectories: true)
        try? fm.createDirectory(at: historyDir(newID), withIntermediateDirectories: true)
        for (k, v) in files {
            try? v.write(to: filesDir(newID).appendingPathComponent(k), atomically: true, encoding: .utf8)
        }
        var copy = p
        copy.id = newID
        copy.name = uniqueName(p.name + " (نسخة)", language: p.language)
        copy.created = Date()
        copy.modified = Date()
        saveMeta(copy)
    }

    // MARK: snapshots

    func snapshots(_ p: Project) -> [Snapshot] {
        let d = historyDir(p.id)
        let names = (try? fm.contentsOfDirectory(atPath: d.path)) ?? []
        return names.compactMap { n -> Snapshot? in
            guard let data = try? Data(contentsOf: d.appendingPathComponent(n)) else { return nil }
            return try? SharedStore.decoder.decode(Snapshot.self, from: data)
        }.sorted { $0.date > $1.date }
    }

    func snapshot(_ p: Project, reason: String) {
        let d = historyDir(p.id)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        let now = Date()
        let s = Snapshot(id: String(Int(now.timeIntervalSince1970 * 1000)), date: now, reason: reason, files: allFiles(p))
        if let data = try? SharedStore.encoder.encode(s) {
            try? data.write(to: d.appendingPathComponent("\(s.id).json"), options: .atomic)
        }
        // trim
        let all = snapshots(p)
        if all.count > maxSnapshots {
            for old in all.suffix(from: maxSnapshots) {
                try? fm.removeItem(at: d.appendingPathComponent("\(old.id).json"))
            }
        }
    }

    func restore(_ s: Snapshot, in id: String) {
        guard var p = project(id) else { return }
        snapshot(p, reason: "قبل الاسترجاع")
        // remove files that are not in the snapshot
        for f in p.files where s.files[f] == nil {
            try? fm.removeItem(at: filesDir(id).appendingPathComponent(f))
        }
        for (k, v) in s.files {
            try? v.write(to: filesDir(id).appendingPathComponent(k), atomically: true, encoding: .utf8)
        }
        let order = p.files.filter { s.files[$0] != nil } + s.files.keys.filter { !p.files.contains($0) }.sorted()
        p.files = order
        if !order.contains(p.activeFile) { p.activeFile = order.first ?? "" }
        p.modified = Date()
        saveMeta(p)
    }

    func deleteSnapshot(_ s: Snapshot, in id: String) {
        try? fm.removeItem(at: historyDir(id).appendingPathComponent("\(s.id).json"))
        objectWillChange.send()
    }

    // MARK: widget bridge

    func saveWidgetData(_ dict: [String: Any], for id: String) {
        var p = SharedStore.widgetPayload(for: id) ?? WidgetPayload()
        if let v = dict["title"] { p.title = "\(v)" }
        if let v = dict["value"] { p.value = "\(v)" }
        if let v = dict["subtitle"] { p.subtitle = "\(v)" }
        if let v = dict["counter"] as? Double { p.counter = v; if dict["value"] == nil { p.value = Self.fmt(v) } }
        if let v = dict["step"] as? Double { p.step = v }
        if let arr = dict["items"] as? [Any] {
            p.items = arr.prefix(12).map { el in
                if let o = el as? [String: Any] {
                    return WidgetItem(text: "\(o["text"] ?? o["title"] ?? "")", done: (o["done"] as? Bool) ?? false)
                }
                return WidgetItem(text: "\(el)", done: false)
            }
        }
        p.updated = Date()
        SharedStore.saveWidgetPayload(p, for: id)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    }

    func widgetStateJSON(for id: String) -> String {
        guard let p = SharedStore.widgetPayload(for: id),
              let data = try? SharedStore.encoder.encode(p),
              let s = String(data: data, encoding: .utf8) else { return "null" }
        return s
    }
}
