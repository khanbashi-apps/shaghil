import Foundation
import JavaScriptCore

/// Beautifies code offline using the bundled js-beautify (MIT).
final class CodeFormatter {
    static let shared = CodeFormatter()

    private lazy var context: JSContext? = {
        guard let ctx = JSContext() else { return nil }
        ctx.evaluateScript("var window = this; var global = this;")
        for name in ["beautify", "beautify-css", "beautify-html"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "js"),
               let src = try? String(contentsOf: url, encoding: .utf8) {
                ctx.evaluateScript(src)
            }
        }
        return ctx
    }()

    func format(_ code: String, language: CodeLanguage, indent: Int = 2) -> String {
        switch language {
        case .json:
            if let data = code.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
               let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes]),
               let s = String(data: out, encoding: .utf8) {
                // JSONSerialization uses 2-space indent already
                return s
            }
            return run("js_beautify", code, indent) ?? code
        case .javascript, .typescript:
            return run("js_beautify", code, indent) ?? code
        case .css:
            return run("css_beautify", code, indent) ?? code
        case .html, .svg, .xml:
            return run("html_beautify", code, indent) ?? code
        default:
            // Python / Swift / text: tidy trailing whitespace and blank-line runs only
            let lines = code.components(separatedBy: "\n").map { line -> String in
                var l = line
                while l.last == " " || l.last == "\t" { l.removeLast() }
                return l.replacingOccurrences(of: "\t", with: String(repeating: " ", count: 4))
            }
            var out: [String] = []
            for l in lines {
                if l.isEmpty, let last = out.last, last.isEmpty, out.count > 1, out[out.count - 2].isEmpty { continue }
                out.append(l)
            }
            return out.joined(separator: "\n")
        }
    }

    private func run(_ fn: String, _ code: String, _ indent: Int) -> String? {
        guard let ctx = context, let f = ctx.objectForKeyedSubscript(fn), !f.isUndefined else { return nil }
        let opts: [String: Any] = [
            "indent_size": indent,
            "end_with_newline": false,
            "preserve_newlines": true,
            "max_preserve_newlines": 2,
            "wrap_line_length": 0,
            "indent_inner_html": true,
            "extra_liners": [String]()
        ]
        let r = f.call(withArguments: [code, opts])
        guard let s = r?.toString(), r?.isString == true else { return nil }
        return s
    }
}
