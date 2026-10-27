/// A value with the name a file gives it, kept in the file's order: an environment variable, a
/// default, a file to copy.
public struct Named<Value: Equatable & Sendable>: Equatable, Sendable {
    public var name: String
    public var value: Value

    public init(_ name: String, _ value: Value) {
        self.name = name
        self.value = value
    }
}

extension Array {
    /// `self`, with each of `other`'s names replacing the same name here, in place, and new names
    /// after: how a set's values lay over the set it extends.
    func overlaid<Value>(with other: [Named<Value>]) -> [Named<Value>] where Element == Named<Value> {
        var result = self
        for entry in other {
            if let index = result.firstIndex(where: { $0.name == entry.name }) {
                result[index] = entry
            } else {
                result.append(entry)
            }
        }
        return result
    }
}
