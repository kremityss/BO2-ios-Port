import Foundation

/// Directly decoded T6 weapon tuning from the deployed web game's ESM exports.
struct WebBallistics: Decodable {
    struct DamageBand: Decodable { let damage: Float; let range: Float }
    struct Spread: Decodable {
        let standMin: Float
        let max: Float
        let moveAdd: Float
        let fireAdd: Float
        let decayRate: Float
        let duckedMin: Float
        let duckedMax: Float
    }
    struct Kick: Decodable {
        let pitchMin: Float
        let pitchMax: Float
        let yawMin: Float
        let yawMax: Float
        let centerSpeed: Float
    }
    let damage: Float
    let ranges: [DamageBand]
    let locations: [String: Float]
    let hipSpread: Spread
    let adsSpread: Float
    let hipKick: Kick
    let adsKick: Kick

    func damageAt(distanceMetres: Float, headshot: Bool) -> Float {
        let sourceUnits = max(0,distanceMetres) * 100
        var current = damage
        for band in ranges where band.range > 0 && sourceUnits >= band.range {
            current = band.damage
        }
        return current * (locations[headshot ? "head" : "torso"] ?? 1)
    }

    func spreadDegrees(moving: Float, crouched: Bool, ads: Bool, bloom: Float) -> Float {
        if ads { return adsSpread }
        let minSpread = crouched ? hipSpread.duckedMin : hipSpread.standMin
        let maxSpread = crouched ? hipSpread.duckedMax : hipSpread.max
        return min(maxSpread, minSpread + hipSpread.moveAdd * max(0,min(1,moving)) + bloom)
    }
}

private struct WebWeaponData: Decodable { let ballistics: WebBallistics? }
private struct WebWeaponFile: Decodable {
    let version: Int
    let weapons: [String: WebWeaponData]
}

final class WebWeaponRegistry {
    static let shared = WebWeaponRegistry()
    private let data: [String: WebWeaponData]
    private init() {
        if let url = Bundle.main.url(forResource:"MerkWebWeapons",withExtension:"json"),
           let raw = try? Data(contentsOf:url),
           let file = try? JSONDecoder().decode(WebWeaponFile.self,from:raw),file.version == 1 {
            data=file.weapons
        } else { data=[:] }
    }
    func ballistics(for index: Int) -> WebBallistics? {
        let ids=["m27","an94","dsr50","fiveseven"]
        guard ids.indices.contains(index) else { return nil }
        return data[ids[index]]?.ballistics
    }
}
