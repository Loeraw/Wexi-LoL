import AppKit
import Foundation
import RiftCore

@MainActor final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case current
        case available(String)
        case failed
    }

    @Published private(set) var state: State = .idle
    private(set) var releaseURL: URL?
    private var task: Task<Void, Never>?
    private var lastCheckStartedAt = Date.distantPast

    deinit { task?.cancel() }

    func check(currentVersion: String) {
        task?.cancel()
        lastCheckStartedAt = Date()
        state = .checking
        task = Task { [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/Loeraw/Wexi-LoL/releases/latest")!)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("WexiLoL/\(currentVersion)", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 8
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled,
                      let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let release = try JSONDecoder().decode(LatestRelease.self, from: data)
                releaseURL = URL(string: release.htmlURL)
                let version = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                state = SemanticVersion.isNewer(version, than: currentVersion) ? .available(version) : .current
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed
            }
        }
    }

    func checkIfNeeded(currentVersion: String, minimumInterval: TimeInterval) {
        guard state != .checking,
              Date().timeIntervalSince(lastCheckStartedAt) >= minimumInterval else { return }
        check(currentVersion: currentVersion)
    }

    func openRelease() {
        guard let releaseURL else { return }
        NSWorkspace.shared.open(releaseURL)
    }

    private struct LatestRelease: Decodable {
        let tagName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}
