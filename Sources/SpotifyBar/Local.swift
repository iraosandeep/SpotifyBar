import SwiftUI

/// Drop-in for `@State`. The macOS 27 SDK implements `@State` as a macro whose
/// plugin only ships with Xcode, so a Command Line Tools build can't use it.
final class LocalBox<T>: ObservableObject {
    @Published var value: T
    init(_ value: T) { self.value = value }
}

@propertyWrapper
struct Local<T>: DynamicProperty {
    @StateObject private var box: LocalBox<T>
    init(wrappedValue: T) { _box = StateObject(wrappedValue: LocalBox(wrappedValue)) }
    var wrappedValue: T {
        get { box.value }
        nonmutating set { box.value = newValue }
    }
    var projectedValue: Binding<T> { $box.value }
}
