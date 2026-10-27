import SwiftUI
import IslandCore

@MainActor
struct TasksView: View {
    @Environment(\.islandAccent) private var accent
    @ObservedObject var store: IslandStore
    @State private var list: TaskList = .today
    @State private var editing: IslandTask?
    @State private var adding = false
    @State private var title = ""
    var body: some View {
        VStack(spacing: 12) {
            if let task = editing {
                TaskEditor(task: task, save: { store.upsertTask($0); editing = nil }, cancel: { editing = nil })
            } else if adding {
                TaskEditor(task: IslandTask(title: title), save: { store.upsertTask($0); title = ""; adding = false }, cancel: { adding = false })
            } else {
                IslandSegments(options: TaskList.allCases, selection: $list, title: { $0.rawValue })
                HStack {
                    TextField("Новая задача…", text: $title).textFieldStyle(.plain)
                        .onSubmit { addQuickTask() }
                    Button { adding = true } label: { Image(systemName: "calendar.badge.clock") }.help("Добавить срок и напоминание")
                    Button { addQuickTask() } label: { Image(systemName: "plus.circle.fill").foregroundStyle(accent) }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).help("Добавить задачу")
                }.buttonStyle(IslandButtonStyle(.bare)).padding(12).islandCard()
                let tasks = TaskQuery.tasks(store.state.tasks, in: list, now: store.now)
                if tasks.isEmpty {
                    EmptyState(icon: "checklist", title: "Здесь пока пусто", detail: list == .today ? "Добавьте задачу и начните фокус-сессию." : "Задачи появятся в этом списке автоматически.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(tasks) { task in taskRow(task) }
                        }
                    }
                }
                if !store.notificationsEnabled {
                    Button("Разрешить напоминания") { store.enableNotifications() }.font(.caption).buttonStyle(IslandButtonStyle(.bare)).foregroundStyle(accent)
                }
            }
        }
        .onChange(of: editing != nil || adding) { _, value in store.editingForm = value }
        .onDisappear { store.editingForm = false }
    }
    private func addQuickTask() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.upsertTask(IslandTask(title: title)); title = ""; list = .today
    }
    private func taskRow(_ task: IslandTask) -> some View {
        HStack(spacing: 10) {
            Button { store.completeTask(task.id) } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle").font(.title3)
                    .foregroundStyle(task.isCompleted ? accent : .white.opacity(0.35))
            }.accessibilityLabel(task.isCompleted ? "Вернуть задачу" : "Завершить задачу")
            Button { editing = task } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(.system(size: 13, weight: .medium)).strikethrough(task.isCompleted).lineLimit(2)
                    HStack(spacing: 8) {
                        if let due = task.dueAt {
                            Text(due, format: .dateTime.day().month(.abbreviated).hour().minute())
                                .foregroundStyle(task.isOverdue(at: store.now) ? .orange : .secondary)
                        }
                        if task.reminderAt != nil { Image(systemName: "bell") }
                        if task.focusedSeconds > 0 { Text("\(task.focusedSeconds / 60) мин фокуса") }
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if !task.isCompleted {
                Button { store.startFocus(taskID: task.id) } label: { Image(systemName: "play.circle").font(.title3).foregroundStyle(accent) }
                    .help("Начать фокус-сессию")
            }
        }.buttonStyle(IslandButtonStyle(.bare)).padding(12).islandCard()
            .contextMenu {
                Button("Редактировать") { editing = task }
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
    @State private var dueEnabled = false
    @State private var reminderEnabled = false
    @State private var dueDate = Date().addingTimeInterval(3600)
    @State private var reminderDate = Date().addingTimeInterval(1800)
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Задача").font(.headline)
            TextField("Название задачи", text: $task.title).textFieldStyle(IslandTextFieldStyle())
            Toggle("Срок выполнения", isOn: $dueEnabled)
            if dueEnabled { DatePicker("Срок", selection: $dueDate).labelsHidden() }
            Toggle("Напомнить", isOn: $reminderEnabled)
            if reminderEnabled { DatePicker("Напоминание", selection: $reminderDate, in: Date()...).labelsHidden() }
            Spacer(minLength: 0)
            HStack {
                Button("Отмена", action: cancel)
                Spacer()
                Button("Сохранить") {
                    task.dueAt = dueEnabled ? dueDate : nil
                    task.reminderAt = reminderEnabled ? reminderDate : nil
                    save(task)
                }.buttonStyle(IslandButtonStyle(.filled)).disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.onAppear {
            dueEnabled = task.dueAt != nil; reminderEnabled = task.reminderAt != nil
            dueDate = task.dueAt ?? dueDate; reminderDate = task.reminderAt ?? reminderDate
        }
    }
}
