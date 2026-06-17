import AppKit
import EventKit
import SwiftUI

struct CalendarRGB: Hashable {
    var red: Double
    var green: Double
    var blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    static let fallback = CalendarRGB(red: 0.35, green: 0.48, blue: 0.82)

    static func from(_ calendar: EKCalendar) -> CalendarRGB {
        if let cg = calendar.cgColor, let ns = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) {
            return CalendarRGB(
                red: Double(ns.redComponent),
                green: Double(ns.greenComponent),
                blue: Double(ns.blueComponent)
            )
        }
        return fallback
    }
}
