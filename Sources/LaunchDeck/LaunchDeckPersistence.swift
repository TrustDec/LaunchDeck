import CoreData
import Foundation

@MainActor
final class LaunchDeckPersistenceController {
    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "LaunchDeck", managedObjectModel: model)

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.persistentStoreDescriptions.forEach {
            $0.shouldMigrateStoreAutomatically = true
            $0.shouldInferMappingModelAutomatically = true
        }

        container.loadPersistentStores { _, error in
            if let error {
                LaunchDeckDiagnostics.log("core data store load failed: \(error.localizedDescription)")
            }
        }

        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    func loadLayout() -> [LaunchItem]? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "LayoutEntry")
        let records = (try? container.viewContext.fetch(request)) ?? []
        guard !records.isEmpty else {
            return nil
        }

        let entries: [StoredLayoutEntry] = records.compactMap { record in
            guard let id = record.value(forKey: "id") as? UUID,
                  let kind = record.value(forKey: "kind") as? String else {
                return nil
            }

            return StoredLayoutEntry(
                id: id,
                parentID: record.value(forKey: "parentID") as? UUID,
                title: record.value(forKey: "title") as? String ?? "Item",
                subtitle: record.value(forKey: "subtitle") as? String,
                kind: kind,
                bundlePath: record.value(forKey: "bundlePath") as? String,
                orderIndex: record.value(forKey: "orderIndex") as? Int64 ?? 0
            )
        }

        let entriesByParent = Dictionary(grouping: entries, by: \.parentID)
        return materialize(parentID: nil, entriesByParent: entriesByParent)
    }

    func saveLayout(items: [LaunchItem]) {
        let context = container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "LayoutEntry")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        _ = try? context.execute(deleteRequest)

        guard let entity = NSEntityDescription.entity(forEntityName: "LayoutEntry", in: context) else {
            return
        }

        for entry in flatten(items: items, parentID: nil) {
            let record = NSManagedObject(entity: entity, insertInto: context)
            record.setValue(entry.id, forKey: "id")
            record.setValue(entry.parentID, forKey: "parentID")
            record.setValue(entry.title, forKey: "title")
            record.setValue(entry.subtitle, forKey: "subtitle")
            record.setValue(entry.kind, forKey: "kind")
            record.setValue(entry.bundlePath, forKey: "bundlePath")
            record.setValue(entry.orderIndex, forKey: "orderIndex")
        }

        do {
            try context.save()
        } catch {
            LaunchDeckDiagnostics.log("core data layout save failed: \(error.localizedDescription)")
        }
    }

    func loadSnapshot() -> LaunchDeckSnapshot? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "SnapshotRecord")
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        guard let record = try? container.viewContext.fetch(request).first,
              let payload = record.value(forKey: "payload") as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(LaunchDeckSnapshot.self, from: payload)
    }

    func saveSnapshot(items: [LaunchItem]) {
        let context = container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "SnapshotRecord")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        _ = try? context.execute(deleteRequest)

        guard let entity = NSEntityDescription.entity(forEntityName: "SnapshotRecord", in: context) else {
            return
        }

        let record = NSManagedObject(entity: entity, insertInto: context)
        record.setValue(UUID(), forKey: "id")
        record.setValue(Date(), forKey: "updatedAt")
        record.setValue(try? JSONEncoder().encode(LaunchDeckSnapshot(items: items)), forKey: "payload")

        do {
            try context.save()
        } catch {
            LaunchDeckDiagnostics.log("core data save failed: \(error.localizedDescription)")
        }
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let snapshotEntity = NSEntityDescription()
        snapshotEntity.name = "SnapshotRecord"
        snapshotEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let snapshotIDAttribute = NSAttributeDescription()
        snapshotIDAttribute.name = "id"
        snapshotIDAttribute.attributeType = .UUIDAttributeType
        snapshotIDAttribute.isOptional = false

        let updatedAtAttribute = NSAttributeDescription()
        updatedAtAttribute.name = "updatedAt"
        updatedAtAttribute.attributeType = .dateAttributeType
        updatedAtAttribute.isOptional = false

        let payloadAttribute = NSAttributeDescription()
        payloadAttribute.name = "payload"
        payloadAttribute.attributeType = .binaryDataAttributeType
        payloadAttribute.isOptional = false
        payloadAttribute.allowsExternalBinaryDataStorage = true

        snapshotEntity.properties = [snapshotIDAttribute, updatedAtAttribute, payloadAttribute]

        let layoutEntity = NSEntityDescription()
        layoutEntity.name = "LayoutEntry"
        layoutEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let idAttribute = NSAttributeDescription()
        idAttribute.name = "id"
        idAttribute.attributeType = .UUIDAttributeType
        idAttribute.isOptional = false

        let parentIDAttribute = NSAttributeDescription()
        parentIDAttribute.name = "parentID"
        parentIDAttribute.attributeType = .UUIDAttributeType
        parentIDAttribute.isOptional = true

        let titleAttribute = NSAttributeDescription()
        titleAttribute.name = "title"
        titleAttribute.attributeType = .stringAttributeType
        titleAttribute.isOptional = false

        let subtitleAttribute = NSAttributeDescription()
        subtitleAttribute.name = "subtitle"
        subtitleAttribute.attributeType = .stringAttributeType
        subtitleAttribute.isOptional = true

        let kindAttribute = NSAttributeDescription()
        kindAttribute.name = "kind"
        kindAttribute.attributeType = .stringAttributeType
        kindAttribute.isOptional = false

        let bundlePathAttribute = NSAttributeDescription()
        bundlePathAttribute.name = "bundlePath"
        bundlePathAttribute.attributeType = .stringAttributeType
        bundlePathAttribute.isOptional = true

        let orderIndexAttribute = NSAttributeDescription()
        orderIndexAttribute.name = "orderIndex"
        orderIndexAttribute.attributeType = .integer64AttributeType
        orderIndexAttribute.isOptional = false

        layoutEntity.properties = [
            idAttribute,
            parentIDAttribute,
            titleAttribute,
            subtitleAttribute,
            kindAttribute,
            bundlePathAttribute,
            orderIndexAttribute,
        ]

        model.entities = [snapshotEntity, layoutEntity]
        return model
    }

    private func flatten(items: [LaunchItem], parentID: UUID?) -> [StoredLayoutEntry] {
        items.enumerated().flatMap { index, item in
            let current = StoredLayoutEntry(
                id: item.id,
                parentID: parentID,
                title: item.title,
                subtitle: item.subtitle,
                kind: item.kind.rawValue,
                bundlePath: item.bundleURL?.path(),
                orderIndex: Int64(index)
            )

            return [current] + flatten(items: item.children, parentID: item.id)
        }
    }

    private func materialize(parentID: UUID?, entriesByParent: [UUID?: [StoredLayoutEntry]]) -> [LaunchItem] {
        let children = (entriesByParent[parentID] ?? []).sorted { $0.orderIndex < $1.orderIndex }
        return children.map { entry in
            LaunchItem(
                id: entry.id,
                title: entry.title,
                subtitle: entry.subtitle,
                kind: LaunchItem.Kind(rawValue: entry.kind) ?? .app,
                bundleURL: entry.bundlePath.map(URL.init(fileURLWithPath:)),
                children: materialize(parentID: entry.id, entriesByParent: entriesByParent)
            )
        }
    }
}

struct LaunchDeckSnapshot: Codable {
    let items: [LaunchItemSnapshot]

    init(items: [LaunchItem]) {
        self.items = items.map(LaunchItemSnapshot.init)
    }
}

struct LaunchItemSnapshot: Codable {
    let id: UUID
    let title: String
    let subtitle: String?
    let kind: String
    let bundlePath: String?
    let children: [LaunchItemSnapshot]

    init(item: LaunchItem) {
        id = item.id
        title = item.title
        subtitle = item.subtitle
        kind = item.kind.rawValue
        bundlePath = item.bundleURL?.path()
        children = item.children.map(LaunchItemSnapshot.init)
    }

    func materialize() -> LaunchItem {
        LaunchItem(
            id: id,
            title: title,
            subtitle: subtitle,
            kind: LaunchItem.Kind(rawValue: kind) ?? .app,
            bundleURL: bundlePath.map(URL.init(fileURLWithPath:)),
            children: children.map { $0.materialize() }
        )
    }
}

private struct StoredLayoutEntry {
    let id: UUID
    let parentID: UUID?
    let title: String
    let subtitle: String?
    let kind: String
    let bundlePath: String?
    let orderIndex: Int64
}
