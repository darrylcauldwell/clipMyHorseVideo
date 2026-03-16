import os

enum Log {
    static let general = Logger(subsystem: "dev.dreamfold.clipMyHorseVideo", category: "general")
    static let composition = Logger(subsystem: "dev.dreamfold.clipMyHorseVideo", category: "composition")
    static let export = Logger(subsystem: "dev.dreamfold.clipMyHorseVideo", category: "export")
    static let photos = Logger(subsystem: "dev.dreamfold.clipMyHorseVideo", category: "photos")
}
