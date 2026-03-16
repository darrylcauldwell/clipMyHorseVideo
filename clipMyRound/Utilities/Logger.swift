import os

enum Log {
    static let general = Logger(subsystem: "dev.dreamfold.clipMyRound", category: "general")
    static let composition = Logger(subsystem: "dev.dreamfold.clipMyRound", category: "composition")
    static let export = Logger(subsystem: "dev.dreamfold.clipMyRound", category: "export")
    static let photos = Logger(subsystem: "dev.dreamfold.clipMyRound", category: "photos")
}
