import DayFlowCore
import SwiftUI
import UniformTypeIdentifiers

/// Sounds: mute, volume, and your own clips, which live in the Clips folder
/// (Files › On My iPhone › DayFlow › Clips).
struct SoundsSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var volume: Double = 80
    @State private var choosing = false
    @State private var recording = false
    @State private var showHelp = false
    @State private var renaming: CustomClip?
    @State private var newName = ""
    @State private var removing: CustomClip?

    static let clipTypes: [UTType] = ["mp3", "wav", "m4a", "aac", "ogg"].compactMap { UTType(filenameExtension: $0) } + [.audio]

    var body: some View {
        Form {
            Section {
                Toggle("Play sounds", isOn: Binding(get: { model.settings.sound }, set: { v in model.update { $0.sound = v } }))
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Volume")
                        Spacer()
                        Text("\(Int(volume))%").foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: $volume, in: 0...100, step: 1) {
                        Text("Volume")
                    } minimumValueLabel: {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    } onEditingChanged: { editing in
                        if !editing {
                            model.update { $0.volume = Int(volume) }
                            let r = model.typeOf(Specs.defaultType).reminders.start
                            model.preview(r.sound, fade: false)
                        }
                    }
                }
                .disabled(!model.settings.sound)
            } footer: {
                Text("Reminders play at your ringer volume; this sets how loud DayFlow is within it. It can make sounds quieter than the ringer, never louder. With the silent switch on, reminders vibrate without a sound.")
            }

            Section {
                ForEach(model.clips) { c in clipRow(c) }
                ForEach(model.folderFiles) { f in folderRow(f) }
                Menu {
                    Button { recording = true } label: { Label("Record a clip…", systemImage: "mic") }
                    Button { choosing = true } label: { Label("Choose a file…", systemImage: "folder") }
                    Divider()
                    Button { showHelp = true } label: { Label("How do I add music?", systemImage: "questionmark.circle") }
                } label: {
                    // The whole row opens the menu, not just its words.
                    Label("Add a clip", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
            } header: {
                Text("Your clips")
            } footer: {
                Text("Your clips are in the Files app, under On My iPhone › DayFlow › Clips. Tap a clip to hear it; touch and hold to rename or remove it.")
            }
        }
        .navigationTitle("Sounds")
        .onAppear {
            volume = Double(model.settings.volume)
            model.scanClips()
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: Self.clipTypes) { result in
            switch result {
            case .success(let url): model.addClip(from: url)
            case .failure(let error): model.showError(error)
            }
        }
        .sheet(isPresented: $recording) { RecorderSheet() }
        .sheet(isPresented: $showHelp) { ClipsHelpSheet() }
        // `presenting` hands the clip to the buttons: the alert clears `renaming` as it closes,
        // which can happen before a button's action runs.
        .alert("Rename clip", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { c in
            TextField("Name", text: $newName)
            Button("Rename") { model.renameClip(c.id, to: newName) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The file in the Clips folder is renamed too. Reminders that use this clip keep it.")
        }
        .confirmationDialog(removing.map { "Remove \"\($0.name)\"?" } ?? "", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { c in
            Button("Remove", role: .destructive) { model.removeClip(c.id) }
        } message: { _ in
            Text("Its file is deleted from the Clips folder. Reminders that use it go back to their starting sound.")
        }
    }

    func clipRow(_ c: CustomClip) -> some View {
        Button { model.preview(c.soundId, fade: false) } label: {
            HStack {
                Image(systemName: "waveform").foregroundStyle(Palette.accent)
                Text(c.name).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "play.fill").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(c.name)
        .accessibilityHint("Plays the clip")
        .contextMenu {
            Button { newName = c.name; renaming = c } label: { Label("Rename…", systemImage: "pencil") }
            Button(role: .destructive) { removing = c } label: { Label("Remove", systemImage: "trash") }
        }
        .swipeActions {
            Button(role: .destructive) { removing = c } label: { Label("Remove", systemImage: "trash") }
            Button { newName = c.name; renaming = c } label: { Label("Rename", systemImage: "pencil") }.tint(.gray)
        }
    }

    @ViewBuilder func folderRow(_ f: FolderFile) -> some View {
        switch f.problem {
        case .needsPiece:
            Button { model.choosePiece(of: f) } label: {
                HStack {
                    Image(systemName: "scissors").foregroundStyle(Palette.sun)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.name).foregroundStyle(.primary)
                        Text("Too long: \(f.message)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityHint("Opens Choose 30 seconds")
        case .unusable:
            HStack {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.file).foregroundStyle(.secondary)
                    Text(f.message).font(.caption).foregroundStyle(.secondary)
                }
            }
            .swipeActions {
                Button(role: .destructive) { model.deleteFolderFile(f) } label: { Label("Delete file", systemImage: "trash") }
            }
        }
    }
}

/// "How do I add music?"
struct ClipsHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Add your own sounds") {
                    help("mic", "Record one", "Add a clip → Record a clip.")
                    help("folder", "From Files, iCloud Drive or Mail", "Add a clip → Choose a file, or tap Share on the file and choose DayFlow.")
                    help("laptopcomputer.and.iphone", "From your Mac", "AirDrop the file to your iPhone and choose DayFlow.")
                    help("folder.badge.plus", "The Clips folder", "In the Files app: On My iPhone → DayFlow → Clips. Anything you put there shows up here the next time you open Sounds.")
                    help("waveform.circle", "Voice Memos", "Open the memo → Share → DayFlow.")
                }
                Section("What works") {
                    Text("mp3, wav, m4a, aac or ogg files. Clips play for up to 30 seconds; for a longer song, you choose which 30 seconds to use, and the full song moves to Clips → Originals.")
                }
                Section("What doesn't") {
                    Text("Songs from the Music app or Apple Music. They're protected, so no other app can play them. You need an actual audio file.")
                }
            }
            .navigationTitle("How do I add music?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    func help(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Palette.accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
