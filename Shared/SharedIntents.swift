import Foundation
import AppIntents
import WidgetKit

// MARK: - Project entity (used by Shortcuts and widget configuration)

struct ProjectEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "مشروع"
    static var defaultQuery = ProjectQuery()

    var id: String
    var name: String
    var emoji: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(emoji) \(name)")
    }

    init(id: String, name: String, emoji: String) {
        self.id = id
        self.name = name
        self.emoji = emoji
    }

    init(_ s: ProjectSummary) {
        self.init(id: s.id, name: s.name, emoji: s.iconEmoji)
    }
}

struct ProjectQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ProjectEntity] {
        SharedStore.loadIndex().filter { identifiers.contains($0.id) }.map(ProjectEntity.init)
    }

    func suggestedEntities() async throws -> [ProjectEntity] {
        SharedStore.loadIndex().map(ProjectEntity.init)
    }

    func entities(matching string: String) async throws -> [ProjectEntity] {
        SharedStore.loadIndex()
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(ProjectEntity.init)
    }
}

// MARK: - Widget configuration

struct SelectProjectIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "اختر مشروعاً"
    static var description = IntentDescription("المشروع الذي يظهر في الويدجت.")

    @Parameter(title: "المشروع")
    var project: ProjectEntity?

    init() {}
}

// MARK: - Interactive widget actions

struct ToggleWidgetItemIntent: AppIntent {
    static var title: LocalizedStringResource = "تبديل عنصر"
    static var isDiscoverable: Bool = false

    @Parameter(title: "المشروع") var projectID: String
    @Parameter(title: "الرقم") var index: Int

    init() {}
    init(projectID: String, index: Int) {
        self.projectID = projectID
        self.index = index
    }

    func perform() async throws -> some IntentResult {
        if var p = SharedStore.widgetPayload(for: projectID), var items = p.items, items.indices.contains(index) {
            items[index].done.toggle()
            p.items = items
            p.updated = Date()
            SharedStore.saveWidgetPayload(p, for: projectID)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct ChangeCounterIntent: AppIntent {
    static var title: LocalizedStringResource = "تغيير العداد"
    static var isDiscoverable: Bool = false

    @Parameter(title: "المشروع") var projectID: String
    @Parameter(title: "المقدار") var delta: Double

    init() {}
    init(projectID: String, delta: Double) {
        self.projectID = projectID
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        var p = SharedStore.widgetPayload(for: projectID) ?? WidgetPayload()
        let newValue = (p.counter ?? 0) + delta
        p.counter = newValue
        p.value = newValue.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(newValue)) : String(newValue)
        p.updated = Date()
        SharedStore.saveWidgetPayload(p, for: projectID)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
