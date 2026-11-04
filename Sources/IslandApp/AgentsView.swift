import SwiftUI
import IslandCore

@MainActor
struct AgentsView: View {
    @ObservedObject var agents: AgentService
    var now: Date
    var visible = true
    @State private var connections = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Агенты").font(.system(size: 22, weight: .semibold, design: .rounded))
                Spacer()
                if !agents.activity.sessions.isEmpty {
                    Button(connections ? "К работе" : "Подключения") { connections.toggle() }
                        .buttonStyle(IslandButtonStyle(.soft)).recordingTarget("Подключения агентов")
                }
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
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Подключите Claude Code или Codex")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("Время работы и запросы разрешения от Claude Code и Codex появятся здесь. Подключите клиент один раз и начните новую задачу.")
                    .font(.system(size: 12)).foregroundStyle(IslandPalette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(AgentProvider.allCases) { provider in
                    HStack(spacing: 12) {
                        AgentPetView(provider: provider, size: 42)
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
                    }.padding(.vertical, 8)
                    if provider != AgentProvider.allCases.last { Divider().overlay(IslandPalette.separator) }
                }
            }
            Text("Для терминальных клиентов с поддержкой hooks. После подключения перезапустите клиент. Браузерные чаты не подключаются; поддержка десктопных клиентов зависит от их версии.")
                .font(.system(size: 11)).foregroundStyle(IslandPalette.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Настройки событий сохраняются с резервной копией. Island не запрашивает ключи или вход в аккаунт. Если Island закрыт, запрос вернётся в клиент.")
                .font(.system(size: 11)).foregroundStyle(IslandPalette.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func approval(_ request: AgentEvent) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                AgentPetView(provider: request.provider, size: 24, waiting: true, visible: visible)
                Text("Нужно разрешение").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(max(0, Int(request.expiresAt.timeIntervalSince(now)))) с")
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(IslandPalette.secondary)
            }
            Text(request.provider.title + " · " + request.project + " · " + request.tool)
                .font(.system(size: 11, weight: .medium)).foregroundStyle(IslandPalette.secondary).lineLimit(1)
            Text(request.cwd).font(.system(size: 10)).foregroundStyle(IslandPalette.secondary).lineLimit(2)
                .help(request.cwd).textSelection(.enabled)
            GeometryReader { geometry in
                ScrollView([.vertical, .horizontal]) {
                    Text(request.input ?? "").font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                        .frame(minWidth: max(0, geometry.size.width - 20), alignment: .topLeading).padding(10)
                }
            }.frame(height: 64).background(IslandPalette.background, in: RoundedRectangle(cornerRadius: 9))
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
        }.padding(10).islandCard(tint: IslandPalette.mint)
    }
    private func sessionRow(_ session: AgentSession) -> some View {
        HStack(spacing: 12) {
            AgentPetView(provider: session.provider, size: 42, working: session.status == .working, waiting: session.status == .waiting, visible: visible)
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
