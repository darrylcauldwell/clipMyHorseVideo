import AppIntents

struct StartEditingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Editing My Round"
    static let description: IntentDescription = "Opens ClearRound to the clip picker to start building your showjumping round."
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NavigationState.shared.pendingDestination = .picker
        Log.intents.info("StartEditingIntent performed")
        return .result()
    }
}
