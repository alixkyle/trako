import AppKit
import Combine
import CoreGraphics
import Foundation

@MainActor
final class ActivityTracker: ObservableObject {
    @Published private(set) var days: [String: TimeInterval]
    @Published private(set) var hourly: [String: [String: TimeInterval]]
    @Published private(set) var projects: [Project]
    @Published private(set) var segmentsByDay: [String: [TimeSegment]]
    /// Projects checked in the menu bar; empty = General (untagged) for the current stretch.
    @Published var activeProjectIDs: Set<String> = [] {
        didSet {
            if oldValue != activeProjectIDs {
                reconcileOpenSegment(at: Date())
                saveActiveProjects()
            }
        }
    }
    /// Dashboard display only — one color at a time on the Minutes heatmap.
    @Published var chartFocus: ChartFocus = .allTime
    @Published private(set) var idleSeconds: TimeInterval = 0
    @Published private(set) var isSystemAvailable = true
    @Published var isManuallyPaused: Bool {
        didSet {
            UserDefaults.standard.set(isManuallyPaused, forKey: Self.manualPauseKey)
            lastTick = Date()
            if isManuallyPaused {
                closeOpenSegment(at: lastTick)
            } else if isActivelyCounting {
                reconcileOpenSegment(at: lastTick)
            }
            persist()
        }
    }
    @Published var idleThreshold: TimeInterval {
        didSet {
            UserDefaults.standard.set(idleThreshold, forKey: Self.idleThresholdKey)
            persist()
        }
    }
    @Published var pauseWhenScreenLocked: Bool {
        didSet {
            UserDefaults.standard.set(pauseWhenScreenLocked, forKey: Self.pauseWhenScreenLockedKey)
            reconcileTrackingState(at: Date())
        }
    }

    private static let idleThresholdKey = "idle-threshold-seconds"
    private static let manualPauseKey = "manual-pause-enabled"
    private static let pauseWhenScreenLockedKey = "pause-when-screen-locked"
    private static let screenIsLockedNotification = Notification.Name("com.apple.screenIsLocked")
    private static let screenIsUnlockedNotification = Notification.Name("com.apple.screenIsUnlocked")
    private static let activeProjectsKey = "active-project-ids"
    private static let legacyActiveProjectKey = "active-project-id"
    private let store: UsageStore
    private var openSegment: OpenTimeSegment?
    private var timer: Timer?
    private var autosaveTimer: Timer?
    private var lastTick = Date()
    private var cancellables = Set<AnyCancellable>()
    private var screenLockObservers: [NSObjectProtocol] = []
    private var isScreenLocked = false

    init(store: UsageStore = UsageStore()) {
        self.store = store
        let archive = store.load()
        self.days = archive.days
        self.hourly = archive.hourly
        self.projects = archive.projects
        self.segmentsByDay = archive.segmentsByDay
        self.openSegment = archive.openSegment

        let savedThreshold = UserDefaults.standard.double(forKey: Self.idleThresholdKey)
        self.idleThreshold = savedThreshold > 0 ? savedThreshold : 60
        self.isManuallyPaused = UserDefaults.standard.bool(forKey: Self.manualPauseKey)
        if UserDefaults.standard.object(forKey: Self.pauseWhenScreenLockedKey) == nil {
            self.pauseWhenScreenLocked = true
        } else {
            self.pauseWhenScreenLocked = UserDefaults.standard.bool(forKey: Self.pauseWhenScreenLockedKey)
        }

        if let ids = UserDefaults.standard.stringArray(forKey: Self.activeProjectsKey) {
            self.activeProjectIDs = Set(ids)
        } else if let legacyID = UserDefaults.standard.string(forKey: Self.legacyActiveProjectKey) {
            self.activeProjectIDs = [legacyID]
        }

        if store.needsConsolidationSave {
            persist()
        }

        if isActivelyCounting {
            reconcileOpenSegment(at: Date())
        } else {
            closeOpenSegment(at: Date())
        }

        start()
        startAutosave()
        subscribeToPowerAndScreenEvents()
        subscribeToScreenLockEvents()
    }

    deinit {
        timer?.invalidate()
        autosaveTimer?.invalidate()
        let center = DistributedNotificationCenter.default()
        screenLockObservers.forEach { center.removeObserver($0) }
    }

    func persist() {
        save()
    }

    // MARK: - Segment queries

    func segments(on date: Date, through end: Date = Date()) -> [TimeSegment] {
        let dayKey = DayKey.key(for: date)
        var list = segmentsByDay[dayKey] ?? []

        if let open = openSegment, open.dayKey == dayKey {
            list.append(open.closed(at: end))
        }

        return list.sorted { $0.start < $1.start }
    }

    func filteredSeconds(for date: Date, focus: ChartFocus, isPro: Bool) -> TimeInterval {
        guard isPro, !focus.showsAllTotals else {
            return days[DayKey.key(for: date), default: 0]
        }

        let matching = segments(on: date).filter { $0.matches(focus: focus) }
        return TimeSegmentMath.unionDuration(of: matching)
    }

    func filteredTodayClockText(isPro: Bool) -> String {
        DurationFormat.clock(filteredSeconds(for: Date(), focus: chartFocus, isPro: isPro))
    }

    var todayClockText: String {
        DurationFormat.clock(todaySeconds)
    }

    var todaySeconds: TimeInterval {
        days[DayKey.key(for: Date()), default: 0]
    }

    func filteredWeeklySeconds(isPro: Bool) -> TimeInterval {
        recentDays.suffix(7).map { filteredSeconds(for: $0.date, focus: chartFocus, isPro: isPro) }.reduce(0, +)
    }

    var weeklySeconds: TimeInterval {
        recentDays.suffix(7).map(\.activeSeconds).reduce(0, +)
    }

    func filteredActiveDayAverageSeconds(isPro: Bool) -> TimeInterval {
        let activeDays = recentDays.suffix(7).filter {
            filteredSeconds(for: $0.date, focus: chartFocus, isPro: isPro) > 0
        }
        guard !activeDays.isEmpty else {
            return 0
        }
        let total = activeDays.reduce(0.0) {
            $0 + filteredSeconds(for: $1.date, focus: chartFocus, isPro: isPro)
        }
        return total / Double(activeDays.count)
    }

    var activeDayAverageSeconds: TimeInterval {
        let activeDays = recentDays.suffix(7).filter { $0.activeSeconds > 0 }
        guard !activeDays.isEmpty else {
            return 0
        }
        return activeDays.map(\.activeSeconds).reduce(0, +) / Double(activeDays.count)
    }

    func filteredActiveDayAverageDetail(isPro: Bool) -> String {
        let activeDayCount = recentDays.suffix(7).filter {
            filteredSeconds(for: $0.date, focus: chartFocus, isPro: isPro) > 0
        }.count
        return activeDayCount == 1 ? "1 active day" : "\(activeDayCount) active days"
    }

    var activeDayAverageDetail: String {
        let activeDayCount = recentDays.suffix(7).filter { $0.activeSeconds > 0 }.count
        return activeDayCount == 1 ? "1 active day" : "\(activeDayCount) active days"
    }

    func filteredCurrentStreak(isPro: Bool) -> Int {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        var streak = 0

        for offset in 0..<365 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                break
            }
            if filteredSeconds(for: date, focus: chartFocus, isPro: isPro) > 0 {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    var currentStreak: Int {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        var streak = 0

        for offset in 0..<365 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                break
            }
            if days[DayKey.key(for: date), default: 0] > 0 {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    var activeProjectNames: String {
        let names = projects.filter { activeProjectIDs.contains($0.id) }.map(\.name)
        if names.isEmpty {
            return "General"
        }
        return names.joined(separator: ", ")
    }

    // MARK: - Projects

    func addProject(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        projects.append(Project(name: trimmed))
        save()
    }

    func deleteProject(id: String) {
        projects.removeAll { $0.id == id }
        activeProjectIDs.remove(id)
        if case .project(let focusID) = chartFocus, focusID == id {
            chartFocus = .total
        }
        for dayKey in segmentsByDay.keys {
            segmentsByDay[dayKey] = segmentsByDay[dayKey]?.map { segment in
                var updated = segment
                updated.projectIDs = updated.projectIDs.filter { $0 != id }
                return updated
            }
        }
        if let open = openSegment {
            let remaining = open.projectIDSet.subtracting([id])
            openSegment = OpenTimeSegment(dayKey: open.dayKey, start: open.start, projectIDs: remaining)
        }
        save()
    }

    func toggleActiveProject(id: String) {
        if activeProjectIDs.contains(id) {
            activeProjectIDs.remove(id)
        } else {
            activeProjectIDs.insert(id)
        }
    }

    func setChartFocus(_ focus: ChartFocus) {
        chartFocus = focus
    }

    var chartFocusSummary: String {
        switch chartFocus {
        case .allTime:
            return "All time"
        case .total:
            return "Total"
        case .project(let id):
            return projects.first(where: { $0.id == id })?.name ?? "Project"
        }
    }

    func projectSecondsToday(projectID: String) -> TimeInterval {
        let matching = segments(on: Date()).filter { $0.contains(projectID: projectID) }
        return TimeSegmentMath.unionDuration(of: matching)
    }

    func untaggedSecondsToday() -> TimeInterval {
        let matching = segments(on: Date()).filter(\.isUntagged)
        return TimeSegmentMath.unionDuration(of: matching)
    }

    // MARK: - Tracking state

    var isActivelyCounting: Bool {
        !isManuallyPaused
            && isSystemAvailable
            && !isPausedForScreenLock
            && idleSeconds < idleThreshold
    }

    private var isPausedForScreenLock: Bool {
        pauseWhenScreenLocked && isScreenLocked
    }

    var pauseButtonTitle: String {
        isManuallyPaused ? "Resume" : "Pause"
    }

    var pauseButtonSystemImage: String {
        isManuallyPaused ? "play.fill" : "pause.fill"
    }

    var pauseStateDescription: String {
        if isManuallyPaused {
            return "Paused manually"
        }
        if !isSystemAvailable {
            return "Paused while Mac sleeps"
        }
        if isPausedForScreenLock {
            return "Paused while screen locked"
        }
        if idleSeconds >= idleThreshold {
            return "Paused while idle"
        }
        return "Tracking"
    }

    var recentDays: [UsageDay] {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())

        return (0..<14).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            let key = DayKey.key(for: date)
            return UsageDay(date: date, activeSeconds: days[key, default: 0])
        }
        .reversed()
    }

    func hourSpanColumns(for date: Date, isPro: Bool) -> [HourSpanColumn] {
        let dayKey = DayKey.key(for: date)
        let daySegments = segments(on: date)

        return (0..<24).map { hour in
            let hourKey = String(format: "%02d", hour)
            let label = hour % 6 == 0 ? "\(hour)" : ""
            let bounds = hourBounds(on: date, hour: hour) ?? (date, date)
            let fallbackSeconds = hourly[dayKey]?[hourKey] ?? 0

            var minutes = (0..<60).map { minute in
                let minuteStart = bounds.start.addingTimeInterval(TimeInterval(minute * 60))
                let minuteEnd = minuteStart.addingTimeInterval(60)
                return minuteSlot(
                    minute: minute,
                    from: daySegments,
                    start: minuteStart,
                    end: minuteEnd,
                    isPro: isPro,
                    hourFallbackSeconds: fallbackSeconds
                )
            }
            assignDisplayRangeLabels(
                to: &minutes,
                hour: hour,
                hourStart: bounds.start,
                segments: daySegments
            )

            return HourSpanColumn(
                id: "\(dayKey)-\(hourKey)",
                hour: hour,
                label: label,
                minutes: minutes
            )
        }
    }

    func bars(for range: ChartRange, selectedDate: Date, isPro: Bool) -> [UsageBar] {
        switch range {
        case .day:
            return hourlyBars(for: selectedDate, isPro: isPro)
        case .week:
            return dailyBarsForWeek(containing: selectedDate, isPro: isPro)
        case .month:
            return dailyBarsForMonth(containing: selectedDate, isPro: isPro)
        case .year:
            return monthlyBarsForYear(containing: selectedDate, isPro: isPro)
        }
    }

    func chartTitle(for range: ChartRange, selectedDate: Date) -> String {
        let formatter = DateFormatter()

        switch range {
        case .day:
            return DateLabels.fullDay(selectedDate)
        case .week:
            formatter.dateStyle = .medium
            guard
                let interval = Calendar.autoupdatingCurrent.dateInterval(of: .weekOfYear, for: selectedDate),
                let end = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 6, to: interval.start)
            else {
                return "Selected week"
            }
            return "\(formatter.string(from: interval.start)) - \(formatter.string(from: end))"
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: selectedDate)
        case .year:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: selectedDate)
        }
    }

    var bestDay: UsageDay? {
        recentDays.max(by: { $0.activeSeconds < $1.activeSeconds })
    }

    func resetToday() {
        let key = DayKey.key(for: Date())
        days[key] = 0
        hourly[key] = [:]
        segmentsByDay[key] = []
        openSegment = nil
        if isActivelyCounting {
            reconcileOpenSegment(at: Date())
        }
        save()
    }

    func toggleManualPause() {
        isManuallyPaused.toggle()
    }

    // MARK: - Segment lifecycle

    private func reconcileOpenSegment(at date: Date) {
        guard isActivelyCounting else {
            closeOpenSegment(at: date)
            return
        }

        let dayKey = DayKey.key(for: date)

        if let open = openSegment {
            if open.dayKey != dayKey || open.projectIDSet != activeProjectIDs {
                appendClosedSegment(open.closed(at: date))
                openSegment = OpenTimeSegment(dayKey: dayKey, start: date, projectIDs: activeProjectIDs)
            }
        } else {
            openSegment = OpenTimeSegment(dayKey: dayKey, start: date, projectIDs: activeProjectIDs)
        }
    }

    private func closeOpenSegment(at date: Date) {
        guard let open = openSegment else {
            return
        }
        appendClosedSegment(open.closed(at: date))
        openSegment = nil
    }

    private func appendClosedSegment(_ segment: TimeSegment) {
        guard segment.duration > 0 else {
            return
        }
        let dayKey = DayKey.key(for: segment.start)
        segmentsByDay[dayKey, default: []].append(segment)
    }

    private func start() {
        timer?.invalidate()
        lastTick = Date()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func startAutosave() {
        autosaveTimer?.invalidate()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.persist()
            }
        }
    }

    private func tick() {
        let now = Date()
        let elapsed = min(now.timeIntervalSince(lastTick), 5)
        lastTick = now
        let anyInput = CGEventType(rawValue: UInt32.max) ?? .null
        idleSeconds = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)

        let wasCounting = openSegment != nil
        let isCounting = isActivelyCounting

        if wasCounting, !isCounting {
            closeOpenSegment(at: now)
        } else if !wasCounting, isCounting {
            reconcileOpenSegment(at: now)
        } else if isCounting {
            reconcileOpenSegment(at: now)
        }

        guard isCounting else {
            return
        }

        let dayKey = DayKey.key(for: now)
        let hourKey = HourKey.key(for: now)
        days[dayKey, default: 0] += elapsed
        hourly[dayKey, default: [:]][hourKey, default: 0] += elapsed
        save()
    }

    private func save() {
        store.save(
            UsageArchive(
                days: days,
                hourly: hourly,
                projects: projects,
                segmentsByDay: segmentsByDay,
                openSegment: openSegment
            )
        )
    }

    private func saveActiveProjects() {
        UserDefaults.standard.set(Array(activeProjectIDs), forKey: Self.activeProjectsKey)
        if let first = activeProjectIDs.sorted().first {
            UserDefaults.standard.set(first, forKey: Self.legacyActiveProjectKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.legacyActiveProjectKey)
        }
    }

    private func hourBounds(on date: Date, hour: Int) -> (start: Date, end: Date)? {
        let calendar = Calendar.autoupdatingCurrent
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = 0
        components.second = 0

        guard let start = calendar.date(from: components),
              let end = calendar.date(byAdding: .hour, value: 1, to: start) else {
            return nil
        }
        return (start, end)
    }

    private func dayBounds(on date: Date) -> (start: Date, end: Date)? {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return nil
        }
        return (start, end)
    }

    private func segments(from rangeStart: Date, to rangeEnd: Date) -> [TimeSegment] {
        let calendar = Calendar.autoupdatingCurrent
        var day = calendar.startOfDay(for: rangeStart)
        let endDay = calendar.startOfDay(for: rangeEnd)
        var collected: [TimeSegment] = []

        while day < endDay {
            collected.append(contentsOf: segments(on: day, through: Date()))
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = nextDay
        }

        return collected
    }

    private func chartContent(
        from rangeStart: Date,
        to rangeEnd: Date,
        isPro: Bool,
        fallbackSeconds: TimeInterval
    ) -> (slices: [ChartBarSlice], total: TimeInterval) {
        guard isPro, !projects.isEmpty else {
            return ([], fallbackSeconds)
        }

        let matchingSegments = segments(from: rangeStart, to: rangeEnd).filter { segment in
            let clipStart = max(segment.start, rangeStart)
            let clipEnd = min(segment.end, rangeEnd)
            return clipStart < clipEnd
        }

        guard !matchingSegments.isEmpty else {
            return ([], fallbackSeconds)
        }

        let useFilter = !chartFocus.showsAllTotals
        var sliceTotals: [String: TimeInterval] = [:]

        for segment in matchingSegments {
            let clipStart = max(segment.start, rangeStart)
            let clipEnd = min(segment.end, rangeEnd)
            let duration = clipEnd.timeIntervalSince(clipStart)

            if segment.isUntagged {
                if !useFilter {
                    sliceTotals[Self.untaggedSliceKey, default: 0] += duration
                }
                continue
            }

            for projectID in segment.projectIDs {
                if !useFilter {
                    sliceTotals[projectID, default: 0] += duration
                } else if case .project(let focusID) = chartFocus, focusID == projectID {
                    sliceTotals[projectID, default: 0] += duration
                }
            }
        }

        let unionTotal = TimeSegmentMath.unionDuration(
            of: matchingSegments.filter { $0.matches(focus: chartFocus) },
            within: rangeStart,
            rangeEnd: rangeEnd
        )

        let slices = sliceTotals
            .map { key, seconds in
                ChartBarSlice(
                    id: "\(key)-\(rangeStart.timeIntervalSince1970)",
                    projectID: key == Self.untaggedSliceKey ? nil : key,
                    activeSeconds: seconds
                )
            }
            .filter { $0.activeSeconds > 0 }
            .sorted { $0.activeSeconds > $1.activeSeconds }

        let total = unionTotal > 0 ? unionTotal : fallbackSeconds
        return (slices, total)
    }

    private static let untaggedSliceKey = "__untagged__"

    private func minuteSlot(
        minute: Int,
        from daySegments: [TimeSegment],
        start minuteStart: Date,
        end minuteEnd: Date,
        isPro: Bool,
        hourFallbackSeconds: TimeInterval
    ) -> HourMinuteSlot {
        let overlapping = daySegments.filter { segment in
            max(segment.start, minuteStart) < min(segment.end, minuteEnd)
        }

        if overlapping.isEmpty {
            return fallbackMinuteSlot(
                minute: minute,
                hourFallbackSeconds: hourFallbackSeconds
            )
        }

        guard isPro else {
            return activeMinuteSlot(minute: minute, projectID: nil)
        }

        switch chartFocus {
        case .allTime, .total:
            guard !overlapping.isEmpty else {
                return HourMinuteSlot(minute: minute, isActive: false)
            }
            return activeMinuteSlot(minute: minute, projectID: nil)
        case .project(let focusID):
            guard overlapping.contains(where: { $0.projectIDs.contains(focusID) }) else {
                return HourMinuteSlot(minute: minute, isActive: false)
            }
            return activeMinuteSlot(minute: minute, projectID: focusID)
        }
    }

    private func activeMinuteSlot(minute: Int, projectID: String?) -> HourMinuteSlot {
        HourMinuteSlot(minute: minute, isActive: true, projectID: projectID)
    }

    private func fallbackMinuteSlot(minute: Int, hourFallbackSeconds: TimeInterval) -> HourMinuteSlot {
        let activeMinuteCount = min(60, max(Int(hourFallbackSeconds / 60), 0))
        let isActive = minute < activeMinuteCount
        return HourMinuteSlot(minute: minute, isActive: isActive, projectID: nil)
    }

    /// One tooltip per contiguous lit block (no merging across idle gaps in the hour).
    private func assignDisplayRangeLabels(
        to minutes: inout [HourMinuteSlot],
        hour: Int,
        hourStart: Date,
        segments: [TimeSegment]
    ) {
        var index = 0
        while index < minutes.count {
            guard minutes[index].isActive else {
                minutes[index].rangeLabel = nil
                index += 1
                continue
            }

            var end = index
            while end + 1 < minutes.count, minutes[end + 1].isActive {
                end += 1
            }

            let rangeStart = hourStart.addingTimeInterval(TimeInterval(index * 60))
            let rangeEnd = hourStart.addingTimeInterval(TimeInterval((end + 1) * 60))
            let label = labelForActiveRun(
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                hour: hour,
                startMinute: index,
                endMinuteInclusive: end,
                segments: segments
            )

            for minute in index...end {
                minutes[minute].rangeLabel = label
            }

            index = end + 1
        }
    }

    private func labelForActiveRun(
        rangeStart: Date,
        rangeEnd: Date,
        hour: Int,
        startMinute: Int,
        endMinuteInclusive: Int,
        segments: [TimeSegment]
    ) -> String {
        let overlapping = segments.filter { segment in
            max(segment.start, rangeStart) < min(segment.end, rangeEnd)
                && segment.matches(focus: chartFocus)
        }

        if let earliest = overlapping.min(by: { $0.start < $1.start }),
           let latest = overlapping.max(by: { $0.end < $1.end }) {
            let clipStart = max(earliest.start, rangeStart)
            let clipEnd = min(latest.end, rangeEnd)
            return TimeRangeFormat.clockRange(from: clipStart, to: clipEnd)
        }

        return TimeRangeFormat.clockRange(
            hour: hour,
            startMinute: startMinute,
            endMinuteInclusive: endMinuteInclusive
        )
    }

    private func filteredHourSeconds(dayKey: String, hourKey: String, date: Date, isPro: Bool) -> TimeInterval {
        guard isPro, !chartFocus.showsAllTotals else {
            return hourly[dayKey]?[hourKey] ?? 0
        }

        let calendar = Calendar.autoupdatingCurrent
        let hour = Int(hourKey) ?? 0
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = 0
        components.second = 0

        guard let hourStart = calendar.date(from: components),
              let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart) else {
            return 0
        }

        let matching = segments(on: date).filter { $0.matches(focus: chartFocus) }
        return TimeSegmentMath.unionDuration(of: matching, within: hourStart, rangeEnd: hourEnd)
    }

    private func hourlyBars(for date: Date, isPro: Bool) -> [UsageBar] {
        let key = DayKey.key(for: date)

        return (0..<24).map { hour in
            let hourKey = String(format: "%02d", hour)
            let label = hour % 6 == 0 ? "\(hour)" : ""
            let displayHour = String(format: "%02d:00", hour)
            let fallback = filteredHourSeconds(dayKey: key, hourKey: hourKey, date: date, isPro: isPro)
            let bounds = hourBounds(on: date, hour: hour) ?? (date, date)
            let chart = chartContent(
                from: bounds.start,
                to: bounds.end,
                isPro: isPro,
                fallbackSeconds: fallback
            )

            return UsageBar(
                id: "\(key)-\(hourKey)",
                label: label,
                accessibilityLabel: "\(displayHour), \(DurationFormat.spoken(chart.total)) active",
                activeSeconds: chart.total,
                date: date,
                slices: chart.slices
            )
        }
    }

    private func dailyBarsForWeek(containing date: Date, isPro: Bool) -> [UsageBar] {
        let calendar = Calendar.autoupdatingCurrent
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return []
        }

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else {
                return nil
            }

            let key = DayKey.key(for: day)
            let fallback = filteredSeconds(for: day, focus: chartFocus, isPro: isPro)
            let bounds = dayBounds(on: day) ?? (day, day)
            let chart = chartContent(from: bounds.start, to: bounds.end, isPro: isPro, fallbackSeconds: fallback)

            return UsageBar(
                id: key,
                label: DateLabels.weekday(day),
                accessibilityLabel: "\(DateLabels.fullDay(day)), \(DurationFormat.spoken(chart.total)) active",
                activeSeconds: chart.total,
                date: day,
                slices: chart.slices
            )
        }
    }

    private func dailyBarsForMonth(containing date: Date, isPro: Bool) -> [UsageBar] {
        let calendar = Calendar.autoupdatingCurrent
        guard
            let interval = calendar.dateInterval(of: .month, for: date),
            let dayRange = calendar.range(of: .day, in: .month, for: date)
        else {
            return []
        }

        return dayRange.compactMap { dayNumber in
            guard let day = calendar.date(byAdding: .day, value: dayNumber - 1, to: interval.start) else {
                return nil
            }

            let key = DayKey.key(for: day)
            let fallback = filteredSeconds(for: day, focus: chartFocus, isPro: isPro)
            let bounds = dayBounds(on: day) ?? (day, day)
            let chart = chartContent(from: bounds.start, to: bounds.end, isPro: isPro, fallbackSeconds: fallback)

            return UsageBar(
                id: key,
                label: dayNumber == 1 || dayNumber % 5 == 0 ? "\(dayNumber)" : "",
                accessibilityLabel: "\(DateLabels.fullDay(day)), \(DurationFormat.spoken(chart.total)) active",
                activeSeconds: chart.total,
                date: day,
                slices: chart.slices
            )
        }
    }

    private func monthlyBarsForYear(containing date: Date, isPro: Bool) -> [UsageBar] {
        let calendar = Calendar.autoupdatingCurrent
        guard let interval = calendar.dateInterval(of: .year, for: date) else {
            return []
        }

        return (0..<12).compactMap { offset in
            guard
                let monthStart = calendar.date(byAdding: .month, value: offset, to: interval.start),
                let monthInterval = calendar.dateInterval(of: .month, for: monthStart)
            else {
                return nil
            }

            let fallback = days.reduce(0) { total, entry in
                let entryDate = DayKey.date(from: entry.key)
                return monthInterval.contains(entryDate) ? total + entry.value : total
            }

            let chart = chartContent(
                from: monthInterval.start,
                to: monthInterval.end,
                isPro: isPro,
                fallbackSeconds: fallback
            )

            return UsageBar(
                id: "month-\(offset)",
                label: DateLabels.month(monthStart),
                accessibilityLabel: "\(DateLabels.month(monthStart)), \(DurationFormat.spoken(chart.total)) active",
                activeSeconds: chart.total,
                date: monthStart,
                slices: chart.slices
            )
        }
    }

    private func reconcileTrackingState(at date: Date) {
        lastTick = date
        if isActivelyCounting {
            reconcileOpenSegment(at: date)
        } else {
            closeOpenSegment(at: date)
        }
    }

    private func subscribeToScreenLockEvents() {
        let center = DistributedNotificationCenter.default()

        screenLockObservers.append(
            center.addObserver(
                forName: Self.screenIsLockedNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.setScreenLocked(true)
                }
            }
        )

        screenLockObservers.append(
            center.addObserver(
                forName: Self.screenIsUnlockedNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.setScreenLocked(false)
                }
            }
        )
    }

    private func setScreenLocked(_ locked: Bool) {
        guard isScreenLocked != locked else {
            return
        }
        isScreenLocked = locked
        reconcileTrackingState(at: Date())
    }

    private func subscribeToPowerAndScreenEvents() {
        let center = NSWorkspace.shared.notificationCenter

        center.publisher(for: NSWorkspace.willSleepNotification)
            .merge(with: center.publisher(for: NSWorkspace.screensDidSleepNotification))
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.isSystemAvailable = false
                    self?.lastTick = Date()
                    self?.closeOpenSegment(at: Date())
                }
            }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didWakeNotification)
            .merge(with: center.publisher(for: NSWorkspace.screensDidWakeNotification))
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.isSystemAvailable = true
                    self?.lastTick = Date()
                    if self?.isActivelyCounting == true {
                        self?.reconcileOpenSegment(at: Date())
                    }
                }
            }
            .store(in: &cancellables)
    }
}
