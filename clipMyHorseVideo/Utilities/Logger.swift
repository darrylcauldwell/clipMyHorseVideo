import os

enum Log {
    static let general = Logger(subsystem: "dev.dreamfold.ClearRound", category: "general")
    static let composition = Logger(subsystem: "dev.dreamfold.ClearRound", category: "composition")
    static let export = Logger(subsystem: "dev.dreamfold.ClearRound", category: "export")
    static let photos = Logger(subsystem: "dev.dreamfold.ClearRound", category: "photos")
    static let classification = Logger(subsystem: "dev.dreamfold.ClearRound", category: "classification")
    static let transcription = Logger(subsystem: "dev.dreamfold.ClearRound", category: "transcription")
    static let intents = Logger(subsystem: "dev.dreamfold.ClearRound", category: "intents")
    static let quality = Logger(subsystem: "dev.dreamfold.ClearRound", category: "quality")
    static let labelling = Logger(subsystem: "dev.dreamfold.ClearRound", category: "labelling")
}
