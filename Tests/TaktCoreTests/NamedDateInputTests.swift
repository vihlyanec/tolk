import Foundation
import Testing
@testable import TaktCore

private let namedDateCalendar = Dates.calendar()
private func namedDate(_ year: Int = 2026, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    namedDateCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

@Test func namedDateAndBareHourProduceSeparateHighlightTokens() throws {
    let text = "📞 Созвон 12 дек в 10"
    let parsed = QuickParser.parse(text, projects: [], tags: [], now: namedDate(2026, 11, 3))
    #expect(parsed.title == "📞 Созвон")
    #expect(parsed.schedule == .timed(namedDate(2026, 12, 12, 10)))
    #expect(parsed.warnings.isEmpty)
    #expect(parsed.tokens.map(\.kind) == [.date, .time])
    #expect(parsed.tokens.map { (text as NSString).substring(with: $0.range) } == ["12 дек", "в 10"])
    let literal = try #require(parsed.tokens.first)
    let kept = QuickParser.parse(text, projects: [], tags: [], now: namedDate(2026, 11, 3), literalRanges: [literal.range])
    #expect(kept.title == "📞 Созвон 12 дек")
    #expect(kept.tokens.map(\.kind) == [.time])
}

@Test(arguments: Array(zip(["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сент", "окт", "ноя", "дек"], 1...12)))
func russianMonthAbbreviationsParse(argument: (String, Int)) {
    let parsed = QuickParser.parse("Встреча 12 \(argument.0)", projects: [], tags: [], now: namedDate(2026, 1, 1))
    #expect(parsed.title == "Встреча")
    #expect(parsed.schedule == .day(namedDate(2026, argument.1, 12)))
}

@Test(arguments: ["12 дек. 2027", "12 декабря 2027", "12 ДЕКАБРЬ 2027"])
func namedDateAcceptsFullMonthPeriodAndExplicitYear(_ phrase: String) {
    let parsed = QuickParser.parse("Встреча \(phrase) в 10:30", projects: [], tags: [], now: namedDate(2026, 11, 3))
    #expect(parsed.title == "Встреча")
    #expect(parsed.schedule == .timed(namedDate(2027, 12, 12, 10, 30)))
}

@Test(arguments: ["31 апр", "29 фев 2026", "12 декабрик", "12 December"])
func invalidNamedDatesStayInTitle(_ phrase: String) {
    let parsed = QuickParser.parse("Встреча \(phrase)", projects: [], tags: [], now: namedDate(2026, 11, 3))
    #expect(parsed.title == "Встреча \(phrase)")
    #expect(parsed.schedule == .unscheduled)
}

@Test func bareHourDoesNotConsumeNumbersOrInvalidClock() {
    for suffix in ["12 задач", "в 24", "в 10:99", "в 100"] {
        let text = "Проверить \(suffix)"
        let parsed = QuickParser.parse(text, projects: [], tags: [], now: namedDate(2026, 11, 3))
        #expect(parsed.title == text && parsed.schedule == .unscheduled)
    }
    let leap = QuickParser.parse("Встреча 29 февраля 2028 в 0", projects: [], tags: [], now: namedDate(2026, 11, 3))
    #expect(leap.schedule == .timed(namedDate(2028, 2, 29)))
    let today = QuickParser.parse("Созвон завтра в 9", projects: [], tags: [], now: namedDate(2026, 11, 3))
    #expect(today.schedule == .timed(namedDate(2026, 11, 4, 9)))
}
