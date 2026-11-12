import SwiftUI

/// Todo lo que la ventana de ajustes necesita saber de una pagina, en un solo sitio.
///
/// Para anadir una pagina nueva:
///   1. un `case` en `SettingsPage` (SettingsModel.swift);
///   2. una entrada en `SettingsPage.registry` (abajo) con titulo, simbolo, grupo, palabras de busqueda, subtitulo y la vista.
/// La barra lateral, el buscador, los filtros y el contador de activos la recogen solos.
struct SettingsPageSpec {
    var title: String
    var symbol: String
    var group: SettingsGroup
    var keywords: [String] = []
    var subtitle: String
    /// La pagina contiene opciones que todavia no son estables: la enseña el filtro «solo experimentales».
    var experimental = false
    /// Si la pagina gobierna una funcion que se enciende y se apaga, dice si ahora esta encendida. nil = no aplica.
    var isOn: (@MainActor (PetStore) -> Bool)?
    var build: @MainActor (PetStore) -> AnyView
}

extension SettingsPage {
    static let registry: [SettingsPage: SettingsPageSpec] = [
        .resumen: .init(title: "resumen", symbol: "square.grid.2x2", group: .inicio, keywords: ["estadisticas", "racha", "nivel", "semana", "hoy", "sesiones", "inicio", "plan", "contexto", "tablero"],
                        subtitle: "lo que ha pasado hoy y esta semana, y el estado de tus agentes.", build: { AnyView(ResumenPage(store: $0)) }),
        .apariencia: .init(title: "apariencia", symbol: "capsule.tophalf.filled", group: .isla, keywords: ["isla", "notch", "pantalla", "ubicacion", "reloj", "compacto", "animaciones", "futbol", "burbuja", "skin", "tema", "monitor", "densidad", "contraste"],
                           subtitle: "dónde sale la isla, qué enseña y cómo se ven las mascotas.", isOn: { $0.layout == .island }, build: { AnyView(AparienciaPage(store: $0)) }),
        .comportamiento: .init(title: "comportamiento", symbol: "cursorarrow.motionlines", group: .isla, keywords: ["activacion", "zona", "retraso", "plegar", "cerrar", "visibilidad", "asomar", "cursor", "raton", "iniciar sesion", "inicio", "arranque", "login", "abrir al encender", "automatico", "escritorio vivo", "teclado"],
                               subtitle: "si se abre al iniciar sesión, cuándo asoma, cuánto tarda en plegarse y cuándo aparece sola.", experimental: true, isOn: { $0.autoVisibility }, build: { AnyView(ComportamientoPage(store: $0)) }),
        .agentes: .init(title: "agentes", symbol: "person.2", group: .agentes, keywords: ["claude", "codex", "contexto", "bloqueo", "avisos", "mostrar", "ocultar", "terminal"],
                        subtitle: "qué agentes vigila claude-pet y qué detalle enseña de cada uno.", isOn: { $0.claudePresent || $0.codexPresent }, build: { AnyView(AgentesPage(store: $0)) }),
        .ahorro: .init(title: "ahorro", symbol: "leaf", group: .agentes, keywords: ["tokens", "gasto", "cache", "caché", "conciso", "consejos", "claude.md", "borrador", "squeeze", "contexto", "ahorrar"],
                       subtitle: "cuántos tokens gastas, dónde se van y qué puedes hacer para gastar menos.", build: { AnyView(TokenSavingsPage(store: $0)) }),
        .permisos: .init(title: "permisos", symbol: "checkmark.shield", group: .seguridad, keywords: ["permitir", "denegar", "reglas", "puntos de restauracion", "riesgo", "bloquear", "aprobar", "siempre"],
                         subtitle: "responder desde la isla, reglas de aprobación y puntos de restauración.", isOn: { $0.islandPermissions }, build: { AnyView(PermisosPage(store: $0)) }),
        .perimetro: .init(title: "perímetro", symbol: "scope", group: .seguridad, keywords: ["cerca", "limite", "carpeta", "archivos", "proteger", "proteccion", "env", "bloquear", "alcance", "glob", "zona"],
                          subtitle: "por dónde puede moverse el agente en cada proyecto, comprobado en el permiso antes de que algo cambie.", isOn: { !$0.perimeters.isEmpty }, build: { AnyView(PerimetroPage(store: $0)) }),
        .privacidad: .init(title: "privacidad", symbol: "lock", group: .seguridad, keywords: ["proyecto", "compartir", "secretos", "telemetria", "datos", "local"],
                           subtitle: "todo se queda en tu Mac. aquí decides qué se comparte y qué se borra.", build: { AnyView(PrivacidadPage(store: $0)) }),
        .guardarropa: .init(title: "guardarropa", symbol: "tshirt", group: .mascota, keywords: ["atuendo", "gorro", "corona", "gafas", "bufanda", "temporada", "nivel", "ropa"],
                            subtitle: "atuendos que se desbloquean al subir de nivel.", build: { AnyView(GuardarropaPage(store: $0)) }),
        .sonidos: .init(title: "sonidos", symbol: "speaker.wave.2", group: .mascota, keywords: ["volumen", "audio", "silencio", "carpeta", "personalizado", "alertas", "interfaz", "probar"],
                        subtitle: "volumen por categoría, prueba de cada sonido y tus propios archivos.", isOn: { $0.soundsEnabled }, build: { AnyView(SonidosPage(store: $0)) }),
        .musica: .init(title: "música", symbol: "music.note", group: .mascota, keywords: ["spotify", "apple music", "reproductor", "cancion", "auriculares", "bailar", "notas", "portada", "reaccion", "player"],
                       subtitle: "reproductor de Spotify y Apple Music en la isla, y cómo reacciona la mascota.", isOn: { $0.musicPlayer }, build: { AnyView(MusicaPage(store: $0)) }),
        .foco: .init(title: "foco y pomodoro", symbol: "timer", group: .mascota, keywords: ["pomodoro", "concentracion", "horario", "descanso", "no molestar"],
                     subtitle: "silencia lo que no importa y trabaja por ciclos.", isOn: { $0.focusMode.isActive(at: Date()) }, build: { AnyView(FocoPage(store: $0)) }),
        .trackpad: .init(title: "trackpad táctil", symbol: "rectangle.and.hand.point.up.left", group: .sistema, keywords: ["tactil", "touch", "tableta", "absoluto", "cursor", "pantalla", "tocar", "esquina"],
                         subtitle: "experimental: usa el trackpad como una superficie táctil de toda la pantalla, sin cámara.", experimental: true, isOn: { _ in TrackpadTouchController.shared.enabled }, build: { _ in AnyView(TrackpadTouchPanel(controller: .shared)) }),
        .plugins: .init(title: "plugins", symbol: "puzzlepiece.extension", group: .sistema, keywords: ["mod", "mods", "extension", "complemento", "addon", "script", "instalar", "commitero", "integracion", "automatizar"],
                        subtitle: "complementos creados por la comunidad que añaden acciones y ajustes a claude-pet.", isOn: { $0.plugins.rows.contains { $0.status == .enabled } }, build: { AnyView(PluginsPage(store: $0)) }),
        .atajos: .init(title: "atajos", symbol: "command", group: .sistema, keywords: ["teclado", "teclas", "combinacion", "global", "control", "opcion"],
                       subtitle: "combinaciones globales. siempre con control y opción más la letra que elijas.", isOn: { $0.globalShortcutsEnabled }, build: { AnyView(AtajosPage(store: $0)) }),
        .copia: .init(title: "copia y restauración", symbol: "arrow.up.arrow.down.circle", group: .sistema, keywords: ["exportar", "importar", "respaldo", "restablecer", "reiniciar", "configuracion", "json"],
                      subtitle: "exporta tus ajustes, impórtalos en otro Mac o vuelve a empezar.", build: { AnyView(CopiaPage(store: $0)) }),
        .acerca: .init(title: "acerca de", symbol: "info.circle", group: .sistema, keywords: ["version", "licencia", "commitero", "ayuda", "codigo", "diagnostico", "soporte", "registro", "logs", "error"],
                       subtitle: "versión, herramientas relacionadas y dónde vive cada dato.", build: { _ in AnyView(AcercaPage()) }),
    ]
}
