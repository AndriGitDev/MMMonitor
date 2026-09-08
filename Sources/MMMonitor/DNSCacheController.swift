import Foundation

enum DNSCacheFlushResult: Equatable, Sendable {
    case succeeded
    case cancelled
    case failed(String)
}

struct DNSCacheFlusher: Sendable {
    // No user-provided value is ever interpolated into this privileged command.
    static let authorizationScript = """
    do shell script "/usr/bin/dscacheutil -flushcache && /usr/bin/killall -HUP mDNSResponder" with administrator privileges
    """

    func flush() async -> DNSCacheFlushResult {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let standardError = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", Self.authorizationScript]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = standardError

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return .failed("The macOS authorization tool could not be started.")
            }

            let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(decoding: errorData, as: UTF8.self)
            return Self.result(
                terminationStatus: process.terminationStatus,
                errorOutput: errorOutput
            )
        }.value
    }

    static func result(terminationStatus: Int32, errorOutput: String) -> DNSCacheFlushResult {
        guard terminationStatus != 0 else { return .succeeded }

        let normalizedError = errorOutput.lowercased()
        if normalizedError.contains("user canceled") || normalizedError.contains("(-128)") {
            return .cancelled
        }

        let detail = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty {
            return .failed("macOS could not flush the DNS cache.")
        }
        return .failed("macOS could not flush the DNS cache. \(detail)")
    }
}

@MainActor
final class DNSCacheController: ObservableObject {
    enum Status: Equatable {
        case idle
        case flushing
        case succeeded
    }

    @Published private(set) var status: Status = .idle
    @Published var errorMessage: String?

    private let flusher: DNSCacheFlusher
    private var statusResetTask: Task<Void, Never>?

    init(flusher: DNSCacheFlusher = DNSCacheFlusher()) {
        self.flusher = flusher
    }

    deinit {
        statusResetTask?.cancel()
    }

    func flush() {
        guard status != .flushing else { return }

        statusResetTask?.cancel()
        status = .flushing
        errorMessage = nil

        Task {
            switch await flusher.flush() {
            case .succeeded:
                status = .succeeded
                scheduleStatusReset()
            case .cancelled:
                status = .idle
            case .failed(let message):
                status = .idle
                errorMessage = message
            }
        }
    }

    private func scheduleStatusReset() {
        statusResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.status = .idle
        }
    }
}
