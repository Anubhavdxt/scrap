import SwiftUI

/// What `@State` does, written without it. On the macOS 27 SDK `@State` is a macro, and its compiler plugin ships with
/// Xcode but not with the Command Line Tools, so a view that uses `@State` can't be built with the tools alone (the
/// build fails with "cannot assign to property: 'self' is immutable"). Every other wrapper we use (`@AppStorage`,
/// `@Environment`, `@StateObject`, `@ObservedObject`, `@Binding`) builds fine, and this one is made of `@StateObject`.
@propertyWrapper
struct Local<Value>: DynamicProperty {
    private final class Box: ObservableObject {
        @Published var value: Value
        init(_ value: Value) { self.value = value }
    }

    @StateObject private var box: Box

    init(wrappedValue: Value) {
        _box = StateObject(wrappedValue: Box(wrappedValue))
    }

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    var projectedValue: Binding<Value> {
        Binding(get: { box.value }, set: { box.value = $0 })
    }
}
