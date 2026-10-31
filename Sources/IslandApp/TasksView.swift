import SwiftUI
import IslandCore

@MainActor
struct TasksView: View {
    @Environment(\.islandAccent) private var accent
    @ObservedObject var store: IslandStore
    @State private var list: TaskList = .today
    @State private var title = ""
    var body: some View {
        VStack(spacing: 12) {
            if let task = store.taskDraft {
                TaskEditor(task: task, initialReminder: store.editingReminder, save: {
                    store.upsertTask($0); store.taskDraft = nil; title = ""
                }, cancel: { store.taskDraft = nil }).id(task.id)
            } else {
                HStack {
                    Text(list == .completed ? "Уже сделано" : "Твои задачи")
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                    Spacer()
                    IslandStateBadge(title: "В списке: \(TaskQuery.tasks(store.state.tasks, in: list, now: store.now).count)", color: accent)
                    Button {
                        store.editingReminder = false; store.taskDraft = IslandTask(title: title)
                        if CommandLine.arguments.contains("--render-preview") { fputs("Task editor: new task button activated\n", stderr) }
                    } label: { Label("Новая", systemImage: "plus") }
                        .buttonStyle(IslandButtonStyle(.filled)).help("Добавить срок и напоминание")
                        .accessibilityLabel("Добавить срок и напоминание").recordingTarget("Добавить срок и напоминание")
                }
                IslandSegments(options: TaskList.allCases, selection: $list, title: { $0.rawValue })
                HStack(spacing: 10) {
                    TextField("Новая задача…", text: $title).textFieldStyle(IslandTextFieldStyle())
                        .font(.system(size: 13)).accessibilityLabel("Новая задача")
                        .onSubmit { addQuickTask() }
                    Button { addQuickTask() } label: { Image(systemName: "plus").frame(width: 18, height: 18) }
                        .buttonStyle(IslandButtonStyle(.filled)).accessibilityLabel("Добавить задачу")
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).help("Добавить задачу")
                }
                let tasks = TaskQuery.tasks(store.state.tasks, in: list, now: store.now)
                if tasks.isEmpty {
                    EmptyState(icon: "checklist", title: "Здесь пока пусто", detail: list == .today ? "Добавьте задачу и начните фокус-сессию." : "Задачи появятся в этом списке автоматически.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(tasks) { task in taskRow(task) }
                        }.padding(1)
                    }
                }
                if !store.notificationsEnabled {
                    Button("Разрешить напоминания") { store.enableNotifications() }.font(.caption).buttonStyle(IslandButtonStyle(.bare)).foregroundStyle(accent)
                }
            }
        }
        .onChange(of: store.taskDraft != nil) { _, value in store.editingForm = value }
        .onAppear { store.editingForm = store.taskDraft != nil }
        .onDisappear { store.editingForm = false }
    }
    private func addQuickTask() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.upsertTask(IslandTask(title: title)); title = ""; list = .today
    }
    private func taskRow(_ task: IslandTask) -> some View {
        HStack(spacing: 10) {
            Button { store.completeTask(task.id) } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle").font(.system(size: 20, weight: .light))
                    .foregroundStyle(task.isCompleted ? accent : IslandPalette.muted).frame(width: 25, height: 28)
            }.accessibilityLabel(task.isCompleted ? "Вернуть задачу" : "Завершить задачу").recordingTarget("Завершить:" + task.title)
            Button { store.editingReminder = false; store.taskDraft = task } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(.system(size: 13, weight: .medium)).strikethrough(task.isCompleted).lineLimit(2)
                        .foregroundStyle(task.isCompleted ? IslandPalette.secondary : IslandPalette.text)
                    HStack(spacing: 8) {
                        if let due = task.dueAt {
                            Text(due, format: .dateTime.day().month(.abbreviated).hour().minute())
                                .foregroundStyle(task.isOverdue(at: store.now) ? .orange : .secondary)
                        }
                        if task.reminderAt != nil { Image(systemName: "bell") }
                        if task.focusedSeconds > 0 { Text("\(task.focusedSeconds / 60) мин фокуса") }
                    }.font(.system(size: 11)).foregroundStyle(IslandPalette.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if !task.isCompleted {
                Button { store.startFocus(taskID: task.id) } label: {
                    Image(systemName: "play.fill").font(.system(size: 11)).foregroundStyle(accent)
                        .frame(width: 30, height: 30).background(accent.opacity(0.1), in: Circle())
                }.help("Начать фокус-сессию").accessibilityLabel("Начать фокус-сессию")
            }
        }.buttonStyle(IslandButtonStyle(.bare)).padding(12).islandCard()
            .contextMenu {
                Button("Редактировать") { store.editingReminder = false; store.taskDraft = task }
                Button("Удалить задачу", role: .destructive) { store.deleteTask(task.id) }
            }
    }
}

@MainActor
struct TaskEditor: View {
    @Environment(\.islandAccent) private var accent
    @State var task: IslandTask
    var save: (IslandTask) -> Void
    var cancel: () -> Void
    @State private var section: String
    @State private var dueEnabled: Bool
    @State private var reminderEnabled: Bool
    @State private var dueDate: Date
    @State private var reminderDate: Date
    @State private var calendarVisible = false
    init(task: IslandTask, initialReminder: Bool = false, save: @escaping (IslandTask) -> Void, cancel: @escaping () -> Void) {
        _task = State(initialValue: task); self.save = save; self.cancel = cancel
        _section = State(initialValue: initialReminder ? "Напоминание" : "Срок")
        _dueEnabled = State(initialValue: task.dueAt != nil)
        _reminderEnabled = State(initialValue: task.reminderAt != nil)
        _dueDate = State(initialValue: task.dueAt ?? Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date().addingTimeInterval(86400))!)
        _reminderDate = State(initialValue: task.reminderAt ?? Date().addingTimeInterval(3600))
    }
    private var invalidReminder: Bool { reminderEnabled && reminderDate <= Date() }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Название задачи", text: $task.title).textFieldStyle(IslandTextFieldStyle())
                .accessibilityLabel("Название задачи").recordingTarget("Название задачи")
            HStack(spacing: 10) {
                IslandSegments(options: ["Срок", "Напоминание"], selection: $section, title: { $0 })
                Button(action: cancel) { Image(systemName: "arrow.uturn.backward") }.help("Отмена")
                Button {
                    task.dueAt = dueEnabled ? dueDate : nil; task.reminderAt = reminderEnabled ? reminderDate : nil
                    save(task)
                } label: { Image(systemName: "checkmark").frame(width: 20) }
                    .buttonStyle(IslandButtonStyle(.filled)).help("Сохранить задачу").recordingTarget("Сохранить задачу")
                    .accessibilityLabel("Сохранить задачу")
                    .disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || invalidReminder)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if section == "Срок" {
                        Toggle("Срок выполнения", isOn: $dueEnabled).font(.caption).recordingTarget("Алерт:срок")
                        if dueEnabled {
                            DeadlineControl(date: $dueDate)
                            HStack {
                                DatePicker("Время", selection: $dueDate, displayedComponents: .hourAndMinute).font(.caption)
                                Spacer()
                                Button { calendarVisible.toggle() } label: { Label("Своя дата", systemImage: "calendar") }.font(.caption).recordingTarget("Своя дата")
                            }
                            if calendarVisible { IslandCalendar(date: $dueDate) }
                            VStack(alignment: .leading, spacing: 9) {
                                Label("Заранее предупредить", systemImage: "bell.badge").font(.caption.bold())
                                Toggle("За день до дедлайна", isOn: $task.alertDayBefore).font(.caption).recordingTarget("Алерт:день")
                                Toggle("За час до дедлайна", isOn: $task.alertHourBefore).font(.caption).recordingTarget("Алерт:час")
                            }.padding(12).islandCard(tint: accent)
                            Text("Уведомления приходят и при закрытом приложении. Прошедшие интервалы пропускаются.")
                                .font(.system(size: 11)).foregroundStyle(IslandPalette.secondary)
                        }
                    } else {
                        Toggle("Напомнить в выбранный день", isOn: $reminderEnabled).font(.caption).recordingTarget("Алерт:напоминание")
                        if reminderEnabled {
                            IslandCalendar(date: $reminderDate)
                            DatePicker("Во сколько", selection: $reminderDate, displayedComponents: .hourAndMinute).font(.caption)
                            if invalidReminder { Text("Выберите время в будущем.").font(.caption).foregroundStyle(.orange) }
                        }
                        Text("Это отдельное напоминание. Алерты за день и за час включаются в разделе «Срок».")
                            .font(.system(size: 11)).foregroundStyle(IslandPalette.secondary)
                    }
                }.padding(.bottom, 4)
            }
        }
    }
}

@MainActor
struct DeadlineControl: View {
    @Environment(\.islandAccent) private var accent
    @Binding var date: Date
    private var calendar: Calendar { Calendar.current }
    private var offset: Double {
        Double(min(14, max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Дедлайн", systemImage: "flag.checkered").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(date, format: .dateTime.day().month(.wide)).font(.system(size: 14, weight: .semibold)).foregroundStyle(accent)
                    .contentTransition(.numericText())
            }
            IslandSlider(value: Binding(get: { offset }, set: { value in
                let components = calendar.dateComponents([.hour, .minute], from: date)
                let day = calendar.date(byAdding: .day, value: Int(value.rounded()), to: calendar.startOfDay(for: Date()))!
                date = calendar.date(bySettingHour: components.hour ?? 18, minute: components.minute ?? 0, second: 0, of: day)!
            }), in: 0...14).accessibilityLabel("Через сколько дней выполнить задачу").recordingTarget("Через сколько дней выполнить задачу")
            HStack {
                Text("Сегодня"); Spacer(); Text("Неделя"); Spacer(); Text("Две недели")
            }.font(.system(size: 9)).foregroundStyle(.secondary)
        }.padding(14).islandCard(tint: accent)
    }
}

@MainActor
struct IslandCalendar: View {
    @Environment(\.islandAccent) private var accent
    @Binding var date: Date
    @State private var month = Date()
    private var calendar: Calendar { Calendar.current }
    private var start: Date { calendar.date(from: calendar.dateComponents([.year, .month], from: month))! }
    private var leading: Int { (calendar.component(.weekday, from: start) + 5) % 7 }
    private var count: Int { calendar.range(of: .day, in: .month, for: start)!.count }
    private var cells: Int { ((leading + count + 6) / 7) * 7 }
    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Button { move(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(IslandButtonStyle(.bare)).recordingTarget("Календарь:назад")
                Spacer()
                Text(month, format: .dateTime.month(.wide).year()).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { move(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(IslandButtonStyle(.bare)).recordingTarget("Календарь:вперёд")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 3) {
                ForEach(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"], id: \.self) { name in
                    Text(name).font(.system(size: 10)).foregroundStyle(IslandPalette.secondary).frame(maxWidth: .infinity)
                }
                ForEach(0..<cells, id: \.self) { index in
                    let day = index - leading + 1
                    if day > 0 && day <= count {
                        let value = calendar.date(byAdding: .day, value: day - 1, to: start)!
                        let selected = calendar.isDate(value, inSameDayAs: date)
                        Button {
                            let time = calendar.dateComponents([.hour, .minute], from: date)
                            date = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: value)!
                        } label: {
                            Text("\(day)").font(.system(size: 12, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? IslandPalette.foreground(on: accent) : IslandPalette.text)
                                .frame(maxWidth: .infinity).frame(height: 26)
                                .background(selected ? accent : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(calendar.isDateInToday(value) ? accent.opacity(0.5) : .clear))
                        }.buttonStyle(IslandButtonStyle(.bare)).accessibilityLabel(value.formatted(date: .complete, time: .omitted))
                            .recordingTarget(value.formatted(date: .complete, time: .omitted))
                    } else { Color.clear.frame(height: 26) }
                }
            }
        }.padding(11).islandCard(tint: accent)
            .onAppear { month = date }
    }
    private func move(_ step: Int) { month = calendar.date(byAdding: .month, value: step, to: start)! }
}
