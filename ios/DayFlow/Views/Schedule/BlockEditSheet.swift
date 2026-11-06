import DayFlowCore
import SwiftUI

/// Editing one event or block. The control at the top switches between them: an event has a
/// time, days and one alarm; a block has a type, start and end times, days and four reminders.
/// Save stays off until it has a name, (for a block) ends after it starts, and has at least one
/// day, the Mac's checks. From the day view, a block that repeats on several days asks whether
/// the change is for that day only.
///
/// A block's reminders are its type's: the Reminders section shows them in one line, and opens
/// the type to change them.
///
/// An event always rings as an alarm (iOS 26 and later); "Ring even on silent" does the same
/// for every reminder of a block. The first time either needs alarms, iOS asks.
///
/// An event from a repeat arrives here only through "Edit only this one": it's already been
/// taken out of its repeat, and saving keeps it that way.
struct BlockEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let editing: BlockEditing

    @State private var block: Block
    @State private var askDays = false
    @State private var askDelete = false
    @State private var newTypeId: String?
    /// The type whose reminders you opened from the Reminders section.
    @State private var openType: String?
    /// The block it was before you switched it to an event, so switching back restores it.
    @State private var asBlock: Block?
    @State private var asEvent: Block?
    /// You turned Ring even on silent on, but alarms aren't allowed.
    @State private var alarmsRefused = false
    @FocusState private var nameFocused: Bool

    init(editing: BlockEditing) {
        self.editing = editing
        _block = State(initialValue: editing.block)
    }

    var isNew: Bool { editing.original == nil }
    var noun: String { block.isEvent ? "event" : "block" }
    var problem: String? { ScheduleEdits.problem(block) }
    /// Taken out of its repeat ("Edit only this one").
    var leavingRepeat: Bool { editing.original?.isRepeat == true }
    var dayChoiceNeeded: Bool {
        guard let day = editing.day, let original = editing.original, !leavingRepeat else { return false }
        return ScheduleEdits.needsDayChoice(original, day: day)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kind", selection: kindBinding.animation(.snappy)) {
                        Label("Event", systemImage: "bell.fill").tag(true)
                        Label("Block", systemImage: "rectangle.fill").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("kind")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    TextField("Name", text: $block.title)
                        .font(.title3)
                        .focused($nameFocused)
                        .submitLabel(.done)
                    if !block.isEvent {
                        Picker("Type", selection: typeBinding) {
                            ForEach(model.types) { t in Text(t.name).tag(t.id) }
                            Divider()
                            Text("New type…").tag(Self.newTypeTag)
                        }
                    }
                } footer: {
                    if leavingRepeat { Text("Saving takes this event out of its repeat, so changes to the repeat won't touch it.") }
                }

                Section {
                    if block.isEvent {
                        DatePicker("At", selection: timeBinding(\.start), displayedComponents: .hourAndMinute)
                    } else {
                        DatePicker("Starts", selection: timeBinding(\.start), displayedComponents: .hourAndMinute)
                        DatePicker("Ends", selection: timeBinding(\.end), displayedComponents: .hourAndMinute)
                        LabeledContent("Length", value: block.lengthMin > 0 ? TimeText.length(minutes: block.lengthMin) : "—")
                    }
                } footer: {
                    if block.isEvent { Text("An event happens at its time and rings once.") }
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

                if block.isEvent { alarmSection } else { reminderSections }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            if editing.day != nil && editing.original!.days.count > 1 && !leavingRepeat { askDelete = true } else { delete(day: nil) }
                        } label: { Text("Delete \(noun)").frame(maxWidth: .infinity) }
                    }
                }
            }
            .navigationTitle(isNew ? "New \(noun)" : "Edit \(noun)")
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
            .navigationDestination(item: $openType) { id in TypeDetailView(typeId: id) }
            .onAppear { if isNew { nameFocused = true } }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(changed)
    }

    static let newTypeTag = "__new"

    var changed: Bool { editing.original.map { $0 != block } ?? true }

    /// Event or block. Switching back and forth keeps what each one had.
    var kindBinding: Binding<Bool> {
        Binding(get: { block.isEvent }, set: { toEvent in
            guard toEvent != block.isEvent else { return }
            if toEvent {
                asBlock = block
                var e = asEvent ?? ScheduleEdits.switched(block, toEvent: true, types: model.types)
                e.title = block.title; e.start = block.start; e.days = block.days
                block = e
            } else {
                asEvent = block
                var b = asBlock ?? ScheduleEdits.switched(block, toEvent: false, types: model.types)
                b.title = block.title; b.days = block.days
                if asBlock != nil {
                    // Keep its length, from the event's time.
                    b = ScheduleEdits.moved(b, by: block.startMin - b.startMin)
                }
                block = b
            }
        })
    }

    /// Picking "New type…" adds a type and opens its reminders; the block uses it.
    var typeBinding: Binding<String> {
        Binding(get: { block.type }, set: { id in
            if id == Self.newTypeTag {
                if let t = model.addType() { block.type = t.id; newTypeId = t.id }
            } else {
                block.type = id
            }
        })
    }

    /// An event's one alarm: its sound or sounds, and fade.
    @ViewBuilder var alarmSection: some View {
        ReminderSection(spec: Specs.eventSpec, reminder: $block.eventAlert, alwaysOn: true)
        Section {
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if model.alarmAccess == .unsupported {
                    Text("It rings as a normal reminder: it follows the silent switch and Focus.")
                } else {
                    Text("It rings like an alarm, through silent mode and Focus, until you tap Stop, or Done to check it off.")
                }
                if model.alarmAccess == .denied {
                    Label("DayFlow isn't allowed to set alarms, so events are normal reminders, quiet on silent. Turn on Alarms in Settings › Apps › DayFlow.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Palette.sun)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("alarms-off-note")
                }
            }
        }
    }

    /// The block's reminders: its type's, in one line that opens the type to change them.
    @ViewBuilder var reminderSections: some View {
        let t = model.typeOf(block.type)
        Section {
            if model.alarmAccess != .unsupported { ringRows }
            Button { openType = t.id } label: {
                LabeledContent {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("From the \(t.name) type").foregroundStyle(.primary)
                        Text(Self.summary(t.reminders)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("type-reminders")
        } header: {
            Text("Reminders")
        } footer: {
            Text("Changing them changes every \(t.name) block. For different reminders, choose another type, or New type….")
        }
    }

    /// "Start, Heads-up 5 min before the end, Time's up".
    static func summary(_ r: TypeReminders) -> String {
        var parts: [String] = []
        if r.prep.on { parts.append("Get ready \(r.prep.lead ?? Specs.defaultLead) min before") }
        if r.start.on { parts.append("Start") }
        if r.warn.on { parts.append("Heads-up \(r.warn.lead ?? Specs.defaultLead) min before the end") }
        if r.end.on { parts.append("Time's up") }
        return parts.isEmpty ? "No reminders" : parts.joined(separator: ", ")
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
        // The first event asks whether DayFlow may set alarms.
        if b.isEvent && model.alarmAccess == .notDetermined { Task { _ = await model.allowAlarms(); model.refreshSoon() } }
        dismiss()
    }

    func delete(day: Int?) {
        guard let original = editing.original else { return }
        model.deleteBlock(original, day: day)
        dismiss()
    }
}

/// What the repeat sheet is editing: a new repeat, or every event of an existing one.
struct RepeatEditing: Identifiable {
    let id = UUID()
    var title: String
    var days: [Int]
    var alert: Reminder
    var rule: RepeatRule
    var isNew: Bool

    /// Editing the repeat an event belongs to.
    init(event e: Block) {
        title = e.title; days = e.days; alert = e.eventAlert
        rule = e.series ?? RepeatRule(first: e.start, last: e.start, every: 30)
        isNew = false
    }

    /// A new repeat: 9:00 to 17:00, every 30 minutes, to start from.
    init(days: [Int], alert: Reminder) {
        title = ""; self.days = days; self.alert = alert
        rule = RepeatRule(first: "09:00", last: "17:00", every: 30)
        isNew = true
    }
}

/// A repeated event: a name, days, sound, and First at, Last at and Every. Save shows what it
/// makes ("Create 17 events: 9:00, 9:30 … 17:00?") before making it. Saving an existing repeat
/// makes its events again.
struct RepeatEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let editing: RepeatEditing

    @State private var title: String
    @State private var days: [Int]
    @State private var alert: Reminder
    @State private var rule: RepeatRule
    @State private var every: String
    @State private var confirming = false
    @State private var askDelete = false
    @FocusState private var nameFocused: Bool

    init(editing: RepeatEditing) {
        self.editing = editing
        _title = State(initialValue: editing.title)
        _days = State(initialValue: editing.days)
        _alert = State(initialValue: editing.alert)
        _rule = State(initialValue: editing.rule)
        _every = State(initialValue: String(editing.rule.every))
    }

    var current: RepeatRule { var r = rule; r.every = Int(every.trimmingCharacters(in: .whitespaces)) ?? 0; return r }
    var times: [Int] { ScheduleEdits.repeatTimes(current) }
    var problem: String? { ScheduleEdits.repeatProblem(title: title, days: days, rule: current) }
    var existing: Int { ScheduleEdits.repeatEvents(rule.id, in: model.blocks).count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $title)
                        .font(.title3)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .accessibilityIdentifier("repeat-name")
                } footer: {
                    if !editing.isNew { Text("Changes apply to all \(existing) events of this repeat. They're made again when you save.") }
                }

                Section {
                    DatePicker("First at", selection: time(\.first), displayedComponents: .hourAndMinute)
                    DatePicker("Last at", selection: time(\.last), displayedComponents: .hourAndMinute)
                    LabeledContent("Every") {
                        HStack(spacing: 6) {
                            TextField("30", text: $every)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 70)
                                .accessibilityIdentifier("repeat-every")
                            Text("min").foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    if problem == nil, let first = times.first, let last = times.last {
                        Text("\(times.count) events: \(BlockRow.time(first)), \(BlockRow.time(times[1]))\(times.count > 2 ? " … " : ", ")\(times.count > 2 ? BlockRow.time(last) : "").")
                            .accessibilityIdentifier("repeat-count")
                    }
                }

                Section("Repeats on") {
                    DayToggles(days: $days)
                        .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8))
                }

                if let problem {
                    Section { Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.subheadline) }
                }

                ReminderSection(spec: Specs.eventSpec, reminder: $alert, alwaysOn: true)
                Section {
                } footer: {
                    Text(model.alarmAccess == .unsupported ? "Each event rings once, as a normal reminder."
                         : "Each event rings once, like an alarm, through silent mode and Focus, until you tap Stop, or Done to check it off.")
                }

                if !editing.isNew {
                    Section {
                        Button(role: .destructive) { askDelete = true } label: {
                            Text("Delete all \(existing) events").frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(editing.isNew ? "New repeated event" : "Edit repeat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing.isNew ? "Create" : "Save") { confirming = true }
                        .fontWeight(.semibold)
                        .disabled(problem != nil)
                }
            }
            .alert(confirmTitle, isPresented: $confirming) {
                Button(editing.isNew ? "Create" : "Save") { save() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(confirmMessage)
            }
            .confirmationDialog("Delete all \(existing) \(editing.title) events?", isPresented: $askDelete, titleVisibility: .visible) {
                Button("Delete all \(existing) events", role: .destructive) { model.deleteRepeat(rule.id); dismiss() }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear { if editing.isNew { nameFocused = true } }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
    }

    var confirmTitle: String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return editing.isNew ? "Create \(times.count) \u{201C}\(name)\u{201D} events?" : "Make \(times.count) \u{201C}\(name)\u{201D} events?"
    }

    /// "On weekdays: 9:00 AM, 9:30 AM … 5:00 PM", and a warning when they need more alarms than
    /// DayFlow sets ahead.
    var confirmMessage: String {
        guard let first = times.first, let last = times.last else { return "" }
        var lines = ["\(ScheduleEdits.daysText(days)): \(BlockRow.time(first)), \(BlockRow.time(times[1]))\(times.count > 2 ? " … \(BlockRow.time(last))" : "")."]
        if !editing.isNew { lines.append("The \(existing) events it has now are replaced.") }
        let perWeek = times.count * days.count
        if model.alarmAccess != .unsupported && perWeek > Planner.alarmLimit {
            lines.append("That's \(perWeek) alarms a week. DayFlow sets the next \(Planner.alarmLimit) ahead and adds more each time it runs, so open DayFlow at least every couple of days.")
        }
        return lines.joined(separator: "\n\n")
    }

    func time(_ key: WritableKeyPath<RepeatRule, String>) -> Binding<Date> {
        Binding(get: {
            let m = HHMM.minutes(rule[keyPath: key]) ?? 0
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            rule[keyPath: key] = HHMM.string((c.hour ?? 0) * 60 + (c.minute ?? 0))
        })
    }

    func save() {
        var a = alert
        a.on = true
        model.saveRepeat(title: title.trimmingCharacters(in: .whitespacesAndNewlines), days: days, alert: a, rule: current,
                         isNew: editing.isNew)
        if model.alarmAccess == .notDetermined { Task { _ = await model.allowAlarms(); model.refreshSoon() } }
        dismiss()
    }
}
