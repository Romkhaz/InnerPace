import Charts
import SwiftUI

/// История: сохранённые тренировки, график текущей пробежки и журнал решений.
struct HistoryView: View {
    @Environment(RunSession.self) private var session
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        List {
            Section("Тренировки") {
                if session.store.workouts.isEmpty {
                    Text("Пока пусто").foregroundStyle(.secondary)
                }
                ForEach(session.store.workouts) { workout in
                    NavigationLink {
                        ReportView(summary: workout)
                    } label: {
                        workoutRow(workout)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { session.store.remove(session.store.workouts[index]) }
                }
            }
            if !session.telemetryFiles.isEmpty {
                Section("Телеметрия") {
                    ForEach(session.telemetryFiles, id: \.self) { url in
                        HStack {
                            Text(url.lastPathComponent)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Spacer()
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { session.deleteTelemetryFile(session.telemetryFiles[index]) }
                    }
                }
            }
            Section("График последней пробежки") {
                if session.samples.count < 2 {
                    Text("Нет данных за пробежку")
                        .foregroundStyle(.secondary)
                } else {
                    chart
                        .frame(height: 260)
                        .padding(.vertical, 8)
                }
            }
            Section("Журнал") {
                if session.events.isEmpty {
                    Text("Пока пусто").foregroundStyle(.secondary)
                }
                ForEach(session.events) { event in
                    HStack(alignment: .firstTextBaseline) {
                        Text(event.time, style: .time)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(event.text)
                    }
                }
            }
        }
        .navigationTitle("История")
        .onAppear { session.refreshTelemetryFiles() }
    }

    private func workoutRow(_ workout: WorkoutSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(workout.date, format: .dateTime.day().month().hour().minute())
                    .font(.headline)
                Spacer()
                Image(systemName: workout.source == .watch ? "applewatch" : "iphone")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Text(formatDistance(workout.distanceMeters))
                Text(formatElapsed(workout.duration))
                Text("\(formatPace(workout.averagePaceSecondsPerKm)) /км")
                if let hr = workout.averageHeartRate {
                    Text("♥ \(Int(hr.rounded()))")
                }
                Text("\(formatEfficiency(workout.efficiencyMetersPerBeat)) м/удар")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    // Пара цветов проверена на различимость при дальтонизме и контраст к фону
    // отдельно для светлой и тёмной темы.
    private var heartRateColor: Color { ZoneStyle.deepCoral }

    private var cadenceColor: Color { Color(red: 0.93, green: 0.49, blue: 0.10) }

    private var chart: some View {
        let samples = session.samples
        let start = samples.first?.time ?? Date()
        let settings = session.settings
        let heartRateName = String(localized: "Пульс")
        let cadenceName = String(localized: "Ритм")
        let minutes: (Date) -> Double = { $0.timeIntervalSince(start) / 60 }

        let heartRates = samples.compactMap(\.smoothedHeartRate)
        let low = min(Double(settings.heartRateMin) - 15, heartRates.min() ?? .infinity, Double(settings.cadenceMin) - 5)
        let high = max(Double(settings.heartRateMax) + 15, heartRates.max() ?? -.infinity, Double(settings.cadenceMax) + 5)

        return Chart {
            RectangleMark(
                yStart: .value("Целевая зона", Double(settings.heartRateMin)),
                yEnd: .value("Целевая зона", Double(settings.heartRateMax))
            )
            .foregroundStyle(ZoneStyle.peach.opacity(0.35))

            ForEach(samples) { sample in
                if let hr = sample.smoothedHeartRate {
                    LineMark(
                        x: .value("Время, мин", minutes(sample.time)),
                        y: .value("в минуту", hr),
                        series: .value("Ряд", heartRateName)
                    )
                    .foregroundStyle(by: .value("Ряд", heartRateName))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                LineMark(
                    x: .value("Время, мин", minutes(sample.time)),
                    y: .value("в минуту", Double(sample.cadence)),
                    series: .value("Ряд", cadenceName)
                )
                .foregroundStyle(by: .value("Ряд", cadenceName))
                .interpolationMethod(.stepEnd)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartForegroundStyleScale([heartRateName: heartRateColor, cadenceName: cadenceColor])
        .chartYScale(domain: low...high)
        .chartXAxisLabel("Время, мин")
        .chartYAxisLabel("в минуту")
        .chartLegend(position: .top, alignment: .leading)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        let total = Int((minutes * 60).rounded())
                        Text(verbatim: String(format: "%d:%02d", total / 60, total % 60))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                AxisValueLabel()
            }
        }
    }
}
