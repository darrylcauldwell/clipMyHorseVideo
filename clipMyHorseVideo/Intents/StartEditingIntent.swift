import AppIntents

struct StartEditingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Editing My Round"
    static var description: IntentDescription = "Opens clipMyHorseVideo to the clip picker to start building your showjumping round."
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NavigationState.shared.pendingDestination = .picker
        Log.intents.info("StartEditingIntent performed")
        return .result()
    }
}
