import Foundation

/// Detects the language of pasted code and suggests a file/project name.
enum Detector {

    static func detect(_ raw: String) -> CodeLanguage {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return .text }
        let head = String(code.prefix(4000))
        let lower = head.lowercased()

        // Markup
        if lower.hasPrefix("<!doctype html") || lower.contains("<html") || lower.contains("<body") || lower.contains("<head") {
            return .html
        }
        if lower.hasPrefix("<svg") || (lower.hasPrefix("<?xml") && lower.contains("<svg")) { return .svg }
        if lower.hasPrefix("<?xml") { return .xml }
        if code.hasPrefix("<") && matches(head, #"<(div|section|main|p|h[1-6]|button|canvas|script|style|span|ul|table|form|img|a|input|nav|header|footer)[\s>/]"#) {
            return .html
        }

        // JSON
        if (code.hasPrefix("{") || code.hasPrefix("[")),
           let data = code.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil {
            return .json
        }

        // Swift
        if matches(head, #"(?m)^\s*import\s+(SwiftUI|UIKit|Foundation|WidgetKit|Combine|AppIntents)\b"#)
            || head.contains("some View") || matches(head, #"(?m)^\s*(struct|class|enum)\s+\w+\s*:\s*(View|App|ObservableObject)"#)
            || matches(head, #"(?m)^\s*(let|var)\s+\w+\s*:\s*[A-Z]\w*(\?|\s*=)"#) && head.contains("func ") {
            return .swift
        }

        // Python
        var py = 0
        if matches(head, #"(?m)^\s*def\s+\w+\s*\(.*\)\s*(->\s*[\w\[\], ]+)?\s*:\s*$"#) { py += 3 }
        if matches(head, #"(?m)^\s*(from\s+[\w.]+\s+import\s+|import\s+[\w.]+\s*$)"#) { py += 2 }
        if head.contains("if __name__") { py += 3 }
        if matches(head, #"(?m)^\s*(elif|except|try)\b.*:\s*$"#) { py += 2 }
        if matches(head, #"(?m)^\s*print\s*\("#) && !head.contains(";") { py += 1 }
        if matches(head, #"(?m)^\s*class\s+\w+(\(.*\))?\s*:\s*$"#) { py += 2 }
        if head.contains("self.") { py += 1 }

        // JavaScript / TypeScript
        var js = 0
        if matches(head, #"\b(const|let|var)\s+\w+\s*="#) { js += 2 }
        if matches(head, #"\bfunction\s*\w*\s*\("#) { js += 2 }
        if head.contains("=>") { js += 1 }
        if matches(head, #"\b(console\.|document\.|window\.|addEventListener|querySelector|require\(|module\.exports|export\s+(default|const|function))"#) { js += 3 }
        if head.contains(";") { js += 1 }
        if matches(head, #"(?m)^\s*import\s+.+\s+from\s+['"]"#) { js += 3 }
        let ts = matches(head, #"\b(interface\s+\w+\s*\{|type\s+\w+\s*=|:\s*(string|number|boolean)\b)"#)

        // CSS
        var css = 0
        if matches(head, #"(?m)^\s*[.#]?[a-zA-Z*:\[][\w\-\s.#:,>+~\[\]="()*]*\{\s*$"#) { css += 2 }
        if matches(head, #"(?m)^\s*[\w-]+\s*:\s*[^;{}]+;\s*$"#) { css += 2 }
        if matches(head, #"@(media|import|keyframes|font-face)|:root\s*\{"#) { css += 3 }
        if js >= 2 { css -= 2 }

        if py >= 3 && py > js { return .python }
        if js >= 3 || (js >= 2 && js >= css) { return ts ? .typescript : .javascript }
        if css >= 3 { return .css }
        if py >= 2 { return .python }

        // Markdown
        if matches(head, #"(?m)^#{1,6}\s+\S"#) || matches(head, #"(?m)^(\*|-)\s+\S"#) && head.contains("**") {
            return .markdown
        }
        if js >= 1 { return .javascript }
        return .text
    }

    // MARK: naming

    static func suggestName(for raw: String, language: CodeLanguage) -> String {
        let code = String(raw.prefix(6000))
        var found: String?
        switch language {
        case .html:
            found = capture(code, #"(?is)<title[^>]*>(.*?)</title>"#)
                ?? capture(code, #"(?is)<h1[^>]*>(.*?)</h1>"#).map(stripTags)
        case .svg:
            found = capture(code, #"(?is)<title[^>]*>(.*?)</title>"#)
        case .javascript, .typescript:
            found = topComment(code, style: .c)
                ?? capture(code, #"\bclass\s+([A-Za-z_]\w*)"#)
                ?? capture(code, #"\bfunction\s+([A-Za-z_$][\w$]*)"#)
                ?? capture(code, #"\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?(?:\(|function)"#)
        case .css:
            found = topComment(code, style: .c)
        case .python:
            found = topComment(code, style: .hash)
                ?? capture(code, #"(?s)^\s*(?:\"\"\"|''')\s*(.+?)(?:\n|\"\"\"|''')"#)
                ?? capture(code, #"(?m)^\s*class\s+([A-Za-z_]\w*)"#)
                ?? capture(code, #"(?m)^\s*def\s+([A-Za-z_]\w*)"#)
        case .swift:
            found = topComment(code, style: .c)
                ?? capture(code, #"\b(?:struct|class|enum|actor)\s+([A-Za-z_]\w*)"#)
                ?? capture(code, #"\bfunc\s+([A-Za-z_]\w*)"#)
        case .markdown:
            found = capture(code, #"(?m)^#{1,6}\s+(.+)$"#)
        case .json:
            found = capture(code, #""(?:name|title)"\s*:\s*"([^"]{1,60})""#)
        default:
            found = nil
        }
        if let f = found.map(clean), !f.isEmpty {
            return String(f.prefix(40))
        }
        return defaultName(language)
    }

    static func defaultName(_ language: CodeLanguage) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd-MM"
        return "\(language.namePrefix)_\(f.string(from: Date()))"
    }

    // MARK: helpers

    private enum CommentStyle { case c, hash }

    private static func topComment(_ code: String, style: CommentStyle) -> String? {
        let lines = code.components(separatedBy: .newlines).prefix(8)
        for raw in lines {
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.isEmpty { continue }
            if l.hasPrefix("#!") || l.lowercased().contains("coding:") || l.hasPrefix("\"use strict") || l.hasPrefix("'use strict") { continue }
            switch style {
            case .c:
                if l.hasPrefix("//") {
                    return meaningful(String(l.dropFirst(2)))
                }
                if l.hasPrefix("/*") {
                    var s = String(l.dropFirst(2))
                    if let r = s.range(of: "*/") { s = String(s[..<r.lowerBound]) }
                    let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "* ").union(.whitespaces))
                    if t.isEmpty, let inner = capture(code, #"(?s)/\*+\s*\*?\s*([^\n*][^\n]*)"#) { return meaningful(inner) }
                    return meaningful(t)
                }
                return nil
            case .hash:
                if l.hasPrefix("#") {
                    return meaningful(String(l.drop(while: { $0 == "#" })))
                }
                return nil
            }
        }
        return nil
    }

    private static func meaningful(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "*-=/#: ").union(.whitespaces))
        if t.count < 2 { return nil }
        let lower = t.lowercased()
        if lower.hasPrefix("eslint") || lower.hasPrefix("@ts-") || lower.hasPrefix("prettier") || lower.hasPrefix("swift-tools") || lower.hasPrefix("copyright") { return nil }
        return t
    }

    private static func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }

    private static func clean(_ s: String) -> String {
        var t = stripTags(s)
        t = t.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&nbsp;", with: " ")
        t = t.replacingOccurrences(of: #"[\\/:*?"<>|\n\r\t]"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func matches(_ s: String, _ pattern: String) -> Bool {
        s.range(of: pattern, options: .regularExpression) != nil
    }

    static func capture(_ s: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
        let r = m.range(at: 1)
        guard r.location != NSNotFound else { return nil }
        let v = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }
}
