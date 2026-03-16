# Storage Options Reference

UserDefaults, @AppStorage, FileManager, Keychain, iCloud KVS, SQLite/GRDB.

## UserDefaults

Simple key-value store for small user preferences. Loaded into memory at app launch.

### Supported Types
- `Bool`, `Int`, `Float`, `Double`, `String`
- `Data`, `Date`, `URL`
- `Array` and `Dictionary` of the above (plist-compatible)
- Any `Codable` via `Data` encoding

### Basic Usage

```swift
let defaults = UserDefaults.standard

// Write
defaults.set(true, forKey: "hasCompletedOnboarding")
defaults.set("dark", forKey: "preferredTheme")
defaults.set(42, forKey: "launchCount")

// Read
let hasOnboarded = defaults.bool(forKey: "hasCompletedOnboarding")
let theme = defaults.string(forKey: "preferredTheme") ?? "system"
let count = defaults.integer(forKey: "launchCount")  // 0 if not set

// Remove
defaults.removeObject(forKey: "preferredTheme")

// Register defaults (fallback values, not written to disk)
defaults.register(defaults: [
    "hasCompletedOnboarding": false,
    "preferredTheme": "system",
    "maxCacheSize": 100
])
```

### Store Codable in UserDefaults

```swift
struct UserPreferences: Codable {
    var fontSize: Int = 14
    var showLineNumbers: Bool = true
    var recentFiles: [String] = []
}

// Save
func savePreferences(_ prefs: UserPreferences) {
    if let data = try? JSONEncoder().encode(prefs) {
        UserDefaults.standard.set(data, forKey: "userPreferences")
    }
}

// Load
func loadPreferences() -> UserPreferences {
    guard let data = UserDefaults.standard.data(forKey: "userPreferences"),
          let prefs = try? JSONDecoder().decode(UserPreferences.self, from: data)
    else { return UserPreferences() }
    return prefs
}
```

### App Group Suite (Shared with Extensions/Widgets)

```swift
// App and widget share data via app group
let shared = UserDefaults(suiteName: "group.com.example.myapp")!
shared.set(42, forKey: "widgetCount")

// In widget:
let count = UserDefaults(suiteName: "group.com.example.myapp")!
    .integer(forKey: "widgetCount")
```

### Limitations
- Do NOT store sensitive data (not encrypted)
- Do NOT store large data (loaded into memory at launch)
- Do NOT store collections that grow unbounded
- No query support -- only key-value access
- `synchronize()` is unnecessary since iOS 12

## @AppStorage (SwiftUI)

Property wrapper that reads/writes UserDefaults and triggers SwiftUI view updates.

```swift
struct SettingsView: View {
    @AppStorage("isDarkMode") private var isDarkMode = false
    @AppStorage("username") private var username = ""
    @AppStorage("fontSize") private var fontSize = 14.0
    @AppStorage("selectedTab") private var selectedTab = 0

    // App group suite
    @AppStorage("widgetData", store: UserDefaults(suiteName: "group.com.example.myapp"))
    private var widgetData = ""

    var body: some View {
        Form {
            Toggle("Dark Mode", isOn: $isDarkMode)
            TextField("Username", text: $username)
            Slider(value: $fontSize, in: 10...24, step: 1) {
                Text("Font Size: \(Int(fontSize))")
            }
            Picker("Tab", selection: $selectedTab) {
                Text("Home").tag(0)
                Text("Search").tag(1)
            }
        }
    }
}
```

### @AppStorage with RawRepresentable Enum

```swift
enum AppTheme: String, CaseIterable {
    case system, light, dark
}

struct ThemePickerView: View {
    @AppStorage("appTheme") private var theme: AppTheme = .system

    var body: some View {
        Picker("Theme", selection: $theme) {
            ForEach(AppTheme.allCases, id: \.self) { theme in
                Text(theme.rawValue.capitalized).tag(theme)
            }
        }
    }
}
```

### When NOT to Use @AppStorage
- Large data (images, files, arrays with 100+ items)
- Sensitive data (use Keychain)
- Complex objects (use SwiftData/Core Data)
- Data that needs querying/sorting

## FileManager

### App Sandbox Directories

| Directory | Purpose | Backed Up | Purged by System |
|-----------|---------|-----------|------------------|
| `Documents/` | User-created content, visible in Files app | Yes | No |
| `Library/Application Support/` | App internal data (databases, caches that need persistence) | Yes | No |
| `Library/Caches/` | Recreatable cached data | No | Yes (low disk) |
| `tmp/` | Temporary files | No | Yes (app not running) |

### Get Directory URLs

```swift
// Documents directory
let documentsURL = FileManager.default
    .urls(for: .documentDirectory, in: .userDomainMask)[0]

// Application Support (preferred for internal data)
let appSupportURL = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

// Caches
let cachesURL = FileManager.default
    .urls(for: .cachesDirectory, in: .userDomainMask)[0]

// Temporary
let tmpURL = FileManager.default.temporaryDirectory
```

### Save and Load Codable to File

```swift
enum FileStorage {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func save<T: Encodable>(
        _ object: T,
        to filename: String,
        in directory: FileManager.SearchPathDirectory = .applicationSupportDirectory
    ) throws {
        let dirURL = FileManager.default
            .urls(for: directory, in: .userDomainMask)[0]

        // Create directory if needed
        try FileManager.default.createDirectory(
            at: dirURL,
            withIntermediateDirectories: true
        )

        let fileURL = dirURL.appendingPathComponent(filename)
        let data = try encoder.encode(object)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    static func load<T: Decodable>(
        _ type: T.Type,
        from filename: String,
        in directory: FileManager.SearchPathDirectory = .applicationSupportDirectory
    ) throws -> T {
        let dirURL = FileManager.default
            .urls(for: directory, in: .userDomainMask)[0]
        let fileURL = dirURL.appendingPathComponent(filename)
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(type, from: data)
    }

    static func delete(
        _ filename: String,
        in directory: FileManager.SearchPathDirectory = .applicationSupportDirectory
    ) throws {
        let dirURL = FileManager.default
            .urls(for: directory, in: .userDomainMask)[0]
        let fileURL = dirURL.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    static func exists(
        _ filename: String,
        in directory: FileManager.SearchPathDirectory = .applicationSupportDirectory
    ) -> Bool {
        let dirURL = FileManager.default
            .urls(for: directory, in: .userDomainMask)[0]
        let fileURL = dirURL.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}

// Usage
struct AppSettings: Codable {
    var serverURL: String
    var syncInterval: TimeInterval
}

let settings = AppSettings(serverURL: "https://api.example.com", syncInterval: 300)
try FileStorage.save(settings, to: "settings.json")

let loaded = try FileStorage.load(AppSettings.self, from: "settings.json")
```

### Save Image Data

```swift
func saveImage(_ image: UIImage, named filename: String) throws -> URL {
    let dirURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Images")

    try FileManager.default.createDirectory(
        at: dirURL,
        withIntermediateDirectories: true
    )

    let fileURL = dirURL.appendingPathComponent(filename)
    guard let data = image.jpegData(compressionQuality: 0.8) else {
        throw NSError(domain: "ImageSave", code: -1)
    }
    try data.write(to: fileURL, options: .atomic)
    return fileURL
}

func loadImage(named filename: String) -> UIImage? {
    let fileURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Images")
        .appendingPathComponent(filename)
    return UIImage(contentsOfFile: fileURL.path)
}
```

### List Files

```swift
func listFiles(in directory: String = "Documents") throws -> [URL] {
    let dirURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
    return try FileManager.default.contentsOfDirectory(
        at: dirURL,
        includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
        options: .skipsHiddenFiles
    )
}
```

## iCloud Key-Value Storage

Simple key-value sync across devices. Great for user preferences.

### Limits
- Total storage: 1 MB per app
- Maximum keys: 1024
- Maximum value size: 1 MB per key
- Not for structured data -- use CloudKit/SwiftData for that

### Setup
1. Enable iCloud capability in Xcode
2. Check "Key-value storage"

### Usage

```swift
let kvStore = NSUbiquitousKeyValueStore.default

// Write (same API as UserDefaults)
kvStore.set(true, forKey: "isPremiumUser")
kvStore.set("dark", forKey: "preferredTheme")
kvStore.set(42.0, forKey: "highScore")

// Explicit sync (optional -- system syncs automatically, but call after batch writes)
kvStore.synchronize()

// Read
let isPremium = kvStore.bool(forKey: "isPremiumUser")
let theme = kvStore.string(forKey: "preferredTheme") ?? "system"

// Listen for external changes (from other devices)
NotificationCenter.default.addObserver(
    forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
    object: kvStore,
    queue: .main
) { notification in
    guard let userInfo = notification.userInfo,
          let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
    else { return }

    switch reason {
    case NSUbiquitousKeyValueStoreServerChange:
        // Another device changed values
        let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
        for key in changedKeys {
            print("Key changed from another device: \(key)")
        }
    case NSUbiquitousKeyValueStoreInitialSyncChange:
        // First sync after install
        break
    case NSUbiquitousKeyValueStoreQuotaViolationChange:
        // Over 1MB limit -- reduce stored data
        break
    default:
        break
    }
}
```

### Sync UserDefaults with iCloud KVS

```swift
class SettingsSync {
    private let defaults = UserDefaults.standard
    private let kvStore = NSUbiquitousKeyValueStore.default
    private let syncKeys = ["preferredTheme", "showNotifications", "fontSize"]

    func startSyncing() {
        // Push local to cloud
        for key in syncKeys {
            if let value = defaults.object(forKey: key) {
                kvStore.set(value, forKey: key)
            }
        }
        kvStore.synchronize()

        // Listen for cloud changes
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore,
            queue: .main
        ) { [weak self] notification in
            self?.handleExternalChange(notification)
        }
    }

    private func handleExternalChange(_ notification: Notification) {
        guard let changedKeys = notification.userInfo?[
            NSUbiquitousKeyValueStoreChangedKeysKey
        ] as? [String] else { return }

        for key in changedKeys where syncKeys.contains(key) {
            if let value = kvStore.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
    }
}
```

## PropertyListEncoder/Decoder

For encoding/decoding Codable types to/from plist format (XML or binary).

```swift
// Encode to plist data
let encoder = PropertyListEncoder()
encoder.outputFormat = .binary  // or .xml

let settings = AppSettings(serverURL: "https://api.example.com", syncInterval: 300)
let data = try encoder.encode(settings)

// Save as .plist file
let plistURL = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("settings.plist")
try data.write(to: plistURL)

// Decode from plist data
let decoder = PropertyListDecoder()
let loaded = try decoder.decode(AppSettings.self, from: data)
```

## SQLite via GRDB.swift

Use when you need full SQL control, cross-platform database compatibility, or are working with existing SQLite databases.

### When to Choose GRDB over SwiftData/Core Data
- Need raw SQL queries or complex JOINs
- Cross-platform app sharing database with Android/web
- Working with existing SQLite database from another platform
- Need precise control over database schema and indexes
- Performance-critical queries beyond what SwiftData provides

### Setup (SPM)

```swift
// Package.swift dependency
.package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")
```

### Define Record Types

```swift
import GRDB

struct Player: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var name: String
    var score: Int
    var createdAt: Date

    // Auto-increment id
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// Table creation
extension Player {
    static func createTable(in db: Database) throws {
        try db.create(table: "player", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull()
            t.column("score", .integer).notNull().defaults(to: 0)
            t.column("createdAt", .datetime).notNull()
        }
        try db.create(indexOn: "player", columns: ["score"])
    }
}
```

### Database Setup

```swift
class AppDatabase {
    let dbQueue: DatabaseQueue

    init() throws {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.sqlite")

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        dbQueue = try DatabaseQueue(path: url.path)

        // Run migrations
        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try Player.createTable(in: db)
        }

        migrator.registerMigration("v2") { db in
            try db.alter(table: "player") { t in
                t.add(column: "email", .text)
            }
        }

        return migrator
    }
}
```

### CRUD Operations

```swift
extension AppDatabase {
    // Create
    func createPlayer(name: String, score: Int) throws -> Player {
        try dbQueue.write { db in
            var player = Player(id: nil, name: name, score: score, createdAt: Date())
            try player.insert(db)
            return player
        }
    }

    // Read
    func allPlayers() throws -> [Player] {
        try dbQueue.read { db in
            try Player
                .order(Column("score").desc)
                .fetchAll(db)
        }
    }

    func topPlayers(limit: Int) throws -> [Player] {
        try dbQueue.read { db in
            try Player
                .order(Column("score").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func player(id: Int64) throws -> Player? {
        try dbQueue.read { db in
            try Player.fetchOne(db, id: id)
        }
    }

    // Update
    func updateScore(id: Int64, score: Int) throws {
        try dbQueue.write { db in
            if var player = try Player.fetchOne(db, id: id) {
                player.score = score
                try player.update(db)
            }
        }
    }

    // Delete
    func deletePlayer(id: Int64) throws {
        try dbQueue.write { db in
            _ = try Player.deleteOne(db, id: id)
        }
    }

    // Raw SQL
    func averageScore() throws -> Double {
        try dbQueue.read { db in
            try Double.fetchOne(db, sql: "SELECT AVG(score) FROM player") ?? 0
        }
    }
}
```

### ValueObservation for Reactive SwiftUI

```swift
import GRDB
import Combine

class PlayerListViewModel: ObservableObject {
    @Published var players: [Player] = []
    private var cancellable: AnyDatabaseCancellable?

    init(database: AppDatabase) {
        // Automatically re-fetches when player table changes
        let observation = ValueObservation.tracking { db in
            try Player
                .order(Column("score").desc)
                .limit(50)
                .fetchAll(db)
        }

        cancellable = observation.start(
            in: database.dbQueue,
            onError: { error in print("DB error: \(error)") },
            onChange: { [weak self] players in
                DispatchQueue.main.async {
                    self?.players = players
                }
            }
        )
    }
}
```

## Storage Decision Flowchart (Summary)

```
START
  |
  v
Is data sensitive (password, token, API key)?
  YES --> Keychain
  NO --> continue
  |
  v
Is it a simple flag/preference (< a few KB)?
  YES --> Need cross-device sync?
    YES --> NSUbiquitousKeyValueStore
    NO  --> @AppStorage / UserDefaults
  NO --> continue
  |
  v
Is it a large binary file (image, video, audio, PDF)?
  YES --> FileManager (Documents or App Support)
  NO --> continue
  |
  v
Is it structured/relational data?
  YES --> Need full SQL or cross-platform DB?
    YES --> SQLite (GRDB.swift)
    NO  --> Target iOS 17+?
      YES --> SwiftData
      NO  --> Core Data
  NO --> continue
  |
  v
Is it a one-off Codable object (config, cached response)?
  YES --> FileManager + JSONEncoder (save to .json file)
  NO --> continue
  |
  v
Need iCloud sync of structured data?
  YES --> Private only?
    YES --> SwiftData with CloudKit or NSPersistentCloudKitContainer
    NO  --> NSPersistentCloudKitContainer (public/shared DB support)
  NO --> Re-evaluate -- one of the above should fit
```
