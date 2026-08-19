import Foundation

struct HeimdallState: Codable {
    var isLocked: Bool
    var lockedAt: Date?
}

final class StateStore {
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Heimdall", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("state.json")
    }

    func load() -> HeimdallState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(HeimdallState.self, from: data) else {
            return HeimdallState(isLocked: false, lockedAt: nil)
        }
        return state
    }

    func save(_ state: HeimdallState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
