import SwiftUI

struct DiffLine: Identifiable, Hashable {
    enum Kind { case same, added, removed }
    let id: Int
    let kind: Kind
    let text: String
    let oldNo: Int?
    let newNo: Int?
}

enum Differ {
    static func diff(old: String, new: String) -> [DiffLine] {
        let a = old.components(separatedBy: "\n")
        let b = new.components(separatedBy: "\n")
        let d = b.difference(from: a)
        var removed = Set<Int>(), inserted = Set<Int>()
        for c in d {
            switch c {
            case .remove(let o, _, _): removed.insert(o)
            case .insert(let o, _, _): inserted.insert(o)
            }
        }
        var out: [DiffLine] = []
        var i = 0, j = 0, n = 0
        while i < a.count || j < b.count {
            if i < a.count, removed.contains(i) {
                out.append(DiffLine(id: n, kind: .removed, text: a[i], oldNo: i + 1, newNo: nil)); i += 1
            } else if j < b.count, inserted.contains(j) {
                out.append(DiffLine(id: n, kind: .added, text: b[j], oldNo: nil, newNo: j + 1)); j += 1
            } else if i < a.count, j < b.count {
                out.append(DiffLine(id: n, kind: .same, text: a[i], oldNo: i + 1, newNo: j + 1)); i += 1; j += 1
            } else if i < a.count {
                out.append(DiffLine(id: n, kind: .removed, text: a[i], oldNo: i + 1, newNo: nil)); i += 1
            } else {
                out.append(DiffLine(id: n, kind: .added, text: b[j], oldNo: nil, newNo: j + 1)); j += 1
            }
            n += 1
        }
        return out
    }

    /// Collapses long unchanged runs, keeping `context` lines around changes.
    static func collapsed(_ lines: [DiffLine], context: Int = 3) -> [DiffLine?] {
        let changed = lines.indices.filter { lines[$0].kind != .same }
        guard !changed.isEmpty else {
            let all: [DiffLine?] = lines.map { Optional($0) }
            return lines.count > 12 ? Array(all.prefix(6)) + [nil] : all
        }
        var keep = Set<Int>()
        for c in changed { for k in max(0, c - context)...min(lines.count - 1, c + context) { keep.insert(k) } }
        var out: [DiffLine?] = []
        var gap = false
        for (i, l) in lines.enumerated() {
            if keep.contains(i) { out.append(l); gap = false } else if !gap { out.append(nil); gap = true }
        }
        return out
    }
}

struct DiffListView: View {
    let lines: [DiffLine]
    @State private var showAll = false

    var stats: (Int, Int) {
        (lines.filter { $0.kind == .added }.count, lines.filter { $0.kind == .removed }.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("\(stats.0)+", systemImage: "plus.circle.fill").foregroundStyle(.green)
                Label("\(stats.1)−", systemImage: "minus.circle.fill").foregroundStyle(.red)
                Spacer()
                Toggle("كل السطور", isOn: $showAll).toggleStyle(.button).font(.caption)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()
            ScrollView([.vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let rows: [DiffLine?] = showAll ? lines.map { Optional($0) } : Differ.collapsed(lines)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        if let l = row { lineView(l) } else {
                            Text("⋯").font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.06))
                        }
                    }
                    if stats.0 == 0 && stats.1 == 0 {
                        Text("لا توجد فروقات — الكود متطابق.").foregroundStyle(.secondary).padding()
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
        }
    }

    private func lineView(_ l: DiffLine) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(l.oldNo.map(String.init) ?? "").frame(width: 34, alignment: .trailing)
            Text(l.newNo.map(String.init) ?? "").frame(width: 34, alignment: .trailing)
            Text(l.kind == .added ? " + " : (l.kind == .removed ? " − " : "   "))
                .fontWeight(.bold)
            Text(l.text.isEmpty ? " " : l.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(l.kind == .same ? Color.primary.opacity(0.75) : Color.primary)
        .padding(.vertical, 2)
        .padding(.trailing, 8)
        .background(l.kind == .added ? Color.green.opacity(0.18) : (l.kind == .removed ? Color.red.opacity(0.18) : Color.clear))
    }
}

/// Shown when pasting an update over existing code.
struct PasteUpdateSheet: View {
    let fileName: String
    let oldText: String
    let newText: String
    var onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DiffListView(lines: Differ.diff(old: oldText, new: newText))
                .navigationTitle("مقارنة التحديث")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("اعتماد") { onApply(); dismiss() }.bold()
                    }
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 0) {
                            Text("مقارنة التحديث").font(.headline)
                            Text(fileName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
        }
    }
}

struct HistoryView: View {
    let project: Project
    @EnvironmentObject var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var snaps: [Snapshot] = []

    var body: some View {
        NavigationStack {
            List {
                if snaps.isEmpty {
                    Text("لا توجد نسخ محفوظة بعد.").foregroundStyle(.secondary)
                }
                Section {
                    ForEach(snaps) { s in
                        NavigationLink {
                            SnapshotDetail(project: project, snapshot: s) { dismiss() }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: icon(for: s.reason))
                                    .font(.title3).foregroundStyle(Color.accentColor)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(s.reason).font(.body.weight(.medium))
                                    Text(s.date.formatted(date: .abbreviated, time: .shortened) + " · " + s.date.formatted(.relative(presentation: .named)))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(s.totalLines) سطر").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.deleteSnapshot(s, in: project.id); reload()
                            } label: { Label("حذف", systemImage: "trash") }
                        }
                    }
                } footer: {
                    Text("يحفظ التطبيق نسخة تلقائياً قبل كل لصق أو تنسيق أو استرجاع، وعند التعديلات الكبيرة. يُحتفظ بآخر 60 نسخة.")
                }
            }
            .navigationTitle("سجل التعديلات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { store.snapshot(project, reason: "نسخة يدوية"); reload() } label: {
                        Label("حفظ نسخة الآن", systemImage: "plus")
                    }
                }
            }
            .onAppear(perform: reload)
        }
    }

    private func reload() { snaps = store.snapshots(project) }

    private func icon(for reason: String) -> String {
        if reason.contains("لصق") { return "doc.on.clipboard" }
        if reason.contains("تنسيق") { return "wand.and.stars" }
        if reason.contains("استرجاع") { return "arrow.uturn.backward" }
        if reason.contains("الأولى") { return "flag" }
        if reason.contains("يدوية") { return "bookmark" }
        return "clock.arrow.circlepath"
    }
}

struct SnapshotDetail: View {
    let project: Project
    let snapshot: Snapshot
    var onRestored: () -> Void
    @EnvironmentObject var store: ProjectStore
    @State private var file: String = ""
    @State private var confirm = false

    var files: [String] { Array(Set(snapshot.files.keys).union(project.files)).sorted() }

    var body: some View {
        VStack(spacing: 0) {
            if files.count > 1 {
                Picker("الملف", selection: $file) {
                    ForEach(files, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(10)
            }
            Text("الأحمر: موجود في هذه النسخة · الأخضر: موجود الآن")
                .font(.caption).foregroundStyle(.secondary).padding(.bottom, 4)
            DiffListView(lines: Differ.diff(old: snapshot.files[file] ?? "", new: store.read(file, in: project.id)))
        }
        .navigationTitle(snapshot.reason)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("استرجاع") { confirm = true }.bold()
            }
        }
        .confirmationDialog("استرجاع هذه النسخة؟", isPresented: $confirm, titleVisibility: .visible) {
            Button("استرجاع") {
                store.restore(snapshot, in: project.id)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onRestored()
            }
        } message: {
            Text("سيُحفظ الوضع الحالي كنسخة قبل الاسترجاع، فلن تفقد شيئاً.")
        }
        .onAppear {
            if file.isEmpty { file = snapshot.files.keys.contains(project.activeFile) ? project.activeFile : (files.first ?? "") }
        }
    }
}
