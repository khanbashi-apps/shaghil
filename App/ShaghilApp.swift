import SwiftUI
import AppIntents

final class Router: ObservableObject {
    static let shared = Router()
    @Published var path: [String] = [] {
        didSet { NSLog("SHAGHIL path \(oldValue) -> \(path)") }
    }
    @Published var runID: String?
    @Published var pasteRequest = UUID?.none
    /// Projects that should open on the preview tab (just pasted / run from a link).
    var openInPreview = Set<String>()

    func handle(_ url: URL) {
        guard url.scheme == AppInfo.scheme else { return }
        let host = url.host ?? ""
        let id = url.pathComponents.dropFirst().first?.lowercased() ?? ""
        switch host {
        case "run":
            if ProjectStore.shared.project(id) != nil { runID = id }
        case "open":
            if ProjectStore.shared.project(id) != nil {
                runID = nil
                path = [id]
            }
        case "paste":
            runID = nil
            pasteRequest = UUID()
        default: break
        }
    }

    func open(_ id: String, preview: Bool) {
        if preview { openInPreview.insert(id) }
        path = [id]
    }
}

@main
struct ShaghilApp: App {
    @StateObject private var store = ProjectStore.shared
    @StateObject private var router = Router.shared
    @AppStorage("appearance") private var appearance = 0

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .environmentObject(router)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar_OM@numbers=latn"))
                .preferredColorScheme(appearance == 1 ? .light : (appearance == 2 ? .dark : nil))
                .tint(Color("AccentColor"))
                .onOpenURL { router.handle($0) }
                .task { DemoSeeder.runIfRequested() }
        }
    }
}

// MARK: - Shortcuts (App Intents)

struct RunProjectIntent: AppIntent {
    static var title: LocalizedStringResource = "تشغيل مشروع"
    static var description = IntentDescription("يفتح مشروعاً من تطبيق شغّل بملء الشاشة.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "المشروع")
    var project: ProjectEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.runID = project.id
        return .result()
    }
}

struct PasteAndRunIntent: AppIntent {
    static var title: LocalizedStringResource = "لصق وتشغيل"
    static var description = IntentDescription("ينشئ مشروعاً من الحافظة ويشغّله.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.pasteRequest = UUID()
        return .result()
    }
}

struct ShaghilShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RunProjectIntent(),
                    phrases: ["شغّل مشروع في \(.applicationName)", "Run project in \(.applicationName)"],
                    shortTitle: "تشغيل مشروع",
                    systemImageName: "play.fill")
        AppShortcut(intent: PasteAndRunIntent(),
                    phrases: ["الصق وشغّل في \(.applicationName)", "Paste and run in \(.applicationName)"],
                    shortTitle: "لصق وتشغيل",
                    systemImageName: "doc.on.clipboard")
    }
}

/// Used only by the CI screenshot run (launch arguments), never in normal use.
enum DemoSeeder {
    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-seedDemo") else { return }
        let store = ProjectStore.shared
        if store.projects.isEmpty {
            for t in [ProjectTemplate.today, ProjectTemplate.counter, ProjectTemplate.todo] { t.make(in: store) }
            store.create(code: "# حساب الفاتورة\ndef total(items):\n    return sum(items)\n\nprint(total([1, 2, 3]))\n")
        }
        if let i = args.firstIndex(of: "-open"), i + 1 < args.count, let first = store.projects.first(where: { $0.name == "مهامي" }) ?? store.projects.first {
            let mode = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if mode == "full" { Router.shared.runID = first.id } else { Router.shared.open(first.id, preview: mode == "run") }
            }
        }
    }
}
