import CoreMedia

extension CMTime {
    var formattedDuration: String {
        guard isValid, !isIndefinite else { return "--:--" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
