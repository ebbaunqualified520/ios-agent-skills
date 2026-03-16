# Core Data Deep Dive

Reference for Core Data (available since iOS 3, mature and stable).

## NSPersistentContainer Setup

### Basic Setup

```swift
import CoreData

class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    // For previews and tests
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        // Seed preview data
        for i in 0..<10 {
            let item = Item(context: context)
            item.title = "Item \(i)"
            item.timestamp = Date()
        }
        try? context.save()
        return controller
    }()

    init(inMemory: Bool = false) {
        // Name must match .xcdatamodeld file name
        container = NSPersistentContainer(name: "Model")

        if inMemory {
            container.persistentStoreDescriptions.first?.url =
                URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { description, error in
            if let error {
                fatalError("Core Data store failed to load: \(error)")
            }
        }

        // Auto-merge changes from background contexts
        container.viewContext.automaticallyMergesChangesFromParent = true

        // Merge policy: store wins on conflict (most common)
        container.viewContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
    }
}
```

### SwiftUI Integration

```swift
@main
struct MyApp: App {
    let controller = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(
                    \.managedObjectContext,
                    controller.container.viewContext
                )
        }
    }
}
```

## NSFetchRequest

### Basic Fetch

```swift
let request = NSFetchRequest<Item>(entityName: "Item")

// Or using generated class
let request: NSFetchRequest<Item> = Item.fetchRequest()

// Predicate (filter)
request.predicate = NSPredicate(
    format: "title CONTAINS[cd] %@ AND isCompleted == %@",
    searchText,
    NSNumber(value: false)
)

// Sort
request.sortDescriptors = [
    NSSortDescriptor(keyPath: \Item.timestamp, ascending: false),
    NSSortDescriptor(keyPath: \Item.title, ascending: true)
]

// Fetch
let items = try context.fetch(request)
```

### Common NSPredicate Formats

```swift
// Equality
NSPredicate(format: "status == %@", "active")

// Comparison
NSPredicate(format: "age >= %d", 18)

// String contains (case-insensitive, diacritic-insensitive)
NSPredicate(format: "name CONTAINS[cd] %@", searchText)

// Begins with / ends with
NSPredicate(format: "email ENDSWITH %@", "@gmail.com")

// IN collection
NSPredicate(format: "category IN %@", ["work", "personal"])

// NULL check
NSPredicate(format: "deletedAt == nil")

// Date range
NSPredicate(format: "createdAt >= %@ AND createdAt < %@", startDate as NSDate, endDate as NSDate)

// Relationship traversal
NSPredicate(format: "folder.name == %@", "Inbox")

// Compound
NSCompoundPredicate(andPredicateWithSubpredicates: [pred1, pred2])
NSCompoundPredicate(orPredicateWithSubpredicates: [pred1, pred2])
NSCompoundPredicate(notPredicateWithSubpredicate: pred)

// Subquery (items where at least one tag name is "urgent")
NSPredicate(format: "SUBQUERY(tags, $tag, $tag.name == %@).@count > 0", "urgent")

// Aggregate
NSPredicate(format: "tasks.@count > %d", 5)
```

### NSSortDescriptor

```swift
// KeyPath-based (type-safe)
NSSortDescriptor(keyPath: \Item.title, ascending: true)

// String-based (needed for relationships)
NSSortDescriptor(key: "folder.name", ascending: true)

// Custom comparator
NSSortDescriptor(
    key: "title",
    ascending: true,
    selector: #selector(NSString.localizedCaseInsensitiveCompare(_:))
)
```

## Background Contexts

### newBackgroundContext

```swift
let bgContext = container.newBackgroundContext()
bgContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

bgContext.perform {
    let request: NSFetchRequest<Item> = Item.fetchRequest()
    let items = try? bgContext.fetch(request)

    items?.forEach { $0.isArchived = true }

    do {
        try bgContext.save()
    } catch {
        bgContext.rollback()
        print("Save failed: \(error)")
    }
}
```

### performBackgroundTask (One-Shot)

```swift
container.performBackgroundTask { context in
    context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

    // Import data
    for dto in dtos {
        let item = Item(context: context)
        item.title = dto.title
        item.timestamp = Date()
    }

    do {
        try context.save()
    } catch {
        print("Background save failed: \(error)")
    }
}
```

### perform vs performAndWait

```swift
// Async -- schedules on context's queue, returns immediately
context.perform {
    // work here
}

// Sync -- blocks calling thread until complete (safe, uses correct queue)
context.performAndWait {
    // work here
}

// Async/await variant (iOS 15+)
try await context.perform {
    // async work
    try context.save()
}
```

## NSFetchedResultsController

For efficiently driving UITableView/UICollectionView with Core Data.

```swift
class ItemListViewController: UITableViewController,
    NSFetchedResultsControllerDelegate
{
    var fetchedResultsController: NSFetchedResultsController<Item>!

    override func viewDidLoad() {
        super.viewDidLoad()

        let request: NSFetchRequest<Item> = Item.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Item.timestamp, ascending: false)
        ]
        request.fetchBatchSize = 20

        fetchedResultsController = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: PersistenceController.shared.container.viewContext,
            sectionNameKeyPath: nil,
            cacheName: "ItemList"
        )
        fetchedResultsController.delegate = self

        do {
            try fetchedResultsController.performFetch()
        } catch {
            print("Fetch failed: \(error)")
        }
    }

    // UITableViewDataSource
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        fetchedResultsController.sections?[section].numberOfObjects ?? 0
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let item = fetchedResultsController.object(at: indexPath)
        cell.textLabel?.text = item.title
        return cell
    }

    // NSFetchedResultsControllerDelegate -- diffable data source approach (iOS 13+)
    func controller(
        _ controller: NSFetchedResultsController<NSFetchRequestResult>,
        didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference
    ) {
        let snapshot = snapshot as NSDiffableDataSourceSnapshot<String, NSManagedObjectID>
        dataSource.apply(snapshot, animatingDifferences: true)
    }
}
```

## Batch Operations

Batch operations bypass the managed object context, operating directly on the persistent store. They are 10-100x faster for bulk operations but skip validation, KVO, and notifications.

### NSBatchInsertRequest

```swift
func batchInsert(items: [[String: Any]]) throws {
    let request = NSBatchInsertRequest(
        entity: Item.entity(),
        objects: items
    )
    request.resultType = .objectIDs

    let result = try viewContext.execute(request) as! NSBatchInsertResult
    let objectIDs = result.objectIDs!

    // CRITICAL: merge changes into viewContext so UI updates
    let changes = [NSInsertedObjectIDsKey: objectIDs]
    NSManagedObjectContext.mergeChanges(
        fromRemoteContextSave: changes,
        into: [viewContext]
    )
}

// Dictionary-based approach
let dictionaries: [[String: Any]] = dtos.map { dto in
    ["title": dto.title, "timestamp": Date(), "isCompleted": false]
}
try batchInsert(items: dictionaries)

// Closure-based approach (more memory efficient for very large imports)
var index = 0
let request = NSBatchInsertRequest(
    entity: Item.entity(),
    managedObjectHandler: { obj in
        guard index < dtos.count else { return true } // stop
        let item = obj as! Item
        item.title = dtos[index].title
        item.timestamp = Date()
        index += 1
        return false // continue
    }
)
```

### NSBatchUpdateRequest

```swift
func markAllCompleted() throws {
    let request = NSBatchUpdateRequest(entity: Item.entity())
    request.predicate = NSPredicate(format: "isCompleted == NO")
    request.propertiesToUpdate = ["isCompleted": true]
    request.resultType = .updatedObjectIDsResultType

    let result = try viewContext.execute(request) as! NSBatchUpdateResult
    let objectIDs = result.result as! [NSManagedObjectID]

    let changes = [NSUpdatedObjectIDsKey: objectIDs]
    NSManagedObjectContext.mergeChanges(
        fromRemoteContextSave: changes,
        into: [viewContext]
    )
}
```

### NSBatchDeleteRequest

```swift
func deleteOldItems(before date: Date) throws {
    let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Item.fetchRequest()
    fetchRequest.predicate = NSPredicate(format: "timestamp < %@", date as NSDate)

    let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
    deleteRequest.resultType = .resultTypeObjectIDs

    let result = try viewContext.execute(deleteRequest) as! NSBatchDeleteResult
    let objectIDs = result.result as! [NSManagedObjectID]

    let changes = [NSDeletedObjectIDsKey: objectIDs]
    NSManagedObjectContext.mergeChanges(
        fromRemoteContextSave: changes,
        into: [viewContext]
    )
}
```

## NSPersistentCloudKitContainer

### Setup

```swift
class CloudPersistenceController {
    let container: NSPersistentCloudKitContainer

    init() {
        container = NSPersistentCloudKitContainer(name: "Model")

        // Private database (default)
        let privateDescription = container.persistentStoreDescriptions.first!
        privateDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.example.myapp"
        )
        // Enable history tracking for CloudKit sync
        privateDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // Public database (optional, separate store)
        let publicDescription = NSPersistentStoreDescription(
            url: URL.applicationSupportDirectory.appending(path: "public.sqlite")
        )
        let publicOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.example.myapp"
        )
        publicOptions.databaseScope = .public
        publicDescription.cloudKitContainerOptions = publicOptions
        publicDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)

        container.persistentStoreDescriptions = [privateDescription, publicDescription]

        container.loadPersistentStores { _, error in
            if let error { fatalError("CloudKit store failed: \(error)") }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
    }
}
```

### Requirements for CloudKit-Synced Models
- All attributes must have default values (or be optional)
- Relationships must be optional
- No unique constraints on synced entities
- Enable CloudKit capability in project settings
- Enable Remote Notifications background mode

### Monitoring Sync Events

```swift
// Observe CloudKit sync events
NotificationCenter.default.addObserver(
    forName: NSPersistentCloudKitContainer.eventChangedNotification,
    object: container,
    queue: .main
) { notification in
    guard let event = notification.userInfo?[
        NSPersistentCloudKitContainer.eventNotificationUserInfoKey
    ] as? NSPersistentCloudKitContainer.Event else { return }

    if event.endDate != nil {
        print("CloudKit event finished: \(event.type)")
        if let error = event.error {
            print("CloudKit sync error: \(error)")
        }
    }
}
```

## Migrations

### Lightweight (Automatic) Migration

Supported changes (no code needed):
- Add new entity
- Add optional attribute or attribute with default value
- Remove attribute
- Rename attribute (set Renaming ID in data model inspector)
- Rename entity (set Renaming ID)
- Add or remove relationship
- Change relationship from to-one to to-many (not reverse)
- Make non-optional attribute optional

```swift
// Lightweight migration is automatic with NSPersistentContainer
// Just modify your .xcdatamodeld, add a new model version, set it as current
let description = container.persistentStoreDescriptions.first!
description.shouldMigrateStoreAutomatically = true  // default: true
description.shouldInferMappingModelAutomatically = true  // default: true
```

### Heavyweight (Manual) Migration

When lightweight migration is insufficient (complex transformations, splitting entities):

1. Create a new model version in .xcdatamodeld
2. Create a mapping model (.xcmappingmodel)
3. Define custom migration policies

```swift
class ItemToTaskMigrationPolicy: NSEntityMigrationPolicy {
    override func createDestinationInstances(
        forSource sInstance: NSManagedObject,
        in mapping: NSEntityMapping,
        manager: NSMigrationManager
    ) throws {
        try super.createDestinationInstances(
            forSource: sInstance, in: mapping, manager: manager
        )

        guard let dest = manager.destinationInstances(
            forEntityMappingName: mapping.name,
            sourceInstances: [sInstance]
        ).first else { return }

        // Transform data
        let oldTitle = sInstance.value(forKey: "title") as? String ?? ""
        dest.setValue(oldTitle.capitalized, forKey: "name")
        dest.setValue(Date(), forKey: "migratedAt")
    }
}
```

### Progressive Migration (Multiple Versions)

```swift
class MigrationManager {
    func migrateStoreIfNeeded(at storeURL: URL) throws {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL
        )

        let models = loadAllModelVersions()

        guard let sourceModel = NSManagedObjectModel.mergedModel(
            from: nil,
            forStoreMetadata: metadata
        ) else { return }

        guard let destModel = models.last,
              !destModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
        else { return } // Already current

        // Find mapping and migrate
        let mappingModel = try NSMappingModel.inferredMappingModel(
            forSourceModel: sourceModel,
            destinationModel: destModel
        )

        let manager = NSMigrationManager(
            sourceModel: sourceModel,
            destinationModel: destModel
        )

        let tempURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent("migration_temp.sqlite")

        try manager.migrateStore(
            from: storeURL,
            type: .sqlite,
            mapping: mappingModel,
            to: tempURL,
            type: .sqlite
        )

        // Replace old store with migrated store
        try FileManager.default.removeItem(at: storeURL)
        try FileManager.default.moveItem(at: tempURL, to: storeURL)
    }
}
```

## Core Data with SwiftUI

### @FetchRequest

```swift
struct ItemListView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        entity: Item.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: false)],
        predicate: NSPredicate(format: "isArchived == NO"),
        animation: .default
    )
    private var items: FetchedResults<Item>

    var body: some View {
        List {
            ForEach(items) { item in
                Text(item.title ?? "Untitled")
            }
            .onDelete(perform: deleteItems)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        offsets.map { items[$0] }.forEach(context.delete)
        try? context.save()
    }
}
```

### @SectionedFetchRequest (iOS 15+)

```swift
struct SectionedItemList: View {
    @SectionedFetchRequest(
        sectionIdentifier: \.categoryName,
        sortDescriptors: [
            SortDescriptor(\.categoryName),
            SortDescriptor(\.title)
        ],
        animation: .default
    )
    private var sections: SectionedFetchResults<String, Item>

    var body: some View {
        List {
            ForEach(sections) { section in
                Section(header: Text(section.id)) {
                    ForEach(section) { item in
                        Text(item.title ?? "")
                    }
                }
            }
        }
    }
}
```

### Dynamic FetchRequest via init

```swift
struct FilteredItems: View {
    @FetchRequest var items: FetchedResults<Item>

    init(category: String) {
        _items = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: false)],
            predicate: NSPredicate(format: "category == %@", category)
        )
    }

    var body: some View {
        List(items) { item in
            Text(item.title ?? "")
        }
    }
}
```

## Performance Tips

### 1. fetchBatchSize

```swift
// Default is 0 (fetch ALL objects into memory)
// Set to ~20 for table/collection views
request.fetchBatchSize = 20
```

### 2. Fetch Only Needed Properties

```swift
request.propertiesToFetch = ["title", "timestamp"]
request.resultType = .dictionaryResultType
// Returns [NSDictionary] instead of managed objects -- much lighter
```

### 3. Prefetch Relationships

```swift
// Avoid N+1 query problem
request.relationshipKeyPathsForPrefetching = ["tags", "folder"]
```

### 4. Count Without Fetching

```swift
let count = try context.count(for: request)
```

### 5. Aggregate Queries

```swift
let request = NSFetchRequest<NSDictionary>(entityName: "Order")
request.resultType = .dictionaryResultType

let sumExpression = NSExpressionDescription()
sumExpression.name = "totalAmount"
sumExpression.expression = NSExpression(
    forFunction: "sum:",
    arguments: [NSExpression(forKeyPath: "amount")]
)
sumExpression.expressionResultType = .decimalAttributeType

request.propertiesToFetch = [sumExpression]

let results = try context.fetch(request)
let total = results.first?["totalAmount"] as? Decimal ?? 0
```

### 6. Denormalize for Read Performance

```swift
// Instead of counting relationship every time:
// item.tags.count (triggers fault, loads all tags)

// Add a denormalized count property:
// item.tagCount (Int, updated on tag add/remove)
```

### 7. Use Separate Contexts for Different Purposes

```swift
// Read-only context with no undo manager (saves memory)
let readContext = container.newBackgroundContext()
readContext.undoManager = nil
readContext.automaticallyMergesChangesFromParent = true

// Write context
let writeContext = container.newBackgroundContext()
writeContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
```

### 8. Persistent History Tracking

```swift
// Enable for detecting changes from extensions, widgets, CloudKit
let description = container.persistentStoreDescriptions.first!
description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

// Process history
NotificationCenter.default.addObserver(
    forName: .NSPersistentStoreRemoteChange,
    object: container.persistentStoreCoordinator,
    queue: .main
) { _ in
    // Fetch and process history transactions
    let request = NSPersistentHistoryChangeRequest.fetchHistory(after: lastToken)
    // ...
}
```
