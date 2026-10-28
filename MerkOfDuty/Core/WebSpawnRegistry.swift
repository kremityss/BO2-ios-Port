import Foundation
import simd

/// Authored spawn entities from the Cloudflare web game's Nuketown nav hints.
/// Positions are transformed at build time using exactly the same origin and
/// scale as the native GLB converter, not estimated from the collision raster.
struct WebSpawnPoint: Decodable {
    let id: String
    let classname: String
    let xyz: [Float]
    let yaw: Float

    enum CodingKeys: String, CodingKey { case id, xyz, yaw; case classname = "class" }

    var position: SIMD3<Float>? {
        guard xyz.count == 3, xyz.allSatisfy({ $0.isFinite }), yaw.isFinite else { return nil }
        return SIMD3<Float>(xyz[0], xyz[1], xyz[2])
    }
}

private struct WebSpawnFile: Decodable {
    let version: Int
    let map: String
    let spawns: [WebSpawnPoint]
}

struct NativeSpawnPose {
    let position: SIMD3<Float> // eye position for the native renderer
    let yaw: Float
    let guid: String
    let group: String
}

final class WebSpawnRegistry {
    private let points: [WebSpawnPoint]
    private var recentlyUsed: [String] = []
    private init(points: [WebSpawnPoint]) { self.points = points }

    static func load() -> WebSpawnRegistry? {
        guard let url = Bundle.main.url(forResource: NativeLevel.selected.resource("MerkWebSpawns"), withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(WebSpawnFile.self, from: data),
              file.version == 1 && file.map == NativeLevel.selected.mapID && !file.spawns.isEmpty else { return nil }
        return WebSpawnRegistry(points: file.spawns)
    }

    /// Authoritative game-mode/team groups. Do not mix TDM allies and axis,
    /// nor silently borrow FFA locations for S&D team spawns.
    private func groups(mode: String, team: Int, initial: Bool) -> [String] {
        switch mode {
        case "snd": return team == 0 ? ["mp_sd_spawn_defender"] : ["mp_sd_spawn_attacker"]
        case "ctf": return team == 0 ? ["mp_ctf_spawn_allies_start", "mp_ctf_spawn_allies"]
                                           : ["mp_ctf_spawn_axis_start", "mp_ctf_spawn_axis"]
        case "dom": return team == 0 ? ["mp_dom_spawn_allies_start", "mp_dom_spawn"]
                                           : ["mp_dom_spawn_axis_start", "mp_dom_spawn"]
        case "ffa": return ["mp_dm_spawn"]
        default:
            if initial {
            // Never use the same free-for-all marker for opposing TDM teams.
            // Distinct authored start markers also keep bots out of the
            // player's immediate camera view at match initialization.
            let authoredGroup = groups(mode: mode, team: team, initial: true).first ?? "mp_dm_spawn"
            let candidates = points.filter { $0.classname == authoredGroup && $0.position != nil }
            if !candidates.isEmpty {
                for offset in 0..<candidates.count {
                    let marker = candidates[(max(0,index) + offset) % candidates.count]
                    guard let location = marker.position,
                          let grounded = collision.nearestAuthoredSpawnGround(
                            at: location, eyeHeight: eyeHeight, radius: 4,
                            maxFloorDifference: 1.25) else { continue }
                    return NativeSpawnPose(position:grounded,yaw:marker.yaw,
                                           guid:marker.id,group:marker.classname)
                }
            }
        }
        // EnemySystem.safeSpawnFor() evaluates projected mp_dm_spawn markers,
        // maximizing distance to threats and penalizing recent/visible spawns.
        let groupsToTry = mode == "tdm" ? ["mp_dm_spawn", "mp_tdm_spawn_team2_start",
                                                "mp_tdm_spawn_allies_start", "mp_tdm_spawn"]
                                             : groups(mode: mode, team: team, initial: initial)
        for group in groupsToTry {
            let candidates = points.filter { $0.classname == group && $0.position != nil }
            var best: NativeSpawnPose?
            var bestScore: Float = -.infinity
            for candidate in candidates {
                guard let original=candidate.position, abs(original.x)<160,abs(original.z)<160,
                      let grounded = collision.nearestAuthoredSpawnGround(
                        at: original, eyeHeight: eyeHeight, radius: 7.5,
                        maxFloorDifference: 1.25) else { continue }
                let feet = grounded - SIMD3<Float>(0,eyeHeight,0)
                let minDistance = threats.map { simd_distance($0,feet) }.min() ?? 22
                let visibleThreats = threats.filter { target in
                    let vector = target + SIMD3<Float>(0,0.42,0)
                                   - (feet + SIMD3<Float>(0,0.42,0))
                    let length = simd_length(vector)
                    return length > 0.01 && !collision.rayHitsWall(
                        from:feet + SIMD3<Float>(0,0.42,0),
                        direction:simd_normalize(vector),distance:length)
                }.count
                let recentIndex = recentlyUsed.firstIndex(of:candidate.id)
                let recentPenalty = recentIndex.map { Float(recentlyUsed.count-$0)*2.4 } ?? 0
                let score = min(minDistance,22) - Float(visibleThreats)*13 - recentPenalty
                if score > bestScore {
                    bestScore=score
                    best=NativeSpawnPose(position:grounded,yaw:candidate.yaw,
                                         guid:candidate.id,group:candidate.classname)
                }
            }
            if let best {
                recentlyUsed.append(best.guid)
                if recentlyUsed.count > 8 { recentlyUsed.removeFirst() }
                return best
            }
        }
        return nil
    }
}
