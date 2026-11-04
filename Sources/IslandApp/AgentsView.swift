import SwiftUI
import IslandCore

@MainActor
struct AgentsView: View {
    @ObservedObject var agents: AgentService
    var now: Date
    var visible = true
    @State private var connections = false
    @State private var connectionKind = "Веб"
    @State private var messageDetails = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Агенты").font(.system(size: 22, weight: .semibold, design: .rounded))
                Spacer()
                if agents.message != nil {
                    Button { messageDetails = true } label: { Image(systemName: "info.circle") }
                        .buttonStyle(IslandButtonStyle(.bare)).help("Инструкция / сообщение подключения")
                }
                if !agents.activity.sessions.isEmpty {
                    Button(connections ? "К работе" : "Подключения") { connections.toggle() }
                        .buttonStyle(IslandButtonStyle(.soft)).recordingTarget("Подключения агентов")
                }
            }
            if connections || agents.activity.sessions.isEmpty {
                connectionView.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if !agents.pending.isEmpty {
                CompactList(items: agents.pending, rowHeight: 210, id: "запросы") { request in approval(request) }
            } else {
                CompactList(items: agents.activity.sessions, rowHeight: 52, id: "агенты") { session in sessionRow(session) }
            }
        }.onAppear { agents.refreshInstallation() }
            .sheet(isPresented: $messageDetails) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Подключение агентов").font(.headline)
                    CompactText(text: agents.message ?? "", id: "сообщение подключения").frame(height: 150)
                    Button("Понятно") { messageDetails = false; agents.message = nil }.buttonStyle(IslandButtonStyle(.filled))
                }.padding(22).frame(width: 440).background(IslandPalette.background).preferredColorScheme(.dark)
            }
    }
    private var connectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            IslandSegments(options: ["Веб", "Терминал", "Браузер"], selection: $connectionKind, title: { $0 })
            if connectionKind == "Браузер" {
                Text("Веб-агенты в Chrome, Edge и Brave").font(.system(size: 14, weight: .semibold))
                Text("Расширение передаёт только начало, завершение и состояние работы на поддерживаемых страницах Claude и ChatGPT/Codex.")
                    .font(.system(size: 11)).foregroundStyle(IslandPalette.secondary)
                Button("Подключить браузер") { agents.installBrowserBridge() }.buttonStyle(IslandButtonStyle(.filled))
                Text("После подключения загрузите папку расширения в браузере и обновите вкладки. Для Safari можно использовать веб-окно Island.")
                    .font(.system(size: 11)).foregroundStyle(IslandPalette.secondary)
            } else {
                ForEach(AgentProvider.allCases) { provider in
                    HStack(spacing: 12) {
                        AgentPetView(provider: provider, size: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(connectionKind == "Веб" ? (provider == .claude ? "Claude" : "ChatGPT / Codex") : provider.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(connectionKind == "Веб" ? "Отдельное веб-окно" : agents.observed.contains(provider) ? "События получены" : agents.installed.contains(provider) ? "Ожидаем задачу" : "Не подключён")
                                .font(.system(size: 10)).foregroundStyle(IslandPalette.secondary)
                        }
                        Spacer()
                        if connectionKind == "Веб" {
                            Button("Открыть") { agents.openWeb(provider) }.buttonStyle(IslandButtonStyle(.soft))
                        } else {
                            Button(agents.installed.contains(provider) ? "Отключить" : "Подключить") {
                                agents.setEnabled(provider, enabled: !agents.installed.contains(provider))
                            }.buttonStyle(IslandButtonStyle(.soft))
                        }
                    }.frame(height: 52)
                }
                Text(connectionKind == "Веб" ? "Статус и время ответа появятся здесь. Вход выполняется на сайте сервиса; если встроенный вход ограничен, подключите расширение браузера." : "Для клиентов с поддержкой hooks. После подключения перезапустите клиент. Разрешения операций доступны через реальные запросы клиента.")
                    .font(.system(size: 11)).foregroundStyle(IslandPalette.secondary)
            }
            Spacer(minLength: 0)
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
            CompactText(text: request.input ?? "", id: "операция " + request.id.uuidString, monospaced: true)
                .padding(8).frame(height: 76).background(IslandPalette.background, in: RoundedRectangle(cornerRadius: 9))
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
                Text(session.displayName + " · " + session.project).font(.system(size: 13, weight: .semibold)).lineLimit(1)
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
