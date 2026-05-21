import SwiftUI

// MARK: - Menu bar tagging (multi-project; no projects = General)

struct MenuBarProjectPicker: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @EnvironmentObject private var pro: ProAccessController
    @State private var newProjectName = ""
    @State private var isShowingUpgrade = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Projects")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if pro.canUseProjects {
                    Text(tracker.activeProjectNames)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if pro.canUseProjects {
                projectToggles

                HStack(spacing: 8) {
                    TextField("New project", text: $newProjectName)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        tracker.addProject(named: newProjectName)
                        newProjectName = ""
                    }
                    .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Button {
                    isShowingUpgrade = true
                } label: {
                    Label("Unlock project tagging with Trako Pro", systemImage: "star.fill")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(TrakoBrand.gradient)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .trakoCard()
        .sheet(isPresented: $isShowingUpgrade) {
            ProUpgradeSheet()
        }
    }

    @ViewBuilder
    private var projectToggles: some View {
        if tracker.projects.isEmpty {
            Text("General")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(tracker.projects) { project in
                    Toggle(isOn: activeBinding(for: project.id)) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(project.color)
                                .frame(width: 8, height: 8)
                            Text(project.name)
                                .font(.callout.weight(.medium))
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private func activeBinding(for projectID: String) -> Binding<Bool> {
        Binding(
            get: { tracker.activeProjectIDs.contains(projectID) },
            set: { isOn in
                if isOn {
                    tracker.activeProjectIDs.insert(projectID)
                } else {
                    tracker.activeProjectIDs.remove(projectID)
                }
            }
        )
    }
}

// MARK: - Dashboard chart focus (view one project at a time)

struct ProjectChartFilterMenu: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @EnvironmentObject private var pro: ProAccessController
    var includesAllTime: Bool = true
    @State private var isShowingUpgrade = false

    var body: some View {
        Group {
            if pro.canUseProjects {
                Menu {
                    if includesAllTime {
                        focusButton("All time", focus: .allTime, color: TrakoBrand.teal)
                        Divider()
                    }

                    if !includesAllTime {
                        focusButton("Total", focus: .total, color: TrakoBrand.teal)
                        Divider()
                    }

                    if !tracker.projects.isEmpty {
                        ForEach(tracker.projects) { project in
                            Button {
                                tracker.setChartFocus(.project(project.id))
                            } label: {
                                HStack {
                                    Label(
                                        project.name,
                                        systemImage: isSelected(project.id) ? "checkmark" : ""
                                    )
                                    Spacer()
                                    Circle()
                                        .fill(project.color)
                                        .frame(width: 8, height: 8)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(tracker.chartFocusSummary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                Button {
                    isShowingUpgrade = true
                } label: {
                    Label("Projects", systemImage: "star.fill")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
        }
        .sheet(isPresented: $isShowingUpgrade) {
            ProUpgradeSheet()
        }
    }

    private func focusButton(_ title: String, focus: ChartFocus, color: Color) -> some View {
        Button {
            tracker.setChartFocus(focus)
        } label: {
            HStack {
                Label(title, systemImage: tracker.chartFocus == focus ? "checkmark" : "")
                Spacer()
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func isSelected(_ projectID: String) -> Bool {
        if case .project(let id) = tracker.chartFocus {
            return id == projectID
        }
        return false
    }
}

// MARK: - Settings

struct ProjectsSettingsSection: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @EnvironmentObject private var pro: ProAccessController
    @State private var newProjectName = ""
    @State private var isShowingUpgrade = false

    var body: some View {
        SettingsSection(title: "Projects (Trako Pro)") {
            if pro.canUseProjects {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Mac time is always tracked. Check projects in the menu bar to tag the current stretch; leave all unchecked for General. The dashboard shows one project (or General) at a time so the Minutes heatmap stays one color.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(tracker.projects) { project in
                        HStack(spacing: 10) {
                            Circle().fill(project.color).frame(width: 10, height: 10)
                            Text(project.name)
                                .font(.body.weight(.medium))
                            Spacer()
                            Button(role: .destructive) {
                                tracker.deleteProject(id: project.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("Project name", text: $newProjectName)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            tracker.addProject(named: newProjectName)
                            newProjectName = ""
                        }
                        .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Project tagging is part of Trako Pro. Free tracking still includes total active time, charts, and idle pause.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("View Trako Pro") {
                        isShowingUpgrade = true
                    }
                    .buttonStyle(TrakoProminentButtonStyle())
                }
            }
        }
        .sheet(isPresented: $isShowingUpgrade) {
            ProUpgradeSheet()
        }
    }
}

struct ProUpgradeSheet: View {
    @EnvironmentObject private var pro: ProAccessController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Trako Pro")
                .font(.largeTitle.weight(.bold))

            Text("Tag stretches to one or more projects from the menu bar. General time is always tracked when no project is checked. View the dashboard one project at a time for clear colors.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Label("Create unlimited projects", systemImage: "checkmark.circle.fill")
                Label("Multi-project tagging while tracking", systemImage: "checkmark.circle.fill")
                Label("Minutes timeline with single-color focus", systemImage: "checkmark.circle.fill")
            }
            .foregroundStyle(TrakoBrand.teal)

            if let product = pro.product {
                Text(product.displayPrice)
                    .font(.title2.weight(.semibold))
            }

            HStack(spacing: 10) {
                Button {
                    Task { await pro.purchase() }
                } label: {
                    if pro.purchaseInFlight {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Buy Trako Pro")
                    }
                }
                .buttonStyle(TrakoProminentButtonStyle())
                .disabled(pro.purchaseInFlight || pro.product == nil)

                Button("Restore Purchases") {
                    Task { await pro.restorePurchases() }
                }
                .buttonStyle(.bordered)
            }

            if let message = pro.lastErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(28)
        .frame(width: 420, height: 440)
    }

}
