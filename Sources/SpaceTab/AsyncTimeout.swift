import Foundation

/// Runs `work` and returns its result, or nil once `timeout` has passed.
/// The work keeps running; a result that arrives late goes to `late`, so
/// nothing is thrown away. For calls that can't be cancelled, such as
/// ScreenCaptureKit's.
func withTimeout<T: Sendable>(
    _ timeout: TimeInterval,
    late: @escaping @Sendable (T) -> Void = { _ in },
    work: @escaping @Sendable () async -> T?
) async -> T? {
    await withCheckedContinuation { continuation in
        let once = ResumeOnce(continuation)
        Task.detached {
            let result = await work()
            if !once.resume(result), let result {
                late(result)
            }
        }
        Task.detached {
            try? await Task.sleep(for: .seconds(timeout))
            _ = once.resume(nil)
        }
    }
}

/// Resumes a continuation at most once.
private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }

    /// Returns false when the continuation was already resumed.
    func resume(_ value: T?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation else { return false }
        self.continuation = nil
        continuation.resume(returning: value)
        return true
    }
}
