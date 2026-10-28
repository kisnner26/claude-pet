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
                        VStack(spacing: 10) {
                            HStack(spacing: 5) {
                                Circle().fill(model.connected ? VT.green : VT.amber).frame(width: 6, height: 6)
                                Text(model.connected ? "Conectado" : "Buscando").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(VT.mute)
                                Spacer()
                            }
                            if let p = model.plan, p.five != nil || p.week != nil { PlanBars(plan: p, compact: true).padding(10).glassEffect(.regular, in: .rect(cornerRadius: 18)) }
                            if model.asks.isEmpty {
                                Text("Nada que aprobar").font(.system(size: 17, weight: .bold, design: .rounded)).padding(.top, 14)
                                Text("Aparecerá aquí cuando Claude pida permiso.").font(.system(size: 11)).foregroundStyle(VT.mute).multilineTextAlignment(.center)
                            } else {
                                ForEach(model.asks) { WatchAsk(ask: $0, model: model) }
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
                if ask.canAllow { Button { model.answer(ask, allow: true) } label: { Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).frame(maxWidth: .infinity) }.tint(VT.blue).buttonStyle(.glassProminent) }
            }
            if !ask.canAllow { Text("Riesgo alto: apruébalo en la Mac.").font(.system(size: 10)).foregroundStyle(VT.amber) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).glassEffect(.regular.tint(VT.riskColor(ask.risk).opacity(0.10)), in: .rect(cornerRadius: 22))
    }
}
