import Foundation

enum SettingsSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }

        // buscador
        check("search-empty", SettingsPage.matching("").count == SettingsPage.allCases.count)
        check("search-title", SettingsPage.matching("sonid") == [.sonidos])
        check("search-accents", SettingsPage.matching("restauracion").contains(.copia) && SettingsPage.matching("RESTAURACIÓN").contains(.copia))
        check("search-keyword", SettingsPage.matching("pomodoro") == [.foco])
        check("search-none", SettingsPage.matching("zzzz").isEmpty)
        check("pages-grouped", Set(SettingsPage.allCases.map(\.group)) == Set(SettingsGroup.allCases))

        // atajos
        var map = ShortcutMap.standard
        check("shortcut-default", map.shortcut(for: "a") == .allow && map.key(for: .pin) == "p")
        check("shortcut-set", map.set(.allow, to: "Z") == nil && map.shortcut(for: "z") == .allow && map.shortcut(for: "a") == nil)
        check("shortcut-taken", map.set(.deny, to: "z") == .taken(by: .allow))
        check("shortcut-bad", map.set(.deny, to: "ab") == .notAKey && map.set(.deny, to: "ñ") == .notAKey && map.set(.deny, to: " ") == .notAKey)
        check("shortcut-same-key", map.set(.allow, to: "z") == nil)
        let round = ShortcutMap.decode(map.encode())
        check("shortcut-roundtrip", round == map)
        check("shortcut-decode-garbage", { let m = ShortcutMap.decode("allow=d,deny=d,xx=1,island,pin=="); return m.key(for: .allow) == "a" && m.key(for: .deny) == "d" && m.key(for: .pin) == "p" }())
        check("shortcut-decode-dup", { let m = ShortcutMap.decode("allow=q,deny=q"); return m.key(for: .allow) == "q" && m.key(for: .deny) == "d" }())

        // volumen por categoria
        let v = SoundCategoryVolumes.decode("interfaz=0.5,alertas=9,mascota=-1,otra=1,interfaz2=x")
        check("catvol-clamp", v[.interface] == 0.5 && v[.alert] == 1 && v[.pet] == 0 && v.count == 3)
        check("catvol-roundtrip", SoundCategoryVolumes.decode(SoundCategoryVolumes.encode(v)) == v)
        check("catvol-garbage", SoundCategoryVolumes.decode("=,=,,nan").isEmpty && SoundCategoryVolumes.decode("interfaz=nan").isEmpty)

        // copia de ajustes
        let suiteName = "claudepet.selftest.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        defer { d.removePersistentDomain(forName: suiteName) }
        d.set(true, forKey: "islandShowClock"); d.set(0.6, forKey: "soundVolume"); d.set("abajo", forKey: "islandPlacement")
        d.set(7, forKey: "focusStart"); d.set("ruido", forKey: "notInSchema")
        let data = SettingsBackup.export(from: d)
        let text = String(decoding: data, as: UTF8.self)
        check("backup-format", text.contains("claude-pet-settings") && !text.contains("notInSchema") && text.contains("islandPlacement"))
        let target = UserDefaults(suiteName: suiteName + ".b")!
        defer { target.removePersistentDomain(forName: suiteName + ".b") }
        let rep = try? SettingsBackup.importing(data, into: target)
        check("backup-roundtrip", rep?.applied == 4 && rep?.skipped.isEmpty == true && target.bool(forKey: "islandShowClock") && target.double(forKey: "soundVolume") == 0.6 && target.string(forKey: "islandPlacement") == "abajo" && target.integer(forKey: "focusStart") == 7)

        func doc(_ s: String) -> Data { Data("{\"format\":\"claude-pet-settings\",\"version\":1,\"settings\":\(s)}".utf8) }
        let hostile = doc("{\"soundVolume\":42,\"islandPlacement\":\"debajo del mar\",\"islandShowClock\":1,\"focusStart\":99,\"focusEnd\":3.5,\"layout\":[1],\"wardrobe\":\"a\\nb\",\"evil\":true,\"autoVisibility\":false}")
        let t2 = UserDefaults(suiteName: suiteName + ".c")!
        defer { t2.removePersistentDomain(forName: suiteName + ".c") }
        let r2 = try? SettingsBackup.importing(hostile, into: t2)
        check("backup-hostile", r2?.applied == 1 && (r2?.skipped.count ?? 0) == 8 && t2.object(forKey: "soundVolume") == nil && t2.object(forKey: "autoVisibility") as? Bool == false)
        check("backup-wrong-format", { do { _ = try SettingsBackup.importing(Data("{\"settings\":{}}".utf8), into: t2); return false } catch { return (error as? SettingsBackup.Failure) == .notSettings } }())
        check("backup-not-json", { do { _ = try SettingsBackup.importing(Data("nope".utf8), into: t2); return false } catch { return (error as? SettingsBackup.Failure) == .invalidJSON } }())
        check("backup-too-large", { do { _ = try SettingsBackup.importing(Data(repeating: 32, count: SettingsBackup.maxBytes + 1), into: t2); return false } catch { return (error as? SettingsBackup.Failure) == .tooLarge } }())
        SettingsBackup.reset(in: t2)
        check("backup-reset", t2.object(forKey: "autoVisibility") == nil)

        print(failures == 0 ? "AJUSTES OK" : "AJUSTES \(failures) FALLOS")
        return failures == 0
    }
}
