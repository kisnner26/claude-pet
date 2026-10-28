import SwiftUI
import ARKit
import VistoCore

struct PairView: View {
    @ObservedObject var model: PhoneModel
    @State private var text = ""
    @State private var wrong = false
    @State private var scanning = false

    var body: some View {
        ZStack {
            VTBackdrop()
            VStack(alignment: .leading, spacing: 18) {
                Spacer()
                Text("VISTO").font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(3).foregroundStyle(VT.mute)
                VStack(alignment: .leading, spacing: -6) {
                    Text("Aprueba.").foregroundStyle(.white)
                    Text("Desde aquí.").foregroundStyle(VT.duo)
                }.font(.system(size: 54, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                Text("Claude Code pide permiso en tu Mac y tú respondes con un toque, en el iPhone o en el Apple Watch.")
                    .font(.system(size: 15)).foregroundStyle(VT.mute).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    Text("CÓDIGO DE EMPAREJAMIENTO").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.6).foregroundStyle(VT.mute)
                    TextField("XXXX-XXXX-XXXX", text: $text)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced)).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .padding(16).glassEffect(.regular, in: .rect(cornerRadius: 20))
                        .onChange(of: text) { _, v in wrong = false; let n = String(Pairing.normalize(v).prefix(12)); let shown = n.count == 12 ? Pairing.display(n) : n; if shown != v { text = shown } }
                    if wrong { Text("Ese código no es válido. Tiene 12 caracteres.").font(.system(size: 12)).foregroundStyle(VT.red) }
                    Text("En claude pet: Ajustes → seguridad → enviar permisos a Visto.").font(.system(size: 12)).foregroundStyle(VT.mute)
                }
                Button { scanning = true } label: { Label("Escanear código de claude pet", systemImage: "qrcode.viewfinder").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 6) }
                    .buttonStyle(.glass)
                Button { wrong = !model.pair(text) } label: { Text("Emparejar").font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 6) }
                    .buttonStyle(.glassProminent).tint(VT.blue).disabled(!Pairing.isValid(text))
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .fullScreenCover(isPresented: $scanning) {
            ZStack(alignment: .topTrailing) {
                QRScanner { code, relay in scanning = false; _ = model.pair(code, relay: relay) }.ignoresSafeArea()
                Button("Cerrar") { scanning = false }.buttonStyle(.glass).padding(20)
            }.overlay(alignment: .bottom) { Text("Apunta al cuadro de Ajustes → permisos en la Mac").font(.system(size: 14, weight: .medium)).padding(12).glassEffect(.regular, in: .capsule).padding(.bottom, 50) }
        }
    }
}

struct HomeView: View {
    @ObservedObject var model: PhoneModel
    @ObservedObject var client: VistoClient
    @ObservedObject private var feel = Feel.shared
    @State private var showSettings = false
    @State private var showAR = false

    private func label(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.6).foregroundStyle(VT.mute).padding(.top, 6)
    }

    var body: some View {
        ZStack {
            VTBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if let n = client.notice { notice(n) }
                    if client.isConnected { hero }
                    if !client.agents.isEmpty {
                        label("AGENTES")
                        VStack(spacing: 14) { ForEach(client.agents) { AgentRow(agent: $0) } }
                            .padding(18).frame(maxWidth: .infinity, alignment: .leading).glassEffect(.regular, in: .rect(cornerRadius: 24))
                    }
                    if !client.asks.isEmpty || !client.questions.isEmpty {
                        label("ESPERAN TU RESPUESTA")
                        ForEach(client.asks) { AskCard(ask: $0, model: model) }
                        ForEach(client.questions) { QuestionCard(q: $0, model: model) }
                    } else if client.agents.isEmpty { empty }
                    if let p = client.plan, p.five != nil || p.week != nil { label("TU PLAN"); planCard(p) }
                    if !client.feed.isEmpty { label("ACTIVIDAD"); feedCard }
                    if client.isConnected { controls; if ARWorldTrackingConfiguration.isSupported { arButton } }
                    if !model.history.isEmpty { label("TUS DECISIONES"); historyCard }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 30)
            }
        }
        .overlay { EdgeGlow(pending: !client.asks.isEmpty || !client.questions.isEmpty, feel: feel) }
        .onAppear { feel.startMotion() }
        .onDisappear { feel.stopMotion() }
        .sheet(isPresented: $showSettings) { SettingsView(model: model, client: client) }
        .fullScreenCover(isPresented: $showAR) { ARScreen(model: model, client: client) }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("VISTO").font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(3).foregroundStyle(VT.mute)
                HStack(spacing: 6) {
                    Circle().fill(client.isConnected ? VT.green : VT.amber).frame(width: 7, height: 7)
                    Text(client.isConnected ? L.tr("Conectado") + " · \(client.hostName ?? "Mac")" : L.tr("Buscando claude pet")).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(client.isConnected ? .white : VT.mute)
                }
                if !client.isConnected, client.detail.contains("rechazó") {
                    Text(client.detail).font(.system(size: 12)).foregroundStyle(VT.amber).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button { showSettings = true } label: { Image(systemName: "gearshape").font(.system(size: 17)).frame(width: 44, height: 44) }.buttonStyle(.glass).clipShape(Circle())
        }
    }

    private var hero: some View {
        let lead = client.agents.first(where: \.isBusy) ?? client.agents.first(where: { $0.state == "waiting" }) ?? client.agents.first
        return VStack(spacing: 0) {
            PetHero(agent: lead, plan: client.plan, size: 250, tilt: feel.tiltOffset)
            HeartbeatLine(state: lead?.state ?? "idle", color: VTFormat.stateColor(lead?.state ?? "idle")).frame(height: 36).padding(.horizontal, 30)
            Text(lead.map { "\(VTFormat.agentName($0.agent)) · \(VTFormat.state($0.state))" } ?? "Sin agentes activos").font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(VT.mute).padding(.top, 4)
            if client.plan?.five != nil || lead?.contextRemaining != nil {
                HStack(spacing: 14) {
                    if let f = client.plan?.five { legend("5 h", f.remaining(), VT.blue) }
                    if let w = client.plan?.week { legend("7 d", w.remaining(), VT.codex) }
                    if let c = lead?.contextRemaining { legend("ctx", c, VT.claude) }
                }.padding(.top, 8)
            }
        }.frame(maxWidth: .infinity)
    }

    private func legend(_ t: String, _ v: Int, _ c: Color) -> some View {
        HStack(spacing: 5) { Circle().fill(c).frame(width: 6, height: 6); Text("\(t) \(v)%").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(VT.mute) }
    }

    private func planCard(_ p: PlanSnapshot) -> some View {
        PlanBars(plan: p).padding(18).frame(maxWidth: .infinity, alignment: .leading).glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var feedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(client.feed.suffix(6).reversed())) { st in
                HStack(spacing: 8) {
                    Circle().fill(VTFormat.agentColor(st.agent)).frame(width: 6, height: 6)
                    Text(st.tool).font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text(st.target).font(.system(size: 12, design: .monospaced)).foregroundStyle(VT.mute).lineLimit(1).truncationMode(.head)
                    Spacer(minLength: 4)
                    if !st.delta.isEmpty { Text(st.delta).font(.system(size: 11, design: .monospaced)).foregroundStyle(VT.green) }
                }
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var arButton: some View {
        Button { showAR = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "arkit").font(.system(size: 20, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ver en realidad aumentada").font(.system(size: 15, weight: .semibold))
                    Text("Las mascotas sobre tu mesa, con su estado y los permisos.").font(.system(size: 12)).foregroundStyle(VT.mute)
                }
                Spacer()
            }.padding(18).frame(maxWidth: .infinity).glassEffect(.regular, in: .rect(cornerRadius: 24))
        }.buttonStyle(.plain)
    }

    private var controls: some View {
        Toggle(isOn: Binding(get: { client.focus }, set: { client.setFocus($0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Modo foco en la Mac").font(.system(size: 15, weight: .semibold))
                Text("Silencia lo menor y deja pasar lo que pide una decisión.").font(.system(size: 12)).foregroundStyle(VT.mute)
            }
        }.tint(VT.blue).padding(18).glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(model.history.prefix(6)) { r in
                HStack(spacing: 8) {
                    Image(systemName: r.allowed ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(r.allowed ? VT.green : VT.red)
                    Text(r.tool).font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text(r.project).font(.system(size: 12, design: .monospaced)).foregroundStyle(VT.mute).lineLimit(1)
                    Spacer()
                    Text(r.at, style: .time).font(.system(size: 11, design: .monospaced)).foregroundStyle(VT.mute)
                }
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func notice(_ n: String) -> some View {
        HStack { Image(systemName: "exclamationmark.circle"); Text(n).font(.system(size: 13)); Spacer(); Button("Ok") { client.clearNotice() } }
            .padding(14).foregroundStyle(VT.amber).glassEffect(.regular.tint(VT.amber.opacity(0.2)), in: .rect(cornerRadius: 18))
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(client.isConnected ? "Todo tranquilo." : "Esperando a claude pet.").font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(client.isConnected ? .white : VT.mute)
            Text(client.isConnected ? "Cuando Claude o Codex trabajen, los verás aquí. Si piden permiso o te preguntan algo, aparecerá en el móvil y en el reloj." : (client.detail.isEmpty ? "Abre claude pet en la Mac, en la misma red." : client.detail))
                .font(.system(size: 14)).foregroundStyle(VT.mute).fixedSize(horizontal: false, vertical: true)
            if !client.isConnected { Button("Reintentar") { model.retry() }.buttonStyle(.glass) }
        }.padding(.top, 30)
    }
}

struct AskCard: View {
    let ask: Ask
    @ObservedObject var model: PhoneModel
    @State private var drag: CGFloat = 0
    @State private var confirmAlways = false
    @State private var crossed = false
    private let threshold: CGFloat = 110

    private func deny() -> some View {
        Button { model.answer(ask, allow: false) } label: { Text("Denegar").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 6) }.buttonStyle(.glass).tint(VT.red)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(ask.tool).font(.system(size: 22, weight: .heavy, design: .rounded))
                Text(ask.project).font(.system(size: 12, design: .monospaced)).foregroundStyle(VT.mute).lineLimit(1)
                Spacer()
                RiskChip(risk: ask.risk)
            }
            if !ask.detail.isEmpty {
                Text(ask.detail).font(.system(size: 13, design: .monospaced)).lineLimit(8).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.35)))
            }
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let left = max(0, Int(ask.expires.timeIntervalSince(ctx.date)))
                Text("caduca en \(left) s").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(left < 20 ? VT.amber : VT.mute)
            }
            if ask.canAllow {
                HStack(spacing: 10) {
                    deny()
                    Button { model.answer(ask, allow: true) } label: { Text("Permitir").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 6) }.buttonStyle(.glassProminent).tint(VT.blue)
                }
                if ask.canAlways {
                    Button { confirmAlways = true } label: { Text("Permitir siempre").font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 4) }.buttonStyle(.glass)
                        .confirmationDialog(L.t("¿Permitir siempre \(ask.tool)?", "Always allow \(ask.tool)?"), isPresented: $confirmAlways, titleVisibility: .visible) {
                            Button("Permitir siempre", role: .destructive) { model.answerAlways(ask) }
                            Button("Cancelar", role: .cancel) {}
                        } message: { Text("Se guarda una regla en la Mac para esta petición y las iguales. Puedes revocarla en Ajustes → permisos.") }
                }
            } else {
                Text("Riesgo alto: desde aquí solo puedes denegar. Para permitirlo, hazlo en la Mac.").font(.system(size: 12)).foregroundStyle(VT.amber).fixedSize(horizontal: false, vertical: true)
                deny()
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(VT.riskColor(ask.risk).opacity(0.10)), in: .rect(cornerRadius: 26))
        .overlay(alignment: drag >= 0 ? .leading : .trailing) { swipeLabel }
        .offset(x: drag).rotationEffect(.degrees(Double(drag) / 14), anchor: .bottom)
        .gesture(DragGesture(minimumDistance: 18)
            .onChanged { v in
                guard abs(v.translation.width) > abs(v.translation.height) else { return }
                // riesgo alto: a la derecha casi no cede, para que se note que no se puede permitir desde aquí
                drag = (v.translation.width > 0 && !ask.canAllow) ? v.translation.width / 6 : v.translation.width
                let now = abs(drag) > threshold
                if now != crossed { crossed = now; if now { Feel.shared.threshold() } }
            }
            .onEnded { _ in
                let d = drag
                if d > threshold, ask.canAllow { withAnimation(.snappy) { drag = 700 }; model.answer(ask, allow: true) }
                else if d < -threshold { withAnimation(.snappy) { drag = -700 }; model.answer(ask, allow: false) }
                else { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { drag = 0 }; if d > threshold { Feel.shared.denied() } }
                crossed = false
            })
    }

    @ViewBuilder private var swipeLabel: some View {
        let p = min(1, abs(drag) / threshold)
        if abs(drag) > 8 {
            Text(drag > 0 ? "PERMITIR" : "DENEGAR").font(.system(size: 13, weight: .black, design: .monospaced)).tracking(1.5)
                .padding(.horizontal, 14).padding(.vertical, 8).foregroundStyle(.white)
                .background(Capsule().fill(drag > 0 ? VT.blue : VT.red)).opacity(p).scaleEffect(0.8 + 0.2 * p).padding(16)
        }
    }
}

/// Una pregunta de Claude con opciones: se elige y se envía. Solo viajan los índices elegidos.
struct QuestionCard: View {
    let q: QAsk
    @ObservedObject var model: PhoneModel
    @State private var picks: [Set<Int>] = []

    private var ready: Bool { picks.count == q.items.count && picks.allSatisfy { !$0.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Claude pregunta").font(.system(size: 20, weight: .heavy, design: .rounded))
                Text(q.project).font(.system(size: 12, design: .monospaced)).foregroundStyle(VT.mute).lineLimit(1)
                Spacer()
            }
            ForEach(Array(q.items.enumerated()), id: \.offset) { i, item in
                VStack(alignment: .leading, spacing: 8) {
                    if !item.header.isEmpty { Text(item.header.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.4).foregroundStyle(VT.mute) }
                    Text(item.question).font(.system(size: 15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(item.options.enumerated()), id: \.offset) { j, opt in
                        let on = picks.indices.contains(i) && picks[i].contains(j)
                        Button { toggle(i, j, multi: item.multi) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: on ? (item.multi ? "checkmark.square.fill" : "largecircle.fill.circle") : (item.multi ? "square" : "circle")).foregroundStyle(on ? VT.blue : VT.mute)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(opt).font(.system(size: 14, weight: .medium)).multilineTextAlignment(.leading)
                                    if j < item.descriptions.count, !item.descriptions[j].isEmpty { Text(item.descriptions[j]).font(.system(size: 11)).foregroundStyle(VT.mute).multilineTextAlignment(.leading) }
                                }
                                Spacer(minLength: 0)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 14).fill(on ? VT.blue.opacity(0.18) : Color.black.opacity(0.28)))
                        }.buttonStyle(.plain)
                    }
                }
            }
            Button { model.reply(q, picks: picks.map { $0.sorted() }) } label: { Text("Enviar respuesta").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 6) }
                .buttonStyle(.glassProminent).tint(VT.blue).disabled(!ready)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).glassEffect(.regular.tint(VT.codex.opacity(0.10)), in: .rect(cornerRadius: 26))
        .onAppear { if picks.count != q.items.count { picks = Array(repeating: [], count: q.items.count) } }
    }

    private func toggle(_ i: Int, _ j: Int, multi: Bool) {
        if picks.count != q.items.count { picks = Array(repeating: [], count: q.items.count) }
        if multi { if picks[i].contains(j) { picks[i].remove(j) } else { picks[i].insert(j) } } else { picks[i] = [j] }
    }
}

struct SettingsView: View {
    @ObservedObject var model: PhoneModel
    @ObservedObject var client: VistoClient
    @ObservedObject private var feel = Feel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var relayText = VistoStore.relay?.display ?? ""
    @State private var relayTLS = VistoStore.relay?.tls ?? false

    var body: some View {
        NavigationStack {
            List {
                Section("Conexión") {
                    LabeledContent("Estado", value: client.isConnected ? L.t("Conectado a \(client.hostName ?? "Mac")", "Connected to \(client.hostName ?? "Mac")") : "Sin conexión")
                    LabeledContent("Apple Watch", value: model.watchPaired ? "Emparejado" : "No encontrado")
                    Button("Reintentar") { model.retry() }
                }
                Section {
                    Picker(selection: $model.language) { ForEach(Lang.allCases) { Text(verbatim: $0.name).tag($0) } } label: { Text("Idioma") }
                }
                Section {
                    Toggle("Pedir Face ID para permitir", isOn: $model.requireFaceID)
                    Toggle("Sonidos", isOn: $feel.sounds)
                    Toggle("Háptica", isOn: $feel.haptics)
                    Toggle("Voz: lee los permisos en voz alta", isOn: $feel.voice)
                    Toggle("Destello de linterna al pedir permiso", isOn: $feel.torch)
                    Toggle("Inclinar la mascota con el giroscopio", isOn: $feel.tilt)
                    Button("Probar") { Feel.shared.ask(tool: "Bash", project: "claude-pet", risky: false) }
                } header: { Text("Sensaciones") } footer: { Text("Los sonidos se sintetizan en el teléfono y respetan el interruptor de silencio. La voz y la linterna empiezan apagadas.") }
                Section {
                    TextField("mi.servidor.com:7777", text: $relayText).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Toggle("TLS (wss/https)", isOn: $relayTLS)
                    if !relayText.isEmpty, RelayEndpoint.parse(relayText, tls: relayTLS) == nil { Text("Dirección no válida.").foregroundStyle(VT.amber).font(.system(size: 12)) }
                } header: { Text("Relay (fuera de casa)") } footer: { Text("Opcional: tu propio servidor relay para usar Visto sin estar en la misma red que la Mac. Solo copia bytes cifrados de extremo a extremo. También se rellena al escanear el QR de claude pet.") }
                .onChange(of: relayText) { _, v in model.relay = RelayEndpoint.parse(v, tls: relayTLS) }
                .onChange(of: relayTLS) { _, v in model.relay = RelayEndpoint.parse(relayText, tls: v) }
                Section("Historial") {
                    Button("Borrar mis decisiones guardadas", role: .destructive) { model.clearHistory() }
                }
                Section {
                    Button("Olvidar este emparejamiento", role: .destructive) { model.unpair(); dismiss() }
                } footer: { Text("Los permisos solo llegan mientras Visto está abierta o puede despertarse por la red local. Si el iPhone la suspende, abre la app para reconectar.") }
            }
            .navigationTitle("Ajustes").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
