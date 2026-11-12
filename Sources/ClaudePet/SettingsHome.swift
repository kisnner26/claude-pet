import SwiftUI
import AppKit

/// Pagina de inicio de los ajustes: un tablero con lo de hoy, la semana, la racha, cada agente, el plan y el contexto.
/// Todo sale de lo que la app ya guarda (`ActivityStats`, `PlanUsage`, `ContextMeter`); no se lee ni se escribe nada nuevo.
struct ResumenPage: View {
    @ObservedObject var store: PetStore
    @ObservedObject private var plan: PlanUsageMonitor
    @Environment(\.settingsDensity) private var density
    @Environment(\.settingsHighContrast) private var high
    @State private var days: [ActivityDay] = []
    @State private var previousWeek = 0

    init(store: PetStore) {
        self.store = store
        _plan = ObservedObject(wrappedValue: store.plan)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density.cardGap) {
            HStack(alignment: .top, spacing: density.cardGap) {
                agentTile(.claude)
                agentTile(.codex)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: density.cardGap) {
                todayTile
                streakTile
            }
            .fixedSize(horizontal: false, vertical: true)
            weekTile
            HStack(alignment: .top, spacing: density.cardGap) {
                planTile
                contextTile
            }
            .fixedSize(horizontal: false, vertical: true)
            SCard(title: "compartir la semana") {
                SRow(title: "resumen de la semana", detail: "texto para pegar, o una imagen para guardar") {
                    HStack(spacing: 8) {
                        SButton(title: "copiar", symbol: "doc.on.doc") {
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.weeklyRecap.markdown(showProject: store.shareProject), forType: .string)
                        }
                        SButton(title: "imagen…", symbol: "photo") {
                            let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "mi-semana.png"
                            if panel.runModal() == .OK, let url = panel.url, let data = RecapCard.png(store.weeklyRecap, showProject: false) { try? data.write(to: url) }
                        }
                    }
                }
            }
            SCard(title: "atajos de trabajo") {
                SRow(title: "mission control", detail: "cambios del proyecto, ramas y conflictos") {
                    SButton(title: "abrir", symbol: "square.grid.2x2") { AppController.shared.showMissionDashboard() }
                }
                SDivider()
                SRow(title: "relevo de sesión", detail: "continuar la misma tarea en otro agente") {
                    SButton(title: "abrir", symbol: "arrow.triangle.swap") { AppController.shared.showRelay() }
                }
            }
            LabCard(store: store)
        }
        .onAppear { reload() }
    }

    private func reload() {
        store.refreshWeeklyRecap()
        let data = ActivityStats.shared.snapshot()
        let now = Date()
        days = ActivityTrend.days(data, endingAt: now, count: 7)
        let before = Calendar(identifier: .gregorian).date(byAdding: .day, value: -7, to: now) ?? now
        previousWeek = ActivityTrend.total(ActivityTrend.days(data, endingAt: before, count: 7))
    }

    // MARK: agentes

    private enum AgentSide { case claude, codex }

    private func agentTile(_ side: AgentSide) -> some View {
        let isClaude = side == .claude
        let name = isClaude ? "claude" : "codex"
        let tint = isClaude ? SettingsTheme.agentClaude : SettingsTheme.agentCodex
        let present = isClaude ? store.claudePresent : store.codexPresent
        let state = isClaude ? store.state : store.codexState
        let working = present && state != .idle
        return STile(title: name, trailing: present ? "conectado" : "sin sesión", tint: tint) {
            HStack(spacing: 14) {
                Group {
                    if isClaude { ClaudeSprite(state: store.state, outfits: store.outfitsNow()) }
                    else { CodexSprite(face: working ? .typing(1) : .prompt(cursor: true), skin: store.codexSkin, outfits: store.outfitsNow(for: .codex)) }
                }
                .frame(width: 64, height: 64).opacity(present ? 1 : 0.55)
                VStack(alignment: .leading, spacing: 4) {
                    Text(working ? state.label.lowercased() : "en reposo").font(.system(size: 20, weight: .semibold)).lineLimit(1)
                    Text(isClaude && working ? store.sessionSummary : (present ? "esperando una tarea" : "abre una sesión para verlo aquí"))
                        .font(.system(size: 11.5)).foregroundStyle(SettingsTheme.muted(high)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: hoy y racha

    private var todayTile: some View {
        let t = store.today
        let rows: [(String, Int, Color)] = [("herramientas", t.tools, SettingsTheme.accent), ("permisos", t.permissions, SettingsTheme.accent), ("errores", t.errors, SettingsTheme.red)]
        let fr = TodayBars.fractions(rows.map(\.1))
        return STile(title: "hoy", trailing: t.activity == 0 ? "sin actividad" : nil) {
            HStack(alignment: .top, spacing: 18) {
                SStat(value: "\(t.sessions)", label: "sesiones").frame(width: 120)
                VStack(spacing: 9) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                SLabel(r.0)
                                Spacer(minLength: 4)
                                Text("\(r.1)").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(r.1 == 0 ? SettingsTheme.muted(high) : Color.white)
                            }
                            SMeter(fraction: r.1 == 0 ? 0 : max(0.06, fr[i]), tint: r.2, height: 4)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var streakTile: some View {
        let r = store.weeklyRecap
        let flags = ActivityTrend.activeFlags(days)
        return STile(title: "racha", trailing: "nivel \(r.level)") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(r.streak)").font(.system(size: 34, weight: .semibold)).monospacedDigit()
                    Text(r.streak == 1 ? "día seguido" : "días seguidos").font(.system(size: 12)).foregroundStyle(SettingsTheme.muted(high))
                }
                HStack(spacing: 6) {
                    ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2).fill(flags[i] ? SettingsTheme.accent : Color.white.opacity(0.10)).frame(height: 14)
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(d.isToday ? Color.white.opacity(0.8) : Color.clear, lineWidth: 1))
                            Text(d.label).font(.system(size: 9, design: .monospaced)).foregroundStyle(d.isToday ? Color.white : SettingsTheme.muted(high))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(r.activeDays) de 7 días con actividad")
            }
        }
    }

    // MARK: semana

    private var weekTile: some View {
        let total = ActivityTrend.total(days)
        let change = ActivityTrend.changeLabel(ActivityTrend.change(current: total, previous: previousWeek))
        let claude = days.reduce(0) { $0 + $1.claude }, codex = days.reduce(0) { $0 + $1.codex }
        let r = store.weeklyRecap
        return STile(title: "esta semana", trailing: r.busiestDay.map { "día más activo: \($0)" }) {
            HStack(alignment: .bottom, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    SStat(value: "\(total)", label: "acciones")
                    if let change { Text(change).font(.system(size: 11, design: .monospaced)).foregroundStyle(SettingsTheme.muted(high)).fixedSize(horizontal: false, vertical: true) }
                    VStack(alignment: .leading, spacing: 5) {
                        agentCount("claude", claude, SettingsTheme.agentClaude)
                        agentCount("codex", codex, SettingsTheme.agentCodex)
                    }
                    if let p = r.topProject { SBadge(text: p, color: SettingsTheme.green).help("proyecto más usado") }
                }
                .frame(width: 190, alignment: .leading)
                SBars(values: days.map { Double($0.activity) }, labels: days.map(\.label), highlight: days.count - 1, height: density == .comfortable ? 92 : 70,
                      summary: "actividad de los últimos 7 días: " + days.map { "\($0.activity)" }.joined(separator: ", "))
            }
        }
    }

    private func agentCount(_ name: String, _ n: Int, _ tint: Color) -> some View {
        HStack(spacing: 7) {
            Rectangle().fill(tint).frame(width: 6, height: 6)
            Text(name).font(.system(size: 11, design: .monospaced)).foregroundStyle(SettingsTheme.muted(high))
            Spacer(minLength: 4)
            Text("\(n)").font(.system(size: 11, weight: .medium, design: .monospaced))
        }
    }

    // MARK: plan y contexto

    private func toneColor(_ t: GaugeTone) -> Color { t == .critical ? SettingsTheme.red : t == .caution ? SettingsTheme.amber : SettingsTheme.agentClaude }

    private var planTile: some View {
        let gauges = PlanGauge.all(plan.usage, now: Date())
        return STile(title: "plan de claude", trailing: plan.usage.map { $0.isStale(now: Date()) ? "dato viejo" : nil } ?? nil) {
            if gauges.isEmpty {
                emptyNote("sin datos del plan todavía. aparecen cuando claude trabaja.")
            } else {
                HStack(spacing: 16) {
                    ForEach(gauges, id: \.title) { g in
                        HStack(spacing: 12) {
                            SRing(fraction: g.remaining, label: "\(Int((g.remaining * 100).rounded()))", tint: toneColor(g.tone), size: 62)
                            VStack(alignment: .leading, spacing: 3) {
                                SLabel(g.title)
                                Text(g.resetText.map { "reinicia en \($0)" } ?? "queda").font(.system(size: 10.5)).foregroundStyle(SettingsTheme.muted(high)).lineLimit(1).fixedSize()
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var contextTile: some View {
        STile(title: "contexto") {
            VStack(alignment: .leading, spacing: 14) {
                contextRow("claude", store.contextReading, SettingsTheme.agentClaude)
                contextRow("codex", store.codexContextReading, SettingsTheme.agentCodex)
            }
        }
    }

    @ViewBuilder private func contextRow(_ name: String, _ reading: ContextReading?, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SLabel(name, tint: tint)
                Spacer(minLength: 4)
                if let r = reading { Text("\(r.remainingPercent) % libre").font(.system(size: 11, weight: .medium, design: .monospaced)) }
                else { Text("sin sesión").font(.system(size: 11, design: .monospaced)).foregroundStyle(SettingsTheme.muted(high)) }
            }
            SMeter(fraction: reading?.remainingFraction ?? 0, tint: reading.map { toneColor($0.pressure.gaugeTone) } ?? tint, height: 5)
        }
        .accessibilityElement(children: .combine)
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(SettingsTheme.muted(high)).fixedSize(horizontal: false, vertical: true)
    }
}
