import Foundation

/// A stretch of active Mac time with the project tags that applied for that period.
struct TimeSegment: Codable, Identifiable, Hashable {
    var id: String
    var start: Date
    var end: Date
    /// Empty = General (untagged). Multiple IDs = same period tagged to several projects.
    var projectIDs: [String]

    init(id: String = UUID().uuidString, start: Date, end: Date, projectIDs: Set<String> = []) {
        self.id = id
        self.start = start
        self.end = end
        self.projectIDs = projectIDs.sorted()
    }

    var duration: TimeInterval {
        max(end.timeIntervalSince(start), 0)
    }

    var isUntagged: Bool {
        projectIDs.isEmpty
    }

    func matches(focus: ChartFocus) -> Bool {
        switch focus {
        case .allTime:
            return true
        case .total:
            return true
        case .project(let id):
            return projectIDs.contains(id)
        }
    }

    func contains(projectID: String) -> Bool {
        projectIDs.contains(projectID)
    }
}

struct OpenTimeSegment: Codable, Equatable {
    var dayKey: String
    var start: Date
    var projectIDs: [String]

    init(dayKey: String, start: Date, projectIDs: Set<String>) {
        self.dayKey = dayKey
        self.start = start
        self.projectIDs = projectIDs.sorted()
    }

    var projectIDSet: Set<String> {
        Set(projectIDs)
    }

    func closed(at end: Date) -> TimeSegment {
        TimeSegment(id: UUID().uuidString, start: start, end: end, projectIDs: projectIDSet)
    }
}

enum TimeSegmentMath {
    /// Merges overlapping intervals and returns total covered seconds (each moment counted once).
    static func unionDuration(of segments: [TimeSegment]) -> TimeInterval {
        unionDuration(of: segments.map { $0.start ..< $0.end })
    }

    static func unionDuration(of ranges: [Range<Date>]) -> TimeInterval {
        guard !ranges.isEmpty else {
            return 0
        }

        let sorted = ranges
            .filter { $0.lowerBound < $0.upperBound }
            .sorted { $0.lowerBound < $1.lowerBound }

        guard var currentStart = sorted.first?.lowerBound,
              var currentEnd = sorted.first?.upperBound else {
            return 0
        }

        var total: TimeInterval = 0

        for range in sorted.dropFirst() {
            if range.lowerBound <= currentEnd {
                currentEnd = max(currentEnd, range.upperBound)
            } else {
                total += currentEnd.timeIntervalSince(currentStart)
                currentStart = range.lowerBound
                currentEnd = range.upperBound
            }
        }

        total += currentEnd.timeIntervalSince(currentStart)
        return total
    }

    /// Seconds in [rangeStart, rangeEnd) covered by the given segments (after union).
    static func unionDuration(
        of segments: [TimeSegment],
        within rangeStart: Date,
        rangeEnd: Date
    ) -> TimeInterval {
        let clipped = segments.compactMap { segment -> Range<Date>? in
            let start = max(segment.start, rangeStart)
            let end = min(segment.end, rangeEnd)
            guard start < end else {
                return nil
            }
            return start ..< end
        }
        return unionDuration(of: clipped)
    }
}
