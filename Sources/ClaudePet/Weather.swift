import Foundation
import CoreLocation
import IOKit.ps

/// Lo que se sabe del tiempo en el sitio del usuario.
struct WeatherReading: Equatable, Codable {
    enum Sky: String, Codable { case clear, cloudy, fog, rain, snow, storm }
    var tempC: Double
    var sky: Sky
    var isDay: Bool
    var windKmh: Double
    var place: String
    var at: Date

    /// Una lectura de mas de tres horas ya no describe el tiempo de ahora.
    func isFresh(_ now: Date = Date()) -> Bool { now.timeIntervalSince(at) < 3 * 3600 }

    var skyName: String {
        switch sky { case .clear: return "despejado"; case .cloudy: return "nublado"; case .fog: return "niebla"; case .rain: return "lluvia"; case .snow: return "nieve"; case .storm: return "tormenta" }
    }
    var summary: String { "\(Int(tempC.rounded())) °C · \(skyName)" + (place.isEmpty ? "" : " · \(place)") }
}

/// La ultima lectura se guarda para que, al abrir la app, las mascotas ya vayan vestidas para el tiempo de hace un rato
/// sin esperar a la red. Solo vale si es reciente (menos de tres horas) y se descarta cualquier cosa rara.
enum WeatherCache {
    static let key = "weatherLast"
    static func save(_ r: WeatherReading?, to d: UserDefaults = .standard) {
        guard let r, let data = try? JSONEncoder().encode(r) else { d.removeObject(forKey: key); return }
        d.set(data, forKey: key)
    }
    static func load(from d: UserDefaults = .standard, now: Date = Date()) -> WeatherReading? {
        guard let data = d.data(forKey: key), data.count < 2_000, let r = try? JSONDecoder().decode(WeatherReading.self, from: data),
              r.tempC > -90, r.tempC < 70, r.isFresh(now), r.at <= now.addingTimeInterval(60) else { return nil }
        return r
    }
}

enum WeatherRules {
    /// Atuendos que el tiempo pide: calor y sol, frio, lluvia o nieve. Puro, para poder probarlo sin red.
    static func outfits(_ w: WeatherReading) -> Set<Outfit> {
        var out: Set<Outfit> = []
        switch w.sky {
        case .rain, .storm: out.insert(.umbrella)
        case .snow: out.formUnion([.earmuffs, .beanie, .scarf])
        default: break
        }
        if w.tempC >= 32 { out.insert(.sunhat); if w.isDay { out.insert(.sunglasses) } }
        else if w.tempC >= 27, w.sky == .clear, w.isDay { out.insert(.sunglasses) }
        if w.tempC <= 18 { out.insert(.scarf) }
        if w.tempC <= 10 { out.insert(.beanie) }
        if w.tempC <= 3 { out.insert(.earmuffs) }
        return out
    }

    /// Como lo siente la mascota: suda, tirita o se queda tranquila.
    static func ambient(_ w: WeatherReading?, batteryLow: Bool) -> Ambient {
        var a = Ambient(lowBattery: batteryLow)
        guard let w, w.isFresh() else { return a }
        a.hot = w.tempC >= 30
        a.cold = w.tempC <= 8
        a.rain = w.sky == .rain || w.sky == .storm
        a.snow = w.sky == .snow
        return a
    }

    /// Respuesta de Open-Meteo (`current`): codigo WMO a un cielo sencillo.
    static func parse(_ data: Data, place: String, at date: Date = Date()) -> WeatherReading? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let cur = root["current"] as? [String: Any],
              let temp = (cur["temperature_2m"] as? NSNumber)?.doubleValue, let code = (cur["weather_code"] as? NSNumber)?.intValue,
              temp > -90, temp < 70 else { return nil }
        let day = ((cur["is_day"] as? NSNumber)?.intValue ?? 1) == 1
        let wind = (cur["wind_speed_10m"] as? NSNumber)?.doubleValue ?? 0
        return WeatherReading(tempC: temp, sky: sky(code: code), isDay: day, windKmh: wind, place: place, at: date)
    }

    static func sky(code: Int) -> WeatherReading.Sky {
        switch code {
        case 0, 1: return .clear
        case 2, 3: return .cloudy
        case 45, 48: return .fog
        case 51...67, 80...82: return .rain
        case 71...77, 85, 86: return .snow
        case 95...99: return .storm
        default: return .cloudy
        }
    }
}

/// Lo que la mascota siente a su alrededor ademas del trabajo: tiempo y bateria.
struct Ambient: Equatable {
    var hot = false
    var cold = false
    var rain = false
    var snow = false
    var lowBattery = false
}

enum Battery {
    /// Nivel en porcentaje si esta con bateria y sin cargar; nil en un Mac de sobremesa o enchufado.
    static func lowLevel() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  let cap = d[kIOPSCurrentCapacityKey] as? Int, let state = d[kIOPSPowerSourceStateKey] as? String else { continue }
            if state == kIOPSBatteryPowerValue, cap <= 15 { return cap }
        }
        return nil
    }
}

/// Pide el tiempo a Open-Meteo con la posicion aproximada (dos decimales, unos 1 km) o con una ciudad escrita.
/// Solo se activa si el usuario lo enciende; no hay clave ni cuenta.
@MainActor
final class WeatherService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var timer: Timer?
    private var city = ""
    var onReading: (WeatherReading?) -> Void = { _ in }
    var onStatus: (String) -> Void = { _ in }

    func start(city: String) {
        self.city = city.trimmingCharacters(in: .whitespaces)
        stop()
        manager.delegate = self
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func refresh() {
        if !city.isEmpty { Task { await fetch(city: city) }; return }
        switch manager.authorizationStatus {
        case .notDetermined: onStatus("pidiendo permiso de ubicación…"); manager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways: manager.requestLocation()
        default: onStatus("sin permiso de ubicación: escribe una ciudad")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus == .authorized || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
            else if manager.authorizationStatus != .notDetermined { onStatus("sin permiso de ubicación: escribe una ciudad") }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in await fetch(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, place: "") }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in onStatus("no se pudo leer la ubicación: escribe una ciudad") }
    }

    private func fetch(city: String) async {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1")]
        guard let url = c.url, let (data, _) = try? await URLSession.shared.data(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let r = (root["results"] as? [[String: Any]])?.first,
              let lat = (r["latitude"] as? NSNumber)?.doubleValue, let lon = (r["longitude"] as? NSNumber)?.doubleValue else {
            onStatus("no encuentro esa ciudad"); return
        }
        await fetch(lat: lat, lon: lon, place: (r["name"] as? String) ?? city)
    }

    private func fetch(lat: Double, lon: Double, place: String) async {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [URLQueryItem(name: "latitude", value: String(format: "%.2f", lat)), URLQueryItem(name: "longitude", value: String(format: "%.2f", lon)),
                        URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day,wind_speed_10m")]
        guard let url = c.url, let (data, resp) = try? await URLSession.shared.data(from: url), (resp as? HTTPURLResponse)?.statusCode == 200,
              let reading = WeatherRules.parse(data, place: place) else { onStatus("no se pudo leer el tiempo"); return }
        onStatus(""); onReading(reading)
    }
}
