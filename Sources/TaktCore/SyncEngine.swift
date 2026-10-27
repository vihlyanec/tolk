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
    public static func ingest(projects: [TickTickProject], tasks: [TickTickTask], inboxIDs: Set<String>, columns: [String: [TickTickColumn]] = [:], into snapshot: inout Snapshot) {
        guard var sync = snapshot.tickTick else { return }
        for remote in projects where !remote.isNote {
            if let key = sync.projects.first(where: { $0.value.remote.id == remote.id })?.key, let id = UUID(uuidString: key) {
                if let i = snapshot.projects.firstIndex(where: { $0.id == id }) {
                    let base = sync.projects[key]!
                    if snapshot.projects[i].name == base.localName { snapshot.projects[i].name = remote.name }
                    if snapshot.projects[i].color == base.localColor { snapshot.projects[i].color = remote.color }
                    if snapshot.projects[i].archived == base.remote.closed { snapshot.projects[i].archived = remote.closed }
                    sync.projects[key] = TickTickProjectLink(remote: remote, local: snapshot.projects[i])
                    sync.projects[key]?.columns = base.columns
                }
            } else {
                var project = Project(name: remote.name, color: remote.color); project.archived = remote.closed
                project.kanban = remote.raw["viewMode"]?.string == "kanban"
                snapshot.projects.append(project); sync.projects[project.id.uuidString] = TickTickProjectLink(remote: remote, local: project)
            }
        }
        for remote in projects where !remote.isNote {
            guard let values = columns[remote.id],
                  let key = sync.projects.first(where: { $0.value.remote.id == remote.id })?.key,
                  let index = snapshot.projects.firstIndex(where: { $0.id.uuidString == key }),
                  var link = sync.projects[key] else { continue }
            importColumns(values, link: &link, project: &snapshot.projects[index], items: &snapshot.items, taskLinks: &sync.links)
            sync.projects[key] = link
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
                importPlacement(remote, original: item, result: &merged, link: &link, sync: sync, localProjectChanged: merge.changed.contains("projectId"))
                var comparable = merged; comparable.modified = item.modified
                if comparable == item { merged.modified = item.modified }
                snapshot.items[index] = merged
                link.remote = remote; link.local = baseline; link.missing = false
                sync.links[key] = link; sync.conflicts[key] = nil; sync.outbox[key] = nil
            } else {
                var item = Item(title: remote.title, projectID: projectID)
                item = TickTickCodec.applying(remote, to: item, snapshot: &snapshot)
                item.projectID = projectID
                var link = TickTickLink(remote: remote, local: TickTickCodec.localFields(item, in: snapshot, remoteProjectID: remote.projectID))
                let original = item
                importPlacement(remote, original: original, result: &item, link: &link, sync: sync, localProjectChanged: false)
                snapshot.items.append(item)
                sync.links[item.id.uuidString] = link
            }
        }
        sync.initialImportDone = true; snapshot.tickTick = sync
        enqueueChanges(in: &snapshot)
    }
    private static func importPlacement(_ remote: TickTickTask, original: Item, result: inout Item, link: inout TickTickLink, sync: TickTickSyncState, localProjectChanged: Bool) {
        guard !localProjectChanged else { return }
        let unchanged = original.section == (link.columnSection ?? "Без раздела")
        let destination = result.projectID.flatMap { sync.projects[$0.uuidString] }
        let label = remote.raw["columnId"]?.string.flatMap { id in destination?.columns?.first { $0.remote.id == id }?.localSection }
        if let label {
            if unchanged { result.section = label }
            // A local drag wins over incoming placement; the remote baseline still
            // advances, so the same pull never silently undoes that local decision.
            link.columnSection = label
        } else if original.projectID != result.projectID {
            // A section from another project cannot follow a remote project move.
            result.section = "Без раздела"; link.columnSection = nil
        }
        // Missing, null, or unknown column IDs never mean 'reset to default'.
    }
    private static func importColumns(_ values: [TickTickColumn], link: inout TickTickProjectLink, project: inout Project, items: inout [Item], taskLinks: inout [String: TickTickLink]) {
        // Defensive validation also protects callers that bypass the HTTP transport.
        guard values.allSatisfy({ !$0.id.isEmpty && $0.projectId == link.remote.id && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(values.map(\.id)).count == values.count else { return }
        let previous = link.columns ?? []
        var next: [TickTickColumnLink] = []
        for column in values.sorted(by: { $0.sortOrder == $1.sortOrder ? $0.id < $1.id : $0.sortOrder < $1.sortOrder }) {
            let old = previous.first { $0.remote.id == column.id }
            var label = old?.localSection ?? column.name
            if old == nil || old?.remote.name != column.name {
                let occupied = Set(project.sections.filter { $0 != old?.localSection })
                label = column.name
                var suffix = 2
                while occupied.contains(label) { label = "\(column.name) (TickTick \(suffix))"; suffix += 1 }
            }
            if let old, old.localSection != label {
                project.sections.removeAll { $0 == old.localSection }
                for i in items.indices where items[i].projectID == project.id && items[i].section == old.localSection { items[i].section = label }
                for key in Array(taskLinks.keys) where taskLinks[key]?.remote.projectID == link.remote.id && taskLinks[key]?.columnSection == old.localSection {
                    taskLinks[key]?.columnSection = label
                }
            }
            if !project.sections.contains(label) { project.sections.append(label) }
            next.append(TickTickColumnLink(remote: column, localSection: label))
        }
        for old in previous where !next.contains(where: { $0.remote.id == old.remote.id }) {
            // Keep a removed stage as a local section if any task still uses it,
            // including deleted tasks that may later be restored. Never lose placement.
            if !items.contains(where: { $0.projectID == project.id && $0.section == old.localSection }) {
                project.sections.removeAll { $0 == old.localSection }
            }
        }
        let imported = Set(next.map(\.localSection))
        project.sections = project.sections.filter { !imported.contains($0) } + next.map(\.localSection)
        link.columns = next
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
