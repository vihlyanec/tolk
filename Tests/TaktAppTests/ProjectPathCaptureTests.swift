import Foundation
import AppKit
import Testing
import TaktCore
@testable import Takt

@MainActor private func pathProject() -> Project {
    var project = Project(name: "Личное пространство")
    project.sections = ["Без раздела", "Спорт", "Спорт силовой"]
    return project
}

@Test @MainActor func formDefersPathsWithSpacesThenCommitsExactStage() throws {
    let project = pathProject()
    var draft = TaskCreationDraft()
    for text in ["План /Личное ", "План /Личное пространство/Спорт ", "План /Личное пространство/Спорт силовой "] {
        draft.item.title = text
        draft.recognize(projects: [project], tags: [], finishing: false)
        #expect(draft.item.title == text && draft.item.projectID == nil)
    }
    draft.recognize(projects: [project], tags: [])
    #expect(draft.item.title == "План " && draft.item.section == "Спорт силовой")
    let state = AppState(demo: true); state.data.projects.append(project)
    let id = try #require(state.capture(draft.item))
    #expect(state.item(id)?.projectID == project.id && state.item(id)?.section == "Спорт силовой")
    draft.item.title += "подробности "
    draft.recognize(projects: [project], tags: [])
    #expect(draft.item.section == "Спорт силовой")
    draft.item.title += "/Личное пространство/Нет "
    draft.recognize(projects: [project], tags: [])
    #expect(draft.item.projectID == project.id && draft.item.section == "Без раздела")
}

@Test @MainActor func projectSuggestionsReplaceWholeUTF16PathAndUseProjectColor() throws {
    let project = pathProject()
    let text = "🏋️ План /Личное пространство/Спорт си"
    let choices = try #require(CaptureSuggestion.projectPaths(in: text, projects: [project]))
    let choice = try #require(choices.first)
    #expect(choices.count == 1 && choice.title == "Личное пространство / Спорт силовой")
    let applied = choice.applying(to: text, lastToken: "си")
    #expect(applied == "🏋️ План /Личное пространство/Спорт силовой ")
    let parsed = QuickParser.parse(applied, projects: [project], tags: [])
    #expect(parsed.section == "Спорт силовой" && parsed.title == "🏋️ План")
    let token = try #require(parsed.tokens.first)
    #expect(SemanticTint.token(token, projects: [project], tags: [], dark: true) == SemanticTint.color(hex: project.color, dark: true))
    let legacy = try #require(CaptureSuggestion.projectPaths(in: "План /\"Личное пространство\"/\"Спорт", projects: [project]))
    #expect(legacy.count == 2 && legacy.allSatisfy { !$0.replacement.contains("\"") })
    #expect(CaptureSuggestion.projectPaths(in: applied, projects: [project]) == nil)
    #expect(CaptureSuggestion.projectPaths(in: "https://example.org/abc", projects: [project]) == nil)
}

@Test @MainActor func quickCapturePersistsStageAndUnknownSectionDefaults() throws {
    let project = pathProject()
    let state = AppState(demo: true); state.data.projects.append(project)
    for (suffix, section) in [("Спорт", "Спорт"), ("Нет", "Без раздела")] {
        let parsed = QuickParser.parse("Тренировка /Личное пространство/" + suffix, projects: [project], tags: [])
        let id = try #require(state.capture(parsed))
        #expect(state.item(id)?.section == section && state.item(id)?.projectID == project.id)
    }
}

@Test @MainActor func pathCompletionIgnoresSlashesInsideQuotedComponents() throws {
    var project = Project(name: "Дом / работа")
    project.sections = ["Без раздела", "Этап / один"]
    let text = "🏠 План /\"Дом / работа\"/Этап"
    let choices = try #require(CaptureSuggestion.projectPaths(in: text, projects: [project]))
    let choice = try #require(choices.first)
    let applied = choice.applying(to: text, lastToken: "Этап")
    let parsed = QuickParser.parse(applied, projects: [project], tags: [])
    #expect(parsed.projectID == project.id && parsed.section == "Этап / один" && parsed.title == "🏠 План")
}
