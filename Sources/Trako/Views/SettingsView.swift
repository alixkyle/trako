import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @EnvironmentObject private var pro: ProAccessController
    @State private var launchAtLogin = LaunchAtLoginController.isEnabled
    @State private var launchAtLoginError: String?

    private let idlePresets: [TimeInterval] = [15, 30, 60, 120, 300]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsHeader

                SettingsSection(title: "General") {
                    Toggle(isOn: $launchAtLogin) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch at login")
                                .font(.body.weight(.medium))
                            Text("Start Trako automatically when you sign in.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .onChange(of: launchAtLogin) { newValue in
                        updateLaunchAtLogin(newValue)
                    }

                    if let launchAtLoginError {
                        Text(launchAtLoginError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                SettingsSection(title: "Idle Detection") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Mark inactive after")
                            Spacer()
                            Text("\(Int(tracker.idleThreshold)) seconds")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(TrakoBrand.teal)
                                .monospacedDigit()
                        }

                        Picker("Inactive Threshold", selection: $tracker.idleThreshold) {
                            ForEach(idlePresets, id: \.self) { seconds in
                                Text("\(Int(seconds))s").tag(seconds)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Slider(value: $tracker.idleThreshold, in: 15...300, step: 15)
                            .tint(TrakoBrand.teal)

                        Text("Trako pauses counting once your Mac has been idle for the selected time.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Toggle(isOn: $tracker.pauseWhenScreenLocked) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pause when screen is locked")
                                    .font(.body.weight(.medium))
                                Text("Stops counting as soon as you lock the screen.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)

                        Text("Trako also pauses when the Mac or display sleeps, and when you tap Pause in the menu bar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ProjectsSettingsSection()

                SettingsSection(title: "Trako Pro") {
                    Toggle(isOn: testingUnlockBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Unlock Pro for testing")
                                .font(.body.weight(.medium))
                            Text(pro.canUseProjects ? "Project tagging and filters are enabled." : "Turn on to try Pro without App Store purchase.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }

                SettingsSection(title: "Privacy") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Trako stores daily and hourly active-time totals locally on this Mac. It does not record apps, windows, websites, keystrokes, or screen contents.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            AppWindowPresenter.shared.showPrivacyPolicy()
                        } label: {
                            Label("Privacy Policy", systemImage: "hand.raised")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520)
        .frame(minHeight: 480)
        .trakoWindowBackground()
    }

    private var settingsHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape.fill")
                .font(.title2)
                .foregroundStyle(TrakoBrand.gradient)

            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.title2.weight(.semibold))
                Text("Tracking preferences for this Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var testingUnlockBinding: Binding<Bool> {
        Binding(
            get: { pro.isTestingUnlockEnabled },
            set: { pro.setTestingUnlocked($0) }
        )
    }

    private func updateLaunchAtLogin(_ isEnabled: Bool) {
        do {
            try LaunchAtLoginController.setEnabled(isEnabled)
            launchAtLoginError = nil
        } catch {
            launchAtLogin = LaunchAtLoginController.isEnabled
            launchAtLoginError = "Could not update launch at login from this build."
        }
    }
}

struct SettingsSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .trakoCard()
        }
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Privacy Policy")
                    .font(.largeTitle.weight(.bold))

                Text("Trako stores aggregate active-time totals locally on your Mac.")

                Text("Trako does not collect, transmit, sell, or share personal data. Trako does not record which apps, windows, websites, documents, keystrokes, screenshots, or screen contents you use.")

                Text("Trako stores daily totals and hourly totals in local app storage so the app can show your usage charts. If you enable Launch at Login, macOS stores that preference using Apple's login item system.")

                Text("You can pause tracking at any time from the menu bar. Trako can also pause when the screen is locked, after a period without keyboard or mouse input, or when the Mac sleeps. You can reset today's tracked time from the menu bar or dashboard.")

                Text("For support, use the support link provided on Trako's App Store product page.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .frame(width: 560)
        .frame(minHeight: 360)
        .trakoWindowBackground()
    }
}
