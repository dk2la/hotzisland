import SwiftUI

/// Content of the settings window. Runs in a normal key window (unlike the
/// island panel), so standard controls behave normally here.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    var playbooks: PlaybookStore
    @State private var editingPlaybook: Playbook?
    @State private var creatingPlaybook = false

    var body: some View {
        Form {
            Section {
                ForEach(playbooks.playbooks) { playbook in
                    HStack {
                        Label(playbook.name, systemImage: playbook.icon)
                        Spacer()
                        Button("Edit") { editingPlaybook = playbook }
                    }
                }
                Button("Add Playbook…") { creatingPlaybook = true }
            } header: {
                Text("Playbooks")
            } footer: {
                Text("One-tap scenarios: open a set of apps, close the rest, switch Focus via a Shortcut, start a timer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(IslandTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                Text(settings.theme.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Appearance")
            }

            Section {
                Picker("When idle", selection: $settings.idleMode) {
                    ForEach(IdleMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                Text("Compact indicators show the playing track or a running timer next to the notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Idle behavior")
            }

            Section {
                ForEach(NotchTab.allCases) { tab in
                    Toggle(isOn: toggleBinding(for: tab)) {
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .disabled(settings.enabledTabs == [tab])
                }
            } header: {
                Text("Modules")
            } footer: {
                Text("Disabled modules disappear from the island's tab bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(item: $editingPlaybook) { playbook in
            PlaybookEditorView(store: playbooks, existing: playbook) {
                editingPlaybook = nil
            }
        }
        .sheet(isPresented: $creatingPlaybook) {
            PlaybookEditorView(store: playbooks, existing: nil) {
                creatingPlaybook = false
            }
        }
    }

    private func toggleBinding(for tab: NotchTab) -> Binding<Bool> {
        Binding(
            get: { settings.isEnabled(tab) },
            set: { _ in settings.toggle(tab) }
        )
    }
}
