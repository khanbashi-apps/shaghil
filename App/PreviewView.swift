import SwiftUI
import WebKit

struct ConsoleEntry: Identifiable, Hashable {
    let id = UUID()
    let level: String
    let message: String
    let time = Date()

    var color: Color {
        switch level {
        case "error": return .red
        case "warn": return .orange
        case "info": return .blue
        default: return .primary
        }
    }

    var icon: String {
        switch level {
        case "error": return "xmark.octagon.fill"
        case "warn": return "exclamationmark.triangle.fill"
        case "info": return "info.circle.fill"
        default: return "chevron.right"
        }
    }
}

final class ConsoleModel: ObservableObject {
    @Published var entries: [ConsoleEntry] = []
    var errorCount: Int { entries.filter { $0.level == "error" }.count }

    func add(_ level: String, _ msg: String) {
        entries.append(ConsoleEntry(level: level, message: msg))
        if entries.count > 500 { entries.removeFirst(entries.count - 500) }
    }

    func clear() { entries.removeAll() }

    var allText: String {
        entries.map { "[\($0.level)] \($0.message)" }.joined(separator: "\n")
    }
}

/// WKWebView that runs a project from the local scheme handler.
struct ProjectWebView: UIViewRepresentable {
    let projectID: String
    let reloadToken: UUID
    var console: ConsoleModel?

    func makeCoordinator() -> Coordinator { Coordinator(projectID: projectID, console: console) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(RunSchemeHandler.shared, forURLScheme: RunSchemeHandler.scheme)
        cfg.websiteDataStore = .default()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true
        let ucc = WKUserContentController()
        let proxy = WeakMessageProxy(context.coordinator)
        ucc.add(proxy, name: "console")
        ucc.add(proxy, name: "widget")
        let state = ProjectStore.shared.widgetStateJSON(for: projectID)
        ucc.addUserScript(WKUserScript(source: Runner.bridgeScript(stateJSON: state), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController = ucc
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .systemBackground
        wv.scrollView.contentInsetAdjustmentBehavior = .automatic
        wv.allowsBackForwardNavigationGestures = false
        if #available(iOS 16.4, *) { wv.isInspectable = true }
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        context.coordinator.token = reloadToken
        NSLog("SHAGHIL webview make \(projectID)")
        wv.load(URLRequest(url: RunSchemeHandler.entryURL(projectID)))
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        context.coordinator.console = console
        if context.coordinator.token != reloadToken {
            context.coordinator.token = reloadToken
            wv.load(URLRequest(url: RunSchemeHandler.entryURL(projectID)))
        }
    }

    static func dismantleUIView(_ wv: WKWebView, coordinator: Coordinator) {
        wv.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        let projectID: String
        var console: ConsoleModel?
        var token = UUID()

        init(projectID: String, console: ConsoleModel?) {
            self.projectID = projectID
            self.console = console
        }

        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "console":
                if let d = message.body as? [String: Any] {
                    let level = d["level"] as? String ?? "log"
                    let msg = d["msg"] as? String ?? ""
                    DispatchQueue.main.async { self.console?.add(level, msg) }
                }
            case "widget":
                if let d = message.body as? [String: Any] {
                    ProjectStore.shared.saveWidgetData(d, for: projectID)
                    DispatchQueue.main.async { self.console?.add("info", "تم تحديث بيانات الويدجت ✓") }
                }
            default: break
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            NSLog("SHAGHIL didFail \(error)")
            console?.add("error", error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NSLog("SHAGHIL didFailProvisional \(error)")
            console?.add("error", error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            NSLog("SHAGHIL didFinish \(webView.url?.absoluteString ?? "")")
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            NSLog("SHAGHIL content process terminated — reloading")
            webView.reload()
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = action.request.url, let s = url.scheme?.lowercased(),
               ["http", "https", "mailto", "tel", "sms"].contains(s), action.navigationType == .linkActivated {
                UIApplication.shared.open(url)
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }

        // JS alert / confirm / prompt support
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            present(webView, title: message, actions: [("حسناً", .default, { completionHandler() })])
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            present(webView, title: message, actions: [("إلغاء", .cancel, { completionHandler(false) }), ("موافق", .default, { completionHandler(true) })])
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let ac = UIAlertController(title: prompt, message: nil, preferredStyle: .alert)
            ac.addTextField { $0.text = defaultText }
            ac.addAction(UIAlertAction(title: "إلغاء", style: .cancel) { _ in completionHandler(nil) })
            ac.addAction(UIAlertAction(title: "موافق", style: .default) { _ in completionHandler(ac.textFields?.first?.text) })
            topController(webView)?.present(ac, animated: true) ?? completionHandler(nil)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                if url.scheme == RunSchemeHandler.scheme { webView.load(navigationAction.request) } else { UIApplication.shared.open(url) }
            }
            return nil
        }

        private func present(_ wv: WKWebView, title: String, actions: [(String, UIAlertAction.Style, () -> Void)]) {
            let ac = UIAlertController(title: nil, message: title, preferredStyle: .alert)
            for a in actions { ac.addAction(UIAlertAction(title: a.0, style: a.1) { _ in a.2() }) }
            if let top = topController(wv) { top.present(ac, animated: true) } else { actions.last?.2() }
        }

        private func topController(_ v: UIView) -> UIViewController? {
            var vc = v.window?.rootViewController
            while let p = vc?.presentedViewController { vc = p }
            return vc
        }
    }
}

/// Avoids the retain cycle between WKUserContentController and its handler.
final class WeakMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(ucc, didReceive: message)
    }
}

// MARK: - Viewport

enum ViewportMode: String, CaseIterable, Identifiable {
    case fit, phone, tablet, desktop
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .fit: return "arrow.up.left.and.arrow.down.right"
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .desktop: return "desktopcomputer"
        }
    }
    var title: String {
        switch self {
        case .fit: return "ملء"
        case .phone: return "آيفون"
        case .tablet: return "آيباد"
        case .desktop: return "كمبيوتر"
        }
    }
    var size: CGSize? {
        switch self {
        case .fit: return nil
        case .phone: return CGSize(width: 390, height: 844)
        case .tablet: return CGSize(width: 820, height: 1180)
        case .desktop: return CGSize(width: 1440, height: 900)
        }
    }
}

// MARK: - Preview screen (inside the project)

struct PreviewPane: View {
    let project: Project
    let reloadToken: UUID
    @ObservedObject var console: ConsoleModel
    @State private var mode: ViewportMode = .fit
    @State private var landscape = false
    @State private var consoleOpen = false
    @State private var consoleHeight: CGFloat = 220

    var body: some View {
        VStack(spacing: 0) {
            if project.language.isRunnable || project.files.contains("index.html") {
                viewportBar
                GeometryReader { geo in
                    stage(in: geo.size)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .background(Color(uiColor: .secondarySystemBackground))
                consolePanel
            } else {
                notRunnable
            }
        }
    }

    private var viewportBar: some View {
        HStack(spacing: 6) {
            ForEach(ViewportMode.allCases) { m in
                Button {
                    withAnimation(.snappy) { mode = m }
                } label: {
                    Image(systemName: m.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 40, height: 32)
                        .background(mode == m ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        .foregroundStyle(mode == m ? Color.accentColor : .secondary)
                }
                .accessibilityLabel(m.title)
            }
            Button {
                withAnimation(.snappy) { landscape.toggle() }
            } label: {
                Image(systemName: "rotate.right")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 32)
                    .foregroundStyle(mode == .fit ? Color.secondary.opacity(0.4) : (landscape ? Color.accentColor : .secondary))
            }
            .disabled(mode == .fit)
            Spacer()
            if let s = mode.size {
                let w = Int(landscape ? s.height : s.width), h = Int(landscape ? s.width : s.height)
                Text("\(w)×\(h)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .environment(\.layoutDirection, .leftToRight)
    }

    @ViewBuilder
    private func stage(in avail: CGSize) -> some View {
        let web = ProjectWebView(projectID: project.id, reloadToken: reloadToken, console: console)
        if let s = mode.size {
            let size = landscape ? CGSize(width: s.height, height: s.width) : s
            let pad: CGFloat = 16
            let scale = min((avail.width - pad) / size.width, (avail.height - pad) / size.height, 1)
            web
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: mode == .desktop ? 8 : 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: mode == .desktop ? 8 : 28, style: .continuous).stroke(Color.primary.opacity(0.25), lineWidth: 3 / max(scale, 0.1)))
                .scaleEffect(scale)
                .frame(width: size.width * scale, height: size.height * scale)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        } else {
            web
        }
    }

    private var consolePanel: some View {
        VStack(spacing: 0) {
            // handle / header
            VStack(spacing: 4) {
                Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 36, height: 5).padding(.top, 6)
                HStack {
                    Label("الكونسول", systemImage: "terminal")
                        .font(.subheadline.weight(.semibold))
                    if console.errorCount > 0 {
                        Text("\(console.errorCount)")
                            .font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                    }
                    Text("\(console.entries.count)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if consoleOpen {
                        Button { UIPasteboard.general.string = console.allText } label: { Image(systemName: "doc.on.doc") }
                        Button { console.clear() } label: { Image(systemName: "trash") }.padding(.leading, 8)
                    }
                    Image(systemName: consoleOpen ? "chevron.down" : "chevron.up").foregroundStyle(.secondary).padding(.leading, 8)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.snappy) { consoleOpen.toggle() } }
            .gesture(DragGesture().onChanged { v in
                if !consoleOpen { if v.translation.height < -20 { withAnimation(.snappy) { consoleOpen = true } }; return }
                consoleHeight = min(max(120, consoleHeight - v.translation.height / 6), 520)
            }.onEnded { v in
                if consoleOpen && v.translation.height > 120 { withAnimation(.snappy) { consoleOpen = false } }
            })

            if consoleOpen {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if console.entries.isEmpty {
                                Text("لا توجد رسائل بعد. استخدم console.log() في الكود.")
                                    .font(.footnote).foregroundStyle(.secondary).padding()
                            }
                            ForEach(console.entries) { e in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: e.icon).font(.caption).foregroundStyle(e.color).padding(.top, 2)
                                    Text(e.message)
                                        .font(.system(size: 12.5, design: .monospaced))
                                        .foregroundStyle(e.level == "log" ? Color.primary : e.color)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Button { UIPasteboard.general.string = e.message } label: {
                                        Image(systemName: "doc.on.doc").font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(e.level == "error" ? Color.red.opacity(0.08) : (e.level == "warn" ? Color.orange.opacity(0.08) : Color.clear))
                                .id(e.id)
                                Divider().opacity(0.5)
                            }
                        }
                        .environment(\.layoutDirection, .leftToRight)
                    }
                    .frame(height: consoleHeight)
                    .onChange(of: console.entries.count) { _, _ in
                        if let last = console.entries.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
            }
        }
        .background(.bar)
    }

    private var notRunnable: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "play.slash").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("تشغيل \(project.language.title) غير متاح داخل الجهاز")
                .font(.headline)
            Text("المعاينة الحية تعمل مع HTML و CSS و JavaScript و JSON و SVG و Markdown. يمكنك تحرير هذا الملف وتنسيقه وحفظ نسخه ومقارنتها.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Full-screen standalone run (opened from a home-screen icon or "تشغيل بملء الشاشة").
struct StandaloneRunView: View {
    let projectID: String
    @Environment(\.dismiss) private var dismiss
    @State private var token = UUID()
    @State private var showHandle = true

    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            ProjectWebView(projectID: projectID, reloadToken: token, console: nil)
                .ignoresSafeArea()
            Button { dismiss() } label: {
                Capsule().fill(Color.secondary.opacity(showHandle ? 0.55 : 0.18))
                    .frame(width: 44, height: 6)
                    .padding(.vertical, 8).padding(.horizontal, 20)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("إغلاق")
        }
        .statusBarHidden(false)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { showHandle = false } }
        }
    }
}
