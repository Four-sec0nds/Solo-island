import SwiftUI
import IslandCore

@MainActor
struct IslandSettingsView: View {
    @Environment(\.islandAccent) private var accent
    @ObservedObject var store: IslandStore
    @ObservedObject var media: MediaService

    private var section: Binding<String> { Binding(get: { store.settingsPage }, set: { store.settingsPage = $0 }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Настройки").font(.system(size: 20, weight: .semibold, design: .rounded))
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    .font(.system(size: 10)).foregroundStyle(IslandPalette.secondary)
            }
            IslandSegments(options: ["Музыка", "Вид", "Алерты", "Фокус", "Система"], selection: section, title: { $0 })
            Group {
                switch store.settingsPage {
                case "Музыка": musicSection
                case "Алерты": notificationsSection
                case "Фокус": focusSection
                case "Система": mediaSection
                default: appearanceSection
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var musicSection: some View {
        settingsSection("Музыкальный сервис", icon: "music.note") {
            MusicProviderGrid(selected: store.state.settings.musicProvider) { store.selectMusicProvider($0) }
            if store.state.settings.musicProvider != nil {
                HStack {
                    Button("Веб-плеер / вход") {
                        if let provider = store.state.settings.musicProvider { store.selectMusicProvider(provider) }
                    }
                    Spacer()
                    Button("Сбросить вход") { store.webMusic.resetSession() }
                        .help("Сбросить только веб-сессию Solo Island. Аккаунты браузеров сохраняются.")
                }.font(.system(size: 10)).buttonStyle(IslandButtonStyle(.bare)).frame(height: 22)
            }
        }
    }

    private var appearanceSection: some View {
        settingsSection("Оформление", icon: "slider.horizontal.3") {
            HStack(spacing: 14) {
                settingSlider("Ширина", value: binding(\.expandedWidth), range: IslandLayout.minimumWidth...IslandLayout.maximumWidth, suffix: "pt")
                settingSlider("Скругление", value: binding(\.cornerRadius), range: 22...40, suffix: "pt")
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Скорость анимации")
                    Spacer()
                    Text(String(format: "%.2f с", store.state.settings.animationDuration)).monospacedDigit()
                        .foregroundStyle(IslandPalette.secondary)
                }.font(.system(size: 12))
                IslandSlider(value: binding(\.animationDuration), in: 0.12...0.6)
                    .accessibilityLabel("Скорость анимации").recordingTarget("Скорость анимации")
            }
            Toggle("Акцент из обложки", isOn: binding(\.coverAccent))
                .font(.system(size: 12)).recordingTarget("Алерт:акцент")
            if !store.state.settings.coverAccent {
                IslandSegments(options: ["mint", "blue", "purple", "orange"], selection: binding(\.accent), title: { value in
                    switch value {
                    case "mint": return "Мятный"
                    case "blue": return "Синий"
                    case "purple": return "Фиолетовый"
                    default: return "Оранжевый"
                    }
                })
            }
        }
    }

    private var notificationsSection: some View {
        settingsSection("Напоминания", icon: "bell") {
            HStack {
                Text("Уведомления о задачах и фокусе").font(.system(size: 12))
                Spacer(minLength: 8)
                if store.notificationsEnabled {
                    IslandStateBadge(title: "Разрешены", symbol: "checkmark", color: accent)
                } else {
                    Button("Разрешить") { store.enableNotifications() }.font(.system(size: 11))
                }
            }
        }
    }

    private var focusSection: some View {
        settingsSection("Не беспокоить", icon: "moon") {
            Text("Имена команд включения и выключения режима из приложения «Быстрые команды».")
                .font(.system(size: 11)).foregroundStyle(IslandPalette.secondary).lineSpacing(2)
            TextField("Имя команды включения", text: binding(\.focusShortcut)).textFieldStyle(IslandTextFieldStyle())
            TextField("Имя команды выключения", text: binding(\.endFocusShortcut)).textFieldStyle(IslandTextFieldStyle())
            Button("Открыть «Быстрые команды»") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
            }.font(.system(size: 11))
        }
    }

    private var mediaSection: some View {
        settingsSection("Плеер macOS", icon: "waveform") {
            HStack {
                Text(media.executable == nil ? "Не установлен" : media.error == nil ? "Подключён" : "Требует внимания")
                    .font(.system(size: 12)).foregroundStyle(media.error == nil ? accent : IslandPalette.pink)
                Spacer()
                Button("Переподключить") { media.start() }.font(.system(size: 11))
            }
            Text("Используется активный плеер macOS. Обложка и перемотка доступны, если их передаёт источник.")
                .font(.system(size: 10)).foregroundStyle(IslandPalette.secondary).lineSpacing(2)
        }
    }

    private func settingsSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandPalette.lavender)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10).islandCard()
    }

    private func binding<T>(_ keyPath: WritableKeyPath<IslandSettings, T>) -> Binding<T> {
        Binding(get: { store.state.settings[keyPath: keyPath] }, set: { value in store.setSettings { $0[keyPath: keyPath] = value } })
    }

    private func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(suffix)").monospacedDigit().foregroundStyle(IslandPalette.secondary)
            }.font(.system(size: 12))
            IslandSlider(value: value, in: range).accessibilityLabel(title).recordingTarget(title)
        }
    }
}
