import Foundation
import simd

struct ArenaBlock {
    let center: SIMD3<Float>
    let size: SIMD3<Float>
    let color: SIMD4<Float>
    var solid: Bool = true
}

struct CombatBot {
    var position: SIMD3<Float>
    var health: Float = 100
    var attackTimer: Float = 0
    var respawnTimer: Float = 0
    var strafe: Float = 1
    var alive: Bool { health > 0 }
}

enum FireMode { case automatic, semiautomatic, bolt }

struct WeaponSpec {
    let name: String
    let rpm: Float
    let damage: Float
    let magazine: Int
    let reserves: Int
    let reloadTime: Float
    let spread: Float
    let mode: FireMode
    let color: SIMD4<Float>

    // Stats copied from the deployed 2026-09-22 weapons.js registry.
    static let roster: [WeaponSpec] = [
        WeaponSpec(name: "M27", rpm: 750, damage: 33, magazine: 30, reserves: 240, reloadTime: 2.1, spread: 0.008,
                   mode: .automatic, color: SIMD4<Float>(0.27, 0.31, 0.28, 1)),
        WeaponSpec(name: "AN-94", rpm: 625, damage: 40, magazine: 30, reserves: 240, reloadTime: 2.15, spread: 0.006,
                   mode: .automatic, color: SIMD4<Float>(0.28, 0.24, 0.18, 1)),
        WeaponSpec(name: "DSR 50", rpm: 300, damage: 98, magazine: 5, reserves: 10, reloadTime: 2.8, spread: 0.002,
                   mode: .bolt, color: SIMD4<Float>(0.34, 0.28, 0.22, 1)),
        WeaponSpec(name: "Five-seven", rpm: 750, damage: 55, magazine: 20, reserves: 40, reloadTime: 1.7, spread: 0.011,
                   mode: .semiautomatic, color: SIMD4<Float>(0.20, 0.23, 0.23, 1))
    ]
}

struct Controls {
    var move = SIMD2<Float>(repeating: 0)
    var firing = false
    var ads = false
    var sprint = false
    var crouch = false
    var jumpQueued = false
    var reloadQueued = false
    var slideQueued = false
}

final class GameWorld {
    var controls = Controls()
    private(set) var pos = SIMD3<Float>(0, 1.65, 15)
    private(set) var yaw: Float = 0
    private(set) var pitch: Float = 0
    private(set) var health: Float = 100
    private(set) var kills = 0
    private(set) var deaths = 0
    private(set) var shots = 0
    private(set) var hits = 0
    private(set) var blocks: [ArenaBlock] = []
    private(set) var bots: [CombatBot] = []
    private(set) var weaponIndex = 0
    private(set) var ammo = 30
    private(set) var reserveAmmo = 150
    private(set) var reloadRemaining: Float = 0
    private(set) var muzzleFlash: Float = 0
    private(set) var recentHit: Float = 0
    private(set) var motionPhase: Float = 0
    private var cooldown: Float = 0
    private var triggerLatched = false
    private var verticalVelocity: Float = 0
    private var horizontalVelocity = SIMD2<Float>(repeating: 0)
    private var slideRemaining: Float = 0
    private var slideDirection = SIMD2<Float>(0, -1)
    private var deadTimer: Float = 0
    private var rng: UInt64 = 0xA3192C41
    private let eyeHeight: Float = 1.65
    private let crouchHeight: Float = 1.08
    private let bodyRadius: Float = 0.36
    private(set) var isGrounded = true
    let levelCollision: NativeCollision?
    private var initialPosition = SIMD3<Float>(0,1.65,15)
    var hasImportedLevel: Bool { levelCollision != nil }

    var weapon: WeaponSpec { WeaponSpec.roster[weaponIndex] }
    var isSliding: Bool { slideRemaining > 0 }
    var reloading: Bool { reloadRemaining > 0 }
    var adsFactor: Float { controls.ads && reloadRemaining <= 0 ? 0.64 : 1 }
    var cameraPosition: SIMD3<Float> { pos + SIMD3<Float>(0, sin(motionPhase) * 0.023 * (isGrounded ? 1 : 0), 0) }
    var forward: SIMD3<Float> {
        normalize(SIMD3<Float>(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)))
    }
    var right: SIMD3<Float> { SIMD3<Float>(cos(yaw), 0, sin(yaw)) }

    init() {
        if let grid = NativeCollision.load(), let spawn = grid.spawn(nearX:0,z:0) {
            levelCollision = grid
            initialPosition = spawn
            pos = spawn
        } else {
            levelCollision = nil
            buildTrainingArena()
        }
        let points: [SIMD3<Float>] = [
            SIMD3<Float>(-10, 0, -11), SIMD3<Float>(11, 0, -14),
            SIMD3<Float>(-21, 0, 5), SIMD3<Float>(19, 0, 2),
            SIMD3<Float>(0, 0, -21), SIMD3<Float>(-6, 0, 19)
        ]
        bots = points.enumerated().map { idx, p in
            let location:SIMD3<Float>
            if let grid=levelCollision {
                location=(grid.spawn(nearX:initialPosition.x+p.x,z:initialPosition.z+p.z) ?? initialPosition)
                    - SIMD3<Float>(0,eyeHeight,0)
            } else {location=p}
            return CombatBot(position:location,strafe:idx.isMultiple(of:2) ? 1 : -1)
        }
    }

    func aim(dx: Float, dy: Float) {
        let sensitivity: Float = controls.ads ? 0.0018 : 0.0036
        yaw += dx * sensitivity
        pitch = max(-1.30, min(1.30, pitch - dy * sensitivity))
    }

    func switchWeapon() {
        weaponIndex = (weaponIndex + 1) % WeaponSpec.roster.count
        ammo = weapon.magazine
        reserveAmmo = weapon.reserves
        reloadRemaining = 0
        cooldown = 0
        triggerLatched = false
    }

    func update(_ rawDelta: Float) {
        let dt = max(0, min(0.033, rawDelta))
        guard dt > 0 else { return }
        cooldown = max(0, cooldown - dt)
        muzzleFlash = max(0, muzzleFlash - dt)
        recentHit = max(0, recentHit - dt)
        if health <= 0 {
            deadTimer -= dt
            if deadTimer <= 0 { respawnPlayer() }
            clearQueued()
            return
        }
        if reloadRemaining > 0 {
            reloadRemaining -= dt
            if reloadRemaining <= 0 {
                let transfer = min(weapon.magazine - ammo, reserveAmmo)
                ammo += transfer
                reserveAmmo -= transfer
                reloadRemaining = 0
            }
        }
        if controls.reloadQueued { startReload() }
        let move = simd_length(controls.move) > 1 ? simd_normalize(controls.move) : controls.move
        let localForward = SIMD2<Float>(sin(yaw), -cos(yaw))
        let localRight = SIMD2<Float>(cos(yaw), sin(yaw))
        let desired = localRight * move.x + localForward * move.y
        let fast = controls.sprint && !controls.ads && move.y > 0.15
        let speed: Float = controls.crouch ? 2.25 : (fast ? 8.4 : (controls.ads ? 3.2 : 5.4))
        let acceleration: Float = isGrounded ? 16 : 5.2
        horizontalVelocity += (desired * speed - horizontalVelocity) * min(1, dt * acceleration)
        if controls.slideQueued && isGrounded && simd_length(horizontalVelocity) > 3.1 {
            slideRemaining = 0.67
            slideDirection = simd_length(horizontalVelocity) > 0.1 ? simd_normalize(horizontalVelocity) : localForward
        }
        if slideRemaining > 0 {
            slideRemaining = max(0, slideRemaining - dt)
            horizontalVelocity = slideDirection * (7.7 + 3.2 * slideRemaining)
        }
        if controls.jumpQueued && isGrounded {
            verticalVelocity = 6.6
            isGrounded = false
            slideRemaining = 0
        }
        verticalVelocity -= 17.8 * dt
        let targetEye = (controls.crouch || isSliding) ? crouchHeight : eyeHeight
        var proposed = pos
        proposed.y += verticalVelocity * dt
        let oldGround=levelCollision?.floorHeight(x:pos.x,z:pos.z) ?? 0
        if proposed.y <= oldGround+targetEye {
            proposed.y = oldGround+targetEye
            verticalVelocity = 0
            isGrounded = true
        }
        proposed.x = resolveAxis(position: SIMD2<Float>(pos.x, pos.z), axis: 0, change: horizontalVelocity.x * dt)
        proposed.z = resolveAxis(position: SIMD2<Float>(proposed.x, pos.z), axis: 1, change: horizontalVelocity.y * dt)
        if isGrounded, let level=levelCollision,
           let ground=level.floorHeight(x:proposed.x,z:proposed.z) {
            proposed.y=ground+targetEye
        }
        pos = proposed
        if simd_length(horizontalVelocity) > 0.3 && isGrounded { motionPhase += dt * (fast ? 15 : 10) } else { motionPhase *= 0.90 }
        if controls.firing { attemptFire() } else { triggerLatched = false }
        updateBots(dt)
        clearQueued()
    }

    private func resolveAxis(position p: SIMD2<Float>, axis: Int, change: Float) -> Float {
        var candidate = (axis == 0 ? p.x : p.y) + change
        candidate = max(-35.0, min(35.0, candidate))
        if axis == 1 { candidate = max(-29.0, min(29.0, candidate)) }
        let probe = axis == 0 ? SIMD2<Float>(candidate, p.y) : SIMD2<Float>(p.x, candidate)
        if let grid=levelCollision {
            let height = controls.crouch || isSliding ? crouchHeight : eyeHeight
            let footY = pos.y - height
            return grid.canOccupy(x:probe.x,z:probe.y,feetY:footY,bodyHeight:height)
                ? candidate : (axis == 0 ? p.x : p.y)
        }
        for b in blocks where b.solid {
            let dx = abs(probe.x - b.center.x)
            let dz = abs(probe.y - b.center.z)
            if dx < b.size.x / 2 + bodyRadius && dz < b.size.z / 2 + bodyRadius {
                return axis == 0 ? p.x : p.y
            }
        }
        return candidate
    }

    private func startReload() {
        guard reloadRemaining <= 0, ammo < weapon.magazine, reserveAmmo > 0 else { return }
        reloadRemaining = weapon.reloadTime
    }

    private func rand() -> Float {
        rng = rng &* 2862933555777941757 &+ 3037000493
        return Float((rng >> 40) & 0xFFFFFF) / 16777216
    }

    private func attemptFire() {
        guard cooldown <= 0, reloadRemaining <= 0 else { return }
        if weapon.mode != .automatic && triggerLatched { return }
        triggerLatched = true
        if ammo <= 0 { startReload(); return }
        ammo -= 1
        shots += 1
        muzzleFlash = 0.09
        cooldown = weapon.mode == .bolt ? 1.15 : 60 / weapon.rpm
        let spread = weapon.spread * (controls.ads ? 0.36 : 1) * (isSliding ? 2 : 1)
        let origin = cameraPosition
        let shotDir = normalize(forward + right * ((rand() - 0.5) * spread) +
                    SIMD3<Float>(0, (rand() - 0.5) * spread, 0))
        var nearest: Float = 120
        var index: Int? = nil
        for i in bots.indices where bots[i].alive {
            let b = bots[i]
            let center = b.position + SIMD3<Float>(0, 1.04, 0)
            let distanceAlong = simd_dot(center - origin, shotDir)
            guard distanceAlong > 0, distanceAlong < nearest else { continue }
            let miss = simd_length(origin + shotDir * distanceAlong - center)
            if miss < 0.72 {
                // Blocks occlude targets (conservative AABB trace).
                let blocked = blocks.contains { $0.solid && rayBlockDistance(origin, shotDir, $0) < distanceAlong }
                    || (levelCollision?.rayHitsWall(from:origin,direction:shotDir,distance:distanceAlong) ?? false)
                if !blocked { nearest = distanceAlong; index = i }
            }
        }
        if let i = index {
            hits += 1
            recentHit = 0.22
            let headshot = simd_length(origin + shotDir * nearest - (bots[i].position + SIMD3<Float>(0, 1.56, 0))) < 0.35
            bots[i].health -= weapon.damage * (headshot ? 1.6 : 1)
            if bots[i].health <= 0 { kills += 1; bots[i].respawnTimer = 3.2 }
        }
        pitch = min(1.3, pitch + (weaponIndex == 2 ? 0.024 : 0.0075))
    }

    private func rayBlockDistance(_ origin: SIMD3<Float>, _ dir: SIMD3<Float>, _ block: ArenaBlock) -> Float {
        let lo = block.center - block.size / 2
        let hi = block.center + block.size / 2
        var tmin: Float = 0
        var tmax: Float = 1e6
        for axis in 0..<3 {
            let o = origin[axis], d = dir[axis]
            if abs(d) < 0.00001 {
                if o < lo[axis] || o > hi[axis] { return .infinity }
            } else {
                let a = (lo[axis] - o) / d, b = (hi[axis] - o) / d
                tmin = max(tmin, min(a, b))
                tmax = min(tmax, max(a, b))
                if tmax < tmin { return .infinity }
            }
        }
        return tmin
    }

    private func updateBots(_ dt: Float) {
        for i in bots.indices {
            if !bots[i].alive {
                bots[i].respawnTimer -= dt
                if bots[i].respawnTimer <= 0 {
                    let theta = rand() * .pi * 2
                    if let grid=levelCollision {
                        let x=initialPosition.x+cos(theta)*16
                        let z=initialPosition.z+sin(theta)*13
                        bots[i].position=(grid.spawn(nearX:x,z:z) ?? initialPosition) - SIMD3<Float>(0,eyeHeight,0)
                    } else {
                        bots[i].position = SIMD3<Float>(cos(theta) * 20, 0, sin(theta) * 17)
                    }
                    bots[i].health = 100
                    bots[i].attackTimer = 1.2
                }
                continue
            }
            let delta = SIMD2<Float>(pos.x - bots[i].position.x, pos.z - bots[i].position.z)
            let distance = simd_length(delta)
            let direction = distance > 0.01 ? delta / distance : SIMD2<Float>(0, 0)
            if distance > 3.5 {
                let desired = direction * dt * 1.55
                let previous = bots[i].position
                bots[i].position.x += desired.x + direction.y * bots[i].strafe * dt * 0.36
                bots[i].position.z += desired.y - direction.x * bots[i].strafe * dt * 0.36
                let boxCollision=blocks.contains { $0.solid && abs(bots[i].position.x - $0.center.x) < $0.size.x / 2 + 0.4 && abs(bots[i].position.z - $0.center.z) < $0.size.z / 2 + 0.4 }
                let mapCollision:Bool
                if let grid=levelCollision {
                    mapCollision = !grid.canOccupy(x:bots[i].position.x,z:bots[i].position.z,feetY:previous.y,bodyHeight:1.8)
                } else { mapCollision=false }
                if boxCollision || mapCollision {
                    bots[i].position=previous
                    bots[i].strafe *= -1
                } else if let grid=levelCollision,
                          let ground=grid.floorHeight(x:bots[i].position.x,z:bots[i].position.z) {
                    bots[i].position.y=ground
                }
            }
            bots[i].attackTimer -= dt
            if distance < 17 && bots[i].attackTimer <= 0 {
                // Simple training-mode AI; multiplayer/netcode not ported yet.
                bots[i].attackTimer = 1.15 + rand() * 0.8
                let eye = bots[i].position + SIMD3<Float>(0, 1.45, 0)
                let dir = normalize(cameraPosition - eye)
                let occluded = blocks.contains { $0.solid && rayBlockDistance(eye, dir, $0) < distance }
                    || (levelCollision?.rayHitsWall(from:eye,direction:dir,distance:distance) ?? false)
                if !occluded {
                    health = max(0, health - (9 + rand() * 6))
                    if health <= 0 { deaths += 1; deadTimer = 2.0 }
                }
            }
        }
    }

    private func respawnPlayer() {
        pos = initialPosition
        health = 100
        verticalVelocity = 0
        horizontalVelocity = .zero
        reloadRemaining = 0
        isGrounded = true
        ammo = weapon.magazine
    }

    private func clearQueued() {
        controls.jumpQueued = false
        controls.slideQueued = false
        controls.reloadQueued = false
    }

    private func buildTrainingArena() {
        let concrete = SIMD4<Float>(0.44, 0.47, 0.48, 1)
        let sand = SIMD4<Float>(0.37, 0.36, 0.32, 1)
        let blue = SIMD4<Float>(0.18, 0.28, 0.36, 1)
        let red = SIMD4<Float>(0.48, 0.26, 0.22, 1)
        func add(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ c: SIMD4<Float>, _ solid: Bool = true) {
            blocks.append(ArenaBlock(center: SIMD3<Float>(x, y, z), size: SIMD3<Float>(w,h,d), color: c, solid: solid))
        }
        // Original, reusable training arena layout. BO2 maps are imported separately.
        add(0, -0.3, 0, 75, 0.6, 65, sand, false)
        add(0, 2, -31, 76, 4, 1, concrete)
        add(0, 2, 31, 76, 4, 1, concrete)
        add(-37, 2, 0, 1, 4, 63, concrete)
        add(37, 2, 0, 1, 4, 63, concrete)
        add(-18, 2.6, -12, 10, 5.2, 9, blue)
        add(-18, 5.4, -12, 11, 0.5, 10, concrete)
        add(17, 2.4, 12, 12, 4.8, 10, red)
        add(17, 5, 12, 13, 0.5, 11, concrete)
        add(-3, 1.3, -5, 5, 2.6, 11, blue)
        add(7, 0.9, -14, 5, 1.8, 3, red)
        add(-10, 0.9, 8, 4, 1.8, 4, concrete)
        add(7, 1, 8, 2.5, 2, 7, sand)
        add(-24, 0.85, 12, 3, 1.7, 5, sand)
        add(25, 1, -8, 4.5, 2, 4, blue)
        add(-1, 0.7, 21, 7, 1.4, 2, red)
        add(26, 0.65, -22, 9, 1.3, 3, concrete)
        for i in 0..<4 {
            let z = Float(-22 + i * 13)
            add(-32, 1.2, z, 1.2, 2.4, 6, blue)
            add(32, 1.2, z + 4, 1.2, 2.4, 5, red)
        }
    }
}
