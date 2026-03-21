enum CropMode: String, CaseIterable, Identifiable {
    case centre = "Centre Crop"
    case smart = "Smart Crop"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .centre: "Static centre crop"
        case .smart: "Follows the horse and rider"
        }
    }

    var iconName: String {
        switch self {
        case .centre: "crop"
        case .smart: "viewfinder"
        }
    }
}
