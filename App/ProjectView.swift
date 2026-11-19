import SwiftUI

struct ProjectView: View {
    let projectID: String
    @EnvironmentObject var store: ProjectStore
    @EnvironmentObject var router: Router
    @Environment(\.dismiss) private var dismiss
    @AppStorage("editorFontSize") private var fontSize: Double = 14

    @StateObject private var editor = EditorController()
    @StateObject private var console = ConsoleModel()

    @State private var tab = 0               // 0 = code, 1 = run
    @State private var text = ""
    @State private var loadedFile = ""
    @State private var reloadToken = UUID()
    @State private var saveWork: DispatchWorkItem?

    @State private var showFind = false
    @State private var findText = ""
    @State private var replaceText = ""
    @State private var caseSensitive = false

    @State private var showHistory = false
    @State private var showRename = false
    @State private var showHome = false
    @State private var showWidgetGuide = false
    @State private var showNewFile = false
    @State private var renameFile: String?
    @State private var pasteUpdate: String?
    @State private var shareURL: URL?
    @State private var confirmDelete = false
    @State private var toast: String?

    var project: Project? { store.project(projectID) }

    var body: some View {
        Group {
            if let p = project {
                content(p)
            } else {
                ContentUnavailableView("المشروع غير موجود", systemImage: "questionmark.folder")
            }
        }
        .overlay(alignment: .top) { ToastView(text: $toast) }
        .onAppear(perform: initialLoad)
        .onDisappear { NSLog("SHAGHIL project disappear"); saveNow() }
    }

    @ViewBuilder
    private func content(_ p: Project) -> some View {
        VStack(spacing: 0) {
            if tab == 0 {
                fileTabs(p)
                if showFind { findBar }
                CodeEditorView(text: $text, language: CodeLanguage.from(fileName: loadedFile), fontSize: CGFloat(fontSize), controller: editor)
                    .background(Color(uiColor: .systemBackground))
            } else {
                PreviewPane(project: p, reloadToken: reloadToken, console: console)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $tab) {
                    Text("الكود").tag(0)
                    Text("التشغيل").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { run() } label: { Image(systemName: "play.fill") }
                    .accessibilityLabel("تشغيل")
                moreMenu(p)
            }
        }
        .onChange(of: tab) { _, t in
            if t == 1 { saveNow(); console.clear(); reloadToken = UUID() }
        }
        .onChange(of: text) { _, _ in scheduleSave() }
        .sheet(isPresented: $showHistory, onDismiss: reloadFromDisk) { HistoryView(project: p) }
        .sheet(isPresented: $showRename) { RenameSheet(project: p) }
        .sheet(isPresented: $showHome) { HomeScreenSheet(project: p) }
        .sheet(isPresented: $showWidgetGuide) { WidgetGuideSheet(project: p) }
        .sheet(isPresented: $showNewFile) {
            FileNameSheet(title: "ملف جديد", initial: suggestNewFileName(p)) { name in
                if store.addFile(name, to: p.id) { switchTo(name) } else { toast = "الاسم مستخدم" }
            }
        }
        .sheet(item: Binding(get: { renameFile.map { NameBox(id: $0) } }, set: { renameFile = $0?.id })) { box in
            FileNameSheet(title: "إعادة تسمية الملف", initial: box.id) { name in
                saveNow()
                if store.renameFile(box.id, to: name, in: p.id) { loadedFile = name } else { toast = "الاسم مستخدم" }
            }
        }
        .sheet(item: Binding(get: { pasteUpdate.map { NameBox(id: $0) } }, set: { pasteUpdate = $0?.id })) { box in
            PasteUpdateSheet(fileName: loadedFile, oldText: text, newText: box.id) {
                saveNow()
                store.write(box.id, file: loadedFile, in: p.id, snapshotReason: "قبل لصق تحديث")
                text = box.id
                reloadToken = UUID()
                toast = "تم اعتماد التحديث ✓"
            }
        }
        .sheet(item: Binding(get: { shareURL.map { ShareBox(url: $0) } }, set: { shareURL = $0?.url })) { box in
            ShareSheet(items: [box.url])
        }
        .confirmationDialog("حذف المشروع؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف نهائياً", role: .destructive) {
                store.delete(p.id)
                dismiss()
            }
        }
    }

    // MARK: file tabs

    private func fileTabs(_ p: Project) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(p.files, id: \.self) { f in
                    let lang = CodeLanguage.from(fileName: f)
                    Button { switchTo(f) } label: {
                        HStack(spacing: 5) {
                            Circle().fill(lang.color).frame(width: 7, height: 7)
                            Text(f).font(.system(size: 13, weight: f == loadedFile ? .semibold : .regular, design: .monospaced))
                        }
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(f == loadedFile ? Color.accentColor.opacity(0.15) : Color(uiColor: .tertiarySystemFill), in: Capsule())
                        .foregroundStyle(f == loadedFile ? Color.accentColor : .primary)
                    }
                    .contextMenu {
                        Button { renameFile = f } label: { Label("إعادة التسمية", systemImage: "pencil") }
                        if p.files.count > 1 {
                            Button(role: .destructive) {
                                saveNow()
                                store.deleteFile(f, in: p.id)
                                if let np = store.project(p.id) { load(np.activeFile, in: np) }
                            } label: { Label("حذف الملف", systemImage: "trash") }
                        }
                    }
                }
                Button { showNewFile = true } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                }
                .accessibilityLabel("ملف جديد")
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
        }
        .environment(\.layoutDirection, .leftToRight)
        .background(.bar)
    }

    // MARK: find bar

    private var findBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("بحث", text: $findText)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { editor.findNext(findText, caseSensitive: caseSensitive) }
                Text(editor.matchInfo).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 40)
                Button { editor.findNext(findText, caseSensitive: caseSensitive, backwards: true) } label: { Image(systemName: "chevron.up") }
                Button { editor.findNext(findText, caseSensitive: caseSensitive) } label: { Image(systemName: "chevron.down") }
                Button { caseSensitive.toggle() } label: {
                    Text("Aa").font(.caption.bold()).padding(5)
                        .background(caseSensitive ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            HStack(spacing: 8) {
                TextField("استبدال بـ", text: $replaceText)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Button("استبدال") { editor.replaceCurrent(findText, with: replaceText, caseSensitive: caseSensitive) }
                    .font(.caption.bold())
                Button("الكل") {
                    let n = editor.replaceAll(findText, with: replaceText, caseSensitive: caseSensitive)
                    toast = n > 0 ? "تم استبدال \(n)" : "لا نتائج"
                }
                .font(.caption.bold())
                Button { withAnimation { showFind = false } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
        }
        .padding(10)
        .background(.bar)
    }

    // MARK: menu

    private func moreMenu(_ p: Project) -> some View {
        Menu {
            Section {
                Button { format() } label: { Label("تنسيق الكود", systemImage: "wand.and.stars") }
                Button { tab = 0; withAnimation { showFind.toggle() } } label: { Label("بحث واستبدال", systemImage: "magnifyingglass") }
                Button { pasteAsUpdate() } label: { Label("لصق تحديث (مع مقارنة)", systemImage: "doc.on.clipboard") }
                Button { saveNow(); showHistory = true } label: { Label("سجل التعديلات", systemImage: "clock.arrow.circlepath") }
            }
            Section {
                Button { saveNow(); router.runID = p.id } label: { Label("تشغيل بملء الشاشة", systemImage: "arrow.up.left.and.arrow.down.right") }
                Button { saveNow(); showHome = true } label: { Label("إضافة إلى الشاشة الرئيسية", systemImage: "apps.iphone.badge.plus") }
                Button { saveNow(); showWidgetGuide = true } label: { Label("ربط بالويدجت", systemImage: "square.grid.2x2") }
                Button { saveNow(); exportPWA(p) } label: { Label("تصدير كتطبيق PWA (ZIP)", systemImage: "shippingbox") }
                Button { saveNow(); shareCurrentFile(p) } label: { Label("مشاركة الملف", systemImage: "square.and.arrow.up") }
                Button { UIPasteboard.general.string = text; toast = "تم نسخ الكود" } label: { Label("نسخ الكود", systemImage: "doc.on.doc") }
            }
            Section {
                Button { showRename = true } label: { Label("الاسم والأيقونة", systemImage: "pencil") }
                Button { saveNow(); store.duplicate(p.id); toast = "تم إنشاء نسخة" } label: { Label("تكرار المشروع", systemImage: "plus.square.on.square") }
                Menu {
                    Button("أصغر") { fontSize = max(10, fontSize - 1) }
                    Button("أكبر") { fontSize = min(26, fontSize + 1) }
                } label: { Label("حجم خط المحرر (\(Int(fontSize)))", systemImage: "textformat.size") }
                Button(role: .destructive) { confirmDelete = true } label: { Label("حذف المشروع", systemImage: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: actions

    private func initialLoad() {
        NSLog("SHAGHIL project appear \(projectID)")
        guard let p = project, loadedFile.isEmpty else { return }
        load(p.activeFile.isEmpty ? p.mainFile : p.activeFile, in: p)
        if router.openInPreview.remove(projectID) != nil, p.language.isRunnable || p.files.contains("index.html") {
            tab = 1
        }
    }

    private func load(_ file: String, in p: Project) {
        loadedFile = file
        text = store.read(file, in: p.id)
        store.setActiveFile(file, in: p.id)
    }

    private func reloadFromDisk() {
        guard let p = project else { return }
        let f = p.files.contains(loadedFile) ? loadedFile : p.activeFile
        load(f, in: p)
        reloadToken = UUID()
    }

    private func switchTo(_ f: String) {
        saveNow()
        guard let p = project else { return }
        load(f, in: p)
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { saveNow() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w)
    }

    private func saveNow() {
        saveWork?.cancel()
        guard !loadedFile.isEmpty, project != nil else { return }
        store.write(text, file: loadedFile, in: projectID)
    }

    private func run() {
        saveNow()
        console.clear()
        if tab == 1 { reloadToken = UUID() } else { tab = 1 }
    }

    private func format() {
        let lang = CodeLanguage.from(fileName: loadedFile)
        let out = CodeFormatter.shared.format(text, language: lang)
        guard out != text else { toast = "الكود منسّق مسبقاً"; return }
        saveNow()
        store.write(out, file: loadedFile, in: projectID, snapshotReason: "قبل التنسيق")
        text = out
        toast = "تم التنسيق ✓ (حُفظت نسخة قبله)"
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func pasteAsUpdate() {
        guard let clip = UIPasteboard.general.string, !clip.isEmpty else { toast = "الحافظة فارغة"; return }
        if clip == text { toast = "الكود في الحافظة مطابق للحالي"; return }
        saveNow()
        pasteUpdate = clip
    }

    private func exportPWA(_ p: Project) {
        if let url = PWAPackager.package(p) { shareURL = url } else { toast = "تعذّر إنشاء الحزمة" }
    }

    private func shareCurrentFile(_ p: Project) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(loadedFile)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        shareURL = url
    }

    private func suggestNewFileName(_ p: Project) -> String {
        for n in ["style.css", "script.js", "app.js", "widget.js", "data.json", "page.html"] where !p.files.contains(n) {
            return n
        }
        return "file\(p.files.count + 1).js"
    }
}

struct NameBox: Identifiable { let id: String }
struct ShareBox: Identifiable { let url: URL; var id: String { url.absoluteString } }

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
