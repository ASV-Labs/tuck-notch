import SwiftUI

// MARK: - Shared bits

/// A one-line text field styled for the island (visible box, focus ring).
struct IslandTextField: View {
    let prompt: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    var onFocusChange: (Bool) -> Void = { _ in }
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(prompt).foregroundColor(DS.Palette.textSecondary))
            .textFieldStyle(.plain)
            .font(DS.Typeface.body)
            .foregroundStyle(DS.Palette.textPrimary)
            .focused($focused)
            .onSubmit(onSubmit)
            .onChange(of: focused) { onFocusChange($0) }
            .padding(.horizontal, DS.Space.s)
            .frame(height: DS.Size.hit)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(DS.Palette.elevated))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .strokeBorder(focused ? DS.Palette.accent : DS.Palette.textSecondary.opacity(0.3), lineWidth: focused ? 2 : 1))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
    }
}

/// A checklist row: circle toggle, text, delete on hover.
struct TodoRow: View {
    let todo: TasksService.Todo
    @EnvironmentObject private var tasks: TasksService
    @State private var hovering = false

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Button { tasks.toggle(todo.id) } label: {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(todo.done ? DS.Palette.success : DS.Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.done ? "Mark \(todo.text) not done" : "Mark \(todo.text) done")
            Text(todo.text)
                .font(DS.Typeface.body)
                .strikethrough(todo.done)
                .foregroundStyle(todo.done ? DS.Palette.textSecondary : DS.Palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if hovering {
                Button { tasks.remove(todo.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(DS.Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(todo.text)")
            }
        }
        .frame(minHeight: 22)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Tiny line chart for a 0…1 series.
struct Sparkline: View {
    let values: [Double]
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: pts[0])
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let step = size.width / CGFloat(SystemStatsService.historyLength - 1)
        let offset = CGFloat(SystemStatsService.historyLength - values.count) * step
        return values.enumerated().map { i, v in
            CGPoint(x: offset + CGFloat(i) * step, y: size.height * (1 - CGFloat(min(1, max(0, v)))) )
        }
    }
}

// MARK: - Home cards

struct TodoCard: View {
    @ObservedObject var vm: NotchViewModel
    @EnvironmentObject private var tasks: TasksService
    @State private var draft = ""

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                CardHeader(symbol: "checklist", title: "To-dos",
                           trailing: tasks.openCount > 0 ? "\(tasks.openCount)" : nil)
                if tasks.todos.isEmpty {
                    Text("Nothing yet").font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary)
                } else {
                    ForEach(tasks.ordered.prefix(2)) { TodoRow(todo: $0) }
                }
                Spacer(minLength: 0)
                IslandTextField(prompt: "Add a task", text: $draft, onSubmit: add, onFocusChange: { vm.pinned = $0 })
            }
        }
    }

    private func add() {
        tasks.add(draft)
        draft = ""
    }
}

struct NotesCard: View {
    @ObservedObject var vm: NotchViewModel
    @EnvironmentObject private var tasks: TasksService

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                CardHeader(symbol: "note.text", title: "Notes")
                NoteEditor(vm: vm, compact: true)
            }
        }
    }
}

struct NoteEditor: View {
    @ObservedObject var vm: NotchViewModel
    var compact = false
    @EnvironmentObject private var tasks: TasksService
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $tasks.note)
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.textPrimary)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .onChange(of: focused) { vm.pinned = $0 }
                .accessibilityLabel("Notes")
            if tasks.note.isEmpty {
                Text(compact ? "Jot something down…" : "Jot something down. It's saved on this Mac as you type.")
                    .font(DS.Typeface.body).foregroundStyle(DS.Palette.textSecondary)
                    .padding(.leading, 5).padding(.top, 1)
                    .allowsHitTesting(false)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(DS.Palette.elevated.opacity(focused ? 1 : 0.6)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
            .strokeBorder(focused ? DS.Palette.accent : Color.clear, lineWidth: 2))
    }
}

struct PulseCard: View {
    @EnvironmentObject private var stats: SystemStatsService
    @EnvironmentObject private var battery: BatteryService

    var body: some View {
        Card(padding: DS.Space.s) {
            HStack(spacing: DS.Space.s) {
                tile(symbol: "cpu", label: "CPU", value: stats.cpu, history: stats.cpuHistory, tint: DS.Palette.success)
                tile(symbol: "memorychip", label: "Memory", value: stats.memory, history: stats.memoryHistory, tint: DS.Palette.accent)
                if let percent = battery.percent {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(battery.onPower ? "Charging" : "Battery",
                              systemImage: battery.onPower ? "battery.100.bolt" : "battery.75")
                            .font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary)
                            .labelStyle(.iconOnly)
                        Text("\(percent)%").font(DS.Typeface.bodyMedium.monospacedDigit()).foregroundStyle(DS.Palette.warning)
                        Spacer(minLength: 0)
                        GeometryReader { geo in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 3).fill(DS.Palette.elevated)
                                RoundedRectangle(cornerRadius: 3).fill(DS.Palette.warning.opacity(0.55))
                                    .frame(height: geo.size.height * CGFloat(percent) / 100)
                            }
                        }
                    }
                    .frame(width: 44)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Battery \(percent) percent\(battery.onPower ? ", charging" : "")")
                }
            }
        }
    }

    private func tile(symbol: String, label: String, value: Double, history: [Double], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(DS.Palette.textSecondary)
                Spacer(minLength: 0)
                Text("\(Int((value * 100).rounded()))%").font(DS.Typeface.bodyMedium.monospacedDigit()).foregroundStyle(tint)
            }
            Sparkline(values: history, tint: tint)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(DS.Palette.elevated.opacity(0.6)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(Int((value * 100).rounded())) percent")
    }
}

// MARK: - Calendar tab

/// Upcoming events grouped by day, next to a month grid with dots on busy days.
struct CalendarTabView: View {
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var notion: NotionService

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.l) {
            agenda.frame(maxWidth: .infinity, alignment: .topLeading)
            MonthGrid(busyDays: calendar.busyDays).frame(width: 182)
        }
    }

    @ViewBuilder private var agenda: some View {
        let groups = AgendaGrouping.group(CalendarCard.mergedEvents(calendar: calendar, notion: notion))
        VStack(alignment: .leading, spacing: DS.Space.s) {
            dayHeader
            if calendar.access != .granted && notion.items.isEmpty {
                Text("Connect your calendars in Settings › Home to see what's next.")
                    .font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary)
                Button("Connect Calendar") { calendar.connect() }.buttonStyle(PillButtonStyle(compact: true))
            }
            if groups.isEmpty, calendar.access == .granted || !notion.items.isEmpty {
                Text("Nothing in the next three days").font(DS.Typeface.body).foregroundStyle(DS.Palette.textSecondary)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(groups, id: \.day) { group in
                        if !Calendar.current.isDateInToday(group.day) {
                            Text(AgendaGrouping.label(for: group.day).uppercased())
                                .font(DS.Typeface.captionMedium).foregroundStyle(DS.Palette.textSecondary)
                                .padding(.top, 2)
                        }
                        ForEach(group.events) { EventRow(event: $0) }
                    }
                }
            }
        }
    }

    private var dayHeader: some View {
        let now = Date()
        let week = Calendar(identifier: .iso8601).component(.weekOfYear, from: now)
        return HStack(spacing: 6) {
            Text(now.formatted(.dateTime.weekday(.abbreviated)).uppercased()).foregroundStyle(DS.Palette.danger)
            Text(now.formatted(.dateTime.day())).foregroundStyle(DS.Palette.textPrimary)
            Text("W\(week)").foregroundStyle(DS.Palette.textSecondary)
        }
        .font(DS.Typeface.bodyMedium)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today, \(now.formatted(date: .complete, time: .omitted)), week \(week)")
    }
}

enum AgendaGrouping {
    struct DayGroup { let day: Date; var events: [CalendarService.Event] }

    static func group(_ events: [CalendarService.Event], calendar: Calendar = .current) -> [DayGroup] {
        var groups: [DayGroup] = []
        for e in events {
            let day = calendar.startOfDay(for: max(e.start, calendar.startOfDay(for: Date())))
            if let i = groups.firstIndex(where: { $0.day == day }) { groups[i].events.append(e) }
            else { groups.append(DayGroup(day: day, events: [e])) }
        }
        return groups.sorted { $0.day < $1.day }
    }

    static func label(for day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

struct EventRow: View {
    let event: CalendarService.Event
    private static let time: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()

    var body: some View {
        HStack(spacing: DS.Space.s) {
            RoundedRectangle(cornerRadius: 1.5).fill(event.color).frame(width: 3)
            Button { if let url = event.openURL { NSWorkspace.shared.open(url) } } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(event.title).font(DS.Typeface.bodyMedium).foregroundStyle(DS.Palette.textPrimary).lineLimit(1)
                    Text(times).font(DS.Typeface.caption)
                        .foregroundStyle(event.isHappening && !event.isAllDay ? DS.Palette.live : DS.Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(event.openURL == nil ? "" : "Open in Notion")
            if let url = event.joinURL {
                Button { NSWorkspace.shared.open(url) } label: { Text("Join").font(DS.Typeface.captionMedium) }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Palette.success)
                    .padding(.horizontal, DS.Space.s)
                    .frame(height: 22)
                    .background(Capsule().fill(DS.Palette.success.opacity(0.16)))
                    .help("Join on \(event.joinService ?? "the call")")
                    .accessibilityLabel("Join \(event.title) on \(event.joinService ?? "video call")")
            }
        }
        .padding(.vertical, 5).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(event.color.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }

    private var times: String {
        if event.isAllDay { return "All day" + (event.openURL != nil ? " · Notion" : "") }
        let t = "\(Self.time.string(from: event.start)) – \(Self.time.string(from: event.end))"
        return event.isHappening ? "Now · until \(Self.time.string(from: event.end))" : t + (event.openURL != nil ? " · Notion" : "")
    }
}

/// Month view (weeks start on the user's first weekday) with today highlighted and busy-day dots.
struct MonthGrid: View {
    let busyDays: Set<Int>
    private let calendar = Calendar.current

    var body: some View {
        let now = Date()
        let cells = Self.cells(for: now, calendar: calendar)
        let today = calendar.component(.day, from: now)
        VStack(spacing: 2) {
            HStack {
                Spacer()
                Text(now.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(DS.Typeface.captionMedium).foregroundStyle(DS.Palette.danger)
            }
            HStack(spacing: 0) {
                ForEach(Array(Self.weekdaySymbols(calendar).enumerated()), id: \.offset) { _, s in
                    Text(s).font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 1) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    ZStack {
                        if let day {
                            if day == today { Circle().fill(DS.Palette.danger).frame(width: 20, height: 20) }
                            Text("\(day)").font(.system(size: 10.5, weight: day == today ? .bold : .regular).monospacedDigit())
                                .foregroundStyle(day == today ? Color.white : DS.Palette.textPrimary)
                            if busyDays.contains(day), day != today {
                                Circle().fill(DS.Palette.textSecondary).frame(width: 3, height: 3).offset(y: 9)
                            }
                        }
                    }
                    .frame(height: 22)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(now.formatted(.dateTime.month(.wide).year())), \(busyDays.count) days with events")
    }

    static func weekdaySymbols(_ calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Leading blanks then 1…n for the month containing `date`.
    static func cells(for date: Date, calendar: Calendar) -> [Int?] {
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let days = calendar.range(of: .day, in: .month, for: date) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + days.map { Optional($0) }
    }
}

// MARK: - Notes tab

struct NotesTabView: View {
    @ObservedObject var vm: NotchViewModel
    @EnvironmentObject private var tasks: TasksService
    @State private var draft = ""

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.l) {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack {
                    Text("To-dos").font(DS.Typeface.captionMedium).foregroundStyle(DS.Palette.textSecondary)
                    Spacer()
                    if tasks.todos.contains(where: \.done) {
                        Button("Clear done") { tasks.clearDone() }.buttonStyle(PillButtonStyle(compact: true))
                    }
                    Text("\(tasks.openCount)").font(DS.Typeface.caption.monospacedDigit()).foregroundStyle(DS.Palette.textSecondary)
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        if tasks.todos.isEmpty {
                            Text("Add your first task below.").font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary)
                        }
                        ForEach(tasks.ordered) { TodoRow(todo: $0) }
                    }
                }
                IslandTextField(prompt: "Add a task and press Return", text: $draft,
                                onSubmit: { tasks.add(draft); draft = "" },
                                onFocusChange: { vm.pinned = $0 })
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("Notes").font(DS.Typeface.captionMedium).foregroundStyle(DS.Palette.textSecondary)
                NoteEditor(vm: vm)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
