import AppKit
import SwiftUI

private enum PopoverLayout {
    static let width: CGFloat = 340
    static let padding: CGFloat = 20
    static let sectionSpacing: CGFloat = 14
    static let cardSpacing: CGFloat = 12
    static let buttonSpacing: CGFloat = 8
    static let buttonHeight: CGFloat = 36
    static let footerSpacing: CGFloat = 12
}

struct MenuBarView: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @EnvironmentObject private var pro: ProAccessController
    @State private var isConfirmingReset = false

    private var lastSevenDays: [TimeInterval] {
        tracker.recentDays.suffix(7).map(\.activeSeconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, PopoverLayout.sectionSpacing)

            VStack(alignment: .leading, spacing: PopoverLayout.cardSpacing) {
                timerPanel
                weekSummary
            }
            .padding(.bottom, PopoverLayout.sectionSpacing)

            MenuBarProjectPicker()
                .padding(.bottom, PopoverLayout.sectionSpacing)

            VStack(spacing: PopoverLayout.buttonSpacing) {
                Button {
                    tracker.toggleManualPause()
                } label: {
                    Label(tracker.pauseButtonTitle, systemImage: tracker.pauseButtonSystemImage)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TrakoProminentButtonStyle())
                .popoverButtonHeight()

                menuActions
            }
            .padding(.bottom, PopoverLayout.footerSpacing)

            Divider()
                .opacity(0.35)
                .padding(.bottom, PopoverLayout.footerSpacing)

            footerActions
        }
        .padding(PopoverLayout.padding)
        .frame(width: PopoverLayout.width)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThickMaterial)
        }
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
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.title3.weight(.semibold))
                .foregroundStyle(TrakoBrand.gradient)

            Text("Trako")
                .font(.system(size: 20, weight: .semibold, design: .rounded))

            Spacer()

            StatusBadge(
                title: tracker.pauseStateDescription,
                isActive: tracker.isActivelyCounting
            )
        }
    }

    private var timerPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(tracker.todayClockText)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(TrakoBrand.gradient)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 46, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .trakoCard(elevated: true)
    }

    private var weekSummary: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Last 7 days")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(DurationFormat.compact(tracker.weeklySeconds))
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
            }

            Spacer()

            MiniSparkline(values: lastSevenDays)
        }
        .frame(minHeight: 56)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .trakoCard()
    }

    private var menuActions: some View {
        VStack(spacing: PopoverLayout.buttonSpacing) {
            Button {
                AppWindowPresenter.shared.showDashboard(tracker: tracker, pro: pro)
            } label: {
                Label("Open Dashboard", systemImage: "chart.bar.xaxis")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .popoverButtonHeight()

            Button {
                AppWindowPresenter.shared.showSettings(tracker: tracker, pro: pro)
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .popoverButtonHeight()
        }
        .buttonStyle(.bordered)
    }

    private var footerActions: some View {
        HStack {
            Button(role: .destructive) {
                isConfirmingReset = true
            } label: {
                Label("Reset Today", systemImage: "arrow.counterclockwise")
            }

            Spacer()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

private extension View {
    func popoverButtonHeight() -> some View {
        frame(height: PopoverLayout.buttonHeight)
    }
}
