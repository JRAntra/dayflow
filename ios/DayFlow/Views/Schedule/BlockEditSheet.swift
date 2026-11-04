import DayFlowCore
import SwiftUI

/// Editing one block: name, type, times, length and days. Save stays off until the block has a
/// name, ends after it starts and has at least one day, the Mac's checks. From the day view, a
/// block that repeats on several days asks whether the change is for that day only.
struct BlockEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let editing: BlockEditing

    @State private var block: Block
    @State private var askDays = false
    @State private var askDelete = false
    @State private var newTypeId: String?
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
                        ForEach(model.types) { t in Text(t.name).tag(t.id) }
                        Divider()
                        Text("New type…").tag(Self.newTypeTag)
                    }
                }

                Section {
                    DatePicker("Starts", selection: timeBinding(\.start), displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: timeBinding(\.end), displayedComponents: .hourAndMinute)
                    LabeledContent("Length", value: block.lengthMin > 0 ? TimeText.length(minutes: block.lengthMin) : "—")
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
            .onAppear { if isNew { nameFocused = true } }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(changed)
    }

    static let newTypeTag = "__new"

    var changed: Bool { editing.original.map { $0 != block } ?? true }

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
