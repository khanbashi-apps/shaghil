import UIKit

/// Lightweight regex-based syntax highlighter.
struct SyntaxHighlighter {
    var language: CodeLanguage
    var fontSize: CGFloat

    private static func dyn(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) }
    }

    static let plain = UIColor.label
    static let keyword = dyn(0xAD3DA4, 0xFF7AB2)
    static let string = dyn(0xC41A16, 0xFC6A5D)
    static let number = dyn(0x1C00CF, 0xD9C97C)
    static let comment = dyn(0x5D6C79, 0x7F8C98)
    static let tag = dyn(0x0B4F79, 0x5DD8FF)
    static let attr = dyn(0x815F03, 0xFFA14F)
    static let function = dyn(0x326D74, 0x67B7A4)
    static let type = dyn(0x3900A0, 0xD0A8FF)

    var font: UIFont { .monospacedSystemFont(ofSize: fontSize, weight: .regular) }

    static var paragraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.baseWritingDirection = .leftToRight
        p.alignment = .left
        p.lineSpacing = 2
        return p
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: Self.plain, .paragraphStyle: Self.paragraph]
    }

    private struct Rule {
        let re: NSRegularExpression
        let color: UIColor
        let group: Int
        init(_ pattern: String, _ color: UIColor, group: Int = 0, options: NSRegularExpression.Options = []) {
            self.re = try! NSRegularExpression(pattern: pattern, options: options)
            self.color = color
            self.group = group
        }
    }

    private static let jsKeywords = "break|case|catch|class|const|continue|debugger|default|delete|do|else|export|extends|finally|for|from|function|if|import|in|instanceof|let|new|return|super|switch|this|throw|try|typeof|var|void|while|with|yield|async|await|of|true|false|null|undefined|static|get|set|interface|type|implements|enum|as"
    private static let pyKeywords = "and|as|assert|async|await|break|class|continue|def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|nonlocal|not|or|pass|raise|return|try|while|with|yield|True|False|None|self|print"
    private static let swiftKeywords = "associatedtype|class|deinit|enum|extension|fileprivate|func|import|init|inout|internal|let|open|operator|private|protocol|public|static|struct|subscript|typealias|var|break|case|continue|default|defer|do|else|fallthrough|for|guard|if|in|repeat|return|switch|where|while|as|catch|false|is|nil|self|Self|super|throw|throws|true|try|some|any|async|await|actor|override|mutating|weak|lazy|final|@State|@Binding|@Published|@ObservedObject|@StateObject|@Environment|@MainActor"

    private static var cache: [CodeLanguage: [Rule]] = [:]

    private static func rules(for lang: CodeLanguage) -> [Rule] {
        if let r = cache[lang] { return r }
        var r: [Rule] = []
        let num = Rule(#"\b(0x[0-9a-fA-F]+|\d+(\.\d+)?)\b"#, number)
        let dq = Rule(#""(?:[^"\\\n]|\\.)*""#, string)
        let sq = Rule(#"'(?:[^'\\\n]|\\.)*'"#, string)
        let bt = Rule(#"`(?:[^`\\]|\\.)*`"#, string)
        let call = Rule(#"\b([A-Za-z_$][\w$]*)\s*(?=\()"#, function, group: 1)
        let typeR = Rule(#"\b[A-Z][A-Za-z0-9_]*\b"#, type)
        let lineC = Rule(#"//[^\n]*"#, comment)
        let blockC = Rule(#"/\*[\s\S]*?\*/"#, comment)

        switch lang {
        case .javascript, .typescript, .json:
            r = [typeR, call, Rule("\\b(\(jsKeywords))\\b", keyword), num, dq, sq, bt, lineC, blockC]
            if lang == .json { r = [num, Rule(#"\b(true|false|null)\b"#, keyword), dq, Rule(#""(?:[^"\\\n]|\\.)*"(?=\s*:)"#, attr)] }
        case .python:
            r = [typeR, call, Rule("\\b(\(pyKeywords))\\b", keyword), Rule(#"@\w+"#, attr), num, dq, sq,
                 Rule(#"(\"\"\"|''')[\s\S]*?\1"#, string), Rule(#"#[^\n]*"#, comment)]
        case .swift:
            r = [typeR, call, Rule("(?<![\\w@])(\(swiftKeywords))\\b", keyword), Rule(#"@\w+"#, keyword), num, dq, lineC, blockC]
        case .css:
            r = [Rule(#"(?m)^[^{}\n]+(?=\{)"#, tag),
                 Rule(#"([\w-]+)\s*(?=:[^;{}]*;)"#, attr, group: 1),
                 Rule(#"#[0-9a-fA-F]{3,8}\b"#, number),
                 Rule(#"\b\d+(\.\d+)?(px|em|rem|%|vh|vw|s|ms|deg|fr)?\b"#, number),
                 Rule(#"@[\w-]+"#, keyword),
                 Rule(#"!important"#, keyword),
                 dq, sq, blockC]
        case .html, .svg, .xml:
            r = [Rule(#"</?[A-Za-z][\w:-]*"#, tag), Rule(#"/?>"#, tag),
                 Rule(#"\s([A-Za-z_:][\w:.-]*)(?=\s*=)"#, attr, group: 1),
                 dq, sq,
                 Rule(#"<!DOCTYPE[^>]*>"#, comment, options: [.caseInsensitive]),
                 Rule(#"<!--[\s\S]*?-->"#, comment)]
        case .markdown:
            r = [Rule(#"(?m)^#{1,6}\s.*$"#, keyword), Rule(#"\*\*[^*\n]+\*\*"#, tag), Rule(#"`[^`\n]+`"#, string),
                 Rule(#"(?m)^\s*([-*+]|\d+\.)\s"#, attr), Rule(#"\[[^\]]*\]\([^)]*\)"#, function)]
        case .text:
            r = []
        }
        cache[lang] = r
        return r
    }

    /// Embedded <style>/<script> blocks in HTML get CSS/JS colouring.
    private static let styleBlock = try! NSRegularExpression(pattern: #"(?is)<style[^>]*>(.*?)</style>"#)
    private static let scriptBlock = try! NSRegularExpression(pattern: #"(?is)<script[^>]*>(.*?)</script>"#)

    func highlight(_ storage: NSTextStorage) {
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: full)
        if storage.length < 300_000 {
            let text = storage.string
            apply(Self.rules(for: language), to: storage, text: text, in: full)
            if language == .html {
                for (re, lang) in [(Self.styleBlock, CodeLanguage.css), (Self.scriptBlock, CodeLanguage.javascript)] {
                    for m in re.matches(in: text, range: full) {
                        let inner = m.range(at: 1)
                        guard inner.location != NSNotFound, inner.length > 0 else { continue }
                        storage.addAttribute(.foregroundColor, value: Self.plain, range: inner)
                        apply(Self.rules(for: lang), to: storage, text: text, in: inner)
                    }
                }
            }
        }
        storage.endEditing()
    }

    private func apply(_ rules: [Rule], to storage: NSTextStorage, text: String, in range: NSRange) {
        for rule in rules {
            for m in rule.re.matches(in: text, range: range) {
                let rr = m.range(at: rule.group)
                if rr.location != NSNotFound, rr.length > 0 {
                    storage.addAttribute(.foregroundColor, value: rule.color, range: rr)
                }
            }
        }
    }

    static func keywords(for lang: CodeLanguage) -> [String] {
        switch lang {
        case .javascript, .typescript:
            return jsKeywords.components(separatedBy: "|") + ["console.log", "document.querySelector", "addEventListener", "localStorage", "getElementById", "setTimeout", "setInterval", "JSON.stringify", "JSON.parse", "innerHTML", "textContent", "classList", "forEach", "map", "filter", "reduce", "Promise", "fetch"]
        case .python:
            return pyKeywords.components(separatedBy: "|") + ["range", "len", "input", "list", "dict", "enumerate", "append", "return"]
        case .swift:
            return swiftKeywords.components(separatedBy: "|") + ["VStack", "HStack", "ZStack", "Text", "Button", "Image", "padding", "foregroundStyle", "String", "Int", "Double", "Bool"]
        case .css:
            return ["display", "flex", "grid", "position", "absolute", "relative", "background", "background-color", "color", "margin", "padding", "border", "border-radius", "font-size", "font-weight", "font-family", "width", "height", "justify-content", "align-items", "gap", "transition", "transform", "box-shadow", "opacity", "center", "none", "auto", "important"]
        case .html, .svg:
            return ["div", "span", "section", "button", "input", "script", "style", "class", "href", "src", "title", "head", "body", "html", "meta", "link", "header", "footer", "main", "canvas", "viewport", "charset"]
        default:
            return []
        }
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
