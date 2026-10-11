//
//  OfflineTimeout.swift
//  CampusSync
//
//  Firestore's async writes (`commit`, `setData`, `delete`) finish only when the server answers,
//  and they cannot be cancelled, so offline they never return and a screen would spin forever.
//  `withTimeout` races the operation against a timer and returns whichever finishes first
//  WITHOUT waiting for the other (a task group would wait for the stuck write). The write itself
//  stays queued in Firestore and goes through when the connection returns.
//

import Foundation

func withTimeout<T>(
    seconds: Double = 8,
    onTimeout: @escaping () -> Error,
    _ operation: @escaping () async throws -> T
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let gate = ResumeOnce()
        Task {
            do {
                let value = try await operation()
                if gate.claim() { continuation.resume(returning: value) }
            } catch {
                if gate.claim() { continuation.resume(throwing: error) }
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if gate.claim() { continuation.resume(throwing: onTimeout()) }
        }
    }
}

/// Lets exactly one of the two racing tasks resume the continuation. Both run on the main actor.
private final class ResumeOnce {
    private var claimed = false
    func claim() -> Bool {
        if claimed { return false }
        claimed = true
        return true
    }
}
