import SwiftUI
import IslandCore

@MainActor
struct IslandSettingsView: View {
    @Environment(\.islandAccent) private var accent
    @ObservedObject var store: IslandStore
    @ObservedObject var media: MediaService
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Solo Island").font(.title3.bold())
                        Text("Своя точка управления").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("0.2.0").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
                settingSlider("Ширина", value: binding(\.expandedWidth), range: 460...640, suffix: "pt")
                settingSlider("Скругление", value: binding(\.cornerRadius), range: 16...36, suffix: "pt")
                VStack(alignment: .leading, spacing: 5) {
                    Text("Скорость анимации").font(.caption)
                    Slider(value: binding(\.animationDuration), in: 0.12...0.6)
                }
                Toggle("Акцент из обложки", isOn: binding(\.coverAccent)).font(.caption)
                if !store.state.settings.coverAccent {
                    Picker("Цвет", selection: binding(\.accent)) {
                        Text("Мятный").tag("mint"); Text("Синий").tag("blue")
                        Text("Фиолетовый").tag("purple"); Text("Оранжевый").tag("orange")
                    }.font(.caption)
                }
                Divider()
                HStack {
                    Label("Уведомления", systemImage: "bell").font(.caption)
                    Spacer()
                    if store.notificationsEnabled { Text("Разрешены").foregroundStyle(accent).font(.caption) }
                    else { Button("Разрешить") { store.enableNotifications() }.font(.caption) }
                }
                Divider()
                Text("«Не беспокоить» во время фокуса").font(.caption.bold())
                Text("Создайте две команды в приложении «Быстрые команды»: одну для включения «Не беспокоить», другую для выключения. Укажите их имена ниже. Кнопка включения находится в разделе «Фокус».")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Имя команды включения", text: binding(\.focusShortcut)).textFieldStyle(.roundedBorder)
                TextField("Имя команды выключения", text: binding(\.endFocusShortcut)).textFieldStyle(.roundedBorder)
                Button("Открыть «Быстрые команды»") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")) }.font(.caption)
                Divider()
                HStack {
                    Text("Медиаплеер").font(.caption.bold())
                    Spacer()
                    Text(media.executable == nil ? "Не установлен" : media.error == nil ? "Подключён" : "Требует внимания").font(.caption).foregroundStyle(.secondary)
                    Button("Переподключить") { media.start() }.font(.caption)
                }
                Text("Используется активный плеер macOS. Источники передают разный набор данных: обложку и перемотку показываем при их наличии.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Divider()
                Text("Файлы и задачи хранятся на этом Mac. Календарь, статистика системы и батарея не используются.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.bottom, 6)
        }
    }
    private func binding<T>(_ keyPath: WritableKeyPath<IslandSettings, T>) -> Binding<T> {
        Binding(get: { store.state.settings[keyPath: keyPath] }, set: { value in store.setSettings { $0[keyPath: keyPath] = value } })
    }
    private func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(spacing: 5) {
            HStack { Text(title); Spacer(); Text("\(Int(value.wrappedValue)) \(suffix)").foregroundStyle(.secondary) }.font(.caption)
            Slider(value: value, in: range)
        }
    }
}
