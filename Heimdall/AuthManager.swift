import Foundation
import LocalAuthentication

enum AuthResult {
    case success
    case cancelled
    case failure(String)
}

/// Thin wrapper around LocalAuthentication. Deliberately does not implement
/// any custom password-checking path: `.deviceOwnerAuthentication` already
/// tries Touch ID first and falls back to the real macOS account password via
/// the system's own secure UI, which is the only correct way to validate the
/// Mac password from a third-party app.
final class AuthManager {
    // Held for the duration of the in-flight evaluation. evaluatePolicy is
    // asynchronous and returns immediately, so an LAContext with no external
    // strong reference can be deallocated by ARC before Touch ID / password
    // verification actually completes — silently killing the check and
    // leaving the completion handler never called. Keeping it as a property
    // (rather than a local `let`) is what keeps it alive until it's done.
    private var context: LAContext?

    func authenticate(reason: String, completion: @escaping (AuthResult) -> Void) {
        // Cancel and drop any previous in-flight evaluation so a fresh call
        // (e.g. the user tapping Unlock again) always starts clean, rather
        // than potentially being wedged behind a stuck earlier attempt.
        if let previous = context {
            HeimdallLog.auth.notice("authenticate: invalidating previous in-flight context")
            previous.invalidate()
        }

        let context = LAContext()
        self.context = context
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        HeimdallLog.auth.notice("canEvaluatePolicy(.deviceOwnerAuthentication) = \(canEvaluate, privacy: .public), error = \(String(describing: error), privacy: .public)")
        guard canEvaluate else {
            self.context = nil
            completion(.failure(error?.localizedDescription ?? "Authentication is not available on this Mac."))
            return
        }

        HeimdallLog.auth.notice("evaluatePolicy: starting")
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, evalError in
            HeimdallLog.auth.notice("evaluatePolicy: reply received on background thread, success = \(success, privacy: .public), error = \(String(describing: evalError), privacy: .public)")
            DispatchQueue.main.async {
                guard self?.context === context else {
                    HeimdallLog.auth.notice("evaluatePolicy: reply from a superseded context, ignoring")
                    return
                }
                self?.context = nil
                if success {
                    completion(.success)
                    return
                }
                if let laError = evalError as? LAError {
                    switch laError.code {
                    case .userCancel, .appCancel, .systemCancel:
                        completion(.cancelled)
                    default:
                        completion(.failure(laError.localizedDescription))
                    }
                } else {
                    completion(.failure(evalError?.localizedDescription ?? "Authentication failed."))
                }
            }
        }
    }
}
