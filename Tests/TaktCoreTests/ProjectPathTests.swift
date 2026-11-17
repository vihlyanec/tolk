import Foundation
import Testing
@testable import TaktCore

private func personalProject() -> Project {
    var project = Project(name: "Личное")
    project.sections = ["Без раздела", "Спорт", "Спорт силовой", "Планы на завтра"]
    return project
}

@Test(arguments: ["/Личное/Спорт", "/\"Личное\"/\"Спорт\"", "/Личное/\"Спорт\"", "/\"Личное\"/Спорт", "/личное/спорт"])
func projectStagePathsAcceptNewAndLegacySyntax(_ path: String) throws {
    let project = personalProject()
    let parsed = QuickParser.parse("🏋️ Тренировка \(path) !1", projects: [project], tags: [])
    #expect(parsed.title == "🏋️ Тренировка" && parsed.priority == 1)
    #expect(parsed.projectID == project.id && parsed.section == "Спорт")
    #expect(parsed.item().projectID == project.id && parsed.item().section == "Спорт")
    let token = try #require(parsed.tokens.first { $0.kind == .project })
    #expect(token.value == path)
    #expect(("🏋️ Тренировка \(path) !1" as NSString).substring(with: token.range) == path)
}

@Test func projectPathsUseLongestCatalogNamesAndLeaveTitleWords() {
    let short = personalProject()
    var long = Project(name: "Личное пространство")
    long.sections = ["Без раздела", "Спорт", "Спорт силовой"]
    let parsed = QuickParser.parse("Сделать /Личное пространство/Спорт силовой вечером", projects: [short,long], tags: [])
    #expect(parsed.projectID == long.id && parsed.section == "Спорт силовой")
    #expect(parsed.title == "Сделать вечером")
    let words = QuickParser.parse("Дело /Личное/Планы на завтра", projects: [short], tags: [])
    #expect(words.schedule == .unscheduled && words.section == "Планы на завтра" && words.title == "Дело")
    #expect(QuickProjectPath.command(long.name, section: "Спорт силовой") == "/Личное пространство/Спорт силовой")
}

@Test(arguments: ["/Личное/Нет", "/\"Личное\"/\"Неизвестный этап\"", "/Личное/"])
func unknownSectionChoosesOnlyProject(_ path: String) {
    let project = personalProject()
    let parsed = QuickParser.parse("Задача \(path)", projects: [project], tags: [])
    #expect(parsed.projectID == project.id && parsed.section == nil)
    #expect(parsed.item().section == "Без раздела" && parsed.title == "Задача")
    #expect(parsed.warnings.count == 1)
}

@Test func pathCommandsRespectBoundariesAvailabilityAndLiteralOptOut() throws {
    let project = personalProject()
    var archived = Project(name: "Архив"); archived.archived = true
    let note = Project(name: "Заметки", kind: .note)
    let raw = "Ссылка https://example.org/Личное/Спорт и /Личное/Спорт"
    let parsed = QuickParser.parse(raw, projects: [project,archived,note], tags: [])
    #expect(parsed.title == "Ссылка https://example.org/Личное/Спорт и")
    let token = try #require(parsed.tokens.first)
    let selection = NSRange(location: NSMaxRange(token.range), length: 0)
    #expect(QuickLiteralToken.tokenToLiteralize(parsed: parsed, selection: selection, backward: true) == token)
    let literal = QuickParser.parse(raw, projects: [project], tags: [], literalRanges: [token.range])
    #expect(literal.title == raw && literal.projectID == nil)
    for path in ["/Архив", "/Заметки", "/ЛичноеДругое", "/Неизвестный/Спорт"] {
        let unknown = QuickParser.parse("Дело " + path, projects: [project,archived,note], tags: [])
        #expect(unknown.projectID == nil && unknown.title == "Дело " + path)
    }
}

@Test func pathReservedCharactersRoundTripAndProjectOnlyRemainsCompatible() {
    var project = Project(name: "Дом/работа")
    project.sections = ["Без раздела", "Этап \"А\""]
    let path = QuickProjectPath.command(project.name, section: project.sections[1])
    let parsed = QuickParser.parse("Дело " + path, projects: [project], tags: [])
    #expect(parsed.projectID == project.id && parsed.section == project.sections[1] && parsed.title == "Дело")
    let plain = personalProject()
    for spelling in ["/Личное", "/\"Личное\""] {
        let result = QuickParser.parse("Дело " + spelling, projects: [plain], tags: [])
        #expect(result.projectID == plain.id && result.section == nil && result.title == "Дело")
    }
}

@Test func competingProjectPathsStayStableWhenFormConsumesAllCommands() {
    let personal = personalProject()
    var work = Project(name: "Работа"); work.sections = ["Без раздела", "Планы"]
    let text = "Дело /Личное/Спорт /Работа/Планы"
    let quick = QuickParser.parse(text, projects: [personal,work], tags: [])
    #expect(quick.projectID == work.id && quick.section == "Планы")
    #expect(quick.title == "Дело /Личное/Спорт" && quick.warnings.isEmpty)
    let form = QuickParser.parse(text, projects: [personal,work], tags: [], consumeRedundantCommands: true)
    #expect(form.title == "Дело" && form.projectID == work.id && form.section == "Планы")
}

@Test func stageSurvivesSQLiteAndExistingAccountWireTypes() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let project = personalProject()
    let item = QuickParser.parse("Тренировка /Личное/Спорт", projects: [project], tags: []).item()
    var snapshot = Snapshot(); snapshot.projects = [project]; snapshot.items = [item]
    let db = try Database(url: root.appendingPathComponent("path.sqlite"))
    try db.save(snapshot)
    let loaded = try db.load()
    #expect(loaded.items.first?.projectID == project.id && loaded.items.first?.section == "Спорт")
    let account = UUID().uuidString.lowercased()
    let records = try AccountCodec.records(loaded, accountID: account)
    let record = try #require(records.first { $0.kind == "task" })
    #expect(record.data["projectID"] == .string(project.id.uuidString.lowercased()))
    #expect(record.data["section"] == .string("Спорт"))
    var restored = Snapshot()
    try AccountCodec.apply(records, to: &restored)
    #expect(restored.items.first?.section == "Спорт" && restored.items.first?.projectID == project.id)
}
