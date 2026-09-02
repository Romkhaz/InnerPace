import Foundation

/// Дистанция в километрах с двумя знаками, разделитель по локали.
func formatDistance(_ meters: Double) -> String {
    let km = meters / 1000
    return km.formatted(.number.precision(.fractionLength(2))) + " км"
}

/// Темп «мин:сек» на километр. Слишком медленный или неизвестный темп показываем прочерком.
func formatPace(_ secondsPerKm: Double?) -> String {
    guard let secondsPerKm, secondsPerKm.isFinite, secondsPerKm > 0, secondsPerKm < 30 * 60 else { return "—" }
    let total = Int(secondsPerKm.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}
