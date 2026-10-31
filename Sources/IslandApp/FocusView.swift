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
        VStack(spacing: 16) {
            if let focus = store.state.focus {
                HStack(alignment: .center, spacing: 30) {
                    ZStack {
                        Circle().stroke(IslandPalette.raised, lineWidth: 6)
                        Circle().trim(from: 0, to: min(1, max(0, 1 - focus.remaining(at: store.now) / focus.duration)))
                            .stroke(AngularGradient(colors: [accent, IslandPalette.lavender], center: .center),
                                    style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                        VStack(spacing: 8) {
                            Text(store.focusedTime).font(.system(size: 48, weight: .light, design: .rounded)).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.65).frame(width: 158)
                            Text("часы · минуты").font(.system(size: 10)).foregroundStyle(IslandPalette.secondary)
                        }
                    }.frame(width: 196, height: 196)
                    VStack(alignment: .leading, spacing: 16) {
                        IslandStateBadge(title: focus.isPaused ? "На паузе" : "В фокусе",
                                         symbol: focus.isPaused ? "pause.fill" : "timer",
                                         color: focus.isPaused ? IslandPalette.lavender : accent)
                        Text(store.focusTask?.title ?? "Фокус-сессия")
                            .font(.system(size: 22, weight: .semibold, design: .rounded)).lineLimit(3)
                        Button(focus.isPaused ? "Продолжить" : "Пауза") { store.toggleFocusPause() }
                            .buttonStyle(IslandButtonStyle(.filled))
                            .recordingTarget(focus.isPaused ? "Продолжить" : "Пауза")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxWidth: .infinity).padding(.vertical, 28)
                HStack {
                    Button { store.toggleFocusAutomation() } label: {
                        Label(store.focusAutomationActive ? "Выключить «Не беспокоить»" : "Не беспокоить", systemImage: "moon")
                    }.buttonStyle(IslandButtonStyle(.bare)).font(.system(size: 11))
                        .foregroundStyle(store.focusAutomationActive ? accent : IslandPalette.secondary)
                    Spacer(minLength: 8)
                    Button("Закончить сессию") { store.endFocus() }.font(.system(size: 11))
                    Button { store.endFocus(completeTask: true) } label: {
                        Image(systemName: "checkmark").frame(width: 20, height: 20)
                    }.buttonStyle(IslandButtonStyle(.icon)).help("Завершить задачу")
                        .accessibilityLabel("Завершить задачу вместе с фокусом")
                }.padding(.top, 8)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    IslandSectionHeading(title: "Время для важного", subtitle: "Выбери длительность и одну задачу")
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
                        Text("От 1 минуты до 99 часов 59 минут. Длительность сохраняется.").font(.system(size: 10)).foregroundStyle(IslandPalette.secondary)
                    }
                }
                let tasks = store.state.tasks.filter { !$0.isCompleted }
                if tasks.isEmpty {
                    EmptyState(icon: "timer", title: "Выберите, на чём сосредоточиться", detail: "Создайте задачу в соседнем разделе — у каждой есть кнопка запуска фокуса.")
                    Button("Создать задачу") { store.tab = .tasks }.buttonStyle(IslandButtonStyle(.filled))
                } else {
                    Text("Над чем поработаем?").font(.system(size: 12, weight: .medium)).foregroundStyle(IslandPalette.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(tasks) { task in
                                Button { store.startFocus(taskID: task.id) } label: {
                                    HStack(spacing: 12) {
                                        Text(task.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                        Spacer()
                                        Image(systemName: "play.fill").font(.system(size: 11)).foregroundStyle(accent)
                                            .frame(width: 28, height: 28).background(accent.opacity(0.09), in: Circle())
                                    }.padding(13).islandCard()
                                }.buttonStyle(IslandButtonStyle(.bare)).recordingTarget(task.title)
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
            Text(title).font(.system(size: 11)).foregroundStyle(IslandPalette.secondary)
            TextField(title, value: value, format: .number).textFieldStyle(IslandTextFieldStyle()).monospacedDigit()
                .recordingTarget(title)
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
