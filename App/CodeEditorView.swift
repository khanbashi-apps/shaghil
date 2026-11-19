import SwiftUI
import UIKit

/// Holds a reference to the live UITextView so SwiftUI toolbars can drive it.
final class EditorController: ObservableObject {
    weak var textView: UITextView?
    @Published var matchInfo: String = ""

    var text: String { textView?.text ?? "" }

    func insert(_ s: String) {
        guard let tv = textView else { return }
        tv.insertText(s)
    }

    func undo() { textView?.undoManager?.undo() }
    func redo() { textView?.undoManager?.redo() }

    // MARK: find & replace

    private func options(_ caseSensitive: Bool) -> NSString.CompareOptions {
        caseSensitive ? [] : [.caseInsensitive]
    }

    func count(_ query: String, caseSensitive: Bool) -> Int {
        guard !query.isEmpty, let t = textView?.text else { return 0 }
        var c = 0
        var r = t.startIndex..<t.endIndex
        while let f = t.range(of: query, options: options(caseSensitive), range: r) {
            c += 1
            r = f.upperBound..<t.endIndex
            if f.isEmpty { break }
        }
        return c
    }

    @discardableResult
    func findNext(_ query: String, caseSensitive: Bool, backwards: Bool = false) -> Bool {
        guard let tv = textView, !query.isEmpty else { return false }
        let ns = tv.text as NSString
        let sel = tv.selectedRange
        var opts: NSString.CompareOptions = options(caseSensitive)
        var found: NSRange
        if backwards {
            opts.insert(.backwards)
            found = ns.range(of: query, options: opts, range: NSRange(location: 0, length: sel.location))
            if found.location == NSNotFound { found = ns.range(of: query, options: opts) }
        } else {
            let start = sel.location + sel.length
            found = ns.range(of: query, options: opts, range: NSRange(location: start, length: ns.length - start))
            if found.location == NSNotFound { found = ns.range(of: query, options: opts) }
        }
        guard found.location != NSNotFound else { matchInfo = "لا نتائج"; return false }
        tv.selectedRange = found
        tv.scrollRangeToVisible(found)
        tv.flashScrollIndicators()
        let total = count(query, caseSensitive: caseSensitive)
        let before = ns.substring(to: found.location)
        let idx = (before as NSString).components(separatedBy: query).count
        matchInfo = "\(min(idx, total)) / \(total)"
        return true
    }

    func replaceCurrent(_ query: String, with replacement: String, caseSensitive: Bool) {
        guard let tv = textView, !query.isEmpty else { return }
        let ns = tv.text as NSString
        let sel = tv.selectedRange
        if sel.length > 0, ns.substring(with: sel).compare(query, options: options(caseSensitive)) == .orderedSame,
           let range = Range(sel, in: tv.text), let start = tv.position(from: tv.beginningOfDocument, offset: sel.location),
           let end = tv.position(from: start, offset: sel.length), let tr = tv.textRange(from: start, to: end) {
            _ = range
            tv.replace(tr, withText: replacement)
        }
        findNext(query, caseSensitive: caseSensitive)
    }

    func replaceAll(_ query: String, with replacement: String, caseSensitive: Bool) -> Int {
        guard let tv = textView, !query.isEmpty else { return 0 }
        let n = count(query, caseSensitive: caseSensitive)
        guard n > 0 else { return 0 }
        let newText = tv.text.replacingOccurrences(of: query, with: replacement, options: options(caseSensitive))
        let all = tv.textRange(from: tv.beginningOfDocument, to: tv.endOfDocument)!
        tv.replace(all, withText: newText)
        matchInfo = "تم استبدال \(n)"
        return n
    }
}

struct CodeEditorView: UIViewRepresentable {
    @Binding var text: String
    var language: CodeLanguage
    var fontSize: CGFloat
    var controller: EditorController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.spellCheckingType = .no
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no
        tv.keyboardType = .asciiCapable
        tv.keyboardDismissMode = .interactive
        tv.alwaysBounceVertical = true
        tv.semanticContentAttribute = .forceLeftToRight
        tv.textAlignment = .left
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 80, right: 10)
        tv.inputAccessoryView = context.coordinator.makeAccessory()
        tv.text = text
        context.coordinator.highlighter = SyntaxHighlighter(language: language, fontSize: fontSize)
        context.coordinator.rehighlight(tv)
        controller.textView = tv
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        let c = context.coordinator
        c.parent = self
        controller.textView = tv
        var needs = false
        if c.highlighter.language != language || c.highlighter.fontSize != fontSize {
            c.highlighter = SyntaxHighlighter(language: language, fontSize: fontSize)
            needs = true
        }
        if tv.text != text {
            let sel = tv.selectedRange
            tv.text = text
            let len = (text as NSString).length
            tv.selectedRange = NSRange(location: min(sel.location, len), length: 0)
            needs = true
        }
        if needs { c.rehighlight(tv) }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CodeEditorView
        var highlighter: SyntaxHighlighter
        private var pending: DispatchWorkItem?
        private var suggestionStack: UIStackView?
        private var currentPrefix = ""
        private var inserting = false

        private func ins(_ tv: UITextView, _ s: String) {
            inserting = true
            tv.insertText(s)
            inserting = false
        }

        init(_ p: CodeEditorView) {
            parent = p
            highlighter = SyntaxHighlighter(language: p.language, fontSize: p.fontSize)
        }

        func rehighlight(_ tv: UITextView) {
            let sel = tv.selectedRange
            highlighter.highlight(tv.textStorage)
            tv.typingAttributes = highlighter.baseAttributes
            tv.selectedRange = sel
        }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            pending?.cancel()
            let w = DispatchWorkItem { [weak self, weak tv] in
                guard let self, let tv else { return }
                self.rehighlight(tv)
            }
            pending = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: w)
            updateSuggestions(tv)
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            updateSuggestions(tv)
        }

        // Auto-pairs and auto-indent
        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText s: String) -> Bool {
            if inserting { return true }
            let ns = tv.text as NSString
            let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`"]
            if s == "\n" {
                let lineRange = ns.lineRange(for: NSRange(location: range.location, length: 0))
                let line = ns.substring(with: NSRange(location: lineRange.location, length: range.location - lineRange.location))
                let indent = String(line.prefix { $0 == " " || $0 == "\t" })
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let opens = trimmed.hasSuffix("{") || trimmed.hasSuffix("[") || trimmed.hasSuffix("(") || trimmed.hasSuffix(":") && parent.language == .python
                    || (parent.language == .html && trimmed.hasSuffix(">") && !trimmed.hasPrefix("</") && !trimmed.hasSuffix("/>") && !trimmed.contains("</"))
                let next = range.location < ns.length ? ns.substring(with: NSRange(location: range.location, length: 1)) : ""
                if opens && (next == "}" || next == "]" || next == ")") {
                    ins(tv, "\n" + indent + "  " + "\n" + indent)
                    if let pos = tv.position(from: tv.beginningOfDocument, offset: range.location + 1 + indent.count + 2) {
                        tv.selectedTextRange = tv.textRange(from: pos, to: pos)
                    }
                    return false
                }
                ins(tv, "\n" + indent + (opens ? "  " : ""))
                return false
            }
            if range.length == 0, let close = pairs[s] {
                let next = range.location < ns.length ? ns.substring(with: NSRange(location: range.location, length: 1)) : ""
                if (s == "\"" || s == "'" || s == "`") && next == s {
                    moveCursor(tv, by: 1); return false
                }
                if next.isEmpty || next == " " || next == "\n" || [")", "]", "}", ";", ","].contains(next) {
                    if (s == "'" ) && range.location > 0 {
                        let prev = ns.substring(with: NSRange(location: range.location - 1, length: 1))
                        if prev.rangeOfCharacter(from: .alphanumerics) != nil { return true }
                    }
                    ins(tv, s + close)
                    moveCursor(tv, by: -1)
                    return false
                }
            }
            if range.length == 0, [")", "]", "}"].contains(s), range.location < ns.length,
               ns.substring(with: NSRange(location: range.location, length: 1)) == s {
                moveCursor(tv, by: 1); return false
            }
            return true
        }

        private func moveCursor(_ tv: UITextView, by n: Int) {
            guard let cur = tv.selectedTextRange?.start,
                  let p = tv.position(from: cur, offset: n) else { return }
            tv.selectedTextRange = tv.textRange(from: p, to: p)
        }

        // MARK: accessory bar

        func makeAccessory() -> UIView {
            let bar = UIInputView(frame: CGRect(x: 0, y: 0, width: 320, height: 46), inputViewStyle: .keyboard)
            bar.autoresizingMask = .flexibleWidth
            let scroll = UIScrollView()
            scroll.showsHorizontalScrollIndicator = false
            scroll.translatesAutoresizingMaskIntoConstraints = false
            scroll.semanticContentAttribute = .forceLeftToRight
            bar.addSubview(scroll)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: bar.topAnchor),
                scroll.bottomAnchor.constraint(equalTo: bar.bottomAnchor)
            ])
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 6
            row.semanticContentAttribute = .forceLeftToRight
            row.translatesAutoresizingMaskIntoConstraints = false
            scroll.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
                row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
                row.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
                row.heightAnchor.constraint(equalToConstant: 34)
            ])

            let sug = UIStackView()
            sug.axis = .horizontal
            sug.spacing = 6
            sug.semanticContentAttribute = .forceLeftToRight
            suggestionStack = sug
            row.addArrangedSubview(sug)

            let tools: [(String, String)] = [("⇥", "  "), ("↶", "#undo"), ("↷", "#redo")]
            let symbols = ["{ }", "< >", "( )", "[ ]", ";", "=", "\" \"", "' '", "/", ":", ".", ",", "=>", "</", "#", "$", "!", "&", "|", "+", "-", "*", "%", "_", "?", "`"]
            for (t, v) in tools { row.addArrangedSubview(button(t, value: v, tint: true)) }
            for s in symbols {
                let v: String
                switch s {
                case "{ }": v = "{}"
                case "< >": v = "<>"
                case "( )": v = "()"
                case "[ ]": v = "[]"
                case "\" \"": v = "\"\""
                case "' '": v = "''"
                default: v = s
                }
                row.addArrangedSubview(button(s, value: v, tint: false))
            }
            row.addArrangedSubview(button("⌄", value: "#hide", tint: true))
            return bar
        }

        private func button(_ title: String, value: String, tint: Bool, suggestion: Bool = false) -> UIButton {
            var cfg = UIButton.Configuration.filled()
            cfg.title = title
            cfg.baseBackgroundColor = suggestion ? UIColor.tintColor.withAlphaComponent(0.18) : (tint ? .tertiarySystemFill : .secondarySystemBackground)
            cfg.baseForegroundColor = suggestion ? .tintColor : .label
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 11, bottom: 4, trailing: 11)
            cfg.cornerStyle = .medium
            cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
                var a = a
                a.font = UIFont.monospacedSystemFont(ofSize: 16, weight: suggestion ? .semibold : .medium)
                return a
            }
            let b = UIButton(configuration: cfg)
            b.addAction(UIAction { [weak self] _ in self?.tap(value, suggestion: suggestion) }, for: .touchUpInside)
            return b
        }

        private func tap(_ v: String, suggestion: Bool) {
            guard let tv = parent.controller.textView else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if suggestion {
                for _ in 0..<currentPrefix.count { tv.deleteBackward() }
                ins(tv, v)
                return
            }
            switch v {
            case "#undo": tv.undoManager?.undo()
            case "#redo": tv.undoManager?.redo()
            case "#hide": tv.resignFirstResponder()
            case "{}", "<>", "()", "[]", "\"\"", "''":
                ins(tv, v)
                moveCursor(tv, by: -1)
            default:
                ins(tv, v)
            }
        }

        private func updateSuggestions(_ tv: UITextView) {
            guard let stack = suggestionStack else { return }
            let ns = tv.text as NSString
            let loc = tv.selectedRange.location
            var start = loc
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-$.@"))
            while start > 0 {
                let ch = ns.substring(with: NSRange(location: start - 1, length: 1))
                if ch.rangeOfCharacter(from: allowed.inverted) != nil { break }
                start -= 1
            }
            let prefix = loc > start ? ns.substring(with: NSRange(location: start, length: loc - start)) : ""
            currentPrefix = prefix
            stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            guard prefix.count >= 2 else { return }
            var pool = SyntaxHighlighter.keywords(for: parent.language)
            if ns.length < 200_000, let re = try? NSRegularExpression(pattern: #"[A-Za-z_$][\w$-]{2,}"#) {
                let words = re.matches(in: tv.text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
                pool += words
            }
            var seen = Set<String>()
            let lp = prefix.lowercased()
            let matches = pool.filter { w in
                let l = w.lowercased()
                guard l.hasPrefix(lp), l != lp, !seen.contains(w) else { return false }
                seen.insert(w); return true
            }.sorted { $0.count < $1.count }.prefix(4)
            for m in matches {
                stack.addArrangedSubview(button(m, value: m, tint: false, suggestion: true))
            }
        }
    }
}
