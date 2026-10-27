import SwiftUI
import IslandCore

@MainActor
struct FocusView: View {
    @Environment(\.islandAccent) private var accent
    @ObservedObject var store: IslandStore
    @State private var custom = false
    @State private var hours = 0
    @State private var minutes = 25
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
                            .lineLimit(1).minimumScaleFactor(0.65).frame(width: 124)
                        Text("ЧАСЫ · МИНУТЫ").font(.system(size: 7, weight: .medium)).tracking(1).foregroundStyle(.secondary)
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
                    IslandSegments(options: [15, 25, 45, 60, 90, 0], selection: Binding(get: { store.state.settings.customFocusSeconds == nil ? store.state.settings.focusMinutes : 0 }, set: { value in
                        if value == 0 { custom = true; saveCustomTime() }
                        else { custom = false; store.setSettings { $0.focusMinutes = value; $0.customFocusSeconds = nil } }
                    }), title: { $0 == 0 ? "Своё" : "\($0) мин" })
                    if custom || store.state.settings.customFocusSeconds != nil {
                        HStack(spacing: 12) {
                            timeField("Часы", value: $hours, range: 0...99)
                            Text(":").foregroundStyle(accent)
                            timeField("Минуты", value: $minutes, range: 0...59)
                        }.padding(12).islandCard(tint: accent)
                        Text("От 1 минуты до 99 часов 59 минут. Длительность сохраняется.").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
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
            .onAppear {
                let value = min(5999, max(1, Int(ceil(store.state.settings.focusDuration / 60))))
                hours = value / 60; minutes = value % 60
                custom = store.state.settings.customFocusSeconds != nil
            }
    }
    private func timeField(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            TextField(title, value: value, format: .number).textFieldStyle(IslandTextFieldStyle()).monospacedDigit()
                .onChange(of: value.wrappedValue) { _, next in
                    value.wrappedValue = min(range.upperBound, max(range.lowerBound, next))
                    if custom { saveCustomTime() }
                }
        }
    }
    private func saveCustomTime() {
        if hours == 0 && minutes == 0 { minutes = 1 }
        store.setSettings { $0.customFocusSeconds = max(60, min(359940, hours * 3600 + minutes * 60)) }
    }
}
