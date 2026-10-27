import SwiftUI
import IslandCore

@MainActor
struct FocusView: View {
    @Environment(\.islandAccent) private var accent
    @ObservedObject var store: IslandStore
    var body: some View {
        VStack(spacing: 14) {
            if let focus = store.state.focus {
                Text(store.focusTask?.title ?? "Фокус-сессия").font(.headline).lineLimit(2).multilineTextAlignment(.center)
                ZStack {
                    Circle().stroke(.white.opacity(0.08), lineWidth: 5)
                    Circle().trim(from: 0, to: min(1, max(0, 1 - focus.remaining(at: store.now) / focus.duration)))
                        .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 4) {
                        Text(store.focusedTime).font(.system(size: 38, weight: .light, design: .rounded)).monospacedDigit()
                        Text(focus.isPaused ? "ПАУЗА" : "ФОКУС").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(.secondary)
                    }
                }.frame(width: 148, height: 148)
                HStack {
                    Button(focus.isPaused ? "Продолжить" : "Пауза") { store.toggleFocusPause() }
                    Button("Закончить сессию") { store.endFocus() }
                    Button { store.endFocus(completeTask: true) } label: { Image(systemName: "checkmark") }.help("Завершить задачу")
                }.buttonStyle(IslandButtonStyle(.soft))
                Button {
                    store.toggleFocusAutomation()
                } label: {
                    Label(store.focusAutomationActive ? "Выключить «Не беспокоить»" : "Включить «Не беспокоить»", systemImage: "moon.fill")
                }.buttonStyle(IslandButtonStyle(.bare)).font(.caption).foregroundStyle(store.focusAutomationActive ? accent : .secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Длительность сессии").font(.headline)
                    IslandSegments(options: [15, 25, 45, 60, 90], selection: Binding(get: { store.state.settings.focusMinutes }, set: { value in store.setSettings { $0.focusMinutes = value } }), title: { "\($0) мин" })
                }
                let tasks = store.state.tasks.filter { !$0.isCompleted }
                if tasks.isEmpty {
                    EmptyState(icon: "timer", title: "Выберите, на чём сосредоточиться", detail: "Создайте задачу в соседнем разделе — у каждой есть кнопка запуска фокуса.")
                    Button("Создать задачу") { store.tab = .tasks }.buttonStyle(IslandButtonStyle(.filled))
                } else {
                    Text("Выберите задачу для новой сессии").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(tasks) { task in
                                Button { store.startFocus(taskID: task.id) } label: {
                                    HStack { Text(task.title).lineLimit(2); Spacer(); Image(systemName: "play.fill").foregroundStyle(accent) }
                                        .padding(13).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(IslandButtonStyle(.bare))
                            }
                        }
                    }
                }
                if store.focusAutomationActive {
                    Button("Выключить «Не беспокоить»") { store.toggleFocusAutomation() }.font(.caption)
                }
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity)
    }
}
