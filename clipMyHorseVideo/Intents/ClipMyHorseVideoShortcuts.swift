import AppIntents

struct ClearRoundShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartEditingIntent(),
            phrases: [
                "Start editing in \(.applicationName)",
                "Build my round in \(.applicationName)",
                "Edit my showjumping video in \(.applicationName)"
            ],
            shortTitle: "Start Editing",
            systemImageName: "figure.equestrian.sports"
        )
        AppShortcut(
            intent: ExportVideoIntent(),
            phrases: [
                "Export my round in \(.applicationName)",
                "Share my video from \(.applicationName)"
            ],
            shortTitle: "Export Video",
            systemImageName: "square.and.arrow.up"
        )
    }
}
