import os

enum Log {
    static let general = Logger(subsystem: "dev.dreamfold.clipMyHorseVideo", category: "general")
    static let composition = Logger(subsystem: "dev.dreamfold.clipMyHorseVideo", category: "composition")
    static let export = Logger(subsystem: "dev.dreamfold.clipMyHorseVideo", category: "export")
    static let photos = Logger(subsystem: "dev.dreamfold.clipMyHorseVideo", category: "photos")
    static let classification = Logger(subsystem: "dev.dreamfold.clipMyHorseVideo", category: "classification")
    static let transcription = Logger(subsystem: "dev.dreamfold.clipMyHorseVideo", category: "transcription")
    static let intents = Logger(subsystem: "dev.dreamfold.clipMyHorseVideo", category: "intents")
    static let quality = Logger(subsystem: "dev.dreamfold.clipMyHorseVideo", category: "quality")
}
