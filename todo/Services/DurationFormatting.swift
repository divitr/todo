import Foundation

enum DurationFormatting {
    static let minDays: Double = 15.0 / (60 * 24)
    static let modelMinDays: Double = 15.0 / (60 * 24)

    static let presetDays: [Double] = [
        15.0 / (60 * 24),
        30.0 / (60 * 24),
        1.0 / 24,
        2.0 / 24,
        4.0 / 24,
        0.25,
        0.5,
        1, 2, 3, 5, 7, 14, 30,
    ]

    static func clamp(_ days: Double) -> Double {
        max(days, modelMinDays)
    }

    static func label(for days: Double) -> String {
        let minutes = Int((days * 24 * 60).rounded())
        if minutes < 60 {
            return "\(max(minutes, 15))m"
        }
        let hours = days * 24
        if hours < 24 {
            if abs(hours - hours.rounded()) < 0.05 {
                return "\(Int(hours.rounded()))h"
            }
            return String(format: "%.1fh", hours)
        }
        if abs(days - days.rounded()) < 0.05 {
            return "\(Int(days.rounded()))d"
        }
        return String(format: "%.1fd", days)
    }

    static func decrement(_ days: inout Double) {
        let clamped = clamp(days)
        if let idx = presetDays.firstIndex(where: { abs($0 - clamped) < 0.001 }) {
            if idx > 0 {
                days = presetDays[idx - 1]
                return
            }
            days = modelMinDays
            return
        }
        if let prev = presetDays.last(where: { $0 < clamped - 0.001 }) {
            days = prev
        } else {
            days = modelMinDays
        }
    }

    static func increment(_ days: inout Double) {
        let clamped = clamp(days)
        if let idx = presetDays.firstIndex(where: { abs($0 - clamped) < 0.001 }) {
            if idx + 1 < presetDays.count {
                days = presetDays[idx + 1]
                return
            }
            days = min(60, clamped + 1)
            return
        }
        if let next = presetDays.first(where: { $0 > clamped + 0.001 }) {
            days = next
        } else {
            days = min(60, clamped + 1)
        }
    }

    static func parseCustom(value: String, unit: DurationInputUnit) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let number = Double(trimmed.replacingOccurrences(of: ",", with: ".")) else {
            return nil
        }
        guard number > 0 else { return nil }
        switch unit {
        case .minutes:
            return clamp(number / (60 * 24))
        case .hours:
            return clamp(number / 24)
        case .days:
            return clamp(number)
        }
    }

    static func customDisplayValue(for days: Double, unit: DurationInputUnit) -> String {
        switch unit {
        case .minutes:
            return String(Int((days * 24 * 60).rounded()))
        case .hours:
            let h = days * 24
            return abs(h - h.rounded()) < 0.05 ? String(Int(h.rounded())) : String(format: "%.1f", h)
        case .days:
            return abs(days - days.rounded()) < 0.05 ? String(Int(days.rounded())) : String(format: "%.2f", days)
        }
    }
}

enum DurationInputUnit: String, CaseIterable, Identifiable {
    case minutes = "min"
    case hours = "hr"
    case days = "days"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minutes: "Minutes"
        case .hours: "Hours"
        case .days: "Days"
        }
    }
}
