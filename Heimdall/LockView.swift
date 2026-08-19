import SwiftUI

struct LockView: View {
    @ObservedObject var lockController: LockController

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .foregroundStyle(.white)

                Text("Heimdall")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)

                Text("This Mac is locked")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.65))

                if let error = lockController.lastErrorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }

                Button(action: {
                    HeimdallLog.lock.notice("Unlock button tapped")
                    lockController.unlock()
                }) {
                    Label(
                        lockController.isAuthenticating ? "Authenticating… (tap to retry)" : "Unlock",
                        systemImage: "touchid"
                    )
                    .frame(width: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(40)
        }
    }
}
