import Foundation

@MainActor
final class DoctorViewModel: ObservableObject {
    @Published var report: DoctorReport?
    @Published var isRunning = false
    @Published var actionInProgress: String?
    @Published var actionError: String?

    #if DEBUG
    @Published var mockScenario: MockDoctorScenario?
    #endif

    private let doctorRunner = DoctorRunner()
    private let processManager = BridgeProcessManager()

    init() {
        #if DEBUG
        // Pick up mock scenario from launch arguments (set by AppDelegate)
        if let raw = UserDefaults.standard.string(forKey: "mockDoctorScenario"),
           let scenario = MockDoctorScenario(rawValue: raw) {
            mockScenario = scenario
            // Clear so subsequent launches aren't affected
            UserDefaults.standard.removeObject(forKey: "mockDoctorScenario")
        }
        #endif
    }

    var requiredChecks: [CheckResult] {
        report?.results.filter { $0.category == "required" } ?? []
    }

    var optionalChecks: [CheckResult] {
        report?.results.filter { $0.category == "optional" } ?? []
    }

    /// Whether all checks pass (used for onboarding completion detection).
    var allPassed: Bool {
        report?.allRequiredPassed ?? false
    }

    func runDoctor() {
        guard !isRunning else { return }
        isRunning = true
        actionError = nil

        Task {
            #if DEBUG
            if let mockScenario {
                report = mockScenario.buildReport()
                isRunning = false
                return
            }
            #endif
            do {
                report = try await doctorRunner.runDoctor()
            } catch {
                actionError = error.localizedDescription
            }
            isRunning = false
        }
    }

    #if DEBUG
    func setMockScenario(_ scenario: MockDoctorScenario?) {
        mockScenario = scenario
        report = scenario?.buildReport()
    }
    #endif

    func setupBridge(port: Int? = nil, apiKey: String? = nil) {
        performAction(String(localized: "Setting up Bridge…")) {
            try await self.processManager.setupService(port: port, apiKey: apiKey)
        }
    }

    func uninstallBridge() {
        performAction(String(localized: "Uninstalling Bridge…")) {
            try await self.processManager.uninstallService()
        }
    }

    func installNode() {
        performAction(String(localized: "Installing Node.js…")) {
            try await self.processManager.installNodeViaHomebrew()
        }
    }

    func installClaudeCode() {
        performAction(String(localized: "Installing Claude Code…")) {
            try await self.processManager.installClaudeCode()
        }
    }

    func installCodex() {
        performAction(String(localized: "Installing Codex…")) {
            try await self.processManager.installCodex()
        }
    }

    func updateBridge() {
        performAction(String(localized: "Updating Bridge…")) {
            try await self.processManager.installOrUpdateBridge()
        }
    }

    func loginProvider(_ providerName: String) {
        performAction(String(localized: "Opening browser for login…")) {
            try await self.processManager.loginProvider(providerName)
        }
    }

    private func performAction(_ label: String, action: @escaping () async throws -> Void) {
        actionInProgress = label
        actionError = nil

        Task {
            do {
                try await action()
                // Re-run doctor after action
                try? await Task.sleep(for: .seconds(1))
                runDoctor()
            } catch {
                actionError = error.localizedDescription
            }
            actionInProgress = nil
        }
    }
}
