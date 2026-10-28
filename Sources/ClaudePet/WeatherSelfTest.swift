import Foundation
import SwiftUI

/// `ClaudePet --selftest-weather`: el tiempo a atuendos, el entorno que sienten, el armario por agente y la paridad de expresiones.
@MainActor
enum WeatherSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }
        func w(_ t: Double, _ sky: WeatherReading.Sky = .clear, day: Bool = true, age: TimeInterval = 0) -> WeatherReading {
            WeatherReading(tempC: t, sky: sky, isDay: day, windKmh: 5, place: "Managua", at: Date().addingTimeInterval(-age))
        }

        check("calor fuerte: sombrero y gafas de sol", WeatherRules.outfits(w(34)) == [.sunhat, .sunglasses])
        check("calor de noche: sin gafas de sol", WeatherRules.outfits(w(34, day: false)) == [.sunhat])
        check("tibio y despejado: solo gafas de sol", WeatherRules.outfits(w(28)) == [.sunglasses])
        check("tibio y nublado: nada", WeatherRules.outfits(w(28, .cloudy)).isEmpty)
        check("templado: nada", WeatherRules.outfits(w(22)).isEmpty)
        check("fresco: bufanda", WeatherRules.outfits(w(15, .cloudy)) == [.scarf])
        check("frio: bufanda y gorro", WeatherRules.outfits(w(8, .cloudy)) == [.scarf, .beanie])
        check("helada: bufanda, gorro y orejeras", WeatherRules.outfits(w(1, .cloudy)) == [.scarf, .beanie, .earmuffs])
        check("lluvia: paraguas", WeatherRules.outfits(w(22, .rain)) == [.umbrella])
        check("nieve: orejeras, gorro y bufanda", WeatherRules.outfits(w(-2, .snow)).isSuperset(of: [.earmuffs, .beanie, .scarf]))
        check("calor con lluvia: sombrero y paraguas", WeatherRules.outfits(w(33, .rain)).isSuperset(of: [.umbrella, .sunhat]))

        check("codigo WMO: despejado", WeatherRules.sky(code: 0) == .clear)
        check("codigo WMO: llovizna y chubasco", WeatherRules.sky(code: 53) == .rain && WeatherRules.sky(code: 81) == .rain)
        check("codigo WMO: nieve", WeatherRules.sky(code: 73) == .snow && WeatherRules.sky(code: 86) == .snow)
        check("codigo WMO: tormenta", WeatherRules.sky(code: 95) == .storm)
        let json = #"{"current":{"temperature_2m":31.4,"weather_code":2,"is_day":1,"wind_speed_10m":12.5}}"#
        let parsed = WeatherRules.parse(Data(json.utf8), place: "León")
        check("respuesta de open-meteo", parsed?.tempC == 31.4 && parsed?.sky == .cloudy && parsed?.isDay == true && parsed?.place == "León")
        check("respuesta rota se rechaza", WeatherRules.parse(Data("no es json".utf8), place: "x") == nil)
        check("temperatura imposible se rechaza", WeatherRules.parse(Data(#"{"current":{"temperature_2m":999,"weather_code":0}}"#.utf8), place: "x") == nil)
        check("lectura vieja ya no vale", !w(20, age: 4 * 3600).isFresh() && w(20, age: 600).isFresh())

        check("ambiente: calor", WeatherRules.ambient(w(33), batteryLow: false).hot)
        check("ambiente: frio", WeatherRules.ambient(w(5), batteryLow: false).cold)
        check("ambiente: lluvia", WeatherRules.ambient(w(20, .rain), batteryLow: false).rain)
        check("ambiente: poca bateria sin tiempo", WeatherRules.ambient(nil, batteryLow: true).lowBattery)
        check("ambiente: lectura vieja se ignora", !WeatherRules.ambient(w(40, age: 5 * 3600), batteryLow: false).hot)

        // la ultima lectura sobrevive al reinicio, pero solo si es reciente y sensata
        let suite = UserDefaults(suiteName: "weather-selftest-\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.dictionaryRepresentation().keys.first ?? "") }
        WeatherCache.save(w(31, .clear, age: 600), to: suite)
        let back = WeatherCache.load(from: suite)
        check("la lectura guardada se recupera", back?.tempC == 31 && back?.sky == .clear && back?.place == "Managua")
        WeatherCache.save(w(31, .clear, age: 4 * 3600), to: suite)
        check("una lectura de hace cuatro horas no vale", WeatherCache.load(from: suite) == nil)
        suite.set(Data("no es json".utf8), forKey: WeatherCache.key)
        check("basura guardada se ignora", WeatherCache.load(from: suite) == nil)
        WeatherCache.save(WeatherReading(tempC: 999, sky: .clear, isDay: true, windKmh: 0, place: "x", at: Date()), to: suite)
        check("una temperatura imposible no se acepta", WeatherCache.load(from: suite) == nil)
        WeatherCache.save(WeatherReading(tempC: 20, sky: .clear, isDay: true, windKmh: 0, place: "x", at: Date().addingTimeInterval(3600)), to: suite)
        check("una lectura del futuro no se acepta", WeatherCache.load(from: suite) == nil)
        WeatherCache.save(nil, to: suite)
        check("al apagar el clima se borra", WeatherCache.load(from: suite) == nil)

        // el entorno cambia la pose: tirita con frio, suda con calor, se preocupa con poca bateria
        var cold = PetScene(); cold.ambient = Ambient(cold: true)
        check("pose: tirita", PetAnimator.pose(at: 1, gaze: .zero, pokes: [], hopStart: nil, motion: true, scene: cold).shivering)
        var hot = PetScene(); hot.ambient = Ambient(hot: true)
        let hotPose = PetAnimator.pose(at: 1, gaze: .zero, pokes: [], hopStart: nil, motion: true, scene: hot)
        check("pose: suda", hotPose.sweating)
        check("particulas: gotas de calor", !PetAnimator.particles(at: 1, pose: hotPose, scene: hot).isEmpty)
        var low = PetScene(); low.ambient = Ambient(lowBattery: true)
        check("pose: poca bateria preocupa", PetAnimator.pose(at: 1, gaze: .zero, pokes: [], hopStart: nil, motion: true, scene: low).worried)
        var rain = PetScene(); rain.ambient = Ambient(rain: true)
        check("particulas: lluvia", !PetAnimator.particles(at: 1, pose: PetPose(), scene: rain).isEmpty)

        // cada agente se viste por separado
        let store = PetStore.shared
        let savedC = store.wardrobe, savedX = store.codexWardrobe
        defer { store.wardrobe = savedC; store.codexWardrobe = savedX }
        store.wardrobe = []; store.codexWardrobe = []
        store.toggleOutfit(.glasses, for: .claude)
        check("armario: gafas solo en claude", store.worn(.glasses, by: .claude) && !store.worn(.glasses, by: .codex))
        store.toggleOutfit(.bow, for: .codex)
        check("armario: lazo solo en codex", store.worn(.bow, by: .codex) && !store.worn(.bow, by: .claude))
        store.toggleOutfit(.glasses, for: .claude)
        check("armario: quitar en uno no toca el otro", !store.worn(.glasses, by: .claude) && store.worn(.bow, by: .codex))

        // paridad: las expresiones de claude existen en el visor de codex
        let faces: [CodexAvatar.Face] = [.dizzy(0), .dizzy(1), .annoyed, .closed, .wide, .worried]
        let base = Set(CodexAvatar.cells(legs: .stand, face: .prompt(cursor: false)).map { "\($0.x),\($0.y),\($0.c)" })
        for f in faces {
            let cells = CodexAvatar.cells(legs: .stand, face: f)
            check("codex: la cara \(f) cambia el visor", Set(cells.map { "\($0.x),\($0.y),\($0.c)" }) != base)
            check("codex: la cara \(f) cabe en el visor", cells.allSatisfy { $0.x >= 0 && $0.x < CodexAvatar.width && $0.y >= 0 && $0.y < CodexAvatar.height })
        }
        for o in Outfit.allCases {
            check("atuendo \(o.rawValue): dibujado para claude y codex", !o.claudeArt.rows.isEmpty && !o.codexCells.isEmpty)
            check("atuendo \(o.rawValue): cabe en la rejilla de claude", o.pixels.allSatisfy { $0.x >= 0 && $0.x < 16 && $0.y >= 0 && $0.y < 16 })
            check("atuendo \(o.rawValue): cabe en la rejilla de codex", o.codexCells.allSatisfy { $0.x >= 0 && $0.x < 18 && $0.y >= 0 && $0.y < 21 })
        }
        let poke: [TimeInterval] = [10.0, 10.5, 11.0]
        check("mareo: tres toques en codex y en claude dan la misma pose",
              PetAnimator.pose(at: 11.1, gaze: .zero, pokes: poke, hopStart: nil, motion: true).dizzy)

        print(failures == 0 ? "CLIMA OK" : "CLIMA \(failures) FALLOS")
        return failures == 0
    }
}
