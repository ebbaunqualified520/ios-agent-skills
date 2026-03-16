# The Composable Architecture (TCA) -- iOS Architecture Reference

## Overview

TCA by Point-Free is a unidirectional data flow architecture for Swift apps. Every feature is defined by four components: State, Action, Reducer, and Store. Effects handle side effects (networking, persistence). TCA provides exhaustive testing via `TestStore`.

**Dependency:** `swift-composable-architecture` (1.0+)

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│   View   │───>│  Action  │───>│ Reducer  │───>│  State   │
│          │<───│          │    │          │    │          │
│          │    │          │<───│ (Effect) │    │          │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
```

View sends Actions -> Reducer processes Action + current State -> returns new State + optional Effects -> Effects can send new Actions -> View re-renders.

---

## Four Components

### 1. State (@ObservableState)

```swift
@Reducer
struct CounterFeature {
    @ObservableState
    struct State: Equatable {
        var count = 0
        var isLoading = false
        var fact: String?
    }
}
```

### 2. Action (enum)

```swift
@Reducer
struct CounterFeature {
    // ...State above...

    enum Action {
        case incrementButtonTapped
        case decrementButtonTapped
        case factButtonTapped
        case factResponse(String)
    }
}
```

### 3. Reducer (body)

```swift
@Reducer
struct CounterFeature {
    @ObservableState
    struct State: Equatable {
        var count = 0
        var isLoading = false
        var fact: String?
    }

    enum Action {
        case incrementButtonTapped
        case decrementButtonTapped
        case factButtonTapped
        case factResponse(String)
    }

    @Dependency(\.numberFact) var numberFact

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .incrementButtonTapped:
                state.count += 1
                state.fact = nil
                return .none

            case .decrementButtonTapped:
                state.count -= 1
                state.fact = nil
                return .none

            case .factButtonTapped:
                state.isLoading = true
                state.fact = nil
                return .run { [count = state.count] send in
                    let fact = try await self.numberFact.fetch(count)
                    await send(.factResponse(fact))
                }

            case .factResponse(let fact):
                state.isLoading = false
                state.fact = fact
                return .none
            }
        }
    }
}
```

### 4. Store + View

```swift
struct CounterView: View {
    @Bindable var store: StoreOf<CounterFeature>

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button("-") { store.send(.decrementButtonTapped) }
                Text("\(store.count)")
                    .font(.largeTitle)
                    .monospacedDigit()
                Button("+") { store.send(.incrementButtonTapped) }
            }

            Button("Get Fact") { store.send(.factButtonTapped) }
                .disabled(store.isLoading)

            if store.isLoading {
                ProgressView()
            }

            if let fact = store.fact {
                Text(fact)
                    .padding()
            }
        }
    }
}
```

---

## Effect System

Effects represent side effects (network calls, timers, persistence). A Reducer returns `Effect<Action>`.

```swift
// No effect
return .none

// Fire-and-forget (no action returned)
return .run { _ in
    try await storage.save(data)
}

// Run and send action back
return .run { send in
    let result = try await apiClient.fetchUser(id)
    await send(.userLoaded(result))
}

// Send action synchronously
return .send(.otherAction)

// Cancel a running effect
return .cancel(id: CancelID.search)

// Cancellable effect
return .run { send in
    let results = try await searchClient.search(query)
    await send(.searchResults(results))
}
.cancellable(id: CancelID.search, cancelInFlight: true)

// Merge multiple effects
return .merge(
    .send(.resetForm),
    .run { send in
        try await analytics.track(.orderPlaced)
    }
)

// Concatenate effects (sequential)
return .concatenate(
    .send(.startLoading),
    .run { send in
        let data = try await api.fetch()
        await send(.dataLoaded(data))
    }
)
```

---

## @Dependency for Dependency Injection

TCA uses its own DI system. Dependencies are declared as `DependencyKey` and accessed via `@Dependency`.

```swift
// MARK: - Define the client

struct NumberFactClient {
    var fetch: @Sendable (Int) async throws -> String
}

// MARK: - Register as dependency

extension NumberFactClient: DependencyKey {
    static let liveValue = NumberFactClient(
        fetch: { number in
            let (data, _) = try await URLSession.shared.data(from: URL(string: "http://numbersapi.com/\(number)")!)
            return String(data: data, encoding: .utf8) ?? "No fact."
        }
    )

    static let testValue = NumberFactClient(
        fetch: unimplemented("NumberFactClient.fetch")
    )

    static let previewValue = NumberFactClient(
        fetch: { number in "Preview fact about \(number)." }
    )
}

extension DependencyValues {
    var numberFact: NumberFactClient {
        get { self[NumberFactClient.self] }
        set { self[NumberFactClient.self] = newValue }
    }
}

// MARK: - Use in Reducer

@Reducer
struct MyFeature {
    @Dependency(\.numberFact) var numberFact
    @Dependency(\.date.now) var now
    @Dependency(\.uuid) var uuid

    // ...
}
```

---

## Full Feature Example: Todo List

```swift
// MARK: - Todo Item Feature

@Reducer
struct TodoFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        let id: UUID
        var title: String
        var isCompleted: Bool = false
    }

    enum Action {
        case toggleCompleted
        case titleChanged(String)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .toggleCompleted:
                state.isCompleted.toggle()
                return .none
            case .titleChanged(let title):
                state.title = title
                return .none
            }
        }
    }
}

// MARK: - Todo List Feature

@Reducer
struct TodoListFeature {
    @ObservableState
    struct State: Equatable {
        var todos: IdentifiedArrayOf<TodoFeature.State> = []
        var newTodoTitle = ""
        var filter: Filter = .all

        enum Filter: String, CaseIterable {
            case all, active, completed
        }

        var filteredTodos: IdentifiedArrayOf<TodoFeature.State> {
            switch filter {
            case .all: return todos
            case .active: return todos.filter { !$0.isCompleted }
            case .completed: return todos.filter { $0.isCompleted }
            }
        }
    }

    enum Action {
        case addTodoButtonTapped
        case newTodoTitleChanged(String)
        case filterChanged(State.Filter)
        case clearCompletedTapped
        case todos(IdentifiedActionOf<TodoFeature>)
    }

    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .addTodoButtonTapped:
                guard !state.newTodoTitle.trimmingCharacters(in: .whitespaces).isEmpty else {
                    return .none
                }
                state.todos.insert(
                    TodoFeature.State(id: uuid(), title: state.newTodoTitle),
                    at: 0
                )
                state.newTodoTitle = ""
                return .none

            case .newTodoTitleChanged(let title):
                state.newTodoTitle = title
                return .none

            case .filterChanged(let filter):
                state.filter = filter
                return .none

            case .clearCompletedTapped:
                state.todos.removeAll { $0.isCompleted }
                return .none

            case .todos:
                return .none
            }
        }
        .forEach(\.todos, action: \.todos) {
            TodoFeature()
        }
    }
}

// MARK: - View

struct TodoListView: View {
    @Bindable var store: StoreOf<TodoListFeature>

    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    TextField("New todo...", text: $store.newTodoTitle.sending(\.newTodoTitleChanged))
                        .textFieldStyle(.roundedBorder)
                    Button("Add") { store.send(.addTodoButtonTapped) }
                }
                .padding(.horizontal)

                Picker("Filter", selection: $store.filter.sending(\.filterChanged)) {
                    ForEach(TodoListFeature.State.Filter.allCases, id: \.self) { filter in
                        Text(filter.rawValue.capitalized)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                List {
                    ForEach(store.scope(state: \.filteredTodos, action: \.todos)) { todoStore in
                        HStack {
                            Button {
                                todoStore.send(.toggleCompleted)
                            } label: {
                                Image(systemName: todoStore.isCompleted ? "checkmark.circle.fill" : "circle")
                            }
                            Text(todoStore.title)
                                .strikethrough(todoStore.isCompleted)
                        }
                    }
                }
            }
            .navigationTitle("Todos")
            .toolbar {
                Button("Clear Done") { store.send(.clearCompletedTapped) }
            }
        }
    }
}
```

---

## Navigation

### Sheet / Full Screen Cover (@Presents)

```swift
@Reducer
struct ParentFeature {
    @ObservableState
    struct State: Equatable {
        @Presents var detail: DetailFeature.State?
    }

    enum Action {
        case showDetailTapped
        case detail(PresentationAction<DetailFeature.Action>)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .showDetailTapped:
                state.detail = DetailFeature.State(itemId: UUID())
                return .none
            case .detail(.presented(.delegate(.didSave))):
                state.detail = nil
                return .none
            case .detail:
                return .none
            }
        }
        .ifLet(\.$detail, action: \.detail) {
            DetailFeature()
        }
    }
}

// View
struct ParentView: View {
    @Bindable var store: StoreOf<ParentFeature>

    var body: some View {
        Button("Show Detail") { store.send(.showDetailTapped) }
            .sheet(item: $store.scope(state: \.detail, action: \.detail)) { detailStore in
                DetailView(store: detailStore)
            }
    }
}
```

### Stack Navigation (StackState)

```swift
@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var path = StackState<Path.State>()
    }

    enum Action {
        case path(StackActionOf<Path>)
        case goToProfile(UUID)
    }

    @Reducer
    enum Path {
        case profile(ProfileFeature)
        case settings(SettingsFeature)
        case orderDetail(OrderDetailFeature)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .goToProfile(let userId):
                state.path.append(.profile(ProfileFeature.State(userId: userId)))
                return .none
            case .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}

// View
struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            HomeView(store: store)
        } destination: { store in
            switch store.case {
            case .profile(let profileStore):
                ProfileView(store: profileStore)
            case .settings(let settingsStore):
                SettingsView(store: settingsStore)
            case .orderDetail(let orderStore):
                OrderDetailView(store: orderStore)
            }
        }
    }
}
```

---

## Testing with TestStore

TCA's killer feature: exhaustive testing.

```swift
import Testing
import ComposableArchitecture
@testable import MyApp

struct CounterFeatureTests {
    @Test
    func increment() async {
        let store = TestStore(initialState: CounterFeature.State()) {
            CounterFeature()
        }

        await store.send(.incrementButtonTapped) {
            $0.count = 1
        }

        await store.send(.incrementButtonTapped) {
            $0.count = 2
        }
    }

    @Test
    func fetchFact() async {
        let store = TestStore(initialState: CounterFeature.State(count: 42)) {
            CounterFeature()
        } withDependencies: {
            $0.numberFact.fetch = { number in
                "\(number) is the answer."
            }
        }

        await store.send(.factButtonTapped) {
            $0.isLoading = true
        }

        await store.receive(\.factResponse) {
            $0.isLoading = false
            $0.fact = "42 is the answer."
        }
    }

    @Test
    func decrement() async {
        let store = TestStore(initialState: CounterFeature.State(count: 5)) {
            CounterFeature()
        }

        await store.send(.decrementButtonTapped) {
            $0.count = 4
        }
    }
}
```

### Testing Child Features (Composition)

```swift
@Test
func addTodo() async {
    let store = TestStore(initialState: TodoListFeature.State()) {
        TodoListFeature()
    } withDependencies: {
        $0.uuid = .incrementing
    }

    await store.send(.newTodoTitleChanged("Buy milk")) {
        $0.newTodoTitle = "Buy milk"
    }

    await store.send(.addTodoButtonTapped) {
        $0.newTodoTitle = ""
        $0.todos.insert(
            TodoFeature.State(id: UUID(0), title: "Buy milk"),
            at: 0
        )
    }
}

@Test
func toggleTodo() async {
    let store = TestStore(
        initialState: TodoListFeature.State(
            todos: [TodoFeature.State(id: UUID(0), title: "Walk dog")]
        )
    ) {
        TodoListFeature()
    }

    await store.send(\.todos[id: UUID(0)].toggleCompleted) {
        $0.todos[id: UUID(0)]?.isCompleted = true
    }
}
```

---

## Performance Tips

1. **Scope stores for child views** -- prevents re-rendering the entire list when one item changes.
2. **Use `IdentifiedArray`** instead of `[Item]` -- O(1) lookup by ID.
3. **Avoid large State structs** -- split into child features with `@Presents` or `Scope`.
4. **Use `.cancellable(cancelInFlight: true)`** for search/debounce effects.
5. **Mark State as `@ObservableState`** -- enables granular observation (TCA 1.7+).

---

## When to Use TCA

### Use TCA when:
- Complex interdependent state across multiple screens
- You need exhaustive, deterministic testing of every state change
- Multiple developers need clear boundaries (one Reducer per feature)
- Side effects are complex (timers, websockets, long-running tasks)
- You value the safety of unidirectional data flow

### Avoid TCA when:
- Simple CRUD app with minimal state
- Solo developer who values speed over structure
- Team is unfamiliar with functional programming
- The learning curve outweighs the project's complexity
- You need rapid prototyping (TCA has more boilerplate upfront)

### Migration path:
- Start with plain MVVM
- If state management becomes painful, introduce TCA for the complex features
- TCA features can coexist with plain SwiftUI views -- gradual adoption is fine

---

## Composition Patterns

### Scope (embed child reducer)

```swift
// Parent owns child state directly
var body: some ReducerOf<Self> {
    Scope(state: \.profile, action: \.profile) {
        ProfileFeature()
    }
    Reduce { state, action in
        // parent logic
    }
}
```

### .ifLet (optional child, e.g., sheet)

```swift
.ifLet(\.$detail, action: \.detail) {
    DetailFeature()
}
```

### .forEach (collection of children, e.g., list)

```swift
.forEach(\.todos, action: \.todos) {
    TodoFeature()
}
```

### Delegate Actions (child communicates to parent)

```swift
// Child
enum Action {
    case saveButtonTapped
    case delegate(Delegate)

    enum Delegate {
        case didSave(Item)
    }
}

// In child reducer:
case .saveButtonTapped:
    return .send(.delegate(.didSave(state.item)))

// Parent handles:
case .child(.presented(.delegate(.didSave(let item)))):
    state.items.append(item)
    return .none
```
