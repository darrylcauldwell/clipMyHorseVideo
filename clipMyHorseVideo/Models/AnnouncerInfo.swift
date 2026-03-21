import SwiftUI

@Observable
@MainActor
final class AnnouncerInfo: Identifiable {
    let id = UUID()
    var riderName: String = ""
    var horseName: String = ""
    var className: String = ""
    var rawTranscript: String = ""
    var isTranscribing: Bool = false

    var hasContent: Bool {
        !riderName.isEmpty || !horseName.isEmpty || !className.isEmpty
    }

    var displayLabel: String {
        var parts: [String] = []
        if !riderName.isEmpty { parts.append(riderName) }
        if !horseName.isEmpty { parts.append("on \(horseName)") }
        return parts.isEmpty ? className : parts.joined(separator: " ")
    }
}
