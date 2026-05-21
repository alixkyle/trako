import AppKit
import SwiftUI

struct HourSpanChartView: View {
    @EnvironmentObject private var tracker: ActivityTracker
    var columns: [HourSpanColumn]
    var useProjectColors: Bool

    @State private var hoverTooltip: String?

    private let chartHeight: CGFloat = 240
    private let axisWidth: CGFloat = 22

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            minuteAxis
            VStack(spacing: 10) {
                ZStack(alignment: .top) {
                    ZStack(alignment: .leading) {
                        gridLines
                        hourColumns
                    }
                    .frame(height: chartHeight)
                    .overlay {
                        MinuteChartHoverOverlay(
                            columns: columns,
                            chartHeight: chartHeight,
                            tooltip: $hoverTooltip
                        )
                    }

                    if let hoverTooltip {
                        Text(hoverTooltip)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                            .overlay {
                                Capsule()
                                    .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                            }
                            .padding(.top, 6)
                            .allowsHitTesting(false)
                    }
                }

                hourLabels
            }
        }
        .overlay {
            if !hasActivity {
                Text("No activity")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hasActivity: Bool {
        columns.contains { column in
            column.minutes.contains { $0.isActive }
        }
    }

    private var hourColumns: some View {
        HStack(alignment: .bottom, spacing: 1) {
            ForEach(columns) { column in
                hourColumn(column)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var minuteAxis: some View {
        VStack {
            Text("60")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
            Spacer()
            Text("0")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .frame(width: axisWidth, height: chartHeight)
    }

    private var gridLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                Spacer()
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func hourColumn(_ column: HourSpanColumn) -> some View {
        VStack(spacing: 0) {
            ForEach((0..<60).reversed(), id: \.self) { minute in
                minuteCell(column.minutes[minute])
            }
        }
        .frame(height: chartHeight)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .allowsHitTesting(false)
    }

    private func minuteCell(_ slot: HourMinuteSlot) -> some View {
        Rectangle()
            .fill(color(for: slot))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(accessibilityLabel(for: slot))
    }

    private func accessibilityLabel(for slot: HourMinuteSlot) -> String {
        guard slot.isActive, let rangeLabel = slot.rangeLabel else {
            return "No activity"
        }
        return "Active \(rangeLabel)"
    }

    private func color(for slot: HourMinuteSlot) -> Color {
        guard slot.isActive else {
            return .clear
        }

        guard useProjectColors else {
            return TrakoBrand.teal.opacity(0.9)
        }

        switch tracker.chartFocus {
        case .allTime:
            return TrakoBrand.teal.opacity(0.9)
        case .total:
            return TrakoBrand.teal.opacity(0.9)
        case .project(let id):
            if let project = tracker.projects.first(where: { $0.id == id }) {
                return project.color.opacity(0.92)
            }
            return TrakoBrand.teal.opacity(0.9)
        }
    }

    private var hourLabels: some View {
        HStack(spacing: 1) {
            Color.clear.frame(width: axisWidth)
            ForEach(columns) { column in
                Text(column.label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(column.label.isEmpty ? .clear : .secondary)
                    .frame(maxWidth: .infinity)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Hover tracking (minute cells are too thin for SwiftUI .help)

struct MinuteChartHoverOverlay: NSViewRepresentable {
    var columns: [HourSpanColumn]
    var chartHeight: CGFloat
    @Binding var tooltip: String?

    func makeNSView(context: Context) -> MinuteChartHoverView {
        let view = MinuteChartHoverView()
        view.onTooltipChange = { tooltip = $0 }
        return view
    }

    func updateNSView(_ nsView: MinuteChartHoverView, context: Context) {
        nsView.columns = columns
        nsView.chartHeight = chartHeight
        nsView.onTooltipChange = { tooltip = $0 }
    }
}

@MainActor
final class MinuteChartHoverView: NSView {
    var columns: [HourSpanColumn] = []
    var chartHeight: CGFloat = 240
    var onTooltipChange: ((String?) -> Void)?

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseMoved(with event: NSEvent) {
        onTooltipChange?(tooltip(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        onTooltipChange?(nil)
    }

    private func tooltip(at location: CGPoint) -> String? {
        guard bounds.width > 0, chartHeight > 0, !columns.isEmpty else {
            return nil
        }

        let columnWidth = bounds.width / CGFloat(columns.count)
        let columnIndex = min(max(Int(location.x / columnWidth), 0), columns.count - 1)
        let column = columns[columnIndex]

        let minuteFromTop = Int((location.y / chartHeight) * 60)
        let minute = 59 - min(max(minuteFromTop, 0), 59)
        let slot = column.minutes[minute]

        guard slot.isActive, let rangeLabel = slot.rangeLabel else {
            return nil
        }
        return rangeLabel
    }
}
