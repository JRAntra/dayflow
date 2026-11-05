import DayFlowCore
import SwiftUI

/// What an import would do, before anything changes: the file's blocks, new types, and any
/// sound problems. Replace backs up your current schedule first.
struct ImportPreviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let preview: ImportPreview
    var replaceTitle = "Replace schedule"
    let apply: (_ applySettings: Bool) -> Void

    @State private var applySettings = true

    var body: some View {
        let unplayable = model.unplayableClips(in: preview)
        NavigationStack {
            List {
                Section {
                    Text(summary).font(.subheadline)
                    if preview.hasSettings {
                        Toggle(preview.isBackup ? "Also restore block types and reminder settings" : "Also use the file's reminder settings",
                               isOn: $applySettings)
                    }
                } footer: {
                    if preview.hasSettings {
                        Text(preview.isBackup
                             ? "Restores the backup's block types exactly, with their reminders, sounds and volume."
                             : "The file's Default matches your Default; other types match by name. Off keeps your own reminders.")
                    }
                }

                if !preview.problems.isEmpty || !unplayable.isEmpty {
                    Section("Sounds") {
                        ForEach(preview.problems, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.sun) }
                        ForEach(unplayable, id: \.id) { c in
                            Label("The iPhone can't play \"\(c.name)\", so \(c.slots) will use the starting sound.",
                                  systemImage: "speaker.slash").foregroundStyle(Palette.sun)
                        }
                    }
                    .font(.footnote)
                }

                if !preview.newTypes.isEmpty {
                    Section("New block types") {
                        Text(preview.newTypes.joined(separator: ", ")).font(.subheadline)
                    }
                }

                Section("\(preview.blocks.count) block\(preview.blocks.count == 1 ? "" : "s")") {
                    ForEach(Array(preview.blocks.enumerated()), id: \.offset) { _, p in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.block.title).font(.body.weight(.medium))
                            Text("\(p.block.isMoment ? "\(BlockRow.time(p.block.startMin)), a moment" : "\(BlockRow.time(p.block.startMin)) – \(BlockRow.time(p.block.endMin))") · \(ScheduleEdits.daysText(p.block.days)) · \(p.typeName)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(preview.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(replaceTitle) {
                        apply(preview.hasSettings && applySettings)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    var summary: String {
        let n = preview.blocks.count
        let blocks = "\(n) block\(n == 1 ? "" : "s")"
        if preview.current == 0 { return "This adds \(blocks)." }
        return "This replaces your \(preview.current) block\(preview.current == 1 ? "" : "s") with \(blocks). Your current schedule is backed up first."
    }
}

/// The newest ten backups, made before every import. They're also in the Files app, under
/// On My iPhone › DayFlow › Backups. Tap one to restore it; share one to send it to your Mac.
struct BackupsView: View {
    @Environment(AppModel.self) private var model
    let restore: (URL) -> Void
    @State private var share: URL?
    @State private var list: [URL] = []

    var body: some View {
        List {
            Section {
                if list.isEmpty {
                    Text("No backups yet. DayFlow makes one before every import.").foregroundStyle(.secondary)
                }
                ForEach(list, id: \.self) { url in
                    HStack {
                        Button { restore(url) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Self.title(url)).foregroundStyle(.primary)
                                Text("Tap to see what restoring it would change").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button { share = url } label: { Image(systemName: "square.and.arrow.up") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Share backup")
                    }
                }
            } footer: {
                Text("DayFlow keeps the newest \(DataStore.maxBackups). You'll also find them in the Files app, under On My iPhone › DayFlow › Backups.")
            }
        }
        .navigationTitle("Backups")
        .onAppear { list = model.backups() }
        .sheet(item: Binding(get: { share.map { ShareURL(url: $0) } }, set: { share = $0?.url })) { s in
            ShareSheet(items: [s.url]).presentationDetents([.medium, .large])
        }
    }

    /// "Wednesday 4 Nov, 3:15 PM" from schedule-2026-11-04-151502-123.json.
    static func title(_ url: URL) -> String {
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-")
        guard parts.count >= 5, let y = Int(parts[1]), let m = Int(parts[2]), let d = Int(parts[3]), parts[4].count == 6,
              let hh = Int(parts[4].prefix(2)), let mm = Int(parts[4].dropFirst(2).prefix(2)),
              let date = Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: hh, minute: mm)) else {
            return url.lastPathComponent
        }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).hour().minute())
    }

    private struct ShareURL: Identifiable { let url: URL; var id: String { url.path } }
}
