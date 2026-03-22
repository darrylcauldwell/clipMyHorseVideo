import AppIntents

struct ExportVideoIntent: AppIntent {
    static let title: LocalizedStringResource = "Export My Round"
    static let description: IntentDescription = "Opens ClearRound to export your assembled showjumping round."
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NavigationState.shared.pendingDestination = .timeline
        Log.intents.info("ExportVideoIntent performed")
        return .result()
    }
}
