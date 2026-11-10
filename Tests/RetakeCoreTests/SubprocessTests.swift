import Foundation
import Testing
@testable import RetakeCore

struct SubprocessTests {
    /// More at once than there are threads for Swift concurrency, each waiting on its tool, as the
    /// tests do in parallel on a CI machine with few cores. Draining the pipes on Dispatch queues
    /// deadlocked here.
    @Test func manyRunAtOnceFromTasks() async throws {
        let results = try await withThrowingTaskGroup(of: Subprocess.Result.self) { group in
            for index in 0..<64 {
                group.addTask { try Subprocess.run("/bin/echo", ["\(index)"]) }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(Set(results.map(\.outputText)) == Set((0..<64).map { "\($0)\n" }))
    }
}
