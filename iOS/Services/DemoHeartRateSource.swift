#if DEBUG
import Foundation

/// Синтетический пульс для отладки в симуляторе: включается аргументом запуска
/// `-demoHeartRate`. Пульс тянется к значению, которое зависит от каденса,
/// с задержкой и небольшим шумом, чтобы регулятор было на чём проверять.
final class DemoHeartRateSource {
    var cadence: () -> Int = { 180 }
    var onHeartRate: ((Int, Date) -> Void)?

    private var timer: Timer?
    private var heartRate = 118.0
    private var phase = 0.0

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoHeartRate")
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        // Целевой пульс: 120 при 180 шагах, плюс 1,6 удара на каждый шаг каденса
        // и «горка» раз в четыре минуты, чтобы пульс уходил выше зоны.
        phase += 1
        // Ниже 130 регулятор ждёт; горка выводит пульс за цель при ритме на нижней границе.
        let hill = phase.truncatingRemainder(dividingBy: 240) > 150 ? 40.0 : 0.0
        let target = 126 + Double(cadence() - 180) * 1.6 + hill
        heartRate += (target - heartRate) * 0.06
        let noise = Double.random(in: -1.5...1.5)
        onHeartRate?(Int((heartRate + noise).rounded()), Date())
    }
}
#endif
