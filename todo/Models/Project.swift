import AppKit
import Foundation
import SwiftData
import SwiftUI

@Model
final class Project {
    var name: String
    var createdAt: Date
    var sortOrder: Int
    var colorHue: Double
    var isInbox: Bool
    var isAllAggregate: Bool
    var colorRed: Double
    var colorGreen: Double
    var colorBlue: Double
    var usesCustomColor: Bool

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.project)
    var tasks: [TaskItem] = []

    init(
        name: String,
        sortOrder: Int = 0,
        colorHue: Double = 0.55,
        isInbox: Bool = false,
        isAllAggregate: Bool = false,
        colorRed: Double = 0.35,
        colorGreen: Double = 0.35,
        colorBlue: Double = 0.35,
        usesCustomColor: Bool = false
    ) {
        self.name = name
        self.createdAt = .now
        self.sortOrder = sortOrder
        self.colorHue = colorHue
        self.isInbox = isInbox
        self.isAllAggregate = isAllAggregate
        self.colorRed = colorRed
        self.colorGreen = colorGreen
        self.colorBlue = colorBlue
        self.usesCustomColor = usesCustomColor
    }

    var hashTag: String {
        if isAllAggregate { return "#all" }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") { return trimmed }
        return "#\(trimmed)"
    }

    var listTitle: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var isUserCategory: Bool { !isInbox && !isAllAggregate }
    var isSystemCategory: Bool { isInbox || isAllAggregate }

    var accentColor: Color {
        if usesCustomColor {
            return Color(red: colorRed, green: colorGreen, blue: colorBlue)
        }
        let level = 0.38 + (colorHue * 0.1).truncatingRemainder(dividingBy: 0.18)
        return Color(white: level)
    }

    var ganttBarColor: Color {
        if isAllAggregate { return Color.primary.opacity(0.75) }
        return categoryColor
    }

    var accentTint: Color {
        categoryColor
    }

    var categoryColor: Color {
        if isAllAggregate { return .primary }
        if usesCustomColor {
            return Color(red: colorRed, green: colorGreen, blue: colorBlue)
        }
        return Self.defaultPaletteColor(at: max(sortOrder, 0))
    }

    var openTaskCount: Int {
        tasks.filter { !$0.isComplete }.count
    }

    func openTaskCount(allTasks: [TaskItem]) -> Int {
        if isAllAggregate {
            return allTasks.filter { !$0.isComplete }.count
        }
        return openTaskCount
    }

    var displayName: String {
        if isAllAggregate { return "#all" }
        if isInbox { return "All" }
        return hashTag
    }

    func configureAsAllAggregate() {
        name = "all"
        isAllAggregate = true
        isInbox = false
        usesCustomColor = true
        colorRed = 0
        colorGreen = 0
        colorBlue = 0
    }

    func applyColor(_ color: Color) {
        let ns = NSColor(color)
        guard let rgb = ns.usingColorSpace(.sRGB) else { return }
        colorRed = Double(rgb.redComponent)
        colorGreen = Double(rgb.greenComponent)
        colorBlue = Double(rgb.blueComponent)
        usesCustomColor = true
    }
}

extension Project {
    static let defaultCategoryHues: [Double] = [0.2, 0.35, 0.5, 0.65, 0.8, 0.95]

    var displayTitle: String {
        Self.normalizedCategoryName(name)
    }

    static func normalizedCategoryName(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "^#+", with: "", options: .regularExpression)
    }

    static func defaultPaletteColor(at index: Int) -> Color {
        let hues = defaultCategoryHues
        let hue = hues[index % hues.count]
        return Color(hue: hue, saturation: 0.45, brightness: 0.42)
    }
}
