import Foundation

/// Sick mode turns Home into a dashboard for an ill child. This first part is the fever line: the
/// temperature a reading counts as a fever at, stored once in Celsius and shown in the phone's unit.
enum SickMode {
    // Settings ▸ Sick mode, in the App Group suite with the other settings.
    static let feverLineKey = "feverLineCelsius"

    /// The fever line is stored once, in Celsius, and shown in the phone's unit.
    static let defaultFeverLine = 38.0
    /// What Settings offers: 37.5 to 38.5 °C in tenths.
    static let feverLineChoices = (375...385).map { Double($0) / 10 }

    static var feverLineCelsius: Double {
        SharedDefaults.suite.object(forKey: feverLineKey) as? Double ?? defaultFeverLine
    }

    static func feverLine(in unit: TemperatureUnit) -> Double {
        unit.convert(feverLineCelsius, from: .celsius)
    }

    /// At or over the line. Compared in tenths, so 38.0 °C and 100.4 °F land on the same side.
    static func isFever(_ value: Double, line: Double) -> Bool {
        (value * 10).rounded() >= (line * 10).rounded()
    }
}
