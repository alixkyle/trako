import Foundation

struct UsageDay: Codable, Identifiable, Hashable {
    var date: Date
    var activeSeconds: TimeInterval

    var id: String { DayKey.key(for: date) }
}

struct UsageArchive: Codable {
    var days: [String: TimeInterval]
    var hourly: [String: [String: TimeInterval]]
    var projects: [Project]
    var projectDays: [String: [String: TimeInterval]]
    var projectHourly: [String: [String: [String: TimeInterval]]]
    var untaggedDays: [String: TimeInterval]
    var untaggedHourly: [String: [String: TimeInterval]]
    var segmentsByDay: [String: [TimeSegment]]
    var openSegment: OpenTimeSegment?

    init(
        days: [String: TimeInterval] = [:],
        hourly: [String: [String: TimeInterval]] = [:],
        projects: [Project] = [],
        projectDays: [String: [String: TimeInterval]] = [:],
        projectHourly: [String: [String: [String: TimeInterval]]] = [:],
        untaggedDays: [String: TimeInterval] = [:],
        untaggedHourly: [String: [String: TimeInterval]] = [:],
        segmentsByDay: [String: [TimeSegment]] = [:],
        openSegment: OpenTimeSegment? = nil
    ) {
        self.days = days
        self.hourly = hourly
        self.projects = projects
        self.projectDays = projectDays
        self.projectHourly = projectHourly
        self.untaggedDays = untaggedDays
        self.untaggedHourly = untaggedHourly
        self.segmentsByDay = segmentsByDay
        self.openSegment = openSegment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.days = try container.decodeIfPresent([String: TimeInterval].self, forKey: .days) ?? [:]
        self.hourly = try container.decodeIfPresent([String: [String: TimeInterval]].self, forKey: .hourly) ?? [:]
        self.projects = try container.decodeIfPresent([Project].self, forKey: .projects) ?? []
        self.projectDays = try container.decodeIfPresent([String: [String: TimeInterval]].self, forKey: .projectDays) ?? [:]
        self.projectHourly = try container.decodeIfPresent([String: [String: [String: TimeInterval]]].self, forKey: .projectHourly) ?? [:]
        self.untaggedDays = try container.decodeIfPresent([String: TimeInterval].self, forKey: .untaggedDays) ?? [:]
        self.untaggedHourly = try container.decodeIfPresent([String: [String: TimeInterval]].self, forKey: .untaggedHourly) ?? [:]
        self.segmentsByDay = try container.decodeIfPresent([String: [TimeSegment]].self, forKey: .segmentsByDay) ?? [:]
        self.openSegment = try container.decodeIfPresent(OpenTimeSegment.self, forKey: .openSegment)
    }
}

struct ChartBarSlice: Identifiable, Hashable {
    var id: String
    var projectID: String?
    var activeSeconds: TimeInterval

    var isUntagged: Bool {
        projectID == nil
    }
}

struct UsageBar: Identifiable, Hashable {
    var id: String
    var label: String
    var accessibilityLabel: String
    var activeSeconds: TimeInterval
    var date: Date?
    var slices: [ChartBarSlice]

    init(
        id: String,
        label: String,
        accessibilityLabel: String,
        activeSeconds: TimeInterval,
        date: Date? = nil,
        slices: [ChartBarSlice] = []
    ) {
        self.id = id
        self.label = label
        self.accessibilityLabel = accessibilityLabel
        self.activeSeconds = activeSeconds
        self.date = date
        self.slices = slices
    }

    var hasVisibleActivity: Bool {
        activeSeconds >= 60
    }

    var hasColoredSlices: Bool {
        !slices.isEmpty
    }
}

enum ChartRange: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"

    var id: String { rawValue }
}

enum ChartDisplayMode: String, CaseIterable, Identifiable {
    case totals = "Bars"
    case hourSpan = "Minutes"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .totals: "chart.bar.fill"
        case .hourSpan: "rectangle.split.3x1.fill"
        }
    }
}

struct HourMinuteSlot: Identifiable, Hashable {
    var id: Int
    var isActive: Bool
    var projectID: String?
    /// Hover tooltip for a continuous stretch, e.g. "14:52 – 14:58".
    var rangeLabel: String?

    init(minute: Int, isActive: Bool, projectID: String? = nil, rangeLabel: String? = nil) {
        self.id = minute
        self.isActive = isActive
        self.projectID = projectID
        self.rangeLabel = rangeLabel
    }
}

struct HourSpanColumn: Identifiable, Hashable {
    var id: String
    var hour: Int
    var label: String
    var minutes: [HourMinuteSlot]
}

enum HourKey {
    static func key(for date: Date) -> String {
        let hour = Calendar.autoupdatingCurrent.component(.hour, from: date)
        return String(format: "%02d", hour)
    }
}

enum DayKey {
    static let calendar = Calendar.autoupdatingCurrent

    static func key(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func date(from key: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key) ?? Date()
    }
}

enum DateLabels {
    static func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    static func monthDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    static func month(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }

    static func fullDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }
}

enum TimeRangeFormat {
    static func clockRange(from start: Date, to end: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    static func clockRange(hour: Int, startMinute: Int, endMinuteInclusive: Int) -> String {
        let start = String(format: "%02d:%02d", hour, startMinute)
        let end = String(format: "%02d:%02d", hour, endMinuteInclusive)
        return "\(start) – \(end)"
    }
}

enum DurationFormat {
    static func compact(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(Int(seconds / 60), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            return "\(minutes)m"
        }

        return "\(hours)h \(minutes)m"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds), 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    static func spoken(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(Int(seconds / 60), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        switch (hours, minutes) {
        case (0, 0):
            return "Less than a minute"
        case (0, _):
            return "\(minutes) minutes"
        case (_, 0):
            return "\(hours) hours"
        default:
            return "\(hours) hours \(minutes) minutes"
        }
    }
}
