import AppKit
import Observation
import Security
import TaktCore

private enum AccountKeychain {
    static func query(_ id: UUID) -> [String: Any] { [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"local.tolk.account",kSecAttrAccount as String:id.uuidString] }
    static func save(_ token: String, id: UUID, origin: String, accountID: String) throws {
        var q = query(id); q[kSecValueData as String] = try JSONSerialization.data(withJSONObject:["token":token,"origin":origin,"accountID":accountID.lowercased()]); q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary,nil)
        guard status == errSecSuccess else { throw TaktError.storage("Не удалось сохранить доступ к аккаунту в Связке ключей") }
    }
    static func read(_ id: UUID, origin: String, accountID: String) throws -> String {
        var q = query(id); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary,&result) == errSecSuccess, let data = result as? Data, let saved = (try? JSONSerialization.jsonObject(with:data)) as? [String:String], saved["origin"] == origin, saved["accountID"] == accountID.lowercased(), let token = saved["token"] else { throw TaktError.storage("Подключите аккаунт заново: доступ не найден в Связке ключей") }
        return token
    }
    static func remove(_ id: UUID) { SecItemDelete(query(id) as CFDictionary) }
}
private final class AccountRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                               newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
private enum AccountAccessError: LocalizedError, Equatable {
    case auth, reset
    var errorDescription: String? { self == .auth ? "Нужно подтвердить доступ к аккаунту заново. Локальная очередь сохранена." : "Сервер восстановлен. Сверьте версии перед продолжением обмена." }
}
private struct AccountAPI {
    var origin: String
    func call(_ path: String, _ body: SyncFields, token: String? = nil) async throws -> Data {
        guard let base = URL(string:origin), base.scheme == "https", base.host != nil, base.user == nil, base.password == nil,
              base.path.isEmpty || base.path == "/", base.query == nil, base.fragment == nil,
              let url = URL(string:origin.trimmingCharacters(in:CharacterSet(charactersIn:"/")) + "/api/device/" + path) else { throw TaktError.invalid("Нужен HTTPS-адрес вашего Толка") }
        var request = URLRequest(url:url); request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        if let token { request.setValue("Bearer " + token,forHTTPHeaderField:"Authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        let session = URLSession(configuration:.ephemeral,delegate:AccountRedirectGuard(),delegateQueue:nil)
        defer { session.finishTasksAndInvalidate() }
        let (data,response) = try await session.data(for:request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if (response as? HTTPURLResponse)?.statusCode == 401 { throw AccountAccessError.auth }
            if (response as? HTTPURLResponse)?.statusCode == 409 { throw AccountAccessError.reset }
            let error = try? JSONDecoder().decode(SyncFields.self,from:data)
            throw TaktError.invalid(error?["error"]?.string ?? "Аккаунт недоступен. Изменения сохранены на Mac.")
        }
        return data
    }
}

@Observable final class AccountService {
    weak var state: AppState?
    var origin = "https://tolk.103-102-229-153.sslip.io"
    var status = "Не подключён"
    var busy = false
    var connecting = false
    var accessRequired = false
    var recoveryRequired = false
    private var timer: Timer?
    private var task: Task<Void,Never>?
    private var pairing: Task<Void,Never>?
    private var generation = UUID()
    init(state: AppState) { self.state = state; origin = state.data.accountSync?.origin ?? origin }
    func start() {
        guard state?.isDemo == false, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval:5,repeats:true) { [weak self] _ in Task { @MainActor in self?.sync() } }
        sync()
    }
    func stop() { timer?.invalidate(); timer = nil; task?.cancel(); pairing?.cancel() }
    func changed() { guard !busy else { return }; sync() }
    func connect(reauthorizing: Bool = false) {
        guard let state, !state.isDemo, !connecting, !busy, state.data.accountSync == nil || reauthorizing else { return }
        let existing = state.data.accountSync
        let endpoint = origin.trimmingCharacters(in:CharacterSet(charactersIn:"/ "))
        let api = AccountAPI(origin:endpoint)
        generation = UUID(); let run = generation
        connecting = true; status = "Подтвердите подключение в браузере"
        pairing = Task { [weak self] in
            guard let self else { return }
            defer { self.connecting = false }
            do {
                let data = try await api.call("start",["name":.string(Host.current().localizedName ?? "Мой Mac")])
                let value = try JSONDecoder().decode(SyncFields.self,from:data)
                guard let code = value["code"]?.string, let secret = value["secret"]?.string,
                      let url = URL(string:endpoint + "/?pair=" + code) else { throw TaktError.invalid("Не удалось начать подключение") }
                NSWorkspace.shared.open(url)
                for _ in 0..<115 {
                    try await Task.sleep(for:.seconds(5)); try Task.checkCancellation()
                    let response = try JSONDecoder().decode(SyncFields.self,from:await api.call("poll",["code":.string(code),"secret":.string(secret)]))
                    guard self.generation == run else { return }
                    if response["pending"]?.bool == true { continue }
                    guard let token = response["token"]?.string, let account = response["account"]?.object,
                          let id = account["id"]?.string, let name = account["name"]?.string else { throw TaktError.invalid("Подключение не подтверждено") }
                    if let existing, existing.accountID != id.lowercased() { throw TaktError.invalid("Войдите в тот же аккаунт, чтобы сохранить очередь и связи.") }
                    var connection = existing ?? AccountSyncState(accountID:id,name:name)
                    connection.connectionID = UUID(); connection.origin = endpoint
                    try AccountKeychain.save(token,id:connection.connectionID,origin:endpoint,accountID:id)
                    self.state?.change(undo:false) { $0.accountSync = connection }
                    guard self.state?.data.accountSync?.connectionID == connection.connectionID else { AccountKeychain.remove(connection.connectionID); return }
                    if let existing { AccountKeychain.remove(existing.connectionID) }
                    self.accessRequired = false; self.connecting = false
                    self.status = "Аккаунт подключён. Объединяем данные…"; self.sync(); return
                }
                self.status = "Время подключения истекло. Начните заново."
            } catch { if !Task.isCancelled { self.status = error.localizedDescription } }
        }
    }
    func cancelConnection() { generation = UUID(); pairing?.cancel(); connecting = false; status = "Подключение отменено" }
    func sync() {
        guard let state, !state.isDemo, let connection = state.data.accountSync, !busy, !connecting, !recoveryRequired, !accessRequired else { return }
        let id = connection.connectionID, api = AccountAPI(origin:connection.origin)
        busy = true; status = "Синхронизация…"
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false }
            do {
                let token = try AccountKeychain.read(id,origin:connection.origin,accountID:connection.accountID)
                for _ in 0..<100 {
                    try Task.checkCancellation()
                    guard let current = self.state?.data.accountSync, current.connectionID == id else { return }
                    let operations = AccountEngine.requestOperations(current)
                    let encoded = try JSONDecoder().decode(SyncJSON.self,from:JSONEncoder().encode(operations))
                    var body: SyncFields = ["cursor":.number(Double(current.cursor)),"operations":encoded]
                    if let epoch = current.epoch { body["epoch"] = .string(epoch) }
                    let response = try JSONDecoder().decode(AccountResponse.self,from:await api.call("sync",body,token:token))
                    guard self.state?.data.accountSync?.connectionID == id else { return }
                    if response.results.isEmpty && response.changes.isEmpty && response.epoch == current.epoch && !response.more && operations.isEmpty {
                        self.status = current.conflicts.isEmpty ? "Синхронизировано с аккаунтом «\(current.name)»" : "Нужно выбрать версию: \(current.conflicts.count)"; return
                    }
                    let previous = self.state?.data
                    var failure: Error?
                    var expectedSync: AccountSyncState?
                    self.state?.change(undo:false,notifyServices:false) { snapshot in
                        do { try AccountEngine.receive(response,sent:operations,in:&snapshot); try AccountEngine.enqueue(in:&snapshot); expectedSync = snapshot.accountSync } catch { failure = error }
                    }
                    if let failure { throw failure }
                    guard self.state?.data.accountSync == expectedSync else { throw TaktError.storage("Ответ сервера не сохранён. Очередь оставлена на Mac.") }
                    if let before = previous, let after = self.state?.data,
                       before.items != after.items || before.projects != after.projects || before.tags != after.tags || before.preferences != after.preferences { self.state?.didSave() }
                    if previous?.tickTick?.options != self.state?.data.tickTick?.options || previous?.appleCalendar?.selected != self.state?.data.appleCalendar?.selected { self.state?.syncCoordinator?.refresh() }
                    if !response.more, let latest = self.state?.data.accountSync, AccountEngine.requestOperations(latest).isEmpty {
                        self.status = latest.conflicts.isEmpty ? "Синхронизировано с аккаунтом «\(latest.name)»" : "Нужно выбрать версию: \(latest.conflicts.count)"; return
                    }
                }
                self.status = "Обмен продолжается…"
            } catch {
                if error as? AccountAccessError == .auth { self.accessRequired = true }
                if error as? AccountAccessError == .reset { self.recoveryRequired = true }
                if !Task.isCancelled { self.status = error.localizedDescription }
            }
        }
    }
    func recover() {
        guard let state, !busy, !state.isDemo else { return }
        do {
            let backup = state.dataURL.deletingLastPathComponent().appendingPathComponent("before-account-recovery-\(UUID().uuidString).json")
            try Database.export(state.data,to:backup)
            state.change(undo:false,notifyServices:false) { AccountEngine.recover(in:&$0) }
            recoveryRequired = false; sync()
        } catch { status = error.localizedDescription }
    }
    func resolve(_ id: String, local: Bool) {
        state?.change(undo:false) { snapshot in
            do { try AccountEngine.resolve(id,useLocal:local,in:&snapshot) }
            catch { self.status = error.localizedDescription }
        }
        sync()
    }
    func disconnect() {
        guard let connection = state?.data.accountSync, connection.pending.isEmpty, connection.conflicts.isEmpty, !busy else { status = "Сначала отправьте изменения и выберите версии конфликтов"; return }
        task?.cancel(); generation = UUID()
        state?.change(undo:false) { $0.accountSync = nil }
        AccountKeychain.remove(connection.connectionID)
        status = "Отключено. Данные оставлены на Mac. Доступ устройства можно отозвать в веб-настройках."
    }
}
