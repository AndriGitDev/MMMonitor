import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

@MainActor
final class TestAssertions: PowerAssertionControlling {
    private(set) var isActive = false
    private(set) var startedModes: [AwakeMode] = []

    func start(mode: AwakeMode) throws {
        startedModes.append(mode)
        isActive = true
    }

    func stop() {
        isActive = false
    }
}

@main
struct AwakeSessionVerification {
    @MainActor
    static func main() {
        require(SessionDuration.menuOptions.count == 6, "all six session durations should be available")
        require(SessionDuration.menuOptions.first?.menuTitle == "30 Minutes", "30-minute session should be first")
        require(SessionDuration.menuOptions.last == .indefinitely, "indefinite session should be last")
        require(SessionDuration.format(seconds: 3_601) == "1h 1m", "remaining time should round up to minutes")
        require(SessionDuration.format(seconds: 3_600) == "1h", "whole hours should omit zero minutes")
        require(SessionDuration.format(seconds: 1) == "1m", "sub-minute time should remain visible")
        require(SessionDuration.format(seconds: 0) == "0m", "expired time should clamp to zero")

        let domain = "local.mmmonitor.awake-verification.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain) ?? .standard
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }

        let assertions = TestAssertions()
        let controller = AwakeSessionController(defaults: defaults, assertions: assertions)
        require(controller.mode == .macOnly, "Mac-only mode should be the default")
        require(!controller.isActive, "a new controller should be inactive")

        controller.start(duration: .indefinitely)
        require(controller.isActive, "starting a session should activate the controller")
        require(controller.remainingText == "Indefinite", "indefinite state should be visible")
        require(assertions.startedModes == [.macOnly], "the selected mode should be asserted")

        controller.selectMode(.macAndDisplay)
        require(controller.mode == .macAndDisplay, "mode changes should be applied")
        require(assertions.startedModes == [.macOnly, .macAndDisplay], "active mode changes should restart assertions")
        require(defaults.integer(forKey: "keepAwakeMode") == AwakeMode.macAndDisplay.rawValue, "mode should persist")

        controller.stop()
        require(!controller.isActive, "stopping should deactivate the session")
        require(controller.remainingText == "Not Active", "stopped state should be visible")
        require(!assertions.isActive, "stopping should release assertions")

        print("Keep Awake duration and session-state checks passed")
    }
}
