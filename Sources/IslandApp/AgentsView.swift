import SwiftUI
import IslandCore

@MainActor
struct AgentStatusButton: View {
    @ObservedObject var agents: AgentService
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: agents.pending.isEmpty ? "terminal" : "hand.raised.fill")
                Text(agents.pending.isEmpty ? "Агенты" : "Запросы · \(agents.pending.count)")
                    .font(.system(size: 11, weight: .medium))
                if agents.activity.current != nil && agents.pending.isEmpty {
                    Circle().fill(IslandPalette.mint).frame(width: 5, height: 5).accessibilityHidden(true)
                }
            }.padding(.horizontal, 9).padding(.vertical, 5)
                .background(IslandPalette.lavender.opacity(0.09), in: Capsule())
        }.buttonStyle(IslandButtonStyle(.bare)).foregroundStyle(agents.pending.isEmpty ? IslandPalette.secondary : IslandPalette.mint)
            .keyboardShortcut("6", modifiers: .command).help("Агенты (⌘6)")
            .accessibilityLabel("Открыть агентов, запросов: \(agents.pending.count)")
            .recordingTarget("Вкладка:Агенты")
    }
}

@MainActor
struct AgentsView: View {
    @ObservedObject var agents: AgentService
    var now: Date
    @State private var connections = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Агенты").font(.system(size: 26, weight: .semibold, design: .rounded))
                Spacer()
                Button(connections ? "К работе" : "Подключения") { connections.toggle() }
                    .buttonStyle(IslandButtonStyle(.soft)).recordingTarget("Подключения агентов")
            }
            if let message = agents.message {
                HStack(alignment: .top) {
                    Text(message).font(.system(size: 11)).foregroundStyle(IslandPalette.secondary)
                    Spacer(minLength: 4)
                    Button { agents.message = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(IslandButtonStyle(.bare)).accessibilityLabel("Скрыть сообщение агентов")
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if connections || agents.activity.sessions.isEmpty { connectionView }
                    else {
                        ForEach(agents.pending) { request in approval(request) }
                        ForEach(agents.activity.sessions) { session in sessionRow(session) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
            }.scrollIndicators(.hidden)
        }.onAppear { agents.refreshInstallation() }
    }
    private var connectionView: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Задача в работе — вы в курсе")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                Text("Время работы и запросы разрешения от Claude Code и Codex появятся здесь. Подключите клиент один раз и начните новую задачу.")
                    .font(.system(size: 12)).foregroundStyle(IslandPalette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(AgentProvider.allCases) { provider in
                    HStack(spacing: 12) {
                        Image(systemName: provider == .claude ? "text.bubble" : "terminal")
                            .font(.system(size: 18, weight: .medium)).foregroundStyle(IslandPalette.lavender)
                            .frame(width: 38, height: 38).background(IslandPalette.raised, in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(provider.title).font(.system(size: 13, weight: .semibold))
                            Text(agents.observed.contains(provider) ? "События получены" : agents.installed.contains(provider) ? "Ожидаем первую задачу" : "Ещё не подключён")
                                .font(.system(size: 11)).foregroundStyle(IslandPalette.secondary)
                        }
                        Spacer()
                        Button(agents.installed.contains(provider) ? "Отключить" : "Подключить") {
                            agents.setEnabled(provider, enabled: !agents.installed.contains(provider))
                        }.buttonStyle(IslandButtonStyle(.soft))
                            .accessibilityLabel((agents.installed.contains(provider) ? "Отключить " : "Подключить ") + provider.title)
                    }.padding(.vertical, 12)
                    if provider != AgentProvider.allCases.last { Divider().overlay(IslandPalette.separator) }
                }
            }
            Text("Для терминальных клиентов с поддержкой hooks. После подключения перезапустите клиент. Браузерные чаты не подключаются; поддержка десктопных клиентов зависит от их версии.")
                .font(.system(size: 11)).foregroundStyle(IslandPalette.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Меняются только настройки событий выбранного клиента, с резервной копией. Вход в аккаунты не требуется. Если Island закрыт, запрос вернётся в клиент.")
                .font(.system(size: 11)).foregroundStyle(IslandPalette.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func approval(_ request: AgentEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill").foregroundStyle(IslandPalette.mint)
                Text("Нужно разрешение").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(max(0, Int(request.expiresAt.timeIntervalSince(now)))) с")
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(IslandPalette.secondary)
            }
            Text(request.provider.title + " · " + request.project + " · " + request.tool)
                .font(.system(size: 11, weight: .medium)).foregroundStyle(IslandPalette.secondary)
            Text(request.cwd).font(.system(size: 10)).foregroundStyle(IslandPalette.secondary).textSelection(.enabled)
            ScrollView([.vertical, .horizontal]) {
                Text(request.input ?? "").font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }.frame(height: 98).background(IslandPalette.background, in: RoundedRectangle(cornerRadius: 9))
            HStack(spacing: 8) {
                Button("Разрешить один раз") { agents.respond(request, decision: .allow) }
                    .buttonStyle(IslandButtonStyle(.filled)).recordingTarget("Разрешить агенту:" + request.id.uuidString)
                Button("Отклонить") { agents.respond(request, decision: .deny) }
                    .buttonStyle(IslandButtonStyle(.soft)).recordingTarget("Отклонить агенту:" + request.id.uuidString)
                Spacer(minLength: 0)
                Button("В клиенте") { agents.respond(request, decision: .client) }
                    .buttonStyle(IslandButtonStyle(.bare)).help("Вернуть запрос в обычное окно подтверждения клиента")
                    .recordingTarget("Вернуть в клиент:" + request.id.uuidString)
            }
        }.padding(14).islandCard(tint: IslandPalette.mint)
    }
    private func sessionRow(_ session: AgentSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: session.status == .finished ? "checkmark.circle" : session.status == .waiting ? "hand.raised" : "terminal")
                .font(.system(size: 18)).foregroundStyle(session.status == .waiting ? IslandPalette.mint : IslandPalette.lavender)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.provider.title + " · " + session.project).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(status(session) + (session.tool.isEmpty ? "" : " · " + session.tool))
                    .font(.system(size: 11)).foregroundStyle(IslandPalette.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.clock(at: now)).font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit()
                Text("ч : мин").font(.system(size: 9)).foregroundStyle(IslandPalette.secondary)
            }
        }.padding(.vertical, 5)
    }
    private func status(_ session: AgentSession) -> String {
        switch session.status {
        case .working: return "Работает"
        case .waiting: return "Ждёт решения"
        case .finished: return "Готово"
        case .interrupted: return "Остановлен"
        case .unknown: return "Нет свежего статуса"
        }
    }
}
