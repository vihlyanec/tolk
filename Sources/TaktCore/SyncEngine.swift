import Foundation

public enum SyncEngine {
    public static func projectID(for item: Item, sync: TickTickSyncState) -> String? {
        guard let id = item.projectID else { return "inbox" }
        return sync.projects[id.uuidString]?.remote.id
    }
    public static func enqueueChanges(in snapshot: inout Snapshot) {
        guard var sync = snapshot.tickTick else { return }
        for item in snapshot.items where item.kind == .task && !item.deleted {
            let key = item.id.uuidString
            guard !sync.localOnly.contains(item.id), let project = projectID(for: item, sync: sync) else { continue }
            let remoteProject = item.projectID == nil ? (sync.links[key]?.remote.projectID ?? project) : project
            let fields = TickTickCodec.localFields(item, in: snapshot, remoteProjectID: remoteProject)
            if let link = sync.links[key] {
                guard sync.conflicts[key] == nil, !link.missing else { continue }
                // An attempted request must first be reconciled with a fresh read.
                if sync.outbox[key]?.attempted == true { continue }
                let changed = Set(fields.keys.filter { fields[$0] != link.local[$0] })
                if changed.isEmpty { sync.outbox[key] = nil; continue }
                let target = TickTickCodec.patch(link.remote, with: fields, keys: changed)
                sync.outbox[key] = TickTickPending(task: target, localFields: fields, creating: link.pendingCreate)
            } else if sync.initialImportDone && (item.projectID != nil || sync.options.sendNewTasks), item.created >= sync.connectedAt {
                var raw = fields; raw["id"] = .string(TickTickCodec.remoteID(item.id))
                let task = TickTickTask(raw)
                sync.links[key] = TickTickLink(remote: task, local: fields, pendingCreate: true)
                sync.outbox[key] = TickTickPending(task: task, localFields: fields, creating: true)
            }
        }
        // A deleted local task remains local-only; never send remote DELETE implicitly.
        sync.outbox = sync.outbox.filter { key, _ in snapshot.items.contains { $0.id.uuidString == key && !$0.deleted } }
        snapshot.tickTick = sync
    }
    public static func ingest(projects: [TickTickProject], tasks: [TickTickTask], inboxIDs: Set<String>, into snapshot: inout Snapshot) {
        guard var sync = snapshot.tickTick else { return }
        for remote in projects where !remote.isNote {
            if let key = sync.projects.first(where: { $0.value.remote.id == remote.id })?.key, let id = UUID(uuidString: key) {
                if let i = snapshot.projects.firstIndex(where: { $0.id == id }) {
                    let base = sync.projects[key]!
                    if snapshot.projects[i].name == base.localName { snapshot.projects[i].name = remote.name }
                    if snapshot.projects[i].color == base.localColor { snapshot.projects[i].color = remote.color }
                    if snapshot.projects[i].archived == base.remote.closed { snapshot.projects[i].archived = remote.closed }
                    sync.projects[key] = TickTickProjectLink(remote: remote, local: snapshot.projects[i])
                }
            } else {
                var project = Project(name: remote.name, color: remote.color); project.archived = remote.closed
                snapshot.projects.append(project); sync.projects[project.id.uuidString] = TickTickProjectLink(remote: remote, local: project)
            }
        }
        snapshot.tickTick = sync
        for remote in tasks where remote.kind != "NOTE" {
            guard !remote.id.isEmpty else { continue }
            let projectID = inboxIDs.contains(remote.projectID) ? nil : sync.projects.first { $0.value.remote.id == remote.projectID }.flatMap { UUID(uuidString: $0.key) }
            // A non-inbox task without a project mapping is incomplete, not a local inbox item.
            guard inboxIDs.contains(remote.projectID) || projectID != nil else { continue }
            if let key = sync.links.first(where: { $0.value.remote.id == remote.id })?.key,
               var link = sync.links[key], let index = snapshot.items.firstIndex(where: { $0.id.uuidString == key }) {
                if let pending = sync.outbox[key], pending.attempted, !link.pendingCreate {
                    let differences = Set(pending.task.fields.keys.filter { pending.task.fields[$0] != remote.fields[$0] })
                    if !differences.isEmpty {
                        sync.conflicts[key] = TickTickConflict(remote: remote, fields: differences)
                        continue
                    }
                    // A lost acknowledgement is reconciled against what was sent, not
                    // the older base. This preserves an Undo performed during the request.
                    link.remote = remote; link.local = pending.localFields; sync.outbox[key] = nil
                }
                if link.pendingCreate, let pending = sync.outbox[key] {
                    link.remote = pending.task; link.local = pending.localFields
                }
                let item = snapshot.items[index]
                let localProject = item.projectID == nil ? link.remote.projectID : (self.projectID(for: item, sync: sync) ?? link.remote.projectID)
                let fields = TickTickCodec.localFields(item, in: snapshot, remoteProjectID: localProject)
                if item.deleted { continue }
                // A pending create found by ID is confirmed and never sent a second time.
                if link.pendingCreate {
                    link.pendingCreate = false; sync.outbox[key] = nil
                }
                let merge = TickTickMerge(baseLocal: link.local, local: fields, baseRemote: link.remote.fields, remote: remote.fields)
                if !merge.conflicts.isEmpty {
                    sync.conflicts[key] = TickTickConflict(remote: remote, fields: merge.conflicts)
                    continue
                }
                var projected = TickTickCodec.applying(remote, to: item, snapshot: &snapshot); projected.projectID = projectID
                let baseline = TickTickCodec.localFields(projected, in: snapshot, remoteProjectID: remote.projectID)
                let combined = TickTickCodec.patch(remote, with: fields, keys: merge.changed)
                var merged = TickTickCodec.applying(combined, to: item, snapshot: &snapshot)
                merged.projectID = merge.changed.contains("projectId") ? item.projectID : projectID
                snapshot.items[index] = merged
                link.remote = remote; link.local = baseline; link.missing = false
                sync.links[key] = link; sync.conflicts[key] = nil; sync.outbox[key] = nil
            } else {
                var item = Item(title: remote.title, projectID: projectID)
                item = TickTickCodec.applying(remote, to: item, snapshot: &snapshot)
                item.projectID = projectID
                snapshot.items.append(item)
                sync.links[item.id.uuidString] = TickTickLink(remote: remote, local: TickTickCodec.localFields(item, in: snapshot, remoteProjectID: remote.projectID))
            }
        }
        sync.initialImportDone = true; snapshot.tickTick = sync
        enqueueChanges(in: &snapshot)
    }
    public static func confirm(key: String, sent: TickTickPending, remote: TickTickTask, in snapshot: inout Snapshot) {
        guard var sync = snapshot.tickTick, var link = sync.links[key] else { return }
        link.remote = remote; link.local = sent.localFields; link.pendingCreate = false; link.missing = false
        sync.links[key] = link; sync.outbox[key] = nil; snapshot.tickTick = sync
        enqueueChanges(in: &snapshot) // Preserve edits made while a network request was suspended.
    }
    public static func resolve(key: String, useLocal: Bool, in snapshot: inout Snapshot) {
        guard var sync = snapshot.tickTick, let conflict = sync.conflicts[key], var link = sync.links[key],
              let index = snapshot.items.firstIndex(where: { $0.id.uuidString == key }) else { return }
        let item = snapshot.items[index]
        var remoteItem = TickTickCodec.applying(conflict.remote, to: item, snapshot: &snapshot)
        remoteItem.projectID = sync.projects.first { $0.value.remote.id == conflict.remote.projectID }.flatMap { UUID(uuidString: $0.key) }
        link.remote = conflict.remote
        link.local = TickTickCodec.localFields(remoteItem, in: snapshot, remoteProjectID: conflict.remote.projectID)
        sync.links[key] = link; sync.conflicts[key] = nil; sync.outbox[key] = nil
        if !useLocal { snapshot.items[index] = remoteItem }
        snapshot.tickTick = sync; enqueueChanges(in: &snapshot)
    }
}
