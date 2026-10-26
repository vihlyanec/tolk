import Foundation
import Testing
import UserNotifications
import TaktCore
@testable import Takt

@Test @MainActor func automaticColorsUseEveryFreePresetBeforeGeneratingNewColors() {
    var snapshot = Snapshot()
    snapshot.projects = [Project(name: "Старый синий", color: "598bff")]
    snapshot.tags = [Tag(name: "старый фиолетовый", color: "#AD94E8")]
    var used = Set((snapshot.projects.map(\.color) + snapshot.tags.map(\.color)).map(SemanticTint.vibrantHex))
    for index in 0..<30 {
        let color = ProjectTagPalette.nextColor(in: snapshot)
        #expect(!used.contains(color))
        if index < 16 { #expect(ProjectTagPalette.choices.contains { $0.hex == color }) }
        used.insert(color); snapshot.tags.append(Tag(name: "Тег \(index)", color: color))
    }
    #expect(used.count == 32)
}
@Test @MainActor func automaticallyCreatedHashtagsReceiveDistinctColors() throws {
    let state = AppState(demo: true)
    let item = try #require(state.data.items.first)
    let used = Set((state.data.tags.map(\.color) + state.data.projects.map(\.color)).map(SemanticTint.vibrantHex))
    state.update(item.id) { $0.body = "#новыйПервый #новыйВторой " }
    let tags = state.data.tags.filter { $0.name.hasPrefix("новый") }
    #expect(tags.count == 2 && Set(tags.map(\.color)).count == 2)
    #expect(tags.allSatisfy { !used.contains($0.color) })
}
@Test @MainActor func legacyReminderCleanupDoesNotDependOnIdentifierPrefix() {
    let old = UNMutableNotificationContent(); old.body = "Такт · 60 мин"
    let current = UNMutableNotificationContent(); current.body = "Напоминание о задаче"
    #expect(Reminders.isLegacy(old))
    #expect(!Reminders.isLegacy(current))
}
