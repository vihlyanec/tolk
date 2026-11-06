import Foundation
import Testing
@testable import TaktCore

private func cloudResponse(_ records: [AccountRecord], cursor: Int = 1, more: Bool = false, results: [AccountResult] = []) throws -> AccountResponse {
    let encoded = try JSONEncoder().encode(records)
    let json = try JSONSerialization.jsonObject(with:encoded)
    let acks = try JSONSerialization.jsonObject(with:JSONEncoder().encode(results))
    return try JSONDecoder().decode(AccountResponse.self,from:JSONSerialization.data(withJSONObject:["results":acks,"changes":json,"cursor":cursor,"more":more,"epoch":"test-epoch"]))
}
@Test func accountWireRoundTripPreservesAllNativeContentAndAbsoluteTime() throws {
    var original = Snapshot()
    let project = Project(name:"Работа",kind:.task), notes = Project(name:"Записи",kind:.note)
    let tag = Tag(name:"главное")
    original.projects = [project,notes]; original.tags = [tag]
    var item = Item(title:"Полная задача",projectID:project.id)
    item.body = "# Заголовок\nДетали 📝"; item.tagIDs = [tag.id]; item.section = "В работе"; item.duration = 95
    item.schedule = .timed(Date(timeIntervalSince1970:1794477600)); item.recurrence = .intervalDays; item.repeatEveryDays = 3
    item.timedReminderOffsets = [0,15,60]; item.checklist = [CheckItem(title:"Шаг")]; item.stickyFrame = [10,20,300,200]
    var note = Item(title:"Заметка",kind:.note,projectID:notes.id); note.stickyColor = "AD94E8"; note.body = "Содержимое"
    original.items = [item,note]; original.preferences.timeZone = "Asia/Dubai"; original.preferences.grouping = ["all":"Дата"]
    let records = try AccountCodec.records(original,accountID:UUID().uuidString)
    var restored = Snapshot(); try AccountCodec.apply(records,to:&restored)
    #expect(restored.projects == original.projects && restored.tags == original.tags)
    #expect(restored.items == original.items && restored.preferences == original.preferences)
    restored.preferences.timeZone = "Europe/London"
    try AccountCodec.apply(records.filter { $0.kind == "task" },to:&restored)
    #expect(restored.items[0].schedule == item.schedule)
}
@Test func cloudDoesNotUploadTickTickKeysOutboxOrLocalDatabasePaths() throws {
    var snapshot = Snapshot(); snapshot.tickTick = TickTickSyncState(connectionID:UUID())
    let data = try JSONEncoder().encode(AccountCodec.records(snapshot,accountID:UUID().uuidString))
    let json = String(decoding:data,as:UTF8.self)
    #expect(!json.contains("connectionID") && !json.contains("outbox") && !json.contains("accountSync"))
}
@Test func cloudOutboxSurvivesRestartAndRemoteChangesPreserveNewerLocalEdits() throws {
    let account = UUID().uuidString
    var snapshot = Snapshot(); let item = Item(title:"До")
    snapshot.items = [item]; snapshot.accountSync = AccountSyncState(accountID:account,name:"QA")
    let records = try AccountCodec.records(snapshot,accountID:account).map { r in var v=r;v.version=1;return v }
    try AccountEngine.receive(cloudResponse(records),sent:[],in:&snapshot)
    snapshot.items[0].title = "Мой заголовок"; try AccountEngine.enqueue(in:&snapshot)
    snapshot = try JSONDecoder().decode(Snapshot.self,from:JSONEncoder().encode(snapshot))
    let sent = AccountEngine.requestOperations(snapshot.accountSync!)
    #expect(sent.count == 1 && sent[0].patch == ["title":.string("Мой заголовок")])
    snapshot.items[0].body = "Дополнение во время сети"; try AccountEngine.enqueue(in:&snapshot)
    var remote = records.first { $0.kind == "task" }!; remote.version = 2; remote.data["title"] = .string("Мой заголовок")
    let ack = try JSONDecoder().decode(AccountResult.self,from:JSONSerialization.data(withJSONObject:["id":sent[0].id,"accepted":true,"record":JSONSerialization.jsonObject(with:JSONEncoder().encode(remote))]))
    try AccountEngine.receive(cloudResponse([remote],cursor:2,results:[ack]),sent:sent,in:&snapshot)
    #expect(snapshot.items[0].title == "Мой заголовок" && snapshot.items[0].body == "Дополнение во время сети")
    #expect(snapshot.accountSync?.pending.count == 1)
}
@Test func cloudInvalidReplyIsTransactionalAndChangedServerEpochCannotAcknowledgeOutbox() throws {
    var snapshot = Snapshot(); snapshot.accountSync = AccountSyncState(accountID:UUID().uuidString,name:"QA")
    snapshot.items = [Item(title:"Личная задача")]; try AccountEngine.enqueue(in:&snapshot)
    let before = snapshot
    let invalid = AccountRecord(id:UUID().uuidString,kind:"task",version:1,data:["title":.string("Ошибка"),"duration":.number(-1)])
    #expect(throws:(any Error).self) { try AccountEngine.receive(cloudResponse([invalid]),sent:[],in:&snapshot) }
    #expect(snapshot == before)
    snapshot.accountSync?.epoch = "previous-server"
    let protected = snapshot
    #expect(throws:(any Error).self) { try AccountEngine.receive(cloudResponse([]),sent:[],in:&snapshot) }
    #expect(snapshot == protected)
}
@Test func recoveringServerKeepsLocalVersionsUntilExplicitDecisionAndDoesNotReuploadDiscardedItems() throws {
    var snapshot = Snapshot(); snapshot.accountSync = AccountSyncState(accountID:UUID().uuidString,name:"QA")
    snapshot.accountSync?.epoch = "old"
    let local = Item(title:"Сохранить до выбора");snapshot.items = [local]
    AccountEngine.recover(in:&snapshot)
    #expect(AccountEngine.requestOperations(snapshot.accountSync!).isEmpty)
    try AccountEngine.receive(cloudResponse([]),sent:[],in:&snapshot)
    #expect(snapshot.items.contains { $0.id == local.id })
    let conflict = try #require(snapshot.accountSync?.conflicts.first { $0.operation.kind == "task" })
    try AccountEngine.resolve(conflict.id,useLocal:false,in:&snapshot)
    try AccountEngine.enqueue(in:&snapshot)
    #expect(snapshot.items.isEmpty)
    #expect(!snapshot.accountSync!.pending.contains { $0.entityID == local.id.uuidString.lowercased() })
}
@Test func nativeRecordsTravelThroughRealPythonServerWithoutLosingMetadata() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer { try? FileManager.default.removeItem(at:directory) }
    var snapshot = Snapshot()
    let project = Project(name:"Interop"); let tag = Tag(name:"Метка")
    snapshot.projects = [project]; snapshot.tags = [tag]
    var item = Item(title:"Mac → iPhone",projectID:project.id)
    item.tagIDs = [tag.id]; item.duration = 95; item.checklist = [CheckItem(title:"Не потерять пункт")]
    item.timedReminderOffsets = [0,15]; item.recurrence = .weekly; item.schedule = .timed(Date(timeIntervalSince1970:1794477600))
    snapshot.items = [item]
    let input = directory.appendingPathComponent("input.json"), output = directory.appendingPathComponent("output.json")
    try JSONEncoder().encode(AccountCodec.records(snapshot,accountID:UUID().uuidString)).write(to:input)
    let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let script = root.appendingPathComponent("web/tests/account_interop.py")
    try #require(FileManager.default.fileExists(atPath:script.path))
    let process = Process();process.executableURL = URL(fileURLWithPath:"/usr/bin/env")
    process.arguments = ["python3",script.path,input.path,output.path]
    process.standardOutput = FileHandle.nullDevice;process.standardError = FileHandle.standardError
    try process.run();process.waitUntilExit(); #expect(process.terminationStatus == 0)
    let response = try JSONDecoder().decode(AccountResponse.self,from:Data(contentsOf:output))
    snapshot.accountSync = AccountSyncState(accountID:UUID().uuidString,name:"QA")
    try AccountEngine.receive(response,sent:[],in:&snapshot)
    let restored = try #require(snapshot.items.first { $0.id == item.id })
    #expect(restored.body == "Изменено на iPhone")
    #expect(restored.checklist == item.checklist && restored.tagIDs == item.tagIDs && restored.duration == 95)
    #expect(restored.schedule == item.schedule && restored.timedReminderOffsets == item.timedReminderOffsets && restored.recurrence == .weekly)
    let child = try #require(snapshot.items.first { $0.repeatParentID == item.id })
    let expected = try #require(RecurringCalendar.next(item,in:[item],calendar:Dates.calendar()))
    #expect(child.id == expected.id && child.schedule == expected.schedule)
}
@Test func unknownOrIncorrectAcknowledgementNeverDropsLocalOperation() throws {
    var snapshot = Snapshot();snapshot.accountSync = AccountSyncState(accountID:UUID().uuidString,name:"QA")
    snapshot.accountSync?.epoch = "test-epoch";snapshot.items = [Item(title:"Не потерять")]
    try AccountEngine.enqueue(in:&snapshot)
    let sent = Array(AccountEngine.requestOperations(snapshot.accountSync!).filter { $0.kind == "task" }.prefix(1))
    let before = snapshot
    let wrong = AccountRecord(id:UUID().uuidString,kind:sent[0].kind,version:1,data:sent[0].patch)
    let ack = try JSONDecoder().decode(AccountResult.self,from:JSONSerialization.data(withJSONObject:["id":sent[0].id,"accepted":true,"record":JSONSerialization.jsonObject(with:JSONEncoder().encode(wrong))]))
    #expect(throws:(any Error).self) { try AccountEngine.receive(cloudResponse([],results:[ack]),sent:sent,in:&snapshot) }
    #expect(snapshot == before)
}
