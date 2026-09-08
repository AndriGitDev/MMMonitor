import AppKit
import Foundation
import IOKit.pwr_mgt

enum AwakeMode: Int, CaseIterable, Identifiable, Sendable {
    case macOnly
    case macAndDisplay

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .macOnly: "Mac Only"
        case .macAndDisplay: "Mac + Display"
        }
    }

    var detail: String {
        switch self {
        case .macOnly: "Keeps the Mac awake while allowing the display to sleep."
        case .macAndDisplay: "Keeps both the Mac and its display awake."
        }
    }
}

enum SessionDuration: Equatable, Hashable, Sendable {
    case timed(TimeInterval)
    case indefinitely

    static let menuOptions: [SessionDuration] = [
        .timed(30 * 60),
        .timed(60 * 60),
        .timed(2 * 60 * 60),
        .timed(4 * 60 * 60),
        .timed(8 * 60 * 60),
        .indefinitely
    ]

    var menuTitle: String {
        switch self {
        case .timed(30 * 60): "30 Minutes"
        case .timed(60 * 60): "1 Hour"
        case .timed(2 * 60 * 60): "2 Hours"
        case .timed(4 * 60 * 60): "4 Hours"
        case .timed(8 * 60 * 60): "8 Hours"
        case .timed(let seconds): Self.format(seconds: seconds)
        case .indefinitely: "Indefinitely"
        }
    }

    static func format(seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(ceil(seconds / 60)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}

enum PowerAssertionError: LocalizedError {
    case couldNotCreateAssertion(IOReturn)

    var errorDescription: String? {
        switch self {
        case .couldNotCreateAssertion(let result):
            "macOS declined the wake request (IOKit error \(result))."
        }
    }
}

@MainActor
protocol PowerAssertionControlling: AnyObject {
    var isActive: Bool { get }
    func start(mode: AwakeMode) throws
    func stop()
}

@MainActor
private final class PowerAssertionController: PowerAssertionControlling {
    private var assertionIDs: [IOPMAssertionID] = []

    var isActive: Bool { !assertionIDs.isEmpty }

    func start(mode: AwakeMode) throws {
        stop()

        do {
            try addAssertion(type: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString)
            if mode == .macAndDisplay {
                try addAssertion(type: kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString)
            }
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        for id in assertionIDs {
            IOPMAssertionRelease(id)
        }
        assertionIDs.removeAll()
    }

    private func addAssertion(type: CFString) throws {
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "MMMonitor Keep Awake session" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            throw PowerAssertionError.couldNotCreateAssertion(result)
        }
        assertionIDs.append(id)
    }

    deinit {
        for id in assertionIDs {
            IOPMAssertionRelease(id)
        }
    }
}

@MainActor
final class AwakeSessionController: NSObject, ObservableObject {
    @Published private(set) var mode: AwakeMode
    @Published private(set) var isActive = false
    @Published private(set) var remainingText = "Not Active"
    @Published var errorMessage: String?

    private enum Keys {
        static let mode = "keepAwakeMode"
    }

    private let assertions: any PowerAssertionControlling
    private let defaults: UserDefaults
    private var endDate: Date?
    private var timer: Timer?

    init(
        defaults: UserDefaults = .standard,
        assertions: (any PowerAssertionControlling)? = nil
    ) {
        self.defaults = defaults
        self.assertions = assertions ?? PowerAssertionController()
        mode = AwakeMode(rawValue: defaults.integer(forKey: Keys.mode)) ?? .macOnly
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    func start(duration: SessionDuration) {
        do {
            try assertions.start(mode: mode)
            switch duration {
            case .timed(let seconds):
                endDate = Date().addingTimeInterval(seconds)
            case .indefinitely:
                endDate = nil
            }
            isActive = true
            startTimerIfNeeded()
            refreshState()
        } catch {
            stop()
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        assertions.stop()
        isActive = false
        remainingText = "Not Active"
    }

    func selectMode(_ newMode: AwakeMode) {
        guard newMode != mode else { return }
        mode = newMode
        defaults.set(newMode.rawValue, forKey: Keys.mode)

        guard assertions.isActive else { return }
        do {
            try assertions.start(mode: newMode)
            refreshState()
        } catch {
            stop()
            errorMessage = error.localizedDescription
        }
    }

    private func startTimerIfNeeded() {
        timer?.invalidate()
        timer = nil
        guard endDate != nil else { return }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        if let endDate, endDate <= Date() {
            stop()
        } else {
            refreshState()
        }
    }

    private func refreshState() {
        isActive = assertions.isActive
        guard isActive else {
            remainingText = "Not Active"
            return
        }
        remainingText = endDate.map {
            SessionDuration.format(seconds: $0.timeIntervalSinceNow)
        } ?? "Indefinite"
    }

    @objc private func applicationWillTerminate(_ notification: Notification) {
        stop()
    }

}
