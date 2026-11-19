import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject var store: ProjectStore
    @EnvironmentObject var router: Router
    @Environment(\.scenePhase) private var scenePhase
    @State private var search = ""
    @State private var clipboardHasText = UIPasteboard.general.hasStrings
    @State private var showNew = false
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var renameTarget: Project?
    @State private var homeTarget: Project?
    @State private var deleteTarget: Project?
    @State private var toast: String?

    var filtered: [Project] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.projects }
        return store.projects.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.language.title.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            ZStack(alignment: .bottom) {
                Group {
                    if store.projects.isEmpty {
                        emptyState
                    } else {
                        projectList
                    }
                }
                pasteButton
            }
            .navigationTitle("شغّل")
            .navigationDestination(for: String.self) { id in
                ProjectView(projectID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showNew = true } label: { Label("مشروع جديد", systemImage: "plus.square") }
                        Button { showImporter = true } label: { Label("فتح ملف من الملفات", systemImage: "folder") }
                        Divider()
                        ForEach(ProjectTemplate.all) { t in
                            Button { let p = t.make(in: store); router.open(p.id, preview: true) } label: {
                                Label("قالب: \(t.title)", systemImage: t.icon)
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
            }
            .searchable(text: $search, prompt: "ابحث في المشاريع")
        }
        .overlay(alignment: .top) { ToastView(text: $toast) }
        .onChange(of: scenePhase) { _, p in if p == .active { clipboardHasText = UIPasteboard.general.hasStrings } }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            clipboardHasText = UIPasteboard.general.hasStrings
        }
        .onChange(of: router.pasteRequest) { _, v in if v != nil { pasteAndRun(); router.pasteRequest = nil } }
        .onAppear { if router.pasteRequest != nil { pasteAndRun(); router.pasteRequest = nil } }
        .fullScreenCover(item: Binding(get: { router.runID.map { RunID(id: $0) } }, set: { router.runID = $0?.id })) { r in
            StandaloneRunView(projectID: r.id)
        }
        .sheet(isPresented: $showNew) { NewProjectSheet { p in router.open(p.id, preview: false) } }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $renameTarget) { p in RenameSheet(project: p) }
        .sheet(item: $homeTarget) { p in HomeScreenSheet(project: p) }
        .confirmationDialog("حذف المشروع؟", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible, presenting: deleteTarget) { p in
            Button("حذف «\(p.name)»", role: .destructive) { store.delete(p.id) }
        } message: { _ in Text("سيُحذف المشروع وكل نسخه المحفوظة نهائياً.") }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText, .html, .sourceCode, .json, .javaScript, .text, .data], allowsMultipleSelection: true) { result in
            importFiles(result)
        }
    }

    // MARK: sections

    private var projectList: some View {
        List {
            ForEach(filtered) { p in
                NavigationLink(value: p.id) {
                    ProjectRow(project: p)
                }
                .contextMenu { menu(for: p) }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { deleteTarget = p } label: { Label("حذف", systemImage: "trash") }
                    Button { renameTarget = p } label: { Label("تسمية", systemImage: "pencil") }.tint(.orange)
                }
                .swipeActions(edge: .leading) {
                    Button { router.runID = p.id } label: { Label("تشغيل", systemImage: "play.fill") }.tint(.green)
                }
            }
            Color.clear.frame(height: 70).listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func menu(for p: Project) -> some View {
        Button { router.runID = p.id } label: { Label("تشغيل بملء الشاشة", systemImage: "play.fill") }
        Button { homeTarget = p } label: { Label("إضافة إلى الشاشة الرئيسية", systemImage: "apps.iphone.badge.plus") }
        Button { renameTarget = p } label: { Label("إعادة التسمية", systemImage: "pencil") }
        Button { store.duplicate(p.id) } label: { Label("تكرار", systemImage: "plus.square.on.square") }
        Divider()
        Button(role: .destructive) { deleteTarget = p } label: { Label("حذف", systemImage: "trash") }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: "#1E1B4B"), Color(hex: "#633CDC")], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 96, height: 96)
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 38, weight: .bold)).foregroundStyle(.white)
                }
                .padding(.top, 30)
                Text("انسخ أي كود… واضغط «الصق وشغّل»")
                    .font(.title3.bold()).multilineTextAlignment(.center)
                Text("يتعرف التطبيق على اللغة ويسمّي الملف ويشغّله فوراً، بدون إنترنت ولا حسابات.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30)

                VStack(alignment: .leading, spacing: 10) {
                    Text("أو ابدأ من قالب").font(.headline).padding(.horizontal, 4)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(ProjectTemplate.all) { t in
                            Button {
                                let p = t.make(in: store)
                                router.open(p.id, preview: true)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(t.emoji).font(.system(size: 30))
                                    Text(t.title).font(.headline).foregroundStyle(.primary)
                                    Text(t.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                                .padding(14)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)
                Spacer(minLength: 100)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var pasteButton: some View {
        Button(action: pasteAndRun) {
            HStack(spacing: 10) {
                Image(systemName: clipboardHasText ? "doc.on.clipboard.fill" : "doc.on.clipboard")
                    .font(.system(size: 19, weight: .semibold))
                Text(clipboardHasText ? "الصق وشغّل الآن" : "الحافظة فارغة")
                    .font(.system(size: 18, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .frame(height: 58)
            .background(
                Capsule().fill(clipboardHasText
                               ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "#633CDC"), Color(hex: "#8B5CF6")], startPoint: .leading, endPoint: .trailing))
                               : AnyShapeStyle(Color.gray.opacity(0.55)))
            )
            .shadow(color: Color(hex: "#633CDC").opacity(clipboardHasText ? 0.4 : 0), radius: 14, y: 6)
        }
        .buttonStyle(PressableStyle())
        .padding(.bottom, 18)
        .animation(.snappy, value: clipboardHasText)
    }

    // MARK: actions

    private func pasteAndRun() {
        guard let text = UIPasteboard.general.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            toast = "انسخ كوداً أولاً ثم ارجع هنا"
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        let p = store.create(code: text)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        router.open(p.id, preview: p.language.isRunnable)
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        var created: Project?
        for url in urls {
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let name = url.lastPathComponent
            if let p = created {
                _ = store.addFile(name, content: text, to: p.id)
            } else {
                let lang = CodeLanguage.from(fileName: name)
                let detected = lang == .text ? Detector.detect(text) : lang
                var p = store.create(code: text, name: Detector.suggestName(for: text, language: detected), language: detected)
                if p.files.first != name, !(detected == .html && name.lowercased() != "index.html" && urls.count > 1) {
                    _ = store.renameFile(p.files[0], to: detected == .html && urls.count > 1 ? "index.html" : name, in: p.id)
                    p = store.project(p.id) ?? p
                }
                created = p
            }
        }
        if let p = created { router.open(p.id, preview: true) }
    }
}

private struct RunID: Identifiable { let id: String }

struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 14) {
            ProjectIcon(project: project, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name).font(.body.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(project.language.short)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(project.language.color.opacity(0.18), in: Capsule())
                        .foregroundStyle(project.language.color)
                    if project.files.count > 1 {
                        Label("\(project.files.count)", systemImage: "doc.on.doc").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(project.modified.formatted(.relative(presentation: .named)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ProjectIcon: View {
    let project: Project
    var size: CGFloat

    var body: some View {
        Group {
            if let img = IconRenderer.customIcon(project.id) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Color(hex: project.iconColorHex).opacity(0.85), Color(hex: project.iconColorHex)], startPoint: .top, endPoint: .bottom)
                    Text(project.iconEmoji).font(.system(size: size * 0.5))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct ToastView: View {
    @Binding var text: String?

    var body: some View {
        Group {
            if let t = text {
                Text(t)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: t) {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        withAnimation { text = nil }
                    }
            }
        }
        .animation(.snappy, value: text)
    }
}
