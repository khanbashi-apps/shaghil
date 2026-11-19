import SwiftUI
import PhotosUI
import WidgetKit

// MARK: - New project

struct NewProjectSheet: View {
    var onCreate: (Project) -> Void
    @EnvironmentObject var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var language: CodeLanguage = .html

    var body: some View {
        NavigationStack {
            Form {
                Section("الاسم") {
                    TextField("اتركه فارغاً لتسمية تلقائية", text: $name)
                }
                Section("اللغة") {
                    Picker("اللغة", selection: $language) {
                        ForEach(CodeLanguage.allCases.filter { $0 != .text }) { l in
                            Text(l.title).tag(l)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                Section("قوالب جاهزة") {
                    ForEach(ProjectTemplate.all) { t in
                        Button {
                            let p = t.make(in: store); dismiss(); onCreate(p)
                        } label: {
                            HStack {
                                Text(t.emoji).font(.title2)
                                VStack(alignment: .leading) {
                                    Text(t.title).foregroundStyle(.primary)
                                    Text(t.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("مشروع جديد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إنشاء") {
                        let starter = starterCode(language)
                        let n = name.trimmingCharacters(in: .whitespaces)
                        let p = store.create(code: starter, name: n.isEmpty ? Detector.defaultName(language) : n, language: language)
                        dismiss(); onCreate(p)
                    }.bold()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func starterCode(_ l: CodeLanguage) -> String {
        switch l {
        case .html: return "<!DOCTYPE html>\n<html lang=\"ar\" dir=\"rtl\">\n<head>\n  <meta charset=\"utf-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n  <title></title>\n</head>\n<body>\n  \n</body>\n</html>\n"
        case .javascript: return "console.log('مرحباً');\n"
        case .css: return "body {\n  \n}\n"
        case .python: return "print(\"مرحباً\")\n"
        case .json: return "{\n  \n}\n"
        case .swift: return "import Foundation\n\n"
        case .markdown: return "# عنوان\n\n"
        case .svg: return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\n  <circle cx=\"50\" cy=\"50\" r=\"40\" fill=\"#633CDC\"/>\n</svg>\n"
        default: return ""
        }
    }
}

// MARK: - Rename + icon

struct RenameSheet: View {
    let project: Project
    @EnvironmentObject var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = ""
    @State private var color = ""
    @State private var photo: PhotosPickerItem?
    @State private var customImage: UIImage?
    @State private var removeCustom = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        IconPreview(emoji: emoji, hex: color, image: removeCustom ? nil : customImage, size: 92)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("الاسم") {
                    TextField("اسم المشروع", text: $name)
                }
                IconPickerSection(emoji: $emoji, color: $color, photo: $photo, hasCustom: customImage != nil && !removeCustom) {
                    removeCustom = true
                }
            }
            .navigationTitle("الاسم والأيقونة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { save(); dismiss() }.bold()
                }
            }
            .onAppear {
                name = project.name; emoji = project.iconEmoji; color = project.iconColorHex
                customImage = IconRenderer.customIcon(project.id)
            }
            .onChange(of: photo) { _, item in
                Task {
                    if let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                        customImage = img; removeCustom = false
                    }
                }
            }
        }
    }

    private func save() {
        store.rename(project.id, to: name)
        store.setIcon(project.id, emoji: emoji, colorHex: color)
        let url = IconRenderer.customIconURL(project.id)
        if removeCustom {
            try? FileManager.default.removeItem(at: url)
        } else if let img = customImage {
            let square = IconRenderer.render(emoji: "", hex: color, image: img, size: 512)
            try? square.pngData()?.write(to: url)
        }
        store.objectWillChange.send()
    }
}

struct IconPreview: View {
    let emoji: String
    let hex: String
    let image: UIImage?
    let size: CGFloat
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Color(hex: hex).opacity(0.85), Color(hex: hex)], startPoint: .top, endPoint: .bottom)
                    Text(emoji).font(.system(size: size * 0.5))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}

struct IconPickerSection: View {
    @Binding var emoji: String
    @Binding var color: String
    @Binding var photo: PhotosPickerItem?
    var hasCustom: Bool
    var onRemoveCustom: () -> Void
    @State private var customEmoji = ""

    var body: some View {
        Section("الأيقونة") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                ForEach(ProjectStore.iconEmojis, id: \.self) { e in
                    Text(e).font(.system(size: 26))
                        .frame(width: 38, height: 38)
                        .background(emoji == e ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .onTapGesture { emoji = e }
                }
            }
            .padding(.vertical, 4)
            HStack {
                TextField("أو اكتب إيموجي", text: $customEmoji)
                    .onChange(of: customEmoji) { _, v in if let c = v.last { emoji = String(c) } }
            }
            HStack(spacing: 10) {
                ForEach(ProjectStore.iconColors, id: \.self) { c in
                    Circle().fill(Color(hex: c)).frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Color.primary, lineWidth: color == c ? 3 : 0).padding(-3))
                        .onTapGesture { color = c }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .environment(\.layoutDirection, .leftToRight)
            PhotosPicker(selection: $photo, matching: .images) {
                Label("اختيار صورة من الألبوم", systemImage: "photo")
            }
            if hasCustom {
                Button(role: .destructive, action: onRemoveCustom) { Label("إزالة الصورة", systemImage: "xmark") }
            }
        }
    }
}

// MARK: - File name

struct FileNameSheet: View {
    let title: String
    let initial: String
    var onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("مثال: style.css", text: $name)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .environment(\.layoutDirection, .leftToRight)
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(["index.html", "style.css", "script.js", "app.js", "widget.js", "data.json", "README.md"], id: \.self) { n in
                                Button(n) { name = n }.buttonStyle(.bordered).font(.caption.monospaced())
                            }
                        }
                    }
                } footer: {
                    Text("اربط الملفات من index.html مثل: <link href=\"style.css\"> و <script src=\"app.js\">. ملف widget.js يشغّله الويدجت مباشرة.")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { onDone(name); dismiss() }.bold().disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { name = initial }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Home screen icon

struct HomeScreenSheet: View {
    let project: Project
    @EnvironmentObject var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var emoji = ""
    @State private var color = ""
    @State private var photo: PhotosPickerItem?
    @State private var customImage: UIImage?
    @State private var removeCustom = false
    @State private var shareURL: URL?
    @State private var status: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        IconPreview(emoji: emoji, hex: color, image: removeCustom ? nil : customImage, size: 76)
                        Text(label.isEmpty ? " " : label).font(.caption).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section("الاسم على الشاشة الرئيسية") {
                    TextField("الاسم", text: $label)
                }
                IconPickerSection(emoji: $emoji, color: $color, photo: $photo, hasCustom: customImage != nil && !removeCustom) { removeCustom = true }

                Section {
                    Button { install() } label: {
                        HStack {
                            Label("إضافة عبر Safari", systemImage: "safari")
                            Spacer()
                            if busy { ProgressView() }
                        }
                    }
                    .bold()
                    Button { saveIcon(); shareURL = WebClipBuilder.profileFile(for: currentProject, label: finalLabel) } label: {
                        Label("حفظ ملف التثبيت في «الملفات»", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("التثبيت")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let status { Text(status).foregroundStyle(Color.accentColor) }
                        Text("١. اضغط «إضافة عبر Safari» ثم «سماح».")
                        Text("٢. افتح الإعدادات ← «تم تنزيل ملف التعريف» ← تثبيت.")
                        Text("ستظهر الأيقونة على الشاشة الرئيسية، وتفتح المشروع بملء الشاشة مباشرة وتحتفظ ببياناته، بدون إنترنت.")
                    }
                }

                Section {
                    HStack {
                        Text(SharedStore.runURL(project.id).absoluteString)
                            .font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                            .environment(\.layoutDirection, .leftToRight)
                        Spacer()
                        Button { UIPasteboard.general.string = SharedStore.runURL(project.id).absoluteString; status = "تم نسخ الرابط" } label: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                } header: {
                    Text("طريقة بديلة: تطبيق الاختصارات")
                } footer: {
                    Text("في «الاختصارات» أنشئ اختصاراً بإجراء «تشغيل مشروع» من شغّل (أو «فتح URL» بهذا الرابط)، ثم «إضافة إلى الشاشة الرئيسية» واختر أيقونتك.")
                }
            }
            .navigationTitle("إضافة إلى الشاشة الرئيسية")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } }
            }
            .onAppear {
                label = project.name; emoji = project.iconEmoji; color = project.iconColorHex
                customImage = IconRenderer.customIcon(project.id)
            }
            .onChange(of: photo) { _, item in
                Task {
                    if let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                        customImage = img; removeCustom = false
                    }
                }
            }
            .sheet(item: Binding(get: { shareURL.map { ShareBox(url: $0) } }, set: { shareURL = $0?.url })) { b in
                ShareSheet(items: [b.url])
            }
        }
    }

    private var finalLabel: String {
        let t = label.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? project.name : t
    }

    private var currentProject: Project { store.project(project.id) ?? project }

    private func saveIcon() {
        store.setIcon(project.id, emoji: emoji, colorHex: color)
        let url = IconRenderer.customIconURL(project.id)
        if removeCustom {
            try? FileManager.default.removeItem(at: url)
        } else if let img = customImage {
            let square = IconRenderer.render(emoji: "", hex: color, image: img, size: 512)
            try? square.pngData()?.write(to: url)
        }
    }

    private func install() {
        saveIcon()
        guard let data = WebClipBuilder.profile(for: currentProject, label: finalLabel) else { status = "تعذّر إنشاء الملف"; return }
        busy = true
        ProfileServer.shared.serve(data) { url in
            busy = false
            if let url {
                UIApplication.shared.open(url)
                status = "افتح الإعدادات لإكمال التثبيت"
            } else {
                status = "تعذّر تشغيل الخادم المحلي — استخدم «حفظ ملف التثبيت»"
            }
        }
    }
}

// MARK: - Widget guide

struct WidgetGuideSheet: View {
    let project: Project
    @EnvironmentObject var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    let snippet = """
    // أرسل بيانات إلى ويدجت «شغّل» من صفحتك:
    shaghil.widget({
      title: 'مهامي',
      value: '3 متبقية',
      subtitle: 'اليوم',
      items: [{ text: 'شراء الخبز', done: false }],
      counter: 5   // يظهر زرّا + و − في الويدجت الكبير
    });

    // آخر حالة (بعد الضغط على الويدجت):
    console.log(shaghil.state);
    """

    let widgetJS = """
    // أو أضف ملف widget.js يشغّله الويدجت بنفسه كل ربع ساعة:
    function widget(state) {
      return { title: 'الساعة', value: new Date().toLocaleTimeString('ar') };
    }
    """

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("square.fill", "صغير", "يفتح مشروعاً بلمسة، أو يعرض رقماً حياً من الكود.")
                    row("rectangle.fill", "متوسط", "آخر ٣ مشاريع + زر «لصق وتشغيل».")
                    row("square.split.2x2.fill", "كبير", "ويدجت حي: عنوان وقيمة وقائمة قابلة للتعليم وعدّاد.")
                } header: { Text("الأحجام") } footer: {
                    Text("اضغط مطولاً على الشاشة الرئيسية ← تعديل ← إضافة أداة ← شغّل. ثم اضغط على الويدجت ← تعديل الأداة لاختيار «\(project.name)».")
                }
                Section("من الكود") {
                    code(snippet)
                    code(widgetJS)
                    Button {
                        UIPasteboard.general.string = snippet; copied = true
                    } label: { Label(copied ? "تم النسخ" : "نسخ المثال", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    if !project.files.contains("widget.js") {
                        Button {
                            _ = store.addFile("widget.js", content: widgetJS.replacingOccurrences(of: "// أو أضف ملف widget.js يشغّله الويدجت بنفسه كل ربع ساعة:\n", with: "// يشغّل الويدجت هذه الدالة بنفسه كل ربع ساعة\n"), to: project.id)
                            dismiss()
                        } label: { Label("إضافة widget.js لهذا المشروع", systemImage: "plus") }
                    }
                }
                if let p = SharedStore.widgetPayload(for: project.id) {
                    Section("آخر بيانات وصلت للويدجت") {
                        if let t = p.title { LabeledContent("العنوان", value: t) }
                        if let v = p.value { LabeledContent("القيمة", value: v) }
                        if let i = p.items { LabeledContent("العناصر", value: "\(i.count)") }
                        Button("مسح بيانات الويدجت", role: .destructive) {
                            try? FileManager.default.removeItem(at: SharedStore.widgetURL.appendingPathComponent("\(project.id).json"))
                            WidgetCenter.shared.reloadAllTimelines()
                            dismiss()
                        }
                    }
                }
                if SharedStore.groupURL == nil {
                    Section {
                        Label("الويدجت لا يصل لبيانات التطبيق: أداة التوقيع لم تفعّل «App Groups». فعّلها في إعدادات التوقيع ثم أعد التثبيت.", systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("الويدجت")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } } }
        }
    }

    private func row(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading) {
                Text(title).bold()
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func code(_ s: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(s).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                .padding(10)
        }
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
        .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = 0
    @AppStorage("editorFontSize") private var fontSize: Double = 14

    var body: some View {
        NavigationStack {
            Form {
                Section("المظهر") {
                    Picker("الوضع", selection: $appearance) {
                        Text("تلقائي").tag(0)
                        Text("فاتح").tag(1)
                        Text("داكن").tag(2)
                    }
                    .pickerStyle(.segmented)
                    Stepper("حجم خط المحرر: \(Int(fontSize))", value: $fontSize, in: 10...26)
                }
                Section("التخزين") {
                    LabeledContent("مكان الحفظ", value: SharedStore.groupURL == nil ? "داخل التطبيق" : "مجموعة التطبيق (مع الويدجت)")
                    LabeledContent("الإنترنت", value: "غير مطلوب")
                    LabeledContent("الحسابات", value: "لا يوجد")
                }
                Section("ما يعمل داخل الجهاز") {
                    Text("تشغيل: HTML · CSS · JavaScript · JSON · SVG · Markdown")
                    Text("تحرير وتنسيق: Python · Swift · TypeScript وغيرها")
                }
                Section {
                    LabeledContent("الإصدار", value: AppInfo.version)
                    LabeledContent("المنسّق", value: "js-beautify (MIT)")
                } footer: {
                    Text("شغّل \(AppInfo.version) — محرر ومشغّل أكواد سريع للآيفون.")
                }
            }
            .navigationTitle("الإعدادات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
        }
    }
}
