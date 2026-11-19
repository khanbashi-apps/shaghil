import Foundation
import SwiftUI

// MARK: - Constants shared by the app and the widget

enum AppInfo {
    static let version = "1.0"
    static let appGroup = "group.om.khanbashi.shaghil"
    static let scheme = "shaghil"
}

// MARK: - Language

enum CodeLanguage: String, Codable, CaseIterable, Identifiable {
    case html, css, javascript, typescript, python, json, swift, svg, markdown, xml, text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .html: return "HTML"
        case .css: return "CSS"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .python: return "Python"
        case .json: return "JSON"
        case .swift: return "Swift"
        case .svg: return "SVG"
        case .markdown: return "Markdown"
        case .xml: return "XML"
        case .text: return "نص"
        }
    }

    var short: String {
        switch self {
        case .html: return "HTML"
        case .css: return "CSS"
        case .javascript: return "JS"
        case .typescript: return "TS"
        case .python: return "PY"
        case .json: return "JSON"
        case .swift: return "SWIFT"
        case .svg: return "SVG"
        case .markdown: return "MD"
        case .xml: return "XML"
        case .text: return "TXT"
        }
    }

    var ext: String {
        switch self {
        case .html: return "html"
        case .css: return "css"
        case .javascript: return "js"
        case .typescript: return "ts"
        case .python: return "py"
        case .json: return "json"
        case .swift: return "swift"
        case .svg: return "svg"
        case .markdown: return "md"
        case .xml: return "xml"
        case .text: return "txt"
        }
    }

    /// Default file name used when a project is created from a single paste.
    var mainFileName: String {
        switch self {
        case .html: return "index.html"
        case .css: return "style.css"
        case .javascript: return "script.js"
        case .typescript: return "script.ts"
        case .python: return "main.py"
        case .json: return "data.json"
        case .swift: return "main.swift"
        case .svg: return "image.svg"
        case .markdown: return "README.md"
        case .xml: return "data.xml"
        case .text: return "notes.txt"
        }
    }

    /// Prefix used for auto-generated names (e.g. WebApp_19-11).
    var namePrefix: String {
        switch self {
        case .html: return "WebApp"
        case .css: return "Style"
        case .javascript: return "Script"
        case .typescript: return "Script"
        case .python: return "Python"
        case .json: return "Data"
        case .swift: return "Swift"
        case .svg: return "Image"
        case .markdown: return "Note"
        case .xml: return "XML"
        case .text: return "Text"
        }
    }

    var color: Color {
        switch self {
        case .html: return Color(red: 0.93, green: 0.42, blue: 0.24)
        case .css: return Color(red: 0.25, green: 0.52, blue: 0.96)
        case .javascript: return Color(red: 0.92, green: 0.75, blue: 0.10)
        case .typescript: return Color(red: 0.19, green: 0.47, blue: 0.78)
        case .python: return Color(red: 0.22, green: 0.62, blue: 0.48)
        case .json: return Color(red: 0.55, green: 0.45, blue: 0.85)
        case .swift: return Color(red: 0.98, green: 0.36, blue: 0.27)
        case .svg: return Color(red: 0.95, green: 0.55, blue: 0.20)
        case .markdown: return Color.gray
        case .xml: return Color(red: 0.40, green: 0.60, blue: 0.70)
        case .text: return Color.gray
        }
    }

    /// Whether the in-app preview can run/render this language.
    var isRunnable: Bool {
        switch self {
        case .html, .css, .javascript, .json, .svg, .markdown: return true
        default: return false
        }
    }

    static func from(fileName: String) -> CodeLanguage {
        let e = (fileName as NSString).pathExtension.lowercased()
        switch e {
        case "html", "htm": return .html
        case "css": return .css
        case "js", "mjs": return .javascript
        case "ts": return .typescript
        case "py": return .python
        case "json": return .json
        case "swift": return .swift
        case "svg": return .svg
        case "md", "markdown": return .markdown
        case "xml": return .xml
        default: return .text
        }
    }
}

// MARK: - Project index (lightweight list read by the widget and intents)

struct ProjectSummary: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var language: CodeLanguage
    var modified: Date
    var iconEmoji: String
    var iconColorHex: String
}

// MARK: - Live widget data written by the page (shaghil.widget({...})) or widget.js

struct WidgetItem: Codable, Hashable {
    var text: String
    var done: Bool
}

struct WidgetPayload: Codable, Hashable {
    var title: String?
    var value: String?
    var subtitle: String?
    var items: [WidgetItem]?
    var counter: Double?
    var step: Double?
    var updated: Date?
}

// MARK: - Shared storage

enum SharedStore {
    static var groupURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppInfo.appGroup)
    }

    /// Root folder holding all projects. Uses the App Group when the signer kept it,
    /// otherwise falls back to the app's Documents folder.
    static var rootURL: URL {
        let base: URL
        if let g = groupURL {
            base = g
        } else {
            base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        let url = base.appendingPathComponent("Shaghil", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var projectsURL: URL {
        let u = rootURL.appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static var widgetURL: URL {
        let u = rootURL.appendingPathComponent("Widget", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static var indexURL: URL { rootURL.appendingPathComponent("index.json") }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func loadIndex() -> [ProjectSummary] {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? decoder.decode([ProjectSummary].self, from: data) else { return [] }
        return list.sorted { $0.modified > $1.modified }
    }

    static func saveIndex(_ list: [ProjectSummary]) {
        if let data = try? encoder.encode(list) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    static func widgetPayload(for id: String) -> WidgetPayload? {
        let url = widgetURL.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(WidgetPayload.self, from: data)
    }

    static func saveWidgetPayload(_ p: WidgetPayload, for id: String) {
        let url = widgetURL.appendingPathComponent("\(id).json")
        if let data = try? encoder.encode(p) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func filesURL(for id: String) -> URL {
        projectsURL.appendingPathComponent(id, isDirectory: true).appendingPathComponent("files", isDirectory: true)
    }

    /// Reads widget.js from the project if present (used by the widget to compute a live value).
    static func widgetScript(for id: String) -> String? {
        let dir = filesURL(for: id)
        let candidates = ["widget.js"]
        for c in candidates {
            if let s = try? String(contentsOf: dir.appendingPathComponent(c), encoding: .utf8) { return s }
        }
        return nil
    }

    static func runURL(_ id: String) -> URL { URL(string: "\(AppInfo.scheme)://run/\(id)")! }
    static func openURL(_ id: String) -> URL { URL(string: "\(AppInfo.scheme)://open/\(id)")! }
    static var pasteURL: URL { URL(string: "\(AppInfo.scheme)://paste")! }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
