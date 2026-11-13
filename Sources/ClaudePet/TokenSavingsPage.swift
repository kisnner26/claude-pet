import SwiftUI
import AppKit

/// Pagina «ahorro» de los ajustes: cuanto se gasta, donde se va y que se puede hacer. Solo numeros y porcentajes, sin dinero.
struct TokenSavingsPage: View {
    @ObservedObject var store: PetStore
    @ObservedObject private var model = TokenSavingsModel.shared
    @State private var concise = SavingsPreferences.concise
    @State private var conciseText = SavingsPreferences.conciseText
    @State private var advice = SavingsPreferences.advice

    private static let colors: [Color] = [SettingsTheme.claude, SettingsTheme.green, SettingsTheme.amber, Color.white.opacity(0.55)]
    private var recent: [SessionTokens] { Array(model.snapshot.sessions.prefix(6)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            figures
            sessions
            projects
            claudeMd
            switches
            tips
            tools
        }
        .onAppear { model.refresh() }
    }

    // MARK: cifras

    private var figures: some View {
        let total = model.snapshot.total
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SStat(value: total.cacheHitPercent.map { "\($0) %" } ?? "—", label: "aciertos de caché")
                SStat(value: store.contextReading.map { "\($0.remainingPercent) %" } ?? (TokenSavingsModel.preview ? "38 %" : "—"), label: "contexto restante ahora")
                SStat(value: model.loaded ? TokenFormat.short(total.total) : "…", label: L.t("tokens en \(model.snapshot.sessions.count) sesiones", "tokens in \(model.snapshot.sessions.count) sessions"))
            }
            HStack(spacing: 10) {
                Text("lectura local de ~/.claude/projects, 14 días como máximo. sin precios: los tokens son lo único que no cambia.")
                    .font(.system(size: 11)).foregroundStyle(SettingsTheme.mute).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                SButton(title: model.loading ? "leyendo…" : "actualizar", symbol: "arrow.clockwise") { model.refresh() }
            }
        }
    }

    private var sessions: some View {
        SCard(title: "tokens por sesión reciente", footer: "entrada nueva es lo que se paga entero; la caché leída cuesta mucho menos. una sesión con pocos aciertos de caché suele tener pausas largas o un contexto que cambia.") {
            if recent.isEmpty {
                SRow(title: model.loaded ? "no hay transcripts recientes" : "leyendo transcripts…", detail: model.loaded ? "aparecerán cuando uses Claude Code." : nil) { EmptyView() }
            } else {
                legend
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, s in
                    if index > 0 { SDivider() }
                    sessionRow(s)
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(Array(zip(["entrada nueva", "caché leída", "caché creada", "salida"], Self.colors)), id: \.0) { name, color in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
                    Text(name).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(SettingsTheme.mute)
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 10)
    }

    private func sessionRow(_ s: SessionTokens) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(s.project).font(.system(size: 12.5, weight: .medium, design: .monospaced))
                Text(s.id).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(SettingsTheme.mute)
                if s.partial { SBadge(text: L.tr("parcial"), color: SettingsTheme.amber) }
                Spacer(minLength: 8)
                Text(TokenFormat.short(s.usage.total)).font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                Text(s.usage.cacheHitPercent.map { "caché \($0) %" } ?? "").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(SettingsTheme.mute).frame(width: 74, alignment: .trailing)
            }
            TokenBar(usage: s.usage, colors: Self.colors)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private var projects: some View {
        SCard(title: "por proyecto") {
            if model.snapshot.projects.isEmpty {
                SRow(title: "sin datos todavía") { EmptyView() }
            } else {
                ForEach(Array(model.snapshot.projects.prefix(6).enumerated()), id: \.element.id) { index, p in
                    if index > 0 { SDivider() }
                    SRow(title: p.name, detail: L.t("\(p.sessions) \(p.sessions == 1 ? "sesión" : "sesiones") · salida \(TokenFormat.short(p.usage.output)) · entrada nueva \(TokenFormat.short(p.usage.input))", "\(p.sessions) \(p.sessions == 1 ? "session" : "sessions") · output \(TokenFormat.short(p.usage.output)) · new input \(TokenFormat.short(p.usage.input))")) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(TokenFormat.short(p.usage.total)).font(.system(size: 13, weight: .semibold, design: .monospaced))
                            Text(p.usage.cacheHitPercent.map { "caché \($0) %" } ?? "—").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(SettingsTheme.mute)
                        }
                    }
                }
            }
        }
    }

    // MARK: CLAUDE.md

    private var claudeMd: some View {
        SCard(title: "CLAUDE.md por proyecto", footer: "Claude Code lo lee entero al empezar cada sesión. el borrador se genera solo con los archivos del proyecto, sin modelo, en un archivo nuevo: nunca se sobrescribe un CLAUDE.md.") {
            if let notice = model.notice {
                SRow(title: notice) { SButton(title: "cerrar", symbol: "xmark") { model.notice = nil } }
                SDivider()
            }
            if model.audits.isEmpty {
                SRow(title: model.loaded ? "no hay proyectos con carpeta disponible" : "revisando…") { EmptyView() }
            } else {
                ForEach(Array(model.audits.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { SDivider() }
                    auditRow(item)
                }
            }
        }
    }

    private func auditRow(_ item: ProjectAudit) -> some View {
        let a = item.audit
        let badge: (String, Color) = !a.exists ? ("falta", SettingsTheme.red) : a.isHealthy ? ("en forma", SettingsTheme.green) : ("revisar", SettingsTheme.amber)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(item.name).font(.system(size: 12.5, weight: .medium, design: .monospaced))
                SBadge(text: L.tr(badge.0), color: badge.1)
                if a.exists { Text("≈\(TokenFormat.short(a.tokens)) tokens").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(SettingsTheme.mute) }
                Spacer(minLength: 8)
                SButton(title: "generar borrador…", symbol: "doc.badge.plus") { model.generateDraft(for: item) }
            }
            ForEach(Array(a.findings.prefix(3).enumerated()), id: \.offset) { _, finding in
                Text(finding.message).font(.system(size: 11.5)).foregroundStyle(SettingsTheme.mute).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    // MARK: interruptores

    private var switches: some View {
        SCard(title: "ahorrar", footer: "ninguno toca la API ni la caché del modelo: miden, aconsejan o acortan lo que Claude escribe. el modo conciso lo añade el hook de arranque (pet-brain.sh start), así que vale desde la sesión siguiente.") {
            SToggle(title: "modo conciso", detail: "antepone una instrucción corta de concisión al contexto de arranque de cada sesión de Claude Code.",
                    isOn: Binding(get: { concise }, set: { concise = $0; SavingsPreferences.concise = $0 }))
            if concise {
                SDivider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("instrucción").font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    TextEditor(text: Binding(get: { conciseText.isEmpty ? ConciseMode.defaultText() : conciseText }, set: { conciseText = $0 }))
                        .font(.system(size: 11.5)).scrollContentBackground(.hidden)
                        .frame(height: 74).padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SettingsTheme.line, lineWidth: 1))
                    HStack(spacing: 8) {
                        SButton(title: "guardar", symbol: "checkmark", prominent: true) { SavingsPreferences.conciseText = ConciseMode.sanitize(conciseText); conciseText = SavingsPreferences.conciseText }
                        SButton(title: "texto por defecto", symbol: "arrow.counterclockwise") { conciseText = ""; SavingsPreferences.conciseText = "" }
                        Spacer()
                        Text("~/.claude-pet/conciso.txt").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(SettingsTheme.mute)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
            SDivider()
            SToggle(title: "consejos de ahorro", detail: "una línea discreta en la isla cuando hay algo útil que decir: como mucho una cada 5 minutos y la misma no se repite en media hora.",
                    isOn: Binding(get: { advice }, set: { advice = $0; SavingsPreferences.advice = $0 }))
        }
    }

    private var tips: some View {
        let list = SavingsAdvisor.current(SavingsHub.shared.input(context: store.contextReading, session: nil))
        return SCard(title: "consejos vigentes", footer: "los avisos por un PDF leído o un prompt demasiado general solo salen en el momento, en la isla.") {
            if list.isEmpty {
                SRow(title: "nada que aconsejar ahora", detail: "el contexto va holgado y la caché responde bien.") { EmptyView() }
            } else {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, tip in
                    if index > 0 { SDivider() }
                    SRow(title: tip.message, detail: tip.offersCapsule ? "puedes llevarte las notas a una sesión nueva con el relevo de la isla." : nil) { EmptyView() }
                }
            }
        }
    }

    private var tools: some View {
        SCard(title: "desde la terminal", footer: "claude pet no puede cambiar lo que devuelven las herramientas de Claude Code: este filtro lo aplicas tú, o un alias, a tus propios comandos.") {
            commandRow("comando 2>&1 | ClaudePet --squeeze", "comprime la salida: sin colores ni progreso, repetidas juntas, trazas recortadas y errores siempre enteros.")
            SDivider()
            commandRow("ClaudePet --project-summary [carpeta]", "imprime un borrador de CLAUDE.md. con --write lo guarda como CLAUDE.md.borrador.")
        }
    }

    private func commandRow(_ command: String, _ detail: String) -> some View {
        SRow(title: command, detail: detail) {
            SButton(title: "copiar", symbol: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command, forType: .string) }
        }
    }
}

/// Barra apilada de los cuatro contadores de una sesion.
private struct TokenBar: View {
    let usage: TokenUsage
    let colors: [Color]
    var body: some View {
        GeometryReader { geo in
            let parts = [usage.input, usage.cacheRead, usage.cacheCreate, usage.output]
            let total = max(1, parts.reduce(0, +))
            HStack(spacing: 1) {
                ForEach(0..<4, id: \.self) { i in
                    if parts[i] > 0 { Rectangle().fill(colors[i]).frame(width: max(2, geo.size.width * CGFloat(parts[i]) / CGFloat(total))) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 6)
        .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.06)))
    }
}
