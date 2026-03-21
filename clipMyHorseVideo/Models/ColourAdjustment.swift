struct ColourAdjustment: Equatable {
    var brightness: Double = 0      // -1.0 to 1.0
    var contrast: Double = 1.0      // 0.5 to 2.0
    var saturation: Double = 1.0    // 0.0 to 2.0

    static let `default` = ColourAdjustment()

    var isDefault: Bool {
        self == .default
    }
}
