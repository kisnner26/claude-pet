import SwiftUI
import VistoCore

struct WatchHome: View {
    @ObservedObject var model: WatchModel

    var body: some View {
        Group {
            if model.code == nil {
                VStack(spacing: 8) {
                    Image(systemName: "iphone.and.arrow.forward").font(.title2)
                    Text("Empareja Visto en el iPhone").font(.footnote).foregroundStyle(VT.mute).multilineTextAlignment(.center)
                }
            } else {
                NavigationStack {
                    ScrollView {
                        let snap = model.snap
                        VStack(spacing: 10) {
                            HStack(spacing: 5) {
                                Circle().fill(model.connected ? VT.green : VT.amber).frame(width: 6, height: 6)
                                Text(model.connected ? "Conectado" : "Buscando").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(VT.mute)
                                Spacer()
                            }
                            if model.asks.isEmpty && snap.questions.isEmpty {
                                let lead = snap.agents.first(where: \.isBusy) ?? snap.agents.first
                                PetHero(agent: lead, plan: snap.plan, size: 150)
                                HeartbeatLine(state: lead?.state ?? "idle", color: VTFormat.stateColor(lead?.state ?? "idle")).frame(height: 22).padding(.horizontal, 8)
                            }
                            if !model.asks.isEmpty || !snap.questions.isEmpty {
                                ForEach(model.asks) { WatchAsk(ask: $0, model: model) }
                                ForEach(snap.questions) { WatchQuestion(q: $0, model: model) }
                            }
                            if !snap.agents.isEmpty {
                                VStack(spacing: 10) { ForEach(snap.agents) { AgentRow(agent: $0, compact: true) } }
                                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).glassEffect(.regular, in: .rect(cornerRadius: 20))
                            } else if model.asks.isEmpty && snap.questions.isEmpty {
                                Text(snap.agents.isEmpty ? "Todo tranquilo" : "").font(.system(size: 15, weight: .bold, design: .rounded))
                            }
                            if let p = snap.plan, p.five != nil || p.week != nil { PlanBars(plan: p, compact: true).padding(10).glassEffect(.regular, in: .rect(cornerRadius: 18)) }
                            if let last = snap.feed.last {
                                Text("\(last.tool) · \(last.target)").font(.system(size: 10, design: .monospaced)).foregroundStyle(VT.mute).lineLimit(1).truncationMode(.head)
                            }
                            if model.connected {
                                Toggle("Girar muñeca: denegar", isOn: $model.wristDeny).font(.system(size: 12, weight: .medium)).tint(VT.red)
                                Toggle("Modo foco", isOn: Binding(get: { snap.focus }, set: { model.setFocus($0) })).font(.system(size: 13, weight: .medium)).tint(VT.blue)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
        }
        .containerBackground(for: .navigation) { VTBackdrop() }
    }
}

struct WatchAsk: View {
    let ask: Ask
    @ObservedObject var model: WatchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(ask.tool).font(.system(size: 16, weight: .heavy, design: .rounded)).lineLimit(1)
                Spacer(minLength: 2)
                Circle().fill(VT.riskColor(ask.risk)).frame(width: 7, height: 7)
            }
            Text(ask.project).font(.system(size: 10, design: .monospaced)).foregroundStyle(VT.mute).lineLimit(1)
            if !ask.detail.isEmpty { Text(ask.detail).font(.system(size: 11, design: .monospaced)).lineLimit(4) }
            HStack(spacing: 6) {
                Button { model.answer(ask, allow: false) } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(maxWidth: .infinity) }.tint(VT.red)
                // Double Tap (Apple Watch Series 9, Ultra 2 y posteriores): juntar índice y pulgar permite
                if ask.canAllow { Button { model.answer(ask, allow: true) } label: { Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).frame(maxWidth: .infinity) }.tint(VT.blue).buttonStyle(.glassProminent).handGestureShortcut(.primaryAction) }
            }
            if !ask.canAllow { Text("Riesgo alto: apruébalo en la Mac.").font(.system(size: 10)).foregroundStyle(VT.amber) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).glassEffect(.regular.tint(VT.riskColor(ask.risk).opacity(0.10)), in: .rect(cornerRadius: 22))
    }
}

/// En el reloj solo se responden las preguntas de una sola elección; las demás se contestan en el iPhone.
struct WatchQuestion: View {
    let q: QAsk
    @ObservedObject var model: WatchModel

    private var simple: Bool { q.items.count == 1 && q.items[0].multi == false }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Claude pregunta").font(.system(size: 14, weight: .heavy, design: .rounded))
            Text(q.items.first?.question ?? "").font(.system(size: 12)).lineLimit(5)
            if simple, let item = q.items.first {
                ForEach(Array(item.options.prefix(4).enumerated()), id: \.offset) { j, opt in
                    Button { model.reply(q, picks: [[j]]) } label: { Text(opt).font(.system(size: 12, weight: .medium)).lineLimit(2).frame(maxWidth: .infinity) }.tint(VT.blue)
                }
            } else {
                Text("Respóndela en el iPhone.").font(.system(size: 10)).foregroundStyle(VT.amber)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).glassEffect(.regular.tint(VT.codex.opacity(0.10)), in: .rect(cornerRadius: 22))
    }
}
