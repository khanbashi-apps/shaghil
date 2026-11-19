import WidgetKit
import SwiftUI
import AppIntents
import JavaScriptCore

struct ShaghilEntry: TimelineEntry {
    let date: Date
    let project: ProjectSummary?
    let recent: [ProjectSummary]
    let payload: WidgetPayload?
    let noAccess: Bool
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ShaghilEntry {
        let p = ProjectSummary(id: "demo", name: "مهامي", language: .html, modified: Date(), iconEmoji: "🗒️", iconColorHex: "#2F7BEF")
        return ShaghilEntry(date: Date(), project: p, recent: [p], payload: WidgetPayload(title: "مهامي", value: "2 متبقية", subtitle: nil,
                            items: [WidgetItem(text: "شراء الخبز", done: true), WidgetItem(text: "مراجعة الكود", done: false)], counter: nil, step: nil, updated: Date()), noAccess: false)
    }

    func snapshot(for configuration: SelectProjectIntent, in context: Context) async -> ShaghilEntry {
        let e = entry(for: configuration)
        return e.recent.isEmpty && context.isPreview ? placeholder(in: context) : e
    }

    func timeline(for configuration: SelectProjectIntent, in context: Context) async -> Timeline<ShaghilEntry> {
        let e = entry(for: configuration)
        let hasScript = e.project.flatMap { SharedStore.widgetScript(for: $0.id) } != nil
        let next = Date().addingTimeInterval(hasScript ? 15 * 60 : 60 * 60)
        return Timeline(entries: [e], policy: .after(next))
    }

    private func entry(for config: SelectProjectIntent) -> ShaghilEntry {
        let index = SharedStore.loadIndex()
        let chosen: ProjectSummary? = config.project.flatMap { sel in index.first { $0.id == sel.id } } ?? index.first
        var payload = chosen.flatMap { SharedStore.widgetPayload(for: $0.id) }
        if let id = chosen?.id, let script = SharedStore.widgetScript(for: id) {
            payload = evaluate(script: script, state: payload) ?? payload
        }
        return ShaghilEntry(date: Date(), project: chosen, recent: Array(index.prefix(3)), payload: payload,
                            noAccess: SharedStore.groupURL == nil)
    }

    /// Runs widget(state) from the project's widget.js inside JavaScriptCore.
    private func evaluate(script: String, state: WidgetPayload?) -> WidgetPayload? {
        guard let ctx = JSContext() else { return nil }
        ctx.exceptionHandler = { _, _ in }
        ctx.evaluateScript("var console = { log: function(){}, error: function(){}, warn: function(){} };")
        ctx.evaluateScript(script)
        guard let fn = ctx.objectForKeyedSubscript("widget"), !fn.isUndefined else { return nil }
        var stateObj: Any = NSNull()
        if let s = state, let d = try? SharedStore.encoder.encode(s), let o = try? JSONSerialization.jsonObject(with: d) { stateObj = o }
        guard let r = fn.call(withArguments: [stateObj]), r.isObject, let dict = r.toDictionary() as? [String: Any] else { return nil }
        var p = state ?? WidgetPayload()
        if let v = dict["title"] { p.title = "\(v)" }
        if let v = dict["value"] { p.value = "\(v)" }
        if let v = dict["subtitle"] { p.subtitle = "\(v)" }
        if let arr = dict["items"] as? [Any] {
            p.items = arr.prefix(12).map { el in
                if let o = el as? [String: Any] { return WidgetItem(text: "\(o["text"] ?? "")", done: (o["done"] as? Bool) ?? false) }
                return WidgetItem(text: "\(el)", done: false)
            }
        }
        if let c = dict["counter"] as? NSNumber { p.counter = c.doubleValue }
        p.updated = Date()
        return p
    }
}

// MARK: - Views

struct ShaghilWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: ShaghilEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall: SmallView(entry: entry)
            case .systemMedium: MediumView(entry: entry)
            default: LargeView(entry: entry)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

struct IconTile: View {
    let p: ProjectSummary
    var size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: p.iconColorHex).opacity(0.85), Color(hex: p.iconColorHex)], startPoint: .top, endPoint: .bottom))
            Text(p.iconEmoji).font(.system(size: size * 0.5))
        }
        .frame(width: size, height: size)
    }
}

struct EmptyHint: View {
    let noAccess: Bool
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: noAccess ? "lock.slash" : "chevron.left.forwardslash.chevron.right")
                .font(.title2).foregroundStyle(.secondary)
            Text(noAccess ? "فعّل App Groups عند التوقيع" : "افتح «شغّل» وأضف مشروعاً")
                .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }
}

struct SmallView: View {
    let entry: ShaghilEntry
    var body: some View {
        if let p = entry.project {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    IconTile(p: p, size: 38)
                    Spacer()
                    Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Color(hex: p.iconColorHex))
                }
                Spacer(minLength: 0)
                if let v = entry.payload?.value {
                    Text(v).font(.system(size: 30, weight: .bold, design: .rounded)).minimumScaleFactor(0.4).lineLimit(1)
                        .contentTransition(.numericText())
                    Text(entry.payload?.title ?? p.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(p.name).font(.headline).lineLimit(2)
                    Text(p.language.title).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .widgetURL(SharedStore.runURL(p.id))
        } else {
            EmptyHint(noAccess: entry.noAccess).widgetURL(SharedStore.pasteURL)
        }
    }
}

struct MediumView: View {
    let entry: ShaghilEntry
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("آخر المشاريع").font(.caption.bold()).foregroundStyle(.secondary)
                if entry.recent.isEmpty {
                    Spacer()
                    Text(entry.noAccess ? "فعّل App Groups عند التوقيع" : "لا توجد مشاريع بعد").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                ForEach(entry.recent) { p in
                    Link(destination: SharedStore.runURL(p.id)) {
                        HStack(spacing: 8) {
                            IconTile(p: p, size: 28)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(p.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(p.modified, style: .relative).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            Link(destination: SharedStore.pasteURL) {
                VStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard.fill").font(.system(size: 26, weight: .semibold))
                    Text("لصق\nوتشغيل").font(.caption.bold()).multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .frame(width: 92)
                .frame(maxHeight: .infinity)
                .background(LinearGradient(colors: [Color(hex: "#633CDC"), Color(hex: "#8B5CF6")], startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

struct LargeView: View {
    let entry: ShaghilEntry
    var body: some View {
        if let p = entry.project {
            let pl = entry.payload
            VStack(alignment: .leading, spacing: 10) {
                Link(destination: SharedStore.runURL(p.id)) {
                    HStack(spacing: 10) {
                        IconTile(p: p, size: 34)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(pl?.title ?? p.name).font(.headline).lineLimit(1)
                            if let s = pl?.subtitle { Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer()
                        Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
                    }
                }
                if let v = pl?.value {
                    Text(v).font(.system(size: 44, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.4).lineLimit(1)
                        .contentTransition(.numericText())
                }
                if pl?.counter != nil {
                    HStack(spacing: 12) {
                        counterButton(p.id, -(pl?.step ?? 1), "minus")
                        counterButton(p.id, pl?.step ?? 1, "plus")
                    }
                }
                if let items = pl?.items, !items.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(items.prefix(pl?.counter != nil ? 3 : 6).enumerated()), id: \.offset) { i, it in
                            Button(intent: ToggleWidgetItemIntent(projectID: p.id, index: i)) {
                                HStack(spacing: 8) {
                                    Image(systemName: it.done ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(it.done ? Color(hex: p.iconColorHex) : .secondary)
                                    Text(it.text).font(.subheadline).strikethrough(it.done).foregroundStyle(it.done ? .secondary : .primary).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                if pl == nil {
                    Spacer()
                    Text("أرسل بيانات من الكود عبر shaghil.widget({...}) أو أضف ملف widget.js ليظهر هنا محتوى حي.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                HStack {
                    if let u = pl?.updated { Text(u, style: .time).font(.caption2).foregroundStyle(.tertiary) }
                    Spacer()
                    Text("شغّل").font(.caption2.bold()).foregroundStyle(.tertiary)
                }
            }
        } else {
            EmptyHint(noAccess: entry.noAccess).widgetURL(SharedStore.pasteURL)
        }
    }

    private func counterButton(_ id: String, _ delta: Double, _ icon: String) -> some View {
        Button(intent: ChangeCounterIntent(projectID: id, delta: delta)) {
            Image(systemName: icon).font(.title2.bold())
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct ShaghilWidget: Widget {
    let kind = "ShaghilWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectProjectIntent.self, provider: Provider()) { entry in
            ShaghilWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("شغّل")
        .description("صغير: فتح مشروع · متوسط: آخر المشاريع ولصق وتشغيل · كبير: ويدجت حي من الكود.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct ShaghilWidgetBundle: WidgetBundle {
    var body: some Widget {
        ShaghilWidget()
    }
}
