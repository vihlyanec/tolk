import Foundation

public enum TickTickAPIError: LocalizedError, Equatable, Sendable {
    case authentication, forbidden, missing, rateLimited, server(Int), malformed, incomplete(String), refused(String)
    public var definitelyRejected: Bool {
        switch self {
        case .authentication, .forbidden, .rateLimited, .refused: true
        default: false
        }
    }
    public var errorDescription: String? {
        switch self {
        case .authentication: "Срок доступа TickTick истёк. Подключите аккаунт заново."
        case .forbidden: "TickTick не разрешил операцию. Проверьте права доступа подключения."
        case .missing: "Запись TickTick недоступна."
        case .rateLimited: "TickTick ограничил частоту запросов. Повторим позже."
        case .server(let code): "TickTick ответил ошибкой HTTP \(code). Изменения остаются на Mac."
        case .malformed: "TickTick вернул неполный или неизвестный ответ. Синхронизация остановлена."
        case .incomplete(let message), .refused(let message): message
        }
    }
}
public protocol TickTickTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
public struct TickTickURLTransport: TickTickTransport {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 40
        session = URLSession(configuration: config)
    }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw TickTickAPIError.malformed }
        return (data, response)
    }
}
public struct TickTickPull: Sendable {
    public var projects: [TickTickProject]
    public var tasks: [TickTickTask]
    public var inboxIDs: Set<String>
    /// A missing key means unknown, whereas an empty array is a confirmed empty list.
    public var columns: [String: [TickTickColumn]]
    public init(projects: [TickTickProject], tasks: [TickTickTask], inboxIDs: Set<String>, columns: [String: [TickTickColumn]] = [:]) {
        self.projects = projects; self.tasks = tasks; self.inboxIDs = inboxIDs; self.columns = columns
    }
}
public struct TickTickAPI: Sendable {
    private let token: String
    private let transport: any TickTickTransport
    public init(token: String, transport: any TickTickTransport = TickTickURLTransport()) { self.token = token; self.transport = transport }
    private func component(_ raw: String) throws -> String {
        guard !raw.isEmpty, raw.utf8.count < 256, raw.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { throw TickTickAPIError.malformed }
        return raw
    }
    public func request(_ path: String, method: String = "GET", body: SyncJSON? = nil) async throws -> Data {
        guard let url = URL(string: "https://api.ticktick.com/open/v1/" + path) else { throw TickTickAPIError.malformed }
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200..<300: return data
        case 401: throw TickTickAPIError.authentication
        case 403: throw TickTickAPIError.forbidden
        case 404: throw TickTickAPIError.missing
        case 429: throw TickTickAPIError.rateLimited
        default: throw TickTickAPIError.server(response.statusCode)
        }
    }
    public func projects() async throws -> [TickTickProject] {
        var result: [TickTickProject] = [], seen: Set<String> = []
        for page in 0..<500 {
            let previous = seen
            let data = try await request("project?offset=\(page * 200)&limit=200")
            let values = try JSONDecoder().decode([TickTickProject].self, from: data)
            guard values.allSatisfy({ !$0.id.isEmpty }) else { throw TickTickAPIError.malformed }
            for project in values where !seen.contains(project.id) { result.append(project); seen.insert(project.id) }
            if values.count < 200 { return result }
            if page > 0 && values.allSatisfy({ previous.contains($0.id) }) { throw TickTickAPIError.incomplete("TickTick не применил постраничную загрузку проектов. Данные не удалялись.") }
        }
        throw TickTickAPIError.incomplete("Слишком много проектов для одного прохода синхронизации.")
    }
    private struct ProjectData: Decodable {
        var project: TickTickProject?
        var tasks: [TickTickTask]
        var columns: [TickTickColumn]?
    }
    private func checkedColumns(_ values: [TickTickColumn], projectID: String) throws -> [TickTickColumn] {
        guard values.allSatisfy({ !$0.id.isEmpty && $0.projectId == projectID && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(values.map(\.id)).count == values.count else { throw TickTickAPIError.malformed }
        return values.sorted { $0.sortOrder == $1.sortOrder ? $0.id < $1.id : $0.sortOrder < $1.sortOrder }
    }
    public func columns(projectID: String) async throws -> [TickTickColumn] {
        let data = try await request("project/\(component(projectID))/column")
        return try checkedColumns(JSONDecoder().decode([TickTickColumn].self, from: data), projectID: projectID)
    }
    private func projectData(_ id: String) async throws -> (TickTickProject?, [TickTickTask], [TickTickColumn]?) {
        let data = try await request("project/\(component(id))/data")
        let object = try JSONDecoder().decode(ProjectData.self, from: data)
        guard object.tasks.allSatisfy({ !$0.id.isEmpty }),
              id == "inbox" || object.project == nil || object.project?.id == id else { throw TickTickAPIError.malformed }
        let columns = try object.columns.map { try checkedColumns($0, projectID: object.project?.id ?? id) }
        return (object.project, object.tasks, columns)
    }
    public func pull(includeNotes: Bool = false) async throws -> TickTickPull {
        var projects = try await projects(), tasks: [TickTickTask] = [], inboxIDs: Set<String> = ["inbox"]
        var columns: [String: [TickTickColumn]] = [:]
        do {
            let (inbox, values, _) = try await projectData("inbox")
            if let inbox, !inbox.id.isEmpty { inboxIDs.insert(inbox.id) }
            inboxIDs.formUnion(values.map(\.projectID)); tasks += values
        } catch let error as TickTickAPIError where error == .missing || error == .forbidden {
            let data = try await request("task/filter", method: "POST", body: .object(["projectIds": .array([.string("inbox")]), "status": .array([.number(0)])]))
            let inbox = try JSONDecoder().decode([TickTickTask].self, from: data)
            guard inbox.allSatisfy({ !$0.id.isEmpty && !$0.projectID.isEmpty }) else { throw TickTickAPIError.malformed }
            guard inbox.count < 200 else { throw TickTickAPIError.incomplete("Во «Входящих» TickTick получен лимит 200 задач. Полнота загрузки не подтверждена; импорт не применён.") }
            inboxIDs.formUnion(inbox.map(\.projectID)); tasks += inbox
        }
        projects.removeAll { inboxIDs.contains($0.id) }
        for project in projects where includeNotes || !project.isNote {
            let (_, values, stages) = try await projectData(project.id); tasks += values
            columns[project.id] = stages
        }
        var seen: Set<String> = []
        tasks = tasks.filter { !$0.id.isEmpty && (includeNotes || $0.kind != "NOTE") && seen.insert($0.id).inserted }
        return TickTickPull(projects: projects.filter { includeNotes || !$0.isNote }, tasks: tasks, inboxIDs: inboxIDs, columns: columns)
    }
    public func task(projectID: String, id: String) async throws -> TickTickTask? {
        do {
            let data = try await request("project/\(component(projectID))/task/\(component(id))")
            let task = try JSONDecoder().decode(TickTickTask.self, from: data)
            guard task.id == id else { throw TickTickAPIError.malformed }; return task
        } catch TickTickAPIError.missing { return nil }
    }
    public func save(_ task: TickTickTask, creating: Bool) async throws -> TickTickTask {
        let body = task.raw // Preserve properties unknown to this client.
        let result = try await request("task/batch", method: "POST", body: .object([creating ? "add" : "update": .array([.object(body)])]))
        let ack = try JSONDecoder().decode(SyncFields.self, from: result)
        if let code = ack["id2error"]?.object?[task.id]?.string, code != "EXISTED" {
            throw TickTickAPIError.refused("TickTick не принял изменение (\(code)). Локальная версия сохранена.")
        }
        guard ack["id2etag"]?.object?[task.id] != nil || ack["id2error"]?.object?[task.id]?.string == "EXISTED" else { throw TickTickAPIError.malformed }
        guard let remote = try await self.task(projectID: task.projectID, id: task.id) else { throw TickTickAPIError.malformed }
        return remote
    }
    public func move(_ task: TickTickTask, to project: String) async throws -> TickTickTask {
        _ = try await request("task/move", method: "POST", body: .array([.object(["fromProjectId": .string(task.projectID), "toProjectId": .string(project), "taskId": .string(task.id)])]))
        guard let moved = try await self.task(projectID: project, id: task.id), moved.projectID == project || project == "inbox" else { throw TickTickAPIError.malformed }
        return moved
    }
    public func complete(_ task: TickTickTask) async throws -> TickTickTask {
        _ = try await request("project/\(component(task.projectID))/task/\(component(task.id))/complete", method: "POST")
        guard let remote = try await self.task(projectID: task.projectID, id: task.id), remote.completed else { throw TickTickAPIError.malformed }
        return remote
    }
    public func delete(_ task: TickTickTask) async throws {
        _ = try await request("project/\(component(task.projectID))/task/\(component(task.id))", method: "DELETE")
    }
    public func createProject(_ project: Project) async throws -> TickTickProject {
        let data = try await request("project", method: "POST", body: .object(["name": .string(project.name), "color": .string("#" + project.color), "kind": .string(project.kind == .note ? "NOTE" : "TASK")]))
        let result = try JSONDecoder().decode(TickTickProject.self, from: data)
        guard !result.id.isEmpty else { throw TickTickAPIError.malformed }; return result
    }
}
