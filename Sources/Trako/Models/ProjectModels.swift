import AppKit
import Foundation
import SwiftUI

struct Project: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var colorHex: String

    init(id: String = UUID().uuidString, name: String, colorHex: String = Project.defaultColors.randomElement() ?? "18BCA5") {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }

    var color: Color {
        Color(hex: colorHex) ?? TrakoBrand.teal
    }

    static let defaultColors = [
        "18BCA5", "287EE0", "85FFDE", "F59E0B", "A855F7", "EF4444", "EC4899", "6366F1"
    ]
}

enum ChartFocus: Equatable {
    /// Bars: stacked breakdown by project. Minutes: not shown in menu.
    case allTime
    /// All accumulated active Mac time (single color on Minutes).
    case total
    case project(String)

    var showsAllTotals: Bool {
        switch self {
        case .allTime, .total:
            return true
        case .project:
            return false
        }
    }
}

extension Color {
    init?(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if sanitized.hasPrefix("#") {
            sanitized.removeFirst()
        }
        guard sanitized.count == 6, let value = UInt64(sanitized, radix: 16) else {
            return nil
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String {
        guard let components = NSColor(self).usingColorSpace(.sRGB)?.cgColor.components, components.count >= 3 else {
            return "18BCA5"
        }
        let red = Int(components[0] * 255)
        let green = Int(components[1] * 255)
        let blue = Int(components[2] * 255)
        return String(format: "%02X%02X%02X", red, green, blue)
    }
}
