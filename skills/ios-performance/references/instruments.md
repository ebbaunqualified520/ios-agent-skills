# Instruments Profiling Reference

## General Principles

1. **Always profile on a real device** — Simulator uses x86 translation (Rosetta) or has different CPU/GPU characteristics. Performance numbers from Simulator are meaningless.
2. **Use Release configuration** — Debug builds have optimizations disabled, extra assertions, and sanitizers. Profile Release for real numbers.
3. **Profile specific interactions** — Record 10-30 seconds covering the exact problematic scenario. Don't record 5 minutes of random usage.
4. **Compare before/after** — Save traces as baselines. After optimization, re-profile and compare.
5. **One instrument at a time** (for accuracy) — Running multiple heavy instruments simultaneously can skew results. Time Profiler alone first, then Allocations alone.

## Time Profiler

The most important profiling tool. Shows where CPU time is spent by periodically sampling call stacks (default: every 1ms).

### Essential Settings (Always Enable These)

| Setting | Why |
|---------|-----|
| **Invert Call Tree** | Shows heaviest leaf functions first (where time is actually spent) |
| **Separate by Thread** | Isolates main thread (Thread 1) work from background threads |
| **Hide System Libraries** | Focuses on YOUR code, not Apple frameworks |
| **Separate by State** | Distinguishes running (CPU) vs blocked (waiting) time |
| **Top Functions** | Aggregates time including callees — shows true cost of calling a function |

### Reading Results

```
Weight    Self Weight    Symbol
850ms     2ms           -[MyViewController viewDidLoad]
  800ms   800ms           -[JSONParser parseData:]      ← Hot spot!
  48ms    48ms            -[MyViewController setupUI]
```

- **Weight**: Total time including all callees
- **Self Weight**: Time spent in this function alone (not calling others)
- **Hot spots**: Functions with high Self Weight on the main thread

### Common Findings

| Finding | Cause | Fix |
|---------|-------|-----|
| `JSONDecoder.decode` on main thread | Synchronous JSON parsing | Move to background Task/actor |
| `UIImage(named:)` taking >10ms | Large undecoded image | Downsample, use asset catalog |
| `NSRegularExpression.init` repeated | Creating regex in loop | Cache regex instance |
| `layoutSubviews` called 100x | Constraint thrashing | Batch constraint changes |
| `draw(in:)` taking >16ms | Complex custom drawing | Pre-render to bitmap, simplify |
| `objc_msgSend` high Self Weight | Too many ObjC method calls in hot path | Consider Swift value types |

### Profiling Workflow

1. Product → Profile (Cmd+I) → Choose "Time Profiler"
2. Set recording options: Deferred Mode = Off, sample interval = 1ms
3. Hit Record, perform the problematic interaction on device
4. Stop recording
5. Select the time range of interest (drag on timeline)
6. Enable the four settings above
7. Look at main thread first — find functions with highest Self Weight
8. Double-click a symbol to see source code with time annotations

### Hangs / Hitches Detection

Time Profiler can show "hangs" — periods where the main thread is blocked for >250ms.

```
// In Instruments, use the "Hangs" track or filter Time Profiler for:
// Thread 1 → sort by weight → look for >16.67ms functions
```

As of Xcode 15+, use the dedicated **Thread State Trace** instrument to see exactly when and why the main thread was blocked (waiting on lock, I/O, etc.).

## Allocations

Tracks every `malloc`/`free` (heap allocation and deallocation). Shows what's alive, what's been freed, and where memory is being allocated.

### Key Views

| View | Shows | Use For |
|------|-------|---------|
| **Statistics** | Live allocation count and size by category | Finding what consumes most memory |
| **Call Trees** | Allocation backtraces | Finding WHERE allocations happen |
| **Generations** | Objects alive between generation marks | Finding leaks and growth |
| **VM Tracker** | Virtual memory regions | Understanding full memory footprint |

### Generation Analysis (Leak Detection)

The most powerful technique for finding memory growth:

1. Start recording
2. Navigate to the suspect screen
3. Click **Mark Generation** (creates a baseline)
4. Perform the action that might leak (open/close a screen, scroll a list)
5. Click **Mark Generation** again
6. Repeat steps 4-5 several times
7. Inspect each generation: objects allocated AFTER the mark that are still alive

```
Generation A → Generation B: +2.5MB growth
  Category              Count    Size
  UIImage               45       2.1MB    ← Images not released!
  _NSContiguousString   230      180KB
  MyViewModel           3        24KB     ← ViewModels not deallocated!
```

If memory grows consistently per generation, you have a leak or unbounded cache.

### Allocation Hotspots

Sort by "# Persistent" (objects still alive) and "Persistent Bytes" to find the biggest memory consumers.

```
Category                  # Persistent    Persistent Bytes
VM: ImageIO_JPEG_Data     12              48.2 MB          ← Decoded JPEG buffers
CFData (store)            340             8.1 MB
UIImage                   45              2.1 MB
```

### Transient vs Persistent

- **Transient**: allocated then freed — fine, but excessive churn slows things down
- **Persistent**: allocated and still alive — this IS your memory footprint
- High transient count in tight loops = GC pressure and potential hitches

## Leaks

Periodically scans the heap to find objects that are no longer reachable from any root (global, stack, register) but haven't been freed.

### How It Works
1. Pauses the process
2. Scans all memory for pointer-like values
3. Builds a reachability graph from known roots
4. Objects NOT reachable from any root = leaks

### Limitations
- **Cannot detect retain cycles where objects ARE reachable** — if you hold a reference to object A, and A ↔ B form a cycle, Leaks sees A as reachable (through your reference). Use Memory Graph Debugger for these.
- Scan interval is ~10 seconds — short-lived leaks may be missed
- False positives possible (interior pointers, tagged pointers)

### Leaks Workflow
1. Profile → Leaks instrument
2. Exercise the app for 30-60 seconds
3. Leaks appear as red bars on the timeline
4. Click a leak → see the backtrace of the allocation
5. Identify the class and find the strong reference cycle

### Leaks + Allocations (Combined Template)
Use the "Leaks" template which includes both Leaks and Allocations instruments. This gives you leak detection AND generation analysis in one session.

## Memory Graph Debugger (Xcode)

The best tool for finding retain cycles in reachable objects (which Leaks instrument cannot find).

### How to Use
1. Run app in Debug mode
2. Navigate to the suspect state
3. Click the **Memory Graph** button in Xcode's debug bar (three circles icon)
4. Wait for snapshot to complete
5. Left panel: browse objects by class
6. Center: visual reference graph
7. Purple "!" icons = runtime-detected issues (potential leaks)

### Finding Retain Cycles
1. Look for purple "!" indicators
2. Click on a suspect object
3. Trace the reference chain in the graph view
4. Look for circular paths (A → B → A)
5. Identify which reference should be `weak`

### Exporting for CLI Analysis
```
// In Xcode: File → Export Memory Graph → save as .memgraph

// Then analyze from Terminal:
leaks MyApp.memgraph
leaks MyApp.memgraph --traceTree=0x600000c0a000  // Trace specific object
heap MyApp.memgraph --sortBySize                   // Sort by total size
vmmap MyApp.memgraph --summary                     // VM region summary
```

### What to Look For
- Objects that should have been deallocated (e.g., a ViewController that was popped)
- Growing counts of the same class over time
- Reference chains from closures to view controllers (common cycle source)
- `Timer` or `CADisplayLink` instances holding references to deallocated owners

## Energy Log

Monitors the energy impact of your app across CPU, network, GPS, Bluetooth, display, and more.

### Energy Impact Levels

| Level | Description | User Impact |
|-------|-------------|-------------|
| 0 (Low) | <10% overhead | Ideal |
| 1 (Moderate) | 10-20% | Acceptable for active use |
| 2 (High) | 20-50% | Drains battery noticeably |
| 3 (Very High) | >50% | "This app is killing my battery" |

### What to Monitor

| Component | Good | Bad |
|-----------|------|-----|
| CPU | Bursts of work, then idle | Sustained >30% when "idle" |
| Network | Batched requests, then quiet | Polling every few seconds |
| Location | Significant changes / region monitoring | Continuous GPS updates |
| Bluetooth | Connect, transfer, disconnect | Scanning continuously |
| Display | Standard brightness | Preventing auto-lock unnecessarily |

### Common Energy Drains

```swift
// BAD: Polling every 5 seconds
Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
    self.checkForUpdates()
}

// GOOD: Use push notifications or BGAppRefreshTask
BGAppRefreshTask → system decides optimal timing

// BAD: Continuous GPS
locationManager.startUpdatingLocation()

// GOOD: Significant location changes
locationManager.startMonitoringSignificantLocationChanges()
// or region monitoring for geofences
locationManager.startMonitoring(for: region)

// BAD: Keeping network sessions alive
URLSession.shared.dataTask(with: url)  // Uses default session = keep-alive

// GOOD: Use discretionary background downloads
let config = URLSessionConfiguration.background(withIdentifier: "sync")
config.isDiscretionary = true  // System batches with other downloads
```

### Energy Profiling Workflow
1. Profile → Energy Log
2. Use the device normally for 3-5 minutes
3. Check the energy timeline for spikes
4. Drill into CPU, Network, Location rows to find culprits
5. Cross-reference with code to find the offending component

## Core Animation Instrument

Measures rendering performance: frame rate, GPU utilization, and rendering bottlenecks.

### Debug Options (Most Important)

| Option | What It Shows | Color | Fix |
|--------|--------------|-------|-----|
| **Color Blended Layers** | Layers with transparency that need compositing | Red = blended | Use opaque backgrounds, set `isOpaque = true` |
| **Color Offscreen-Rendered** | Layers rendered offscreen (expensive) | Yellow | Remove `cornerRadius` + `masksToBounds`, use pre-rendered corners |
| **Color Hits Green / Misses Red** | Rasterization cache hits vs misses | Green = cached | Enable `shouldRasterize` for complex static layers |
| **Color Copied Images** | Images that need color format conversion | Blue | Use sRGB, match pixel format to display |
| **Color Misaligned Images** | Images not aligned to pixel boundaries | Magenta | Use whole-number frames, match image size to view |

### Offscreen Rendering Causes

Offscreen rendering is the #1 cause of scrolling jank. The GPU must create a temporary offscreen buffer, render into it, then composite — each frame.

```swift
// EXPENSIVE: cornerRadius + masksToBounds triggers offscreen render
view.layer.cornerRadius = 12
view.layer.masksToBounds = true  // This forces offscreen rendering

// BETTER: Use cornerCurve (iOS 13+) — GPU-optimized
view.layer.cornerRadius = 12
view.layer.cornerCurve = .continuous

// Or pre-render rounded corners in image processing
// Or use a rounded UIBezierPath mask (one-time cost)

// EXPENSIVE: Shadow without path
view.layer.shadowColor = UIColor.black.cgColor
view.layer.shadowOpacity = 0.3
view.layer.shadowRadius = 8
// GPU must calculate shadow shape every frame!

// BETTER: Provide shadow path
view.layer.shadowPath = UIBezierPath(
    roundedRect: view.bounds,
    cornerRadius: 12
).cgPath  // GPU uses pre-calculated path
```

### Frame Rate Analysis
- Target: 60 FPS sustained (16.67ms per frame)
- ProMotion: 120 FPS when active (8.33ms per frame)
- Check for "hitches" — frames taking >16.67ms
- A hitch of 33ms = one visible dropped frame
- A hitch of 100ms = 5 dropped frames = very visible jank

## Network Instrument

Tracks all network requests made by the app.

### What to Look For

| Metric | Good | Bad |
|--------|------|-----|
| Connection reuse | HTTP/2 multiplexing, few new connections | New TCP connection per request |
| Response size | Compressed, paginated | Multi-MB uncompressed JSON |
| Cache hit rate | >50% for repeat resources | 0% (no caching configured) |
| Concurrent requests | 2-4 parallel | 50+ simultaneous |
| Request timing | <200ms average | >2s for simple API calls |

### Common Findings
- Multiple `URLSession` instances instead of sharing one (no connection reuse)
- Images downloaded at full resolution instead of requested size
- No ETag/If-Modified-Since headers (re-downloading unchanged data)
- POST requests for data that could be GET (no caching possible)

## SwiftUI Instrument (Xcode 16+)

Dedicated instrument for profiling SwiftUI view performance.

### Available Tracks

1. **View Body**: Shows every body evaluation — which view, when, how long
2. **View Properties**: Shows which properties changed to trigger the evaluation
3. **Cause & Effect**: Visual graph connecting state changes to view updates
4. **Hitch Risk**: Highlights views likely to miss frame deadlines

### What to Look For

1. **Body evaluation count**: If a view's body is called 100+ times in a few seconds, investigate
2. **Cascading updates**: One state change triggering dozens of view updates
3. **Slow body**: Any single body evaluation taking >2ms
4. **Unexpected evaluations**: Views re-evaluating when their inputs haven't changed

### Using the Cause & Effect Graph
1. Select a view update in the timeline
2. Open the Cause & Effect view
3. Trace backward: which property change caused this view update?
4. Trace forward: which other views were affected by the same change?
5. Identify the root cause and optimize the state dependency chain

### Correlating with Time Profiler
Run SwiftUI instrument alongside Time Profiler to see:
- Which body evaluations are expensive (SwiftUI instrument)
- What exactly is slow inside those evaluations (Time Profiler)

## CLI Tools for Memory Analysis

### leaks

```bash
# Check running process for leaks
leaks MyApp

# Analyze exported memory graph
leaks MyApp.memgraph

# Trace references to a specific address
leaks MyApp.memgraph --traceTree=0x600000c0a000

# Output in JSON for scripting
leaks MyApp.memgraph --json

# Show only Swift objects
leaks MyApp.memgraph --class-filter="MyApp"
```

### heap

```bash
# Show heap contents sorted by size
heap MyApp.memgraph --sortBySize

# Show heap contents sorted by count
heap MyApp.memgraph --sortByCount

# Show only objects of a specific class
heap MyApp.memgraph --className=MyViewController

# Show addresses of specific class
heap MyApp.memgraph --addresses=MyViewController
```

### vmmap

```bash
# Summary of virtual memory regions
vmmap MyApp.memgraph --summary

# Show only dirty memory (what counts toward jetsam)
vmmap MyApp.memgraph --summary | grep -E "DIRTY|SWAPPED"

# Show MALLOC zones
vmmap MyApp.memgraph | grep MALLOC

# Detailed region info
vmmap MyApp.memgraph --verbose
```

### malloc_history (for allocation backtraces)

```bash
# Must run app with MallocStackLogging=1 environment variable
# Then:
malloc_history MyApp <address>
```

## Instruments Best Practices

### Before You Start
1. Close all unnecessary apps on the device
2. Restart the device (clean state)
3. Disable any debug environment variables (unless needed)
4. Use Release configuration
5. Ensure device is not thermally throttled (cool it down if hot)

### During Recording
1. Wait 2-3 seconds after pressing Record before interacting
2. Perform the exact problematic action, slowly and deliberately
3. Repeat the action 3-5 times for consistent data
4. Stop recording after the last repetition

### After Recording
1. Select the time range of ONE repetition
2. Look at main thread first
3. Document findings with screenshots
4. Save the trace file (.trace) as a baseline
5. Make ONE change, re-profile, compare

### Automation
```swift
// Signpost API for custom regions in Instruments
import os

let log = OSLog(subsystem: "com.myapp", category: "Performance")

func processData(_ data: Data) {
    os_signpost(.begin, log: log, name: "Process Data", "size: %d", data.count)
    defer { os_signpost(.end, log: log, name: "Process Data") }

    // ... processing ...
}

// Use Points of Interest instrument to see these markers on the timeline
```

## Profiling Checklist

- [ ] Profiling on a REAL device (not Simulator)
- [ ] Using Release configuration
- [ ] Device is cool (not thermally throttled)
- [ ] One instrument at a time for accuracy
- [ ] Time range selected on timeline before analyzing
- [ ] Time Profiler: Invert Call Tree + Separate by Thread + Hide System Libs enabled
- [ ] Allocations: Generation marking used for leak detection
- [ ] Baseline trace saved for before/after comparison
- [ ] Results cross-referenced with source code
- [ ] Optimizations verified by re-profiling
