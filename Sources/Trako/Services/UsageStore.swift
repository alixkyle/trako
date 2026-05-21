import Foundation
import os

final class UsageStore {
    private let fileManager: FileManager
    private let fileURL: URL
    private let logger = Logger(subsystem: "com.alixkyle.trako", category: "UsageStore")

    /// Set when load merged data from another path and should be written to the canonical file.
    private(set) var needsConsolidationSave = false

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        let appURL = baseURL.appending(path: "Trako", directoryHint: .isDirectory)

        self.fileURL = appURL.appending(path: "usage-stats.json")
    }

    func load() -> UsageArchive {
        var merged = UsageArchive()
        var loadedCanonical = false

        for candidate in candidateURLs {
            guard fileManager.fileExists(atPath: candidate.path) else {
                continue
            }

            guard let archive = decodeArchive(at: candidate) else {
                logger.error("Could not decode usage stats at \(candidate.path, privacy: .public)")
                continue
            }

            if candidate == fileURL {
                loadedCanonical = true
            } else {
                needsConsolidationSave = true
                logger.info("Merged usage stats from \(candidate.path, privacy: .public)")
            }

            merged = merged.merging(archive)
        }

        if !loadedCanonical && !merged.days.isEmpty {
            needsConsolidationSave = true
        }

        return merged
    }

    @discardableResult
    func save(_ archive: UsageArchive) -> Bool {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            let data = try JSONEncoder.prettySorted.encode(archive)
            try data.write(to: fileURL, options: [.atomic])
            needsConsolidationSave = false
            return true
        } catch {
            logger.error("Could not save usage stats: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private var candidateURLs: [URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        let support = home.appending(path: "Library/Application Support", directoryHint: .isDirectory)

        var urls: [URL] = [fileURL]

        let legacyNames = ["Trako", "Focus"]
        for name in legacyNames {
            urls.append(support.appending(path: "\(name)/usage-stats.json"))
        }

        let containerBundleIDs = [
            "com.alixkyle.trako",
            "com.alixkyle.Trako",
            "local.trako.menubar"
        ]

        for bundleID in containerBundleIDs {
            urls.append(
                home
                    .appending(path: "Library/Containers/\(bundleID)/Data/Library/Application Support/Trako/usage-stats.json")
            )
            urls.append(
                home
                    .appending(path: "Library/Containers/\(bundleID)/Data/Library/Application Support/Focus/usage-stats.json")
            )
        }

        var seen = Set<String>()
        return urls.filter { url in
            guard seen.insert(url.path).inserted else {
                return false
            }
            return true
        }
    }

    private func decodeArchive(at url: URL) -> UsageArchive? {
        guard fileManager.isReadableFile(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(UsageArchive.self, from: data)
        } catch {
            return nil
        }
    }
}

extension UsageArchive {
    func merging(_ other: UsageArchive) -> UsageArchive {
        var mergedDays = days
        for (key, value) in other.days {
            mergedDays[key] = max(mergedDays[key, default: 0], value)
        }

        var mergedHourly = hourly
        for (dayKey, otherHours) in other.hourly {
            var dayHours = mergedHourly[dayKey, default: [:]]
            for (hourKey, value) in otherHours {
                dayHours[hourKey] = max(dayHours[hourKey, default: 0], value)
            }
            mergedHourly[dayKey] = dayHours
        }

        var mergedProjects = projects
        for project in other.projects where !mergedProjects.contains(where: { $0.id == project.id }) {
            mergedProjects.append(project)
        }

        var mergedProjectDays = projectDays
        for (dayKey, projectTotals) in other.projectDays {
            var dayTotals = mergedProjectDays[dayKey, default: [:]]
            for (projectID, value) in projectTotals {
                dayTotals[projectID] = max(dayTotals[projectID, default: 0], value)
            }
            mergedProjectDays[dayKey] = dayTotals
        }

        var mergedProjectHourly = projectHourly
        for (dayKey, projectHours) in other.projectHourly {
            var dayHours = mergedProjectHourly[dayKey, default: [:]]
            for (projectID, hours) in projectHours {
                var hourTotals = dayHours[projectID, default: [:]]
                for (hourKey, value) in hours {
                    hourTotals[hourKey] = max(hourTotals[hourKey, default: 0], value)
                }
                dayHours[projectID] = hourTotals
            }
            mergedProjectHourly[dayKey] = dayHours
        }

        var mergedUntaggedDays = untaggedDays
        for (key, value) in other.untaggedDays {
            mergedUntaggedDays[key] = max(mergedUntaggedDays[key, default: 0], value)
        }

        var mergedUntaggedHourly = untaggedHourly
        for (dayKey, hours) in other.untaggedHourly {
            var dayHours = mergedUntaggedHourly[dayKey, default: [:]]
            for (hourKey, value) in hours {
                dayHours[hourKey] = max(dayHours[hourKey, default: 0], value)
            }
            mergedUntaggedHourly[dayKey] = dayHours
        }

        var mergedSegments = segmentsByDay
        for (dayKey, daySegments) in other.segmentsByDay {
            mergedSegments[dayKey, default: []].append(contentsOf: daySegments)
        }

        return UsageArchive(
            days: mergedDays,
            hourly: mergedHourly,
            projects: mergedProjects,
            projectDays: mergedProjectDays,
            projectHourly: mergedProjectHourly,
            untaggedDays: mergedUntaggedDays,
            untaggedHourly: mergedUntaggedHourly,
            segmentsByDay: mergedSegments,
            openSegment: openSegment ?? other.openSegment
        )
    }
}

private extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
