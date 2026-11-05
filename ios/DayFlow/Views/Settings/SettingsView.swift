import DayFlowCore
import SwiftUI

/// Settings: a grouped list like iOS Settings, with the same pages as the Mac's tabs.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { BlockTypesView() } label: {
                        row("Block types", "square.stack.3d.up.fill", .teal, detail: "\(model.types.count)")
                    }
                    NavigationLink { MeetingsSettingsView() } label: {
                        row("Meetings", "person.2.fill", .orange)
                    }
                    NavigationLink { SoundsSettingsView() } label: {
                        row("Sounds", "speaker.wave.2.fill", .pink, detail: model.settings.sound ? "\(model.settings.volume)%" : "Off")
                    }
                    NavigationLink { CalendarsView() } label: {
                        row("Calendars", "calendar", .red, detail: calendarDetail)
                    }
                    NavigationLink { GeneralView() } label: {
                        row("General", "gearshape.fill", .gray)
                    }
                }
                Section {
                    Link(destination: URL(string: "https://github.com/JRAntra/dayflow/blob/main/User%20Guide.md#17-dayflow-on-iphone")!) {
                        Label("User Guide", systemImage: "book")
                    }
                } footer: {
                    Text("DayFlow \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .navigationTitle("Settings")
        }
    }

    var calendarDetail: String {
        guard model.calendarAccess else { return "Off" }
        let n = model.settings.calendars?.count ?? 0
        return n == 0 ? "None" : "\(n)"
    }

    func row(_ title: String, _ icon: String, _ color: Color, detail: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(color.gradient, in: .rect(cornerRadius: 7))
            Text(title)
            Spacer()
            if let detail { Text(detail).foregroundStyle(.secondary) }
        }
    }
}

/// Every type; Default first and never deleted. Swipe left to delete one (its blocks move to Default).
struct BlockTypesView: View {
    @Environment(AppModel.self) private var model
    @State private var opened: String?

    var body: some View {
        List {
            Section {
                ForEach(model.types) { t in
                    NavigationLink {
                        TypeDetailView(typeId: t.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(t.name)
                                if t.isDefault { TypeBadge(name: "Default") }
                            }
                            Text(summary(t)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        if !t.isDefault {
                            Button(role: .destructive) { model.deleteType(t.id) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            } footer: {
                Text("Every block has a type, and its type decides its reminders. Default can be renamed but not deleted; blocks of a deleted type move to it.")
            }
        }
        .navigationTitle("Block types")
        .navigationDestination(item: $opened) { TypeDetailView(typeId: $0) }
        .toolbar {
            Button {
                if let t = model.addType() { opened = t.id }
            } label: { Image(systemName: "plus") }
            .accessibilityLabel("Add block type")
        }
    }

    /// "Prep 10 min · 3 of 4 on · Used by 5 blocks", like the Mac's list.
    func summary(_ t: BlockType) -> String {
        let on = t.reminders.all.filter(\.on).count
        let used = model.store.usedBy(t.id)
        return [t.reminders.prep.on ? "Prep \(t.reminders.prep.lead ?? 5) min" : nil, "\(on) of 4 on",
                used > 0 ? "\(used) block\(used == 1 ? "" : "s")" : nil].compactMap { $0 }.joined(separator: " · ")
    }
}

/// One type: its name and its four reminders.
///
/// It doesn't read `\.dismiss`: on iOS 17 that makes a page on a navigation stack re-render
/// whenever navigation changes, which loops forever once the sound picker is pushed.
struct TypeDetailView: View {
    @Environment(AppModel.self) private var model
    let typeId: String
    @State private var name = ""
    @State private var nameError: String?
    @State private var confirmDelete = false

    var type: BlockType? { model.types.first { $0.id == typeId } }

    var body: some View {
        if let t = type {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .onSubmit { saveName() }
                        .onChange(of: name) { saveName() }
                    if let nameError { Text(nameError).font(.footnote).foregroundStyle(.red) }
                } footer: {
                    let n = model.store.usedBy(t.id)
                    Text(n > 0 ? "Used by \(n) block\(n == 1 ? "" : "s")" : "Not used by any block yet")
                }
                ForEach(TypeReminderKey.allCases, id: \.self) { key in
                    ReminderSection(spec: Specs.spec(key), example: example(key, t), reminder: Binding(
                        get: { type?.reminders[key] ?? t.reminders[key] },
                        set: { r in
                            guard var cur = type else { return }
                            cur.reminders[key] = r
                            model.updateType(cur)
                        }))
                }
                if !t.isDefault {
                    Section {
                        Button("Delete type", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(t.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { name = t.name }
            .confirmationDialog("Delete \(t.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { model.deleteType(t.id) }
            } message: {
                let n = model.store.usedBy(t.id)
                Text(n > 0 ? "\(n) block\(n == 1 ? " uses" : "s use") it. \(n == 1 ? "It" : "They")'ll move to \(model.typeOf(Specs.defaultType).name)." : "No blocks use it.")
            }
        } else {
            ContentUnavailableView("Type deleted", systemImage: "square.stack.3d.up.slash",
                                   description: Text("Its blocks moved to \(model.typeOf(Specs.defaultType).name). Go back to see your block types."))
        }
    }

    func saveName() {
        guard var t = type else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != t.name else { nameError = nil; return }
        if trimmed.isEmpty { nameError = "Every block type needs a name."; return }
        if model.types.contains(where: { $0.id != t.id && $0.name.lowercased() == trimmed.lowercased() }) {
            nameError = "There's already a block type called \"\(trimmed)\"."; return
        }
        nameError = nil
        t.name = trimmed
        model.updateType(t)
    }

    /// What the notification says, with the type's own lead times.
    func example(_ key: TypeReminderKey, _ t: BlockType) -> String {
        switch key {
        case .prep: "\"In \(t.reminders.prep.lead ?? 5) min: Deep work\""
        case .start: "\"Now: Deep work\""
        case .warn: "\"\(t.reminders.warn.lead ?? 5) min left: Deep work\""
        case .end: "\"Time's up: Deep work\""
        }
    }
}

/// One reminder: on or off, minutes ahead (for the early ones), its sound, Fade in, and ▶.
struct ReminderSection: View {
    @Environment(AppModel.self) private var model
    let spec: Specs.ReminderSpec
    var example: String? = nil
    @Binding var reminder: Reminder
    /// Shows the settings without letting them change (a block using its type's reminders).
    var readOnly = false

    var body: some View {
        Section {
            Toggle(isOn: $reminder.on.animation(.snappy)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.label)
                    if let example { Text(example).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .disabled(readOnly)
            if reminder.on {
                if spec.hasLead {
                    if readOnly {
                        LabeledContent("Minutes ahead", value: "\(reminder.lead ?? Specs.defaultLead) min")
                    } else {
                        Stepper(value: Binding(get: { reminder.lead ?? Specs.defaultLead }, set: { reminder.lead = $0 }), in: 1...60) {
                            LabeledContent("Minutes ahead", value: "\(reminder.lead ?? Specs.defaultLead) min")
                        }
                    }
                }
                if readOnly {
                    LabeledContent("Sound", value: model.soundName(reminder.sound))
                } else {
                    NavigationLink {
                        SoundPickerView(title: spec.label, sound: $reminder.sound, fade: reminder.fade, fallback: spec.sound)
                    } label: {
                        LabeledContent("Sound", value: model.soundName(reminder.sound))
                    }
                }
                Toggle(isOn: $reminder.fade) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fade in")
                        Text("Starts quiet and grows to your volume").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(readOnly)
                Button {
                    model.preview(reminder.sound, fade: reminder.fade, fallback: spec.sound)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
            }
        }
    }
}

/// The sound menu: built-ins first, then your clips. Choosing one plays it.
struct SoundPickerView: View {
    @Environment(AppModel.self) private var model
    let title: String
    @Binding var sound: String
    let fade: Bool
    let fallback: String

    var body: some View {
        List {
            Section("Built-in") {
                ForEach(Specs.builtinSounds) { s in row(s.id, s.name) }
            }
            if !model.clips.isEmpty {
                Section("Your clips") {
                    ForEach(model.clips) { c in row(c.soundId, c.name) }
                }
            }
            Section {
            } footer: {
                Text("Previews play even when your iPhone is on silent. Reminders follow your ringer and the silent switch.")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: sound)
        .onDisappear { SoundPlayer.shared.stop() }
    }

    func row(_ id: String, _ name: String) -> some View {
        Button {
            sound = id
            model.preview(id, fade: fade, fallback: fallback)
        } label: {
            HStack {
                Text(name).foregroundStyle(.primary)
                Spacer()
                if sound == id { Image(systemName: "checkmark").foregroundStyle(Palette.accent).fontWeight(.semibold) }
            }
        }
    }
}
