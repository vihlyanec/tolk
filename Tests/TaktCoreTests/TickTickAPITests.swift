import Foundation
import Testing
@testable import TaktCore

private actor StubTickTickTransport: TickTickTransport {
    var requests: [URLRequest] = []
    var replies: [(Int, String)]
    init(_ replies: [(Int, String)]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.networkConnectionLost) }
        let (status, body) = replies.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: [:])!)
    }
}
@Test func tickTickPullIncludesUndatedInboxAndPaginatesWithoutWrites() async throws {
    let transport = StubTickTickTransport([(200, #"[{"id":"project1","name":"Work"}]"#),
        (200, #"{"project":{"id":"actual-inbox"},"tasks":[{"id":"inbox-task","projectId":"actual-inbox","title":"Без даты"}]}"#),
        (200, #"{"tasks":[{"id":"task2","projectId":"project1","title":"Work"}]}"#)])
    let pull = try await TickTickAPI(token: "test-fixture", transport: transport).pull()
    #expect(pull.tasks.count == 2 && pull.inboxIDs.contains("actual-inbox"))
    let requests = await transport.requests
    #expect(requests.count == 3 && requests.allSatisfy { $0.httpMethod == "GET" })
    #expect(requests[0].url?.query?.contains("offset=0&limit=200") == true)
}
@Test func tickTickFilterAtLimitRefusesPartialImport() async throws {
    let rows = (0..<200).map { #"{"id":"task\#($0)","projectId":"inbox"}"# }.joined(separator: ",")
    let transport = StubTickTickTransport([(200, "[]"), (404, ""), (200, "[" + rows + "]")])
    do { _ = try await TickTickAPI(token: "test-fixture", transport: transport).pull(); Issue.record("Partial import accepted") }
    catch let error as TickTickAPIError { if case .incomplete = error {} else { Issue.record("Wrong failure") } }
}
@Test func tickTickHTTPFailuresAreTypedAndDoNotExposeResponse() async {
    for (status, expected) in [(401, TickTickAPIError.authentication), (403, .forbidden), (404, .missing), (429, .rateLimited), (503, .server(503))] {
        let transport = StubTickTickTransport([(status, "sensitive response fixture")])
        do { _ = try await TickTickAPI(token: "test-fixture", transport: transport).request("project"); Issue.record("Expected HTTP failure") }
        catch let error as TickTickAPIError { #expect(error == expected); #expect(!error.localizedDescription.contains("sensitive")) }
        catch { Issue.record("Unexpected error") }
    }
}
@Test func tickTickBatchPreservesUnknownFieldsAndReadsAcknowledgement() async throws {
    let transport = StubTickTickTransport([(200, #"{"id2etag":{"task1":"v2"},"id2error":{}}"#),
        (200, #"{"id":"task1","projectId":"inbox","title":"Saved","future":{"a":1}}"#)])
    let task = TickTickTask(["id": .string("task1"), "projectId": .string("inbox"), "title": .string("Saved"), "future": .object(["a": .number(1)])])
    let result = try await TickTickAPI(token: "test-fixture", transport: transport).save(task, creating: true)
    #expect(result.id == "task1")
    let requests = await transport.requests
    let body = try JSONDecoder().decode(SyncFields.self, from: requests[0].httpBody!)
    #expect(body["add"]?.array?.first?.object?["future"] == task.raw["future"])
    #expect(requests[1].httpMethod == "GET")
}
@Test func tickTickLostCreateResponseDoesNotConfirmPendingWrite() async throws {
    let transport = StubTickTickTransport([])
    let api = TickTickAPI(token: "test-fixture", transport: transport)
    let task = TickTickTask(["id": .string("task1"), "projectId": .string("inbox"), "title": .string("Тест")])
    do { _ = try await api.save(task, creating: true); Issue.record("Expected disconnect") }
    catch { #expect(await transport.requests.count == 1) }
}
@Test func tickTickOnlyDefinitiveRejectionsAllowAutomaticRetry() {
    #expect(TickTickAPIError.rateLimited.definitelyRejected)
    #expect(TickTickAPIError.authentication.definitelyRejected)
    #expect(!TickTickAPIError.server(503).definitelyRejected)
    #expect(!TickTickAPIError.malformed.definitelyRejected)
}
