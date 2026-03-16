# Optimization Reference

## App Launch Optimization

App launch is the first impression. Apple measures "Time to First Frame" and may terminate apps exceeding the watchdog timeout (~20 seconds, but shorter in practice).

### Launch Types

| Type | Definition | Target |
|------|-----------|--------|
| Cold launch | Process not in memory, no cached data | <400ms |
| Warm launch | Process was recently terminated, some disk cache warm | <200ms |
| Resume | App suspended in background, brought to foreground | Instant (<100ms) |

### Pre-main Phase

Everything before `main()` is called. Measured as "pre-main time" in the App Launch instrument.

#### Dynamic Library Loading
Each dynamic framework adds ~10-20ms to launch. The dynamic linker (`dyld`) must:
1. Map the framework into memory
2. Resolve symbols
3. Run initializers

```
// Check your dylib count:
// Xcode → Build Settings → Mach-O Type
// Product → Scheme → Edit Scheme → Diagnostics → Enable "Dynamic Library Loads"

// Target: maximum 6 non-system dynamic frameworks
// Solution: prefer static linking (SPM default), merge frameworks
```

**Reducing dylib load time:**
- Convert dynamic frameworks to static libraries where possible
- SPM packages link statically by default — prefer SPM over CocoaPods
- CocoaPods `use_frameworks! :linkage => :static` forces static linking
- Mergeable Libraries (Xcode 15+): merge multiple dylibs into one at build time

#### Static Initializers
C++ global constructors and `__attribute__((constructor))` functions run before `main()`.

```swift
// BAD: ObjC +load methods (run for EVERY class at launch)
@objc class LegacyManager: NSObject {
    override class func load() {
        // Runs at launch — adds to pre-main time!
        setupLogging()
    }
}

// GOOD: Use +initialize (lazy, runs on first use) or Swift lazy init
@objc class LegacyManager: NSObject {
    override class func initialize() {
        // Runs only when class is first used
        setupLogging()
    }
}

// BEST: Swift lazy static property
class Manager {
    static let shared = Manager()  // Initialized on first access, thread-safe
}
```

### Post-main Phase

Everything from `main()` to the first frame on screen.

#### AppDelegate / App Optimization

```swift
// BAD: Everything in didFinishLaunching
func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    Analytics.initialize(key: "xxx")       // 50ms — network call
    CrashReporter.start()                   // 30ms
    FeatureFlags.sync()                     // 100ms — network call!
    DatabaseMigration.runIfNeeded()         // 200ms — disk I/O!
    PushNotifications.register()            // 20ms
    ThemeManager.apply()                    // 10ms
    // Total: 410ms BEFORE first frame
    return true
}

// GOOD: Only essential work at launch
func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // Only what's needed for the first frame:
    ThemeManager.apply()                    // 10ms — visual, needed now
    return true
}

// Defer everything else
func applicationDidBecomeActive(_ application: UIApplication) {
    Task.detached(priority: .background) {
        Analytics.initialize(key: "xxx")
        CrashReporter.start()
    }
    Task.detached(priority: .utility) {
        await FeatureFlags.sync()
        await DatabaseMigration.runIfNeeded()
    }
    PushNotifications.register()  // Can be slightly delayed
}
```

#### Lazy Initialization

```swift
// BAD: Eagerly initializes ALL services
class AppContainer {
    let analytics = AnalyticsService()
    let database = DatabaseService()
    let imageCache = ImageCacheService()
    let networkMonitor = NetworkMonitor()
}

// GOOD: Lazy initialization — only created when first accessed
class AppContainer {
    lazy var analytics = AnalyticsService()
    lazy var database = DatabaseService()
    lazy var imageCache = ImageCacheService()
    lazy var networkMonitor = NetworkMonitor()
}
```

#### First Screen Data

```swift
// BAD: Network fetch before showing first screen
struct ContentView: View {
    @State private var items: [Item] = []

    var body: some View {
        List(items) { item in
            ItemRow(item: item)
        }
        .task {
            items = try await api.fetchItems()  // 500ms+ delay before content
        }
    }
}

// GOOD: Show cached data immediately, refresh in background
struct ContentView: View {
    @State private var items: [Item] = []

    var body: some View {
        List(items) { item in
            ItemRow(item: item)
        }
        .task {
            // Immediate: show cached data
            if let cached = cache.loadItems() {
                items = cached
            }
            // Background: fetch fresh data
            if let fresh = try? await api.fetchItems() {
                items = fresh
                cache.saveItems(fresh)
            }
        }
    }
}
```

### Asset Optimization

| Strategy | Benefit | When to Use |
|----------|---------|-------------|
| Asset Catalogs | Compile-time optimization, app thinning | Always for bundled images |
| Vector assets (PDF/SVG) | Single asset for all scales | Icons, simple graphics |
| On Demand Resources | Smaller initial download | Level-based games, regional content |
| App Thinning (auto) | Device-specific assets only | Automatic with Asset Catalogs |

### Launch Time Measurement

```swift
// Measure post-main launch time programmatically
class AppDelegate: UIResponder, UIApplicationDelegate {
    let launchStart = CFAbsoluteTimeGetCurrent()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // ... setup ...

        DispatchQueue.main.async {
            let launchTime = CFAbsoluteTimeGetCurrent() - self.launchStart
            print("Launch time: \(launchTime * 1000)ms")
            // Report to analytics
        }
        return true
    }
}

// Or use MetricKit for production monitoring
class MetricsSubscriber: NSObject, MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            if let launchMetric = payload.applicationLaunchMetrics {
                let p50 = launchMetric.histogrammedTimeToFirstDraw
                    .bucketEnumerator  // Analyze distribution
            }
        }
    }
}
```

## Network Performance

### HTTP/2 Connection Reuse

```swift
// BAD: Creating new URLSession per request (no connection reuse)
func fetchUser() async throws -> User {
    let session = URLSession(configuration: .default)  // New session!
    let (data, _) = try await session.data(from: userURL)
    return try JSONDecoder().decode(User.self, from: data)
}

func fetchPosts() async throws -> [Post] {
    let session = URLSession(configuration: .default)  // Another new session!
    let (data, _) = try await session.data(from: postsURL)
    return try JSONDecoder().decode([Post].self, from: data)
}

// GOOD: Shared session — HTTP/2 multiplexes requests on one connection
class APIClient {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4    // Default is fine for HTTP/2
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true          // Wait for network instead of failing
        return URLSession(configuration: config)
    }()

    func fetchUser() async throws -> User {
        let (data, _) = try await Self.session.data(from: userURL)
        return try JSONDecoder().decode(User.self, from: data)
    }
}
```

### Image Format Comparison

| Format | Size (vs JPEG q80) | Encode Speed | Decode Speed | Transparency | iOS Min |
|--------|--------------------|--------------|--------------|-------------|---------|
| JPEG | 1.0x (baseline) | Fast | Fast | No | All |
| PNG | 2-5x larger | Medium | Fast | Yes | All |
| WebP | 0.66-0.75x | Medium | Medium | Yes | 14 |
| HEIF | ~0.50x | Medium | Medium | Yes (HEIF-A) | 11 |
| AVIF | 0.40-0.50x | Slow | Slow | Yes | 16 |

**Recommendation**: Use WebP for network images (broad compatibility, good compression). Use HEIF for on-device storage. Consider AVIF for bandwidth-constrained scenarios on iOS 16+.

### Pagination Strategies

```swift
// Cursor-based (recommended for real-time data)
struct CursorPage<T: Codable>: Codable {
    let items: [T]
    let nextCursor: String?  // Opaque cursor, stable under insertions/deletions
    let hasMore: Bool
}

// Usage
func fetchNextPage() async throws {
    guard let cursor = currentCursor, hasMore else { return }
    let page = try await api.fetchPosts(after: cursor, limit: 20)
    posts.append(contentsOf: page.items)
    currentCursor = page.nextCursor
    hasMore = page.hasMore
}

// Offset-based (simpler, but can skip/duplicate items if data changes)
func fetchPage(offset: Int, limit: Int = 20) async throws -> [Post] {
    try await api.fetchPosts(offset: offset, limit: limit)
}
```

### Caching Layers

```swift
// Layer 1: HTTP cache (URLCache) — automatic with proper headers
let config = URLSessionConfiguration.default
config.urlCache = URLCache(
    memoryCapacity: 50 * 1024 * 1024,   // 50MB memory
    diskCapacity: 200 * 1024 * 1024      // 200MB disk
)
// Server must send Cache-Control/ETag headers for this to work

// Layer 2: In-memory cache (NSCache) — for decoded objects
let imageCache = NSCache<NSURL, UIImage>()
imageCache.countLimit = 100               // Max 100 images
imageCache.totalCostLimit = 50 * 1024 * 1024  // 50MB

// Layer 3: Disk cache — for expensive-to-compute data
func cachedResponse<T: Codable>(for key: String, maxAge: TimeInterval,
                                  fetch: () async throws -> T) async throws -> T {
    let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(key)

    // Check disk cache
    if let data = try? Data(contentsOf: cacheURL),
       let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
       let modified = attrs[.modificationDate] as? Date,
       Date().timeIntervalSince(modified) < maxAge {
        return try JSONDecoder().decode(T.self, from: data)
    }

    // Fetch fresh
    let result = try await fetch()
    let data = try JSONEncoder().encode(result)
    try data.write(to: cacheURL)
    return result
}
```

### Request Compression

```swift
// Compress request body (large JSON payloads)
var request = URLRequest(url: endpoint)
request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
request.httpBody = try jsonData.compressed(using: .zlib)

// Accept compressed responses (URLSession does this by default)
request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
```

## Battery Optimization

### Background Processing

```swift
// BGAppRefreshTask — for short updates (<30 seconds)
func scheduleRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: "com.app.refresh")
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)  // 15 min min
    try? BGTaskScheduler.shared.submit(request)
}

func handleRefresh(_ task: BGAppRefreshTask) {
    scheduleRefresh()  // Schedule next one

    let fetchTask = Task {
        do {
            let data = try await api.fetchUpdates()
            await cache.update(with: data)
            task.setTaskCompleted(success: true)
        } catch {
            task.setTaskCompleted(success: false)
        }
    }

    task.expirationHandler = {
        fetchTask.cancel()
    }
}

// BGProcessingTask — for longer work (minutes, needs power + Wi-Fi)
func scheduleProcessing() {
    let request = BGProcessingTaskRequest(identifier: "com.app.sync")
    request.requiresNetworkConnectivity = true
    request.requiresExternalPower = true          // Only when charging
    request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
    try? BGTaskScheduler.shared.submit(request)
}
```

### Location Service Optimization

| Strategy | Accuracy | Battery Impact | Use For |
|----------|----------|---------------|---------|
| `startUpdatingLocation()` | Best available | Very High | Turn-by-turn navigation only |
| `requestLocation()` | One-shot | Low | Current location check |
| `startMonitoringSignificantLocationChanges()` | ~500m | Very Low | City-level tracking |
| `startMonitoring(for: CLCircularRegion)` | Region boundary | Very Low | Geofencing |
| `CLMonitor` (iOS 17+) | Configurable | Low-Medium | Modern monitoring API |

```swift
// BAD: Continuous GPS for a weather app
locationManager.desiredAccuracy = kCLLocationAccuracyBest
locationManager.startUpdatingLocation()  // Drains battery fast!

// GOOD: One-shot location for weather
locationManager.desiredAccuracy = kCLLocationAccuracyKilometer  // Weather doesn't need GPS
locationManager.requestLocation()  // Single update, then stops

// GOOD: Significant changes for background location features
locationManager.startMonitoringSignificantLocationChanges()
locationManager.allowsBackgroundLocationUpdates = true
```

### Network Request Batching

```swift
// BAD: Individual requests triggered by user actions
func trackEvent(_ name: String) {
    let event = AnalyticsEvent(name: name, timestamp: Date())
    Task {
        try await api.send(event)  // Network request per event!
    }
}

// GOOD: Batch events, send periodically or on threshold
actor EventBatcher {
    private var events: [AnalyticsEvent] = []
    private var batchTask: Task<Void, Never>?

    func track(_ event: AnalyticsEvent) {
        events.append(event)

        if events.count >= 20 {
            flush()  // Threshold reached
        } else if batchTask == nil {
            batchTask = Task {
                try? await Task.sleep(for: .seconds(60))
                flush()  // Timer flush
            }
        }
    }

    func flush() {
        guard !events.isEmpty else { return }
        let batch = events
        events = []
        batchTask?.cancel()
        batchTask = nil

        Task {
            try? await api.sendBatch(batch)
        }
    }
}
```

### Thermal State Monitoring

```swift
// Monitor device thermal state to reduce work when hot
func setupThermalMonitoring() {
    NotificationCenter.default.addObserver(
        forName: ProcessInfo.thermalStateDidChangeNotification,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        self?.handleThermalChange()
    }
}

func handleThermalChange() {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal:
        // Normal operation
        frameRateLimit = 120  // Full ProMotion
        imageQuality = .high
    case .fair:
        // Slightly warm — reduce non-essential work
        frameRateLimit = 60
        imageQuality = .high
    case .serious:
        // Hot — significantly reduce work
        frameRateLimit = 30
        imageQuality = .medium
        pauseBackgroundSync()
    case .critical:
        // Very hot — minimum work to prevent thermal shutdown
        frameRateLimit = 30
        imageQuality = .low
        pauseAllNonEssentialWork()
    @unknown default:
        break
    }
}
```

## Build Performance

### Compiler Type-Checking Warnings

Add these flags to identify functions where the Swift type checker is slow:

```
// Build Settings → Other Swift Flags:
-Xfrontend -warn-long-function-bodies=300
-Xfrontend -warn-long-expression-type-checking=300

// This warns on any function body or expression taking >300ms to type-check
// Common culprits:
// - Complex dictionary/array literals with type inference
// - Long chains of optional operations
// - Complex generic constraints
```

### Fixing Slow Type Checking

```swift
// BAD: Compiler struggles with complex literal type inference
let config = [
    "key1": value1 ?? defaultValue1,
    "key2": someOptional.map { transform($0) } ?? fallback,
    "key3": condition ? optionA : optionB.flatMap { $0.nested },
]

// GOOD: Add explicit type annotations
let config: [String: Any] = [
    "key1": value1 ?? defaultValue1,
    "key2": someOptional.map { transform($0) } ?? fallback,
    "key3": condition ? optionA : optionB.flatMap { $0.nested },
]

// BAD: Long expression chains
let result = items
    .filter { $0.isActive }
    .map { ($0.name, $0.value * multiplier + offset) }
    .sorted { $0.1 > $1.1 }
    .prefix(10)
    .map { "\($0.0): \($0.1)" }
    .joined(separator: ", ")

// GOOD: Break into intermediate steps with type annotations
let active = items.filter { $0.isActive }
let scored: [(String, Double)] = active.map { ($0.name, $0.value * multiplier + offset) }
let top = scored.sorted { $0.1 > $1.1 }.prefix(10)
let result = top.map { "\($0.0): \($0.1)" }.joined(separator: ", ")
```

### Optimization Levels

| Flag | Level | Build Speed | Runtime Speed | Use For |
|------|-------|-------------|---------------|---------|
| `-Onone` | No optimization | Fastest build | Slowest runtime | Debug |
| `-O` | Standard optimization | Medium build | Fast runtime | Release |
| `-Osize` | Size optimization | Medium build | Slightly slower | App size critical |
| `-Owholemodule` | Whole module | Slowest build | Fastest runtime | Release (default) |

**Important**: Never profile with `-Onone` — results are meaningless. Always use `-O` or `-Owholemodule` for performance measurements.

### SPM vs CocoaPods Build Performance

| Aspect | SPM | CocoaPods |
|--------|-----|-----------|
| Incremental build | Better (per-module) | Slower (pod rebuild) |
| Clean build | Fast (parallel targets) | Slower (sequential phases) |
| Linking | Static by default | Dynamic by default (unless configured) |
| Indexing | Fast | Can be slow for large Pods |
| Cache | Built-in binary cache | None (use `cocoapods-binary`) |

**Recommendation**: Migrate to SPM where possible. For large projects:
- Use binary targets for stable dependencies (pre-compiled `.xcframework`)
- Enable "Parallelize Build" in scheme settings
- Use explicit module builds (`-enable-explicit-modules`)

### Build Time Optimization Checklist

```
// Xcode Build Settings for faster builds:
SWIFT_COMPILATION_MODE = wholemodule    // For Release
SWIFT_COMPILATION_MODE = incremental    // For Debug (default)
DEAD_CODE_STRIPPING = YES
STRIP_SWIFT_SYMBOLS = YES               // Smaller binary
DEBUG_INFORMATION_FORMAT = dwarf         // Debug only (not dSYM)
ENABLE_PREVIEWS = NO                    // In CI builds

// Measure build time:
// Product → Perform Action → Build With Timing Summary
// Or: defaults write com.apple.dt.Xcode ShowBuildOperationDuration -bool YES
```

### Binary Dependencies for Stable Code

```swift
// Package.swift — use binary target for stable third-party code
let package = Package(
    name: "MyApp",
    dependencies: [
        // Source dependency — rebuilt every clean build
        .package(url: "https://github.com/actively-developed/lib.git", from: "2.0.0"),
    ],
    targets: [
        .target(name: "MyApp", dependencies: [
            "ActiveLib",
            "StableLib",  // Pre-compiled binary — no rebuild
        ]),
        // Binary target — downloaded once, never recompiled
        .binaryTarget(
            name: "StableLib",
            url: "https://releases.example.com/StableLib-1.0.0.xcframework.zip",
            checksum: "abc123..."
        ),
    ]
)
```

## Common Anti-Patterns

### 1. Main Thread Blocking

The main thread must return from each run loop iteration within 16.67ms (at 60 FPS) for smooth UI. Any synchronous work blocks the entire UI.

```swift
// BAD: Synchronous network on main thread
func viewDidLoad() {
    let data = try! Data(contentsOf: apiURL)  // Blocks UI until complete!
    let users = try! JSONDecoder().decode([User].self, from: data)
    tableView.reloadData()
}

// BAD: Heavy JSON decoding on main thread
func handleResponse(_ data: Data) {
    let payload = try! JSONDecoder().decode(HugePayload.self, from: data)
    self.items = payload.items  // If payload is 5MB, this takes >100ms
}

// GOOD: Decode off main thread
func handleResponse(_ data: Data) {
    Task.detached {
        let payload = try JSONDecoder().decode(HugePayload.self, from: data)
        await MainActor.run {
            self.items = payload.items  // Only UI update on main thread
        }
    }
}

// BAD: Synchronous file I/O on main thread
func save() {
    let data = try! JSONEncoder().encode(largeModel)
    try! data.write(to: saveURL)  // Blocks UI during disk write
}

// GOOD: Async file I/O
func save() async throws {
    try await Task.detached {
        let data = try JSONEncoder().encode(self.largeModel)
        try data.write(to: self.saveURL)
    }.value
}
```

### 2. Excessive Allocations in Loops

Creating objects in hot loops causes allocation pressure, cache misses, and GC pauses.

```swift
// BAD: DateFormatter created per iteration (~1ms each!)
for event in events {  // 10,000 events
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd HH:mm"
    labels.append(fmt.string(from: event.date))
}
// Total: ~10 seconds!

// GOOD: Reuse formatter
let fmt = DateFormatter()
fmt.dateFormat = "yyyy-MM-dd HH:mm"
for event in events {
    labels.append(fmt.string(from: event.date))
}
// Total: ~50ms

// BAD: String interpolation in loop (creates many intermediate Strings)
var result = ""
for item in items {
    result += "\(item.name): \(item.value)\n"  // O(n^2) — copies entire string each +=
}

// GOOD: Use Array + joined (O(n))
let lines = items.map { "\($0.name): \($0.value)" }
let result = lines.joined(separator: "\n")
```

### 3. Large View Hierarchies

Deep or wide view hierarchies are expensive to layout and render.

```swift
// BAD: Deeply nested stacks (each adds layout computation)
VStack {
    HStack {
        VStack {
            HStack {
                VStack {
                    Text(title)  // 5 levels deep = 5 layout passes
                }
            }
        }
    }
}

// GOOD: Flatten with explicit alignment and padding
VStack(alignment: .leading, spacing: 8) {
    Text(title)
        .padding(.horizontal, 16)
}
```

### 4. Using VStack for Large Collections

```swift
// BAD: 10,000 views created upfront — multi-second freeze on appear
ScrollView {
    VStack {
        ForEach(allProducts) { product in  // 10,000 products
            ProductCard(product: product)    // ALL created immediately
        }
    }
}
// Memory: 10,000 * ~2KB per view = ~20MB just in views
// CPU: seconds to create and layout all views

// GOOD: Only visible + buffer views created
ScrollView {
    LazyVStack {
        ForEach(allProducts) { product in
            ProductCard(product: product)    // ~20 visible at a time
        }
    }
}
// Memory: ~20 * ~2KB = ~40KB in views
// CPU: milliseconds to create visible views
```

### 5. Retaining View Controllers

```swift
// BAD: Closure retains the presented VC — it never deallocates after dismissal
class DetailVC: UIViewController {
    func setup() {
        NotificationCenter.default.addObserver(
            forName: .dataChanged,
            object: nil,
            queue: .main
        ) { _ in
            self.reload()  // DetailVC leaks after being dismissed
        }
    }
}

// GOOD: [weak self] in observer
func setup() {
    observer = NotificationCenter.default.addObserver(
        forName: .dataChanged,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        self?.reload()
    }
}

deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
}
```

### 6. Unnecessary Image Decoding

```swift
// BAD: Full-resolution decode for a 44x44 thumbnail
// A 4000x3000 JPEG decodes to 48MB in memory for a tiny thumbnail
cell.imageView.image = UIImage(data: fullResData)

// GOOD: Downsample at decode time
cell.imageView.image = downsample(
    data: fullResData,
    to: CGSize(width: 44, height: 44),
    scale: UIScreen.main.scale
)
```

### 7. Forgetting to Cancel Work

```swift
// BAD: Network request completes even after user navigated away
class SearchVM: ObservableObject {
    func search(_ query: String) {
        Task {
            let results = try await api.search(query)
            self.results = results  // May update a deallocated/invisible view
        }
    }
}

// GOOD: Cancel previous search, use .task for auto-cancellation
struct SearchView: View {
    @State private var query = ""
    @State private var results: [Result] = []

    var body: some View {
        List(results) { ResultRow(result: $0) }
            .searchable(text: $query)
            .task(id: query) {  // Cancels previous search on new query
                guard !query.isEmpty else { results = []; return }
                try? await Task.sleep(for: .milliseconds(300))  // Debounce
                guard !Task.isCancelled else { return }
                results = (try? await api.search(query)) ?? []
            }
    }
}
```

### 8. Recreating Expensive Objects

```swift
// BAD: New JSONDecoder per decode call
func decode<T: Decodable>(_ data: Data) throws -> T {
    let decoder = JSONDecoder()                    // Allocation!
    decoder.dateDecodingStrategy = .iso8601        // Configuration!
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: data)
}

// GOOD: Shared decoder
enum JSON {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    static func decode<T: Decodable>(_ data: Data) throws -> T {
        try decoder.decode(T.self, from: data)
    }
}
```

## Performance Testing

### XCTest Performance Measurement

```swift
func testScrollingPerformance() throws {
    let app = XCUIApplication()
    app.launch()

    let list = app.collectionViews.firstMatch

    let options = XCTMeasureOptions()
    options.iterationCount = 5

    measure(metrics: [
        XCTClockMetric(),           // Wall clock time
        XCTCPUMetric(),             // CPU time + cycles
        XCTMemoryMetric(),          // Peak memory
        XCTStorageMetric(),         // Disk writes
    ], options: options) {
        list.swipeUp(velocity: .fast)
        list.swipeUp(velocity: .fast)
        list.swipeDown(velocity: .fast)
        list.swipeDown(velocity: .fast)
    }
}

func testLaunchPerformance() throws {
    measure(metrics: [XCTApplicationLaunchMetric()]) {
        XCUIApplication().launch()
    }
}
```

### MetricKit for Production Monitoring

```swift
import MetricKit

class PerformanceMonitor: NSObject, MXMetricManagerSubscriber {
    func startMonitoring() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            // Launch time distribution
            if let launch = payload.applicationLaunchMetrics {
                reportLaunchMetrics(launch)
            }

            // Hang rate (main thread blocked >250ms)
            if let hangs = payload.applicationResponsivenessMetrics {
                reportHangRate(hangs)
            }

            // Memory peaks
            if let memory = payload.memoryMetrics {
                reportMemoryPeaks(memory)
            }
        }
    }

    // Diagnostic reports (crash, hang, disk write exceptions)
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            if let hangDiagnostics = payload.hangDiagnostics {
                for hang in hangDiagnostics {
                    reportHangDiagnostic(hang)
                }
            }
        }
    }
}
```

## Optimization Checklist

### Before You Optimize
- [ ] Identified the bottleneck with Instruments (not guessing)
- [ ] Established a baseline measurement
- [ ] Defined a target metric (e.g., "launch <400ms", "scroll 60 FPS")

### Memory
- [ ] No retain cycles (verified with Memory Graph Debugger)
- [ ] Delegates are `weak var`
- [ ] Escaping closures use `[weak self]`
- [ ] Images downsampled to display size
- [ ] Caches have size limits (`NSCache.countLimit`)

### UI Performance
- [ ] No work >16ms on main thread
- [ ] Large lists use `LazyVStack` or `List`
- [ ] SwiftUI views are small and state is scoped low
- [ ] `@Observable` used instead of `ObservableObject` (iOS 17+)
- [ ] No offscreen rendering in scroll views

### Launch
- [ ] Max 6 non-system dynamic frameworks
- [ ] Non-essential init deferred to `applicationDidBecomeActive`
- [ ] First screen shows cached data immediately
- [ ] No synchronous network calls at launch

### Network
- [ ] Single shared `URLSession` (HTTP/2 connection reuse)
- [ ] Images use WebP/HEIF format
- [ ] Proper caching headers (ETag, Cache-Control)
- [ ] Pagination for large datasets

### Battery
- [ ] No continuous GPS for non-navigation features
- [ ] Network requests batched where possible
- [ ] Background tasks use `BGTaskScheduler`
- [ ] Thermal state monitored and work reduced when hot
