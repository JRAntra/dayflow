import DayFlowCore
import SwiftUI

/// Editing one block: name, type, times, length, days and its reminders. Save stays off until
/// the block has a name, ends after it starts (unless it's a moment, with no end) and has at
/// least one day, the Mac's checks. From the day view, a block that repeats on several days asks
/// whether the change is for that day only.
///
/// The Type menu starts with Own reminders: the block's reminder rows are then editable for this
/// block alone (starting as a copy of its type's). With a type, the rows show that type's
/// settings, read-only.
///
/// "Ring even on silent" (iOS 26 and later) turns every reminder of the block into an alarm.
/// The first time it's turned on, iOS asks whether DayFlow may set alarms.
struct BlockEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let editing: BlockEditing

    @State private var block: Block
    @State private var askDays = false
    @State private var askDelete = false
    @State private var newTypeId: String?
    @State private var askUseType: String?
    /// The end it had before Ends was switched off, so switching it back on restores it.
    @State private var lastEnd: String?
    /// You turned Ring even on silent on, but alarms aren't allowed.
    @State private var alarmsRefused = false
    @FocusState private var nameFocused: Bool

    init(editing: BlockEditing) {
        self.editing = editing
        _block = State(initialValue: editing.block)
    }

    var isNew: Bool { editing.original == nil }
    var problem: String? { ScheduleEdits.problem(block) }
    var dayChoiceNeeded: Bool {
        guard let day = editing.day, let original = editing.original else { return false }
        return ScheduleEdits.needsDayChoice(original, day: day)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $block.title)
                        .font(.title3)
                        .focused($nameFocused)
                        .submitLabel(.done)
                    Picker("Type", selection: typeBinding) {
                        Text("Own reminders").tag(Specs.ownType)
                        Divider()
                        ForEach(model.types) { t in Text(t.name).tag(t.id) }
                        Divider()
                        Text("New type…").tag(Self.newTypeTag)
                    }
                }

                Section {
                    DatePicker("Starts", selection: timeBinding(\.start), displayedComponents: .hourAndMinute)
                    Toggle(isOn: endsBinding.animation(.snappy)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ends")
                            if block.isMoment { Text("No end (a moment)").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if !block.isMoment {
                        DatePicker("Ends at", selection: timeBinding(\.end), displayedComponents: .hourAndMinute)
                        LabeledContent("Length", value: block.lengthMin > 0 ? TimeText.length(minutes: block.lengthMin) : "—")
                    }
                } footer: {
                    if block.isMoment { Text("A moment happens at its start time and doesn't last. It gets a Start preparation and a Start reminder.") }
                }

                Section("Repeats on") {
                    DayToggles(days: $block.days)
                        .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8))
                    if dayChoiceNeeded {
                        Text("You're looking at \(ScheduleEdits.dayNames[editing.day!]). When you save, you can change just that day or every day.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if let problem {
                    Section { Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.subheadline) }
                } else if let overlap = ScheduleEdits.overlapText(block, in: model.blocks) {
                    Section {
                        Label("\(overlap). Overlapping blocks are allowed.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Palette.sun).font(.subheadline)
                    }
                }

                reminderSections

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            if editing.day != nil && editing.original!.days.count > 1 { askDelete = true } else { delete(day: nil) }
                        } label: { Text("Delete block").frame(maxWidth: .infinity) }
                    }
                }
            }
            .navigationTitle(isNew ? "New block" : "Edit block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { dayChoiceNeeded && changed ? (askDays = true) : save(allDays: true) }
                        .fontWeight(.semibold)
                        .disabled(problem != nil)
                }
            }
            .confirmationDialog("Change \(block.title)", isPresented: $askDays, titleVisibility: .visible) {
                Button("This day only") { save(allDays: false) }
                Button("All \(editing.original?.days.count ?? 0) days") { save(allDays: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(editing.original?.title ?? "This block") repeats on \(ScheduleEdits.daysText(editing.original?.days ?? [])).")
            }
            .confirmationDialog("Delete \(block.title)", isPresented: $askDelete, titleVisibility: .visible) {
                Button("Remove from \(ScheduleEdits.dayNames[editing.day ?? 0])s only", role: .destructive) { delete(day: editing.day) }
                Button("Delete from all \(editing.original?.days.count ?? 0) days", role: .destructive) { delete(day: nil) }
                Button("Cancel", role: .cancel) {}
            }
            .navigationDestination(item: $newTypeId) { id in TypeDetailView(typeId: id) }
            .confirmationDialog(askUseType.map { "Use \(model.typeOf($0).name)'s reminders instead?" } ?? "",
                                isPresented: Binding(get: { askUseType != nil }, set: { if !$0 { askUseType = nil } }),
                                titleVisibility: .visible, presenting: askUseType) { id in
                Button("Use \(model.typeOf(id).name)'s reminders", role: .destructive) { useType(id) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This block's own reminder settings are removed.")
            }
            .onAppear { if isNew { nameFocused = true } }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(changed)
    }

    static let newTypeTag = "__new"

    var changed: Bool { editing.original.map { $0 != block } ?? true }

    /// Picking "New type…" adds a type and opens its reminders; the block uses it. Own reminders
    /// starts from a copy of the type's; leaving Own reminders for a type asks first.
    var typeBinding: Binding<String> {
        Binding(get: { block.type }, set: { id in
            if id == Self.newTypeTag {
                if let t = model.addType() { useType(t.id); newTypeId = t.id }
            } else if id == Specs.ownType {
                if !block.hasOwnReminders {
                    block.reminders = model.typeOf(block.type).reminders
                    block.type = Specs.ownType
                }
            } else if block.hasOwnReminders {
                askUseType = id
            } else {
                block.type = id
            }
        })
    }

    func useType(_ id: String) {
        block.type = id
        block.reminders = nil
    }

    /// Ends on: a block with an end time. Off: a moment.
    var endsBinding: Binding<Bool> {
        Binding(get: { !block.isMoment }, set: { on in
            if on {
                block.end = lastEnd.flatMap { HHMM.minutes($0).map { $0 > block.startMin } == true ? $0 : nil }
                    ?? HHMM.string(min(block.startMin + 30, 23 * 60 + 59))
            } else {
                lastEnd = block.end
                block.end = ""
            }
        })
    }

    /// The block's reminders: editable with Own reminders, otherwise its type's, read-only.
    /// A moment has only Start preparation and Start.
    @ViewBuilder var reminderSections: some View {
        let keys: [TypeReminderKey] = block.isMoment ? [.prep, .start] : TypeReminderKey.allCases
        let own = block.hasOwnReminders
        let source = own ? (block.reminders ?? Specs.startingTypeReminders) : model.typeOf(block.type).reminders
        Section {
            if model.alarmAccess != .unsupported { ringRows }
        } header: {
            Text("Reminders")
        } footer: {
            Text(own ? "Set just for this block." : "From the \(model.typeOf(block.type).name) type. Change it in Settings › Block types, or choose Own reminders above.")
        }
        ForEach(keys, id: \.self) { key in
            ReminderSection(spec: Specs.spec(key), reminder: Binding(
                get: { source[key] },
                set: { r in
                    guard block.hasOwnReminders else { return }
                    var all = block.reminders ?? Specs.startingTypeReminders
                    all[key] = r
                    block.reminders = all
                }), readOnly: !own)
        }
    }

    /// The switch, and why it can't ring when alarms aren't allowed.
    @ViewBuilder var ringRows: some View {
        Toggle(isOn: ringBinding) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ring even on silent")
                Text("Each reminder rings like an alarm, through silent mode and Focus, until you tap Stop.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("ring-on-silent")
        if model.alarmAccess == .denied && (block.ringsOnSilent || alarmsRefused) {
            VStack(alignment: .leading, spacing: 8) {
                Label(block.ringsOnSilent
                      ? "Alarms are off in Settings. Until you allow them, this block's reminders are normal reminders, quiet on silent."
                      : "DayFlow isn't allowed to set alarms. Turn on Alarms in Settings › Apps › DayFlow, then turn this on again.",
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(Palette.sun)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.footnote.weight(.semibold))
            }
            .accessibilityIdentifier("alarms-off-note")
        }
    }

    /// Turning it on asks for alarms the first time; if they aren't allowed it turns back off.
    var ringBinding: Binding<Bool> {
        Binding(get: { block.ringsOnSilent }, set: { on in
            block.ringsOnSilent = on
            guard on else { return }
            Task {
                if await !model.allowAlarms() {
                    withAnimation { block.ringsOnSilent = false; alarmsRefused = true }
                }
            }
        })
    }

    func timeBinding(_ key: WritableKeyPath<Block, String>) -> Binding<Date> {
        Binding(get: {
            let m = HHMM.minutes(block[keyPath: key]) ?? 0
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            block[keyPath: key] = HHMM.string((c.hour ?? 0) * 60 + (c.minute ?? 0))
        })
    }

    func save(allDays: Bool) {
        var b = block
        b.title = b.title.trimmingCharacters(in: .whitespacesAndNewlines)
        model.saveBlock(b, original: editing.original, day: editing.day, allDays: allDays)
        dismiss()
    }

    func delete(day: Int?) {
        guard let original = editing.original else { return }
        model.deleteBlock(original, day: day)
        dismiss()
    }
}
