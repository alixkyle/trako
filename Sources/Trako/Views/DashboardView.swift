import AppKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @EnvironmentObject private var pro: ProAccessController
    @State private var chartRange: ChartRange = .day
    @State private var selectedDate = Date()
    @State private var isConfirmingReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                statsSection
                ActivityChart(
                    range: $chartRange,
                    selectedDate: $selectedDate,
                    bars: tracker.bars(for: chartRange, selectedDate: selectedDate, isPro: pro.canUseProjects),
                    title: tracker.chartTitle(for: chartRange, selectedDate: selectedDate),
                    showsProjectFilter: pro.canUseProjects
                )
                LocalStoragePanel()
            }
            .padding(32)
            .frame(maxWidth: 1180, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .trakoWindowBackground()
        .alert("Reset today?", isPresented: $isConfirmingReset) {
            Button("Reset Today", role: .destructive) {
                tracker.resetToday()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears today's tracked time and hourly bars. It cannot be undone.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(TrakoBrand.gradient)
                    Text("Trako")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                }

                Text("Your Mac active-time rhythm, without app-level surveillance.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                StatusBadge(
                    title: tracker.pauseStateDescription,
                    isActive: tracker.isActivelyCounting
                )

                Button {
                    tracker.toggleManualPause()
                } label: {
                    Label(tracker.pauseButtonTitle, systemImage: tracker.pauseButtonSystemImage)
                }
                .buttonStyle(TrakoProminentButtonStyle())

                Button(role: .destructive) {
                    isConfirmingReset = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .help("Reset today")

                Button {
                    AppWindowPresenter.shared.showSettings(tracker: tracker, pro: pro)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.bordered)
                .help("Open Settings")
            }
        }
    }

    private var statsSection: some View {
        let isPro = pro.canUseProjects
        let filterDetail = isPro && !tracker.chartFocus.showsAllTotals
            ? "Viewing \(tracker.chartFocusSummary)"
            : tracker.pauseStateDescription

        return VStack(spacing: 14) {
            HeroStatCard(
                value: isPro ? tracker.filteredTodayClockText(isPro: true) : tracker.todayClockText,
                detail: filterDetail
            )

            LazyVGrid(columns: [
                GridItem(.flexible(minimum: 150), spacing: 14),
                GridItem(.flexible(minimum: 150), spacing: 14),
                GridItem(.flexible(minimum: 150), spacing: 14)
            ], spacing: 14) {
                StatCard(
                    title: "Last 7 days",
                    value: DurationFormat.compact(
                        isPro ? tracker.filteredWeeklySeconds(isPro: true) : tracker.weeklySeconds
                    ),
                    detail: "Total active time"
                )
                StatCard(
                    title: "Daily average",
                    value: DurationFormat.compact(
                        isPro ? tracker.filteredActiveDayAverageSeconds(isPro: true) : tracker.activeDayAverageSeconds
                    ),
                    detail: isPro
                        ? tracker.filteredActiveDayAverageDetail(isPro: true)
                        : tracker.activeDayAverageDetail
                )
                StatCard(
                    title: "Streak",
                    value: "\(isPro ? tracker.filteredCurrentStreak(isPro: true) : tracker.currentStreak)d",
                    detail: "Days with activity"
                )
            }
        }
    }
}

struct HeroStatCard: View {
    var value: String
    var detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Today")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(value)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(TrakoBrand.gradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "laptopcomputer")
                .font(.system(size: 44))
                .foregroundStyle(TrakoBrand.gradient.opacity(0.35))
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .trakoCard(elevated: true)
    }
}

struct StatCard: View {
    var title: String
    var value: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(16)
        .trakoCard()
    }
}

struct StatusBadge: View {
    var title: String
    var isActive: Bool

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isActive ? TrakoBrand.teal : Color.orange)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        }
    }
}

struct ActivityChart: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @EnvironmentObject private var pro: ProAccessController
    @Binding var range: ChartRange
    @Binding var selectedDate: Date
    var bars: [UsageBar]
    var title: String
    var showsProjectFilter: Bool
    @State private var isShowingDatePicker = false
    @State private var chartAppeared = false
    @State private var displayMode: ChartDisplayMode = .totals

    private var effectiveDisplayMode: ChartDisplayMode {
        range == .day ? displayMode : .totals
    }

    private var useProjectColors: Bool {
        showsProjectFilter && !tracker.projects.isEmpty
    }

    private var maximum: TimeInterval {
        max(bars.map(\.activeSeconds).max() ?? 1, 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            chartToolbar

            if useProjectColors, effectiveDisplayMode == .totals, tracker.chartFocus.showsAllTotals {
                chartLegend
            }

            Group {
                switch effectiveDisplayMode {
                case .totals:
                    totalsChart
                case .hourSpan:
                    HourSpanChartView(
                        columns: tracker.hourSpanColumns(for: selectedDate, isPro: showsProjectFilter),
                        useProjectColors: useProjectColors
                    )
                }
            }
        }
        .padding(20)
        .trakoCard()
        .onAppear {
            syncChartFocusForDisplayMode()
            withAnimation(.easeOut(duration: 0.45)) {
                chartAppeared = true
            }
        }
        .onChange(of: range) { newRange in
            if newRange != .day {
                displayMode = .totals
            }
            chartAppeared = false
            withAnimation(.easeOut(duration: 0.35)) {
                chartAppeared = true
            }
        }
        .onChange(of: selectedDate) { _ in
            chartAppeared = false
            withAnimation(.easeOut(duration: 0.35)) {
                chartAppeared = true
            }
        }
        .onChange(of: effectiveDisplayMode) { _ in
            syncChartFocusForDisplayMode()
        }
    }

    private func syncChartFocusForDisplayMode() {
        if effectiveDisplayMode == .hourSpan, tracker.chartFocus == .allTime {
            tracker.setChartFocus(.total)
        } else if effectiveDisplayMode == .totals, tracker.chartFocus == .total {
            tracker.setChartFocus(.allTime)
        }
    }

    private var chartToolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                if range == .day {
                    chartModePicker
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if showsProjectFilter {
                    ProjectChartFilterMenu(includesAllTime: effectiveDisplayMode == .totals)
                }
                dateNavigator
                rangePicker
            }
        }
    }

    private var chartModePicker: some View {
        HStack(spacing: 4) {
            ForEach(ChartDisplayMode.allCases) { mode in
                Button {
                    displayMode = mode
                } label: {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(effectiveDisplayMode == mode ? Color.accentColor : .secondary)
                        .frame(width: 28, height: 24)
                        .background(
                            effectiveDisplayMode == mode
                                ? Color.accentColor.opacity(0.18)
                                : Color.primary.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .help(mode.rawValue)
            }
        }
        .padding(.top, 4)
    }

    private var dateNavigator: some View {
        HStack(spacing: 2) {
            Button { moveSelection(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 26, height: 28)
            }
            .buttonStyle(.plain)

            Button { isShowingDatePicker.toggle() } label: {
                Text(dateControlTitle)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .frame(minWidth: 108)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingDatePicker, arrowEdge: .bottom) {
                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
            }

            Button { moveSelection(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 26, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var rangePicker: some View {
        Picker(selection: $range) {
            ForEach(ChartRange.allCases) { range in
                Text(range.rawValue).tag(range)
            }
        } label: {
            EmptyView()
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(minWidth: 220)
        .accessibilityLabel("Chart range")
    }

    private var totalsChart: some View {
        HStack(alignment: .bottom, spacing: barSpacing) {
            ForEach(bars) { bar in
                UsageBarView(
                    bar: bar,
                    maximum: maximum,
                    compact: bars.count > 24,
                    isDrillable: range != .day,
                    animate: chartAppeared,
                    useProjectColors: useProjectColors
                ) {
                    select(bar)
                }
            }
        }
        .frame(height: 260)
        .overlay {
            if bars.allSatisfy({ !$0.hasVisibleActivity }) {
                emptyTotalsOverlay
            }
        }
    }

    private var emptyTotalsOverlay: some View {
        Text("No activity")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private var barSpacing: CGFloat {
        bars.count > 24 ? 5 : 10
    }

    private var chartLegend: some View {
        HStack(spacing: 12) {
            legendSwatch(color: .secondary.opacity(0.5), title: "Untagged")
            ForEach(tracker.projects) { project in
                legendSwatch(color: project.color, title: project.name)
            }
        }
        .font(.caption2)
    }

    private func legendSwatch(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .foregroundStyle(.secondary)
        }
    }

    private var dateControlTitle: String {
        let formatter = DateFormatter()

        switch range {
        case .day:
            if Calendar.autoupdatingCurrent.isDateInToday(selectedDate) {
                return "Today"
            }
            formatter.dateFormat = "d MMM"
            return formatter.string(from: selectedDate)
        case .week:
            if let interval = Calendar.autoupdatingCurrent.dateInterval(of: .weekOfYear, for: selectedDate),
               interval.contains(Date()) {
                return "This Week"
            }

            formatter.dateFormat = "d MMM"
            return "Week of \(formatter.string(from: selectedDate))"
        case .month:
            formatter.dateFormat = "MMM yyyy"
            return formatter.string(from: selectedDate)
        case .year:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: selectedDate)
        }
    }

    private func moveSelection(_ direction: Int) {
        let calendar = Calendar.autoupdatingCurrent
        let component: Calendar.Component

        switch range {
        case .day:
            component = .day
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        case .year:
            component = .year
        }

        if let nextDate = calendar.date(byAdding: component, value: direction, to: selectedDate) {
            selectedDate = nextDate
        }
    }

    private func select(_ bar: UsageBar) {
        guard let date = bar.date else {
            return
        }

        switch range {
        case .day:
            break
        case .week, .month:
            selectedDate = date
            range = .day
        case .year:
            selectedDate = date
            range = .month
        }
    }
}

struct UsageBarView: View {
    @EnvironmentObject private var tracker: ActivityTracker
    var bar: UsageBar
    var maximum: TimeInterval
    var compact: Bool
    var isDrillable: Bool
    var animate: Bool
    var useProjectColors: Bool
    var onSelect: () -> Void

    private var heightRatio: CGFloat {
        guard bar.hasVisibleActivity else {
            return 0
        }

        return CGFloat(max(bar.activeSeconds / maximum, 0.03))
    }

    var body: some View {
        Button {
            onSelect()
        } label: {
            barContent
        }
        .buttonStyle(.plain)
        .disabled(!isDrillable)
        .help(isDrillable ? "View details for \(bar.label)" : "")
        .accessibilityLabel(bar.accessibilityLabel)
        .accessibilityHint(isDrillable ? "Opens a more detailed usage chart." : "")
    }

    private var barContent: some View {
        VStack(spacing: compact ? 5 : 8) {
            Text(DurationFormat.compact(bar.activeSeconds))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .opacity(bar.hasVisibleActivity ? 1 : 0)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            GeometryReader { proxy in
                VStack {
                    Spacer(minLength: 0)
                    if bar.hasVisibleActivity {
                        if useProjectColors, bar.hasColoredSlices {
                            stackedSlices(in: proxy.size, animate: animate)
                        } else {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(TrakoBrand.chartGradient)
                                .frame(height: proxy.size.height * (animate ? heightRatio : 0))
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                if isDrillable {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                }
            }

            Text(bar.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(height: 18)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func stackedSlices(in size: CGSize, animate: Bool) -> some View {
        let barHeight = size.height * (animate ? heightRatio : 0)
        let sliceTotal = bar.slices.map(\.activeSeconds).reduce(0, +)

        VStack(spacing: 0) {
            ForEach(bar.slices.reversed()) { slice in
                let sliceRatio = sliceTotal > 0 ? slice.activeSeconds / sliceTotal : 0
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color(for: slice))
                    .frame(height: barHeight * sliceRatio)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(height: barHeight)
    }

    private func color(for slice: ChartBarSlice) -> Color {
        if slice.isUntagged {
            return Color.secondary.opacity(0.45)
        }
        if let projectID = slice.projectID,
           let project = tracker.projects.first(where: { $0.id == projectID }) {
            return project.color
        }
        return TrakoBrand.teal
    }
}

struct LocalStoragePanel: View {
    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: "lock.laptopcomputer")
                .font(.system(size: 32))
                .foregroundStyle(TrakoBrand.gradient)

            VStack(alignment: .leading, spacing: 6) {
                Text("Private by Design")
                    .font(.headline)
                Text("Trako stores daily totals on this Mac and never records which apps, windows, or websites you use.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(20)
        .trakoCard()
    }
}
