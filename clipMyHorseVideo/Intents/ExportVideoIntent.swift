import AppIntents

struct ExportVideoIntent: AppIntent {
    static var title: LocalizedStringResource = "Export My Round"
    static var description: IntentDescription = "Opens clipMyHorseVideo to export your assembled showjumping round."
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NavigationState.shared.pendingDestination = .timeline
        Log.intents.info("ExportVideoIntent performed")
        return .result()
    }
}
