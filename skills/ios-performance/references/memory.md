# Memory Management Reference

## ARC Fundamentals

Automatic Reference Counting (ARC) tracks how many strong references point to each class instance. When the count drops to zero, the instance is deallocated. ARC only applies to **reference types** (classes, closures, actors). Value types (structs, enums, tuples) are not reference-counted.

### Reference Types

| Type | Increments RC | Prevents Deallocation | Becomes nil | Use When |
|------|--------------|----------------------|-------------|----------|
| `strong` (default) | Yes | Yes | N/A | Ownership relationship |
| `weak` | No | No | Yes (optional) | Delegate, cache, back-reference |
| `unowned` | No | No | No (crash if accessed) | Guaranteed shorter-lived reference |

### When to Use Each

**`strong`** (default) — use for ownership. Parent owns child. ViewModel owns service.

**`weak`** — use when:
- Delegate pattern (child references parent)
- Cache entries (allow deallocation under memory pressure)
- Any back-reference that could create a cycle
- Closure captures where you are not certain about lifetimes
- Always `weak var` (must be optional, must be variable)

**`unowned`** — use ONLY when:
- The referenced object is guaranteed to outlive the referencing object
- Classic example: `lazy var` closure referencing `self` (the property can't exist without the instance)
- Another: child object that absolutely cannot exist without parent
- **Accessing a deallocated `unowned` reference is a runtime crash** — when in doubt, use `weak`

```swift
// unowned is safe here: closure cannot outlive self
class SearchController {
    let debouncer: Debouncer

    init() {
        debouncer = Debouncer(delay: 0.3) { [unowned self] in
            self.performSearch()  // self always alive while debouncer exists
        }
    }
}

// weak is safer here: callback timing is uncertain
class DataLoader {
    func load() {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }  // self may have been deallocated
            self.process(data)
        }.resume()
    }
}
```

## Retain Cycles

A retain cycle occurs when two or more objects hold strong references to each other, preventing ARC from ever deallocating them. This is the most common source of memory leaks in iOS.

### Pattern 1: Closure Capturing Self

```swift
// RETAIN CYCLE: self → closure (stored property), closure → self
class ViewController: UIViewController {
    var onComplete: (() -> Void)?

    func setup() {
        onComplete = {
            self.dismiss(animated: true)  // closure strongly captures self
        }
    }
}

// FIX: [weak self]
func setup() {
    onComplete = { [weak self] in
        self?.dismiss(animated: true)
    }
}
```

### Pattern 2: Delegate Cycle

```swift
// RETAIN CYCLE: viewController → tableView → delegate (viewController)
protocol TableDelegate {
    func didSelect(_ item: Item)  // Not constrained to AnyObject!
}

class MyVC: UIViewController, TableDelegate {
    let tableManager = TableManager()

    func viewDidLoad() {
        tableManager.delegate = self  // Strong reference back to self
    }
}

class TableManager {
    var delegate: TableDelegate?  // Strong! Creates cycle
}

// FIX: Constrain protocol, make delegate weak
protocol TableDelegate: AnyObject {
    func didSelect(_ item: Item)
}

class TableManager {
    weak var delegate: TableDelegate?  // Weak breaks cycle
}
```

### Pattern 3: Timer Retain Cycle

```swift
// RETAIN CYCLE: self → timer (via invalidate responsibility), timer → self (target)
class Poller {
    var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(
            timeInterval: 5.0,
            target: self,      // Timer strongly retains target!
            selector: #selector(poll),
            userInfo: nil,
            repeats: true
        )
    }

    deinit {
        timer?.invalidate()  // Never called — cycle prevents dealloc
    }
}

// FIX: Use block-based timer with [weak self]
func start() {
    timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
        self?.poll()
    }
}
```

### Pattern 4: NotificationCenter (Pre-iOS 9 / Block-Based)

```swift
// RETAIN CYCLE: observer block captures self, NotificationCenter retains block
class MyVC: UIViewController {
    var observer: NSObjectProtocol?

    func setup() {
        observer = NotificationCenter.default.addObserver(
            forName: .userDidLogin,
            object: nil,
            queue: .main
        ) { _ in
            self.refresh()  // Strong capture!
        }
    }
}

// FIX: [weak self] + remove observer
func setup() {
    observer = NotificationCenter.default.addObserver(
        forName: .userDidLogin,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        self?.refresh()
    }
}

deinit {
    if let observer {
        NotificationCenter.default.removeObserver(observer)
    }
}
```

### Pattern 5: Combine Sink Without Store

```swift
// LEAK: AnyCancellable is discarded, but closure may still hold self
class MyVM: ObservableObject {
    func subscribe() {
        publisher
            .sink { [weak self] value in  // [weak self] is still needed
                self?.handle(value)
            }
            .store(in: &cancellables)  // Must store to keep subscription alive
    }
}
```

## When [weak self] is NOT Needed

Non-escaping closures do not store the closure beyond the function call. They execute synchronously and release all captures when the function returns. No retain cycle is possible.

```swift
// These are ALL non-escaping — no [weak self] needed:
let mapped = array.map { self.transform($0) }
let filtered = array.filter { self.isValid($0) }
let reduced = array.reduce(0) { $0 + self.score($1) }
array.forEach { self.process($0) }
let sorted = array.sorted { self.compare($0, $1) }
let compacted = array.compactMap { self.convert($0) }

// UIView.animate IS escaping (despite feeling synchronous)
UIView.animate(withDuration: 0.3) { [weak self] in
    self?.view.alpha = 0  // [weak self] technically needed but...
}
// In practice, UIView.animate completes quickly and Apple holds the only
// reference. Omitting [weak self] here won't leak, but it's technically escaping.

// DispatchQueue IS escaping — [weak self] recommended
DispatchQueue.main.async { [weak self] in
    self?.updateUI()
}

// Task {} IS escaping — [weak self] recommended for long-running tasks
Task { [weak self] in
    let data = await self?.fetchData()
    await self?.display(data)
}
```

## [weak self] Guard Patterns

```swift
// Pattern 1: guard let self (most common)
someAsyncCall { [weak self] result in
    guard let self else { return }
    self.name = result.name
    self.reload()
}

// Pattern 2: Optional chaining (simple one-liners)
someAsyncCall { [weak self] result in
    self?.reload()
}

// Pattern 3: if let for conditional work
someAsyncCall { [weak self] result in
    if let self {
        self.process(result)
    }
}
```

## Value Types vs Reference Types

### Stack vs Heap Allocation

| Aspect | Value Types (struct, enum) | Reference Types (class, actor) |
|--------|---------------------------|-------------------------------|
| Storage | Stack (usually) | Heap (always) |
| Copying | Deep copy (bit-for-bit) | Reference copy (pointer) |
| ARC overhead | None | Yes (retain/release) |
| Thread safety | Safe (each thread has own copy) | Unsafe (shared mutable state) |
| Identity | No (`===` not available) | Yes (`===` compares identity) |
| Inheritance | No | Yes |
| Mutability | `mutating` keyword needed | Mutable by default |
| Deinit | No `deinit` | Has `deinit` |

### When to Use struct
- Data models (DTOs, API responses)
- Small, frequently-copied values
- Thread-safe data passing
- When identity doesn't matter (two `Point(x: 1, y: 2)` are equal)

### When to Use class
- Shared mutable state (view models, services, managers)
- Identity matters (this specific instance, not just equal values)
- Inheritance needed
- Interop with ObjC/UIKit (UIViewController, etc.)
- When copying is expensive and sharing is intended

### Performance Implications

```swift
// struct: Stack-allocated (fast), no ARC
struct Point {
    var x: Double
    var y: Double
}

var a = Point(x: 1, y: 2)
var b = a        // Copies value — O(1) bit copy, no heap allocation
b.x = 3         // a.x is still 1

// class: Heap-allocated (slower), ARC overhead on every copy
class PointClass {
    var x: Double
    var y: Double
    init(x: Double, y: Double) { self.x = x; self.y = y }
}

var a = PointClass(x: 1, y: 2)  // Heap allocation + ARC init
var b = a        // Copies pointer, increments reference count
b.x = 3         // a.x is ALSO 3 (shared reference)

// IMPORTANT: Structs containing reference types still incur ARC
struct User {
    var name: String     // String uses COW (heap buffer when large)
    var avatar: UIImage  // Reference type inside struct = ARC on copy
}
```

### Large Structs Warning
Structs larger than ~4 machine words (32 bytes on arm64) may be heap-allocated by the compiler. Very large structs with many value-type fields incur copy overhead. Profile if in doubt.

## Copy-on-Write (COW)

Swift's standard library collections (Array, Dictionary, Set, String) use COW: multiple references share the same underlying buffer until one of them mutates.

```swift
var a = [1, 2, 3]       // Buffer allocated
var b = a                // b shares a's buffer (no copy yet)
// At this point, a and b point to the SAME memory

b.append(4)             // NOW the buffer is copied (b gets its own copy)
// a = [1, 2, 3], b = [1, 2, 3, 4]
```

### Implementing Custom COW

```swift
final class StorageBuffer<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

struct COWContainer<T> {
    private var buffer: StorageBuffer<T>

    init(_ value: T) {
        buffer = StorageBuffer(value)
    }

    var value: T {
        get { buffer.value }
        set {
            // Only copy if multiple references exist
            if !isKnownUniquelyReferenced(&buffer) {
                buffer = StorageBuffer(newValue)
            } else {
                buffer.value = newValue
            }
        }
    }
}
```

### COW Pitfall: Holding Multiple References

```swift
// BAD: Dictionary access creates a temporary reference, breaking COW uniqueness
var dict = [key: [1, 2, 3]]
dict[key]?.append(4)  // This may copy the array unnecessarily

// BETTER: Remove, mutate, re-insert
var array = dict.removeValue(forKey: key)!
array.append(4)
dict[key] = array  // Single owner the whole time
```

## Memory Debugging Tools

### 1. Xcode Memory Graph Debugger
- Debug menu → Debug Memory Graph (or click the memory graph button in debug bar)
- Shows all live objects and their reference relationships
- Purple "!" icons indicate potential leaks (objects not reachable from roots)
- Click an object to see its reference chain — follow strong references to find cycles
- Export `.memgraph` file for CLI analysis

### 2. Instruments — Allocations
- Tracks every heap allocation and deallocation
- **Statistics view**: shows live allocation count and size by category
- **Generation marking**: Mark Generation button creates a snapshot. Objects allocated after a mark but still alive at the next mark are "new persistent" — potential leaks
- **Call Trees**: shows where allocations originate
- Workflow: Mark generation → perform action → mark again → inspect growth

### 3. Instruments — Leaks
- Periodically scans heap for unreachable object cycles
- Shows leak size and backtrace of allocation
- Limitation: cannot detect retain cycles where objects ARE still reachable (use Memory Graph for those)

### 4. Instruments — VM Tracker
- Shows virtual memory regions (dirty, clean, compressed, swapped)
- Useful for understanding total memory footprint beyond just heap allocations
- "Dirty memory" is the key metric — this is what counts toward jetsam limits

### 5. CLI Tools

```bash
# Analyze a .memgraph file
leaks --outputGraph=output App.memgraph

# Show heap contents
heap App.memgraph --sortBySize

# Show virtual memory map
vmmap App.memgraph --summary
vmmap App.memgraph | grep MALLOC

# Find reference chains to a specific object
leaks App.memgraph --traceTree=0x600000c0a000
```

### 6. Autorelease Pool for ObjC Interop

When creating many ObjC objects in a loop (e.g., processing images, parsing data), wrap in `autoreleasepool` to release them per iteration instead of waiting for the run loop drain.

```swift
// BAD: All temporary ObjC objects accumulate until loop ends
for path in imagePaths {
    let image = UIImage(contentsOfFile: path)  // ObjC under the hood
    processImage(image)
}

// GOOD: Each iteration drains its pool
for path in imagePaths {
    autoreleasepool {
        let image = UIImage(contentsOfFile: path)
        processImage(image)
    }
}
```

## Common Leak Patterns Summary

| Pattern | Cause | Fix |
|---------|-------|-----|
| Closure captures self | Escaping closure stored as property | `[weak self]` |
| Strong delegate | Delegate property is strong | `weak var delegate` |
| Timer retains target | `Timer.scheduledTimer(target:)` | Block-based timer + `[weak self]` |
| NotificationCenter block | Observer block captures self | `[weak self]` + remove observer |
| Combine sink | Sink closure captures self | `[weak self]` + store cancellable |
| URLSession delegate | Session retains delegate until invalidated | `finishTasksAndInvalidate()` |
| CADisplayLink | Display link retains target | `[weak self]` or invalidate in willMove(toWindow:) |
| DispatchSource | Event handler captures self | `[weak self]` or cancel source |
| Nested closures | Inner closure captures self through outer | `[weak self]` in outermost closure |
| Circular model refs | Parent ↔ Child strong references | Make child's parent reference `weak` |
