# SwiftData Deep Dive

Reference for SwiftData (iOS 17+, macOS 14+, visionOS 1+).

## @Model Macro

The `@Model` macro transforms a Swift class into a persistent model. It automatically makes the class conform to `PersistentModel` and `Observable`.

### Supported Property Types
- Primitives: `Bool`, `Int`, `Int8/16/32/64`, `UInt` variants, `Float`, `Double`, `String`
- Foundation: `Date`, `Data`, `URL`, `UUID`, `Decimal`
- Collections: `Array`, `Dictionary`, `Set` of supported types
- Enums: any `RawRepresentable` with `Codable` conformance
- Structs: any `Codable` struct
- Optionals of all the above
- Relationships to other `@Model` types

### Basic Model

```swift
import SwiftData

@Model
final class Note {
    var title: String
    var content: String
    var createdAt: Date = Date.now
    var isPinned: Bool = false

    init(title: String, content: String) {
        self.title = title
        self.content = content
    }
}
```

## @Attribute Options

```swift
@Model
final class User {
    // Unique constraint -- upserts on conflict
    @Attribute(.unique) var email: String

    // Store large data externally (not in SQLite row)
    @Attribute(.externalStorage) var avatarData: Data?

    // Index for Spotlight search
    @Attribute(.spotlight) var displayName: String

    // Encrypt at rest (Data Protection)
    @Attribute(.encrypt) var sensitiveNotes: String?

    // Ephemeral -- stored but not included in migration hashing
    @Attribute(.ephemeral) var sessionToken: String?

    // Transient -- NOT stored at all (computed/cached)
    @Transient var fullName: String { "\(firstName) \(lastName)" }

    var firstName: String
    var lastName: String

    // Custom column name for migration compatibility
    @Attribute(originalName: "user_name") var username: String

    init(email: String, firstName: String, lastName: String, username: String) {
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.username = username
    }
}
```

### Attribute Summary

| Option | Effect |
|--------|--------|
| `.unique` | Creates unique constraint, upserts on conflict |
| `.externalStorage` | Stores data in separate file (good for large Data/blobs) |
| `.spotlight` | Indexes property for Spotlight search |
| `.encrypt` | Encrypts property at rest |
| `.ephemeral` | Stored but excluded from schema migration hashing |
| `@Transient` | Not stored in database at all |
| `originalName:` | Maps to different column name (for renames) |

## @Relationship

### Delete Rules

| Rule | Behavior |
|------|----------|
| `.cascade` | Deleting parent deletes all related children |
| `.nullify` | Deleting parent sets child's reference to nil (default) |
| `.deny` | Prevents deletion if related objects exist |
| `.noAction` | Does nothing (can leave orphans -- use cautiously) |

### Relationship Examples

```swift
// One-to-Many with cascade delete
@Model
final class Folder {
    var name: String
    @Relationship(deleteRule: .cascade, inverse: \Document.folder)
    var documents: [Document] = []

    init(name: String) {
        self.name = name
    }
}

@Model
final class Document {
    var title: String
    var folder: Folder?

    init(title: String, folder: Folder? = nil) {
        self.title = title
        self.folder = folder
    }
}

// Many-to-Many
@Model
final class Student {
    var name: String
    @Relationship(inverse: \Course.students)
    var courses: [Course] = []

    init(name: String) {
        self.name = name
    }
}

@Model
final class Course {
    var title: String
    var students: [Student] = []

    init(title: String) {
        self.title = title
    }
}

// One-to-One
@Model
final class Profile {
    var bio: String
    @Relationship(inverse: \Account.profile)
    var account: Account?

    init(bio: String) {
        self.bio = bio
    }
}

@Model
final class Account {
    var username: String
    var profile: Profile?

    init(username: String) {
        self.username = username
    }
}
```

## ModelContainer and ModelConfiguration

### Basic Setup in SwiftUI App

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Note.self, Folder.self])
    }
}
```

### Custom Configuration

```swift
@main
struct MyApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([Note.self, Folder.self])
        let config = ModelConfiguration(
            "MyStore",
            schema: schema,
            url: URL.applicationSupportDirectory.appending(path: "myapp.store"),
            allowsSave: true,
            cloudKitDatabase: .private("iCloud.com.myapp")
        )
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
```

### In-Memory Container for Tests

```swift
@MainActor
func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Note.self, Folder.self,
        configurations: config
    )
}

// Usage in test
@Test @MainActor
func testNoteCreation() throws {
    let container = try makeTestContainer()
    let context = container.mainContext

    let note = Note(title: "Test", content: "Body")
    context.insert(note)
    try context.save()

    let descriptor = FetchDescriptor<Note>()
    let notes = try context.fetch(descriptor)
    #expect(notes.count == 1)
    #expect(notes.first?.title == "Test")
}
```

### Multiple Configurations (Separate Stores)

```swift
let localConfig = ModelConfiguration(
    "Local",
    schema: Schema([CacheItem.self]),
    url: URL.cachesDirectory.appending(path: "cache.store")
)
let cloudConfig = ModelConfiguration(
    "Cloud",
    schema: Schema([Note.self]),
    cloudKitDatabase: .private("iCloud.com.myapp")
)
let container = try ModelContainer(
    for: Schema([Note.self, CacheItem.self]),
    configurations: localConfig, cloudConfig
)
```

## ModelContext CRUD

```swift
// Get context from environment
@Environment(\.modelContext) private var context

// INSERT
let note = Note(title: "New", content: "Content")
context.insert(note)
// autosave will persist (or call context.save() explicitly)

// FETCH
let descriptor = FetchDescriptor<Note>(
    predicate: #Predicate { $0.isPinned },
    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
)
let pinned = try context.fetch(descriptor)

// UPDATE -- just modify the object
note.title = "Updated Title"
// autosave handles persistence

// DELETE
context.delete(note)

// EXPLICIT SAVE (when autosave is off or you need immediate persistence)
try context.save()

// COUNT without fetching objects
let count = try context.fetchCount(descriptor)

// CHECK if context has unsaved changes
if context.hasChanges {
    try context.save()
}
```

## @Query Macro

### Basic Queries

```swift
struct NoteListView: View {
    // All notes, sorted by creation date
    @Query(sort: \Note.createdAt, order: .reverse)
    private var notes: [Note]

    // Filtered and sorted
    @Query(
        filter: #Predicate<Note> { $0.isPinned },
        sort: \Note.title
    )
    private var pinnedNotes: [Note]

    // With animation
    @Query(sort: \Note.createdAt, animation: .default)
    private var animatedNotes: [Note]

    var body: some View {
        List(notes) { note in
            Text(note.title)
        }
    }
}
```

### Dynamic Queries via init

```swift
struct FilteredNoteList: View {
    @Query private var notes: [Note]

    init(searchText: String, showPinnedOnly: Bool) {
        let predicate: Predicate<Note>?
        if searchText.isEmpty && !showPinnedOnly {
            predicate = nil
        } else if searchText.isEmpty {
            predicate = #Predicate<Note> { $0.isPinned }
        } else if !showPinnedOnly {
            predicate = #Predicate<Note> {
                $0.title.localizedStandardContains(searchText)
            }
        } else {
            predicate = #Predicate<Note> {
                $0.isPinned && $0.title.localizedStandardContains(searchText)
            }
        }

        _notes = Query(
            filter: predicate,
            sort: [SortDescriptor(\Note.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        List(notes) { note in
            NoteRow(note: note)
        }
    }
}
```

## #Predicate Macro

### Boolean and Comparison

```swift
let pinned = #Predicate<Note> { $0.isPinned }
let recent = #Predicate<Note> { $0.createdAt > Date.now.addingTimeInterval(-86400) }
let long = #Predicate<Note> { $0.content.count > 1000 }
```

### Compound Predicates

```swift
let filtered = #Predicate<Note> { note in
    note.isPinned && !note.title.isEmpty
}

let either = #Predicate<Note> { note in
    note.isPinned || note.createdAt > cutoffDate
}
```

### String Operations

```swift
let search = #Predicate<Note> { note in
    note.title.localizedStandardContains("meeting")
}

let startsWith = #Predicate<Note> { note in
    note.title.starts(with: "Draft")
}
```

### Optionals

```swift
let hasFolder = #Predicate<Note> { $0.folder != nil }

// Compare optional safely
let inFolder = #Predicate<Note> { note in
    if let folder = note.folder {
        return folder.name == "Work"
    }
    return false
}
```

### Collections

```swift
let hasDocuments = #Predicate<Folder> { folder in
    !folder.documents.isEmpty
}

let manyDocs = #Predicate<Folder> { folder in
    folder.documents.count > 5
}
```

## FetchDescriptor

### Pagination

```swift
// Page 1 (items 0-19)
var page1 = FetchDescriptor<Note>(sort: [SortDescriptor(\.createdAt, order: .reverse)])
page1.fetchLimit = 20
page1.fetchOffset = 0

// Page 2 (items 20-39)
var page2 = page1
page2.fetchOffset = 20
```

### Count Only

```swift
var descriptor = FetchDescriptor<Note>(
    predicate: #Predicate { !$0.isPinned }
)
let count = try context.fetchCount(descriptor)
```

### Enumerate for Large Datasets (Memory-Efficient)

```swift
let descriptor = FetchDescriptor<Note>(
    sort: [SortDescriptor(\.createdAt)]
)

// Processes in batches, autoreleasing memory
try context.enumerate(descriptor, batchSize: 100) { note in
    // Process each note
    note.content = note.content.trimmingCharacters(in: .whitespaces)
}
```

## iOS 18: #Index and #Unique Macros

```swift
// Index for faster queries on specific properties
@Model
final class Note {
    #Index<Note>([\.createdAt], [\.isPinned, \.createdAt])

    var title: String
    var content: String
    var createdAt: Date = Date.now
    var isPinned: Bool = false

    init(title: String, content: String) {
        self.title = title
        self.content = content
    }
}

// Unique constraint on compound properties
@Model
final class Enrollment {
    #Unique<Enrollment>([\.studentID, \.courseID])

    var studentID: String
    var courseID: String
    var enrolledAt: Date = Date.now

    init(studentID: String, courseID: String) {
        self.studentID = studentID
        self.courseID = courseID
    }
}
```

### History Tracking (iOS 18)

```swift
// Enable history tracking to detect changes across launches
let config = ModelConfiguration(
    "MyStore",
    schema: Schema([Note.self]),
    url: storeURL
)
// History is automatically tracked

// Fetch history transactions
let historyDescriptor = HistoryDescriptor<DefaultHistoryTransaction>()
let transactions = try context.fetchHistory(historyDescriptor)

for transaction in transactions {
    for change in transaction.changes {
        switch change {
        case .insert(let inserted):
            print("Inserted: \(inserted.changedPersistentIdentifier)")
        case .update(let updated):
            print("Updated: \(updated.changedPersistentIdentifier)")
        case .delete(let deleted):
            print("Deleted: \(deleted.changedPersistentIdentifier)")
        }
    }
}
```

## Migration

### VersionedSchema

```swift
// Version 1 -- original schema
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [NoteV1.self]
    }

    @Model
    final class NoteV1 {
        var title: String
        var body: String

        init(title: String, body: String) {
            self.title = title
            self.body = body
        }
    }
}

// Version 2 -- added createdAt, renamed body -> content
enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [NoteV2.self]
    }

    @Model
    final class NoteV2 {
        var title: String
        @Attribute(originalName: "body") var content: String
        var createdAt: Date = Date.now

        init(title: String, content: String) {
            self.title = title
            self.content = content
        }
    }
}
```

### SchemaMigrationPlan

```swift
enum NoteMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    // Lightweight -- just adding a property with default and renaming via originalName
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )
}

// Custom migration (when data transformation is needed)
enum ComplexMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )

    static let migrateV2toV3 = MigrationStage.custom(
        fromVersion: SchemaV2.self,
        toVersion: SchemaV3.self,
        willMigrate: { context in
            // Pre-migration: transform data while still in V2 format
            let notes = try context.fetch(FetchDescriptor<SchemaV2.NoteV2>())
            for note in notes {
                note.content = note.content.trimmingCharacters(in: .whitespaces)
            }
            try context.save()
        },
        didMigrate: { context in
            // Post-migration: populate new fields in V3 format
        }
    )
}

// Apply migration plan to container
let container = try ModelContainer(
    for: SchemaV2.NoteV2.self,
    migrationPlan: NoteMigrationPlan.self
)
```

## CloudKit Integration

### Requirements
- All properties must have default values or be optional
- No `.unique` constraints (CloudKit does not support them)
- Relationships must be optional on at least one side
- Enable CloudKit capability in Xcode project settings
- Enable background modes > Remote notifications

### Setup

```swift
@Model
final class SharedNote {
    // CloudKit-compatible: all have defaults or are optional
    var title: String = ""
    var content: String = ""
    var createdAt: Date = Date.now
    @Attribute(.externalStorage) var imageData: Data?
    var folder: SharedFolder?

    init(title: String = "", content: String = "") {
        self.title = title
        self.content = content
    }
}

// Container with CloudKit
let config = ModelConfiguration(
    cloudKitDatabase: .private("iCloud.com.example.myapp")
)
let container = try ModelContainer(
    for: SharedNote.self, SharedFolder.self,
    configurations: config
)
```

### CloudKit Limitations with SwiftData
- Only private database is supported (no public or shared)
- No `.unique` constraints
- For public/shared databases, use Core Data + NSPersistentCloudKitContainer

## @ModelActor for Concurrency

Model objects are NOT Sendable. Use `@ModelActor` for background work and pass `PersistentIdentifier` between actors.

```swift
@ModelActor
actor NoteService {
    // modelContext and modelExecutor are auto-synthesized

    func importNotes(from data: [NoteDTO]) throws -> [PersistentIdentifier] {
        var ids: [PersistentIdentifier] = []
        for dto in data {
            let note = Note(title: dto.title, content: dto.content)
            modelContext.insert(note)
            ids.append(note.persistentModelID)
        }
        try modelContext.save()
        return ids
    }

    func updateNote(id: PersistentIdentifier, title: String) throws {
        guard let note = modelContext.model(for: id) as? Note else { return }
        note.title = title
        try modelContext.save()
    }

    func deleteAll() throws {
        try modelContext.delete(model: Note.self)
        try modelContext.save()
    }

    func exportAll() throws -> [NoteDTO] {
        let descriptor = FetchDescriptor<Note>(
            sort: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor).map { note in
            NoteDTO(title: note.title, content: note.content)
        }
    }
}

// Usage from MainActor
@MainActor
class NoteViewModel {
    let service: NoteService

    init(container: ModelContainer) {
        self.service = NoteService(modelContainer: container)
    }

    func importData(_ dtos: [NoteDTO]) async throws {
        // Returns PersistentIdentifiers (Sendable) not model objects
        let ids = try await service.importNotes(from: dtos)
        // Use ids to refresh UI or fetch on main context
    }
}
```

## Performance Tips

### 1. Add Indexes on Queried Properties

```swift
@Model
final class Message {
    #Index<Message>([\.timestamp], [\.isRead, \.timestamp])

    var text: String
    var timestamp: Date = Date.now
    var isRead: Bool = false
    // ...
}
```

### 2. Paginate Large Lists

```swift
func fetchPage(page: Int, pageSize: Int = 20) throws -> [Note] {
    var descriptor = FetchDescriptor<Note>(
        sort: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    descriptor.fetchLimit = pageSize
    descriptor.fetchOffset = page * pageSize
    return try context.fetch(descriptor)
}
```

### 3. Use enumerate for Batch Processing

```swift
// Memory-efficient iteration over large datasets
let descriptor = FetchDescriptor<Note>()
try context.enumerate(descriptor, batchSize: 500) { note in
    // Process without keeping all objects in memory
}
```

### 4. Background Actor for Heavy Work

```swift
@ModelActor
actor DataImporter {
    func importCSV(url: URL) throws {
        let lines = try String(contentsOf: url).components(separatedBy: .newlines)
        for line in lines {
            let parts = line.components(separatedBy: ",")
            guard parts.count >= 2 else { continue }
            let record = Record(name: parts[0], value: parts[1])
            modelContext.insert(record)
        }
        try modelContext.save()
    }
}
```

### 5. External Storage for Blobs

```swift
@Model
final class Photo {
    var caption: String
    @Attribute(.externalStorage) var imageData: Data?
    @Attribute(.externalStorage) var thumbnailData: Data?
    // SwiftData stores these as files, not in the SQLite row
}
```
