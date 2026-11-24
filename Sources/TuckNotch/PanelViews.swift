import SwiftUI
import UniformTypeIdentifiers

struct EmptyCardLabel: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: DS.Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(DS.Palette.textSecondary)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DS.Palette.elevated))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DS.Typeface.bodyMedium).foregroundStyle(DS.Palette.textPrimary)
                Text(detail).font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Mute · Audio output · Keep awake · Presentation.
struct QuickControlsCard: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var mic: MicService
    @EnvironmentObject private var audio: AudioDeviceService
    @EnvironmentObject private var keepAwake: KeepAwakeService

    var body: some View {
        Card(padding: DS.Space.s) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.xs), GridItem(.flexible(), spacing: DS.Space.xs)],
                      spacing: DS.Space.xs) {
                if mic.available {
                    toggleTile(symbol: mic.isMuted ? "mic.slash.fill" : "mic.fill",
                               label: mic.isMuted ? "Muted" : "Mic on",
                               on: mic.isMuted, tint: DS.Palette.danger) { mic.toggle() }
                } else {
                    toggleTile(symbol: "mic.slash", label: "No mic control", on: false, tint: nil) {}
                        .disabled(true)
                }
                Menu {
                    ForEach(audio.outputs) { device in
                        Button {
                            audio.select(device)
                        } label: {
                            if device.id == audio.currentOutputID {
                                Label(device.name, systemImage: "checkmark")
                            } else {
                                Text(device.name)
                            }
                        }
                    }
                } label: {
                    tileLabel(symbol: "hifispeaker.fill", label: audio.currentOutput?.name ?? "Output", on: false, tint: nil)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .accessibilityLabel("Audio output, \(audio.currentOutput?.name ?? "unknown")")

                Menu {
                    ForEach(KeepAwakeService.durations) { option in
                        Button(option.label) { keepAwake.start(minutes: option.minutes) }
                    }
                    if keepAwake.isActive {
                        Divider()
                        Button("Turn Off") { keepAwake.stop() }
                    }
                } label: {
                    tileLabel(symbol: "cup.and.saucer.fill",
                              label: keepAwake.isActive ? "Awake \(keepAwake.remainingText ?? "")" : "Keep awake",
                              on: keepAwake.isActive, tint: DS.Palette.accent)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .accessibilityLabel(keepAwake.isActive ? "Keep awake on" : "Keep awake")

                toggleTile(symbol: settings.presentationMode ? "eye.slash.fill" : "eye",
                           label: "Present", on: settings.presentationMode, tint: DS.Palette.warning) {
                    settings.presentationMode.toggle()
                }
                .help("Hide the island's content and pause clipboard history")
            }
        }
    }

    private func toggleTile(symbol: String, label: String, on: Bool, tint: Color?, action: @escaping () -> Void) -> some View {
        Button(action: action) { tileLabel(symbol: symbol, label: label, on: on, tint: tint) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func tileLabel(symbol: String, label: String, on: Bool, tint: Color?) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            Text(label).font(.system(size: 10, weight: .medium)).lineLimit(1).truncationMode(.middle)
        }
        .foregroundStyle(on ? (tint ?? DS.Palette.textPrimary) : DS.Palette.textPrimary)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
            .fill(on ? DS.Palette.elevatedPressed : DS.Palette.elevated))
        .contentShape(Rectangle())
    }
}

// MARK: - Media

struct MediaView: View {
    @EnvironmentObject private var np: NowPlayingService
    @EnvironmentObject private var audio: AudioDeviceService
    @EnvironmentObject private var lyrics: LyricsService
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Group {
            if let track = np.track {
                HStack(alignment: .center, spacing: DS.Space.l) {
                    artwork
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).font(DS.Typeface.title).foregroundStyle(DS.Palette.textPrimary).lineLimit(1)
                            HStack(spacing: DS.Space.s) {
                                if !track.artist.isEmpty {
                                    Text(track.artist).font(DS.Typeface.body).foregroundStyle(DS.Palette.textSecondary).lineLimit(1)
                                }
                                sourceChip(track)
                            }
                        }
                        progress(track)
                        controls
                        if settings.lyricsEnabled && lyrics.state != .off {
                            lyricsStrip
                        } else {
                            volume
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if np.permissionDenied {
                VStack(spacing: DS.Space.m) {
                    Image(systemName: "lock.shield").font(.system(size: 24)).foregroundStyle(DS.Palette.warning)
                    Text("Tuck Notch needs permission to read Music or Spotify.")
                        .font(DS.Typeface.body).foregroundStyle(DS.Palette.textPrimary)
                    Button("Open Automation Settings") { np.openAutomationSettings() }
                        .buttonStyle(PillButtonStyle(prominent: true))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let browser = np.browsersNeedingSetup.first {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    EmptyCardLabel(symbol: "safari", title: "One setting needed for \(BrowserMediaProvider.shortBrowserName(browser.displayName))",
                                   detail: "Tuck Notch sees a media tab but the browser blocks it from reading what's playing.")
                    Text(browser.setupInstructions)
                        .font(DS.Typeface.caption).foregroundStyle(DS.Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 400)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: DS.Space.m) {
                    EmptyCardLabel(symbol: "music.note", title: "Nothing playing",
                                   detail: "Play something in \(NowPlayingService.supportedSourcesDescription).")
                        .frame(maxWidth: 380)
                    volume.frame(maxWidth: 340)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var artwork: some View {
        Group {
            if let image = np.artwork {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.Palette.surface)
            }
        }
        .frame(width: 140, height: 140)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .accessibilityHidden(true)
    }

    private func sourceChip(_ track: NowPlayingService.Track) -> some View {
        Label("Playing from \(track.sourceName)", systemImage: track.sourceName.hasPrefix("YouTube") ? "play.rectangle.fill" : "music.note")
            .font(DS.Typeface.caption)
            .foregroundStyle(DS.Palette.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, 2)
            .background(Capsule().fill(DS.Palette.elevated))
    }

    /// Current and next lyric line, following the song.
    private var lyricsStrip: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let index = lyrics.index(at: np.estimatedPosition(at: context.date))
            VStack(alignment: .leading, spacing: 2) {
                switch lyrics.state {
                case .loading:
                    Text("Finding lyrics…").foregroundStyle(DS.Palette.textSecondary)
                case .instrumental:
                    Text("♪ Instrumental").foregroundStyle(DS.Palette.textSecondary)
                case .notFound, .plainOnly, .off:
                    Text(lyrics.state == .plainOnly ? "No synced lyrics for this song" : "No lyrics found")
                        .foregroundStyle(DS.Palette.textSecondary)
                case .synced:
                    let current = index.map { lyrics.lines[$0].text } ?? "♪"
                    let next = index.map { $0 + 1 < lyrics.lines.count ? lyrics.lines[$0 + 1].text : "" }
                        ?? (lyrics.lines.first?.text ?? "")
                    Text(current.isEmpty ? "♪" : current)
                        .font(DS.Typeface.bodyMedium)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                        .id(current)
                        .transition(.opacity)
                    Text(next)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            .font(DS.Typeface.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(DS.Palette.surface))
            .animation(DS.Motion.content, value: index)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Lyrics")
        }
    }

    private func progress(_ track: NowPlayingService.Track) -> some View {
        TimelineView(.periodic(from: .now, by: np.isPlaying ? 0.5 : 60)) { context in
            let position = np.estimatedPosition(at: context.date)
            let fraction = track.duration > 0 ? min(1, position / track.duration) : 0
            VStack(spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.Palette.elevated)
                        Capsule().fill(DS.Palette.live).frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 4)
                HStack {
                    Text(Format.clock(position))
                    Spacer()
                    Text(track.duration > 0 ? "−" + Format.clock(max(0, track.duration - position)) : "Live")
                }
                .font(DS.Typeface.caption.monospacedDigit())
                .foregroundStyle(DS.Palette.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Position \(Format.clock(np.position)) of \(Format.clock(track.duration))")
    }

    private var controls: some View {
        HStack(spacing: DS.Space.xl) {
            Button { np.previous() } label: { Image(systemName: "backward.fill") }
                .accessibilityLabel("Previous track")
            Button { np.playPause() } label: {
                Image(systemName: np.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 22, weight: .semibold))
            }
            .accessibilityLabel(np.isPlaying ? "Pause" : "Play")
            .keyboardShortcut(.space, modifiers: [])
            Button { np.next() } label: { Image(systemName: "forward.fill") }
                .accessibilityLabel("Next track")
        }
        .font(.system(size: 17, weight: .semibold))
        .buttonStyle(IconButtonStyle(size: 36, tint: DS.Palette.textPrimary))
        .frame(maxWidth: .infinity)
    }

    private var volume: some View {
        HStack(spacing: DS.Space.s) {
            if np.volumeAvailable {
                volumeSlider
            } else {
                Text("This output has no volume control")
                    .font(DS.Typeface.caption)
                Spacer()
            }
            outputMenu
        }
        .foregroundStyle(DS.Palette.textSecondary)
    }

    private var volumeSlider: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "speaker.fill").font(.system(size: 11))
            Slider(
                value: Binding(get: { np.volume }, set: { np.setVolume($0) }),
                in: 0...100,
                onEditingChanged: { editing in np.isDraggingVolume = editing }
            )
            .controlSize(.small)
            .tint(DS.Palette.textPrimary)
            .accessibilityLabel("Volume")
            .accessibilityValue("\(Int(np.volume)) percent")
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 11))
        }
    }

    private var outputMenu: some View {
            Menu {
                ForEach(audio.outputs) { device in
                    Button(device.id == audio.currentOutputID ? "✓ \(device.name)" : device.name) { audio.select(device) }
                }
            } label: {
                Image(systemName: "airplayaudio")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: DS.Size.hit, height: DS.Size.hit)
            .help("Output: \(audio.currentOutput?.name ?? "Unknown")")
            .accessibilityLabel("Audio output, \(audio.currentOutput?.name ?? "unknown")")
    }
}

// MARK: - Shelf

struct ShelfView: View {
    @ObservedObject var vm: NotchViewModel
    @EnvironmentObject private var shelf: ShelfService

    var body: some View {
        Group {
            if shelf.items.isEmpty {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(vm.isDropTargeted ? DS.Palette.accent : DS.Palette.textSecondary.opacity(0.5))
                    .overlay {
                        VStack(spacing: DS.Space.s) {
                            Image(systemName: "tray.and.arrow.down").font(.system(size: 26, weight: .medium))
                                .foregroundStyle(DS.Palette.textPrimary)
                            Text("Drop files on the notch to keep them here")
                                .font(DS.Typeface.bodyMedium).foregroundStyle(DS.Palette.textPrimary)
                            Text("Drag them back out whenever you need them. Files stay where they are.")
                                .font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary)
                        }
                    }
            } else {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    HStack {
                        Text(shelf.items.count == 1 ? "1 item" : "\(shelf.items.count) items")
                            .font(DS.Typeface.captionMedium).foregroundStyle(DS.Palette.textSecondary)
                        Spacer()
                        Button { ShelfTools.airDrop(shelf.items) } label: { Label("AirDrop", systemImage: "airplayaudio") }
                            .buttonStyle(PillButtonStyle())
                            .help("Send everything on the shelf with AirDrop")
                        Button("Clear") { shelf.clear() }
                            .buttonStyle(PillButtonStyle())
                            .accessibilityLabel("Clear shelf")
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Space.s) {
                            ForEach(shelf.items, id: \.self) { url in ShelfItemView(url: url) }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ShelfItemView: View {
    let url: URL
    @EnvironmentObject private var shelf: ShelfService
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 52, height: 52)
            Text(url.lastPathComponent)
                .font(DS.Typeface.caption).foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(2).multilineTextAlignment(.center).frame(width: 88)
        }
        .padding(DS.Space.s)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
            .fill(hovering ? DS.Palette.elevated : DS.Palette.surface))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { shelf.remove(url) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(DS.Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .frame(width: DS.Size.hit, height: DS.Size.hit)
                .accessibilityLabel("Remove \(url.lastPathComponent) from shelf")
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { shelf.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { shelf.open(url) }
            Button("Show in Finder") { shelf.reveal(url) }
            Button("Copy Path") { shelf.copyPath(url) }
            Button("AirDrop…") { ShelfTools.airDrop([url]) }
            if ShelfTools.isConvertibleImage(url) {
                Menu("Convert to") {
                    ForEach(ShelfTools.Format.allCases, id: \.self) { format in
                        Button(format.label) { convert(format) }
                    }
                }
            }
            Divider()
            Button("Remove from Shelf") { shelf.remove(url) }
        }
        .help(url.path)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(url.lastPathComponent)
        .accessibilityHint("Drag out to use. Double-click to open.")
        .accessibilityAction(named: "Open") { shelf.open(url) }
        .accessibilityAction(named: "Show in Finder") { shelf.reveal(url) }
        .accessibilityAction(named: "Remove") { shelf.remove(url) }
        .accessibilityAction(named: "AirDrop") { ShelfTools.airDrop([url]) }
    }

    private func convert(_ format: ShelfTools.Format) {
        let source = url
        let shelf = shelf
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) { ShelfTools.convert(source, to: format) }.value
            if let result {
                shelf.add([result])
                A11y.announce("Converted to \(format.label)")
            } else {
                NSSound.beep()
            }
        }
    }
}

// MARK: - Clipboard

struct ClipboardView: View {
    @ObservedObject var vm: NotchViewModel
    @EnvironmentObject private var clip: ClipboardService
    @EnvironmentObject private var settings: AppSettings
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var filtered: [ClipboardService.Item] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let base = clip.items.sorted { a, b in a.pinned != b.pinned ? a.pinned : a.date > b.date }
        guard !q.isEmpty else { return base }
        return base.filter { $0.searchText.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: DS.Space.s) {
            HStack(spacing: DS.Space.s) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(DS.Palette.textSecondary)
                    TextField("Search clipboard", text: $query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .accessibilityLabel("Search clipboard history")
                }
                .font(DS.Typeface.body)
                .padding(.horizontal, DS.Space.s)
                .frame(height: DS.Size.hit)
                .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(DS.Palette.surface))

                Button { settings.clipboardPaused.toggle() } label: {
                    Image(systemName: settings.clipboardPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(IconButtonStyle(active: settings.clipboardPaused))
                .help(settings.clipboardPaused ? "Resume recording" : "Pause recording")
                .accessibilityLabel(settings.clipboardPaused ? "Resume clipboard recording" : "Pause clipboard recording")

                Button("Clear") { clip.clear() }
                    .buttonStyle(PillButtonStyle())
                    .disabled(!clip.items.contains { !$0.pinned })
                    .help("Clears history; pinned items stay")
                    .accessibilityLabel("Clear clipboard history")
            }

            if !clip.isRecording {
                Text(settings.presentationMode && !settings.clipboardPaused
                     ? "Paused while presentation mode is on."
                     : "Recording paused. New copies aren't saved.")
                    .font(DS.Typeface.caption).foregroundStyle(DS.Palette.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if filtered.isEmpty {
                Text(clip.items.isEmpty
                     ? "Copy text or an image and it shows up here. History stays in memory; only pinned text is saved."
                     : "No matches.")
                    .font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { item in ClipRow(item: item) }
                    }
                }
            }
        }
        .onChange(of: searchFocused) { focused in vm.pinned = focused }
    }
}

struct ClipRow: View {
    let item: ClipboardService.Item
    @EnvironmentObject private var clip: ClipboardService
    @EnvironmentObject private var settings: AppSettings
    @State private var hovering = false
    @State private var copied = false
    @State private var ocrRunning = false

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Button(action: copy) {
                HStack(spacing: DS.Space.s) {
                    thumbnail
                    Text(item.preview)
                        .font(DS.Typeface.body).foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: DS.Space.s)
                    if item.pinned {
                        Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(DS.Palette.live)
                            .accessibilityHidden(true)
                    }
                    Text(copied ? "Copied" : Format.ago(item.date))
                        .font(DS.Typeface.caption)
                        .foregroundStyle(copied ? DS.Palette.success : DS.Palette.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel((item.pinned ? "Pinned. " : "") + (item.isImage ? item.preview : "Text: \(item.preview)"))
            .accessibilityHint("Copies to the clipboard")

            if item.isImage {
                Button(action: ocr) {
                    if ocrRunning { ProgressView().controlSize(.small) } else { Image(systemName: "text.viewfinder") }
                }
                .buttonStyle(IconButtonStyle())
                .help("Copy text from image")
                .accessibilityLabel("Copy text from image")
            } else {
                Button { clip.togglePin(item) } label: { Image(systemName: item.pinned ? "pin.slash" : "pin") }
                    .buttonStyle(IconButtonStyle())
                    .opacity(hovering || item.pinned ? 1 : 0.35)
                    .help(item.pinned ? "Unpin" : "Pin (keeps it across launches)")
                    .accessibilityLabel(item.pinned ? "Unpin" : "Pin")
            }

            Button { clip.remove(item) } label: { Image(systemName: "xmark") }
                .buttonStyle(IconButtonStyle())
                .opacity(hovering ? 1 : 0.35)
                .accessibilityLabel("Delete item")
        }
        .padding(.horizontal, DS.Space.s)
        .frame(minHeight: 34)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
            .fill(hovering ? DS.Palette.surface : Color.clear))
        .onHover { hovering = $0 }
        .contextMenu {
            if let app = item.sourceApp, app != Bundle.main.bundleIdentifier, !settings.excludedApps.contains(app) {
                Button("Never Record From \(appName(app))") {
                    settings.excludedApps.append(app)
                    clip.remove(item)
                }
            }
            Button(item.pinned ? "Unpin" : "Pin") { clip.togglePin(item) }.disabled(item.isImage)
            Button("Delete") { clip.remove(item) }
        }
    }

    @ViewBuilder private var thumbnail: some View {
        switch item.content {
        case .text:
            Image(systemName: "text.alignleft").font(.system(size: 12)).foregroundStyle(DS.Palette.textSecondary)
                .frame(width: 22, height: 22)
        case .image(let image):
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }

    private func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func copy() {
        clip.copy(item)
        flash()
    }

    private func ocr() {
        ocrRunning = true
        clip.recognizeText(in: item) { ok in
            ocrRunning = false
            if ok { flash() }
        }
    }

    private func flash() {
        copied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            copied = false
        }
    }
}

// MARK: - Focus timer

struct TimerView: View {
    @EnvironmentObject private var timer: TimerService

    var body: some View {
        HStack(spacing: DS.Space.xl) {
            ZStack {
                Circle().stroke(DS.Palette.elevated, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(DS.Palette.live, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(DS.reduceMotion ? nil : .linear(duration: 0.25), value: timer.progress)
                VStack(spacing: 2) {
                    Text(timer.finished ? "Done" : timer.formatted)
                        .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text(timer.mode.rawValue).font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary)
                }
            }
            .frame(width: 140, height: 140)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(timer.mode.rawValue) timer, \(timer.finished ? "done" : "\(timer.formatted) remaining")")

            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack(spacing: DS.Space.s) {
                    Button("Focus 25") { timer.set(.focus, minutes: 25) }
                    Button("Break 5") { timer.set(.shortBreak, minutes: 5) }
                    Button("Long 15") { timer.set(.longBreak, minutes: 15) }
                }
                .buttonStyle(PillButtonStyle())

                HStack(spacing: DS.Space.s) {
                    Stepper(value: $timer.customMinutes, in: 1...180) {
                        Text("\(timer.customMinutes) min")
                            .font(DS.Typeface.body.monospacedDigit())
                            .foregroundStyle(DS.Palette.textPrimary)
                            .frame(width: 60, alignment: .leading)
                    }
                    .accessibilityLabel("Custom minutes")
                    .accessibilityValue("\(timer.customMinutes)")
                    Button("Set") { timer.set(.custom, minutes: timer.customMinutes) }
                        .buttonStyle(PillButtonStyle())
                }

                HStack(spacing: DS.Space.s) {
                    Button(timer.isRunning ? "Pause" : (timer.finished ? "Restart" : "Start")) { timer.toggle() }
                        .buttonStyle(PillButtonStyle(prominent: true))
                    Button("Reset") { timer.reset() }
                        .buttonStyle(PillButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Activity (external providers)

struct ActivityListView: View {
    @EnvironmentObject private var engine: ActivityEngine

    var body: some View {
        let items = engine.ordered
        if items.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                EmptyCardLabel(symbol: "bolt.horizontal.circle", title: "No activities",
                               detail: "Agents, builds and servers can post here.")
                Text("Publish with tools/tucknotch-activity, or write JSON to ~/Library/Application Support/TuckNotch/Inbox/")
                    .font(DS.Typeface.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .textSelection(.enabled)
                Button("Reveal Inbox Folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([ExternalActivityInbox.inboxURL])
                }
                .buttonStyle(PillButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView {
                LazyVStack(spacing: DS.Space.xs) {
                    ForEach(items) { activity in
                        ActivityRow(activity: activity)
                            .padding(DS.Space.s)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                .fill(DS.Palette.surface))
                    }
                }
            }
        }
    }
}
