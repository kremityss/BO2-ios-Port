import Foundation
import simd

/// Coarse grid collision and floor heights baked from recovered map geometry.
/// This is not yet equivalent to precision capsule/triangle physics.
final class NativeCollision {
    private let width: Int
    private let height: Int
    private let originX: Float
    private let originZ: Float
    private let resolution: Float
    private let floors: [Int16]
    private let wallBottoms: [Int16]
    private let wallTops: [Int16]
    private let absent = Int16.min

    private init?(data: Data) {
        let bytes=[UInt8](data)
        guard bytes.count>=24 && Array(bytes[0..<8]) == Array("MERKCOL1".utf8) else { return nil }
        func u16(_ i:Int)->UInt16 { UInt16(bytes[i]) | UInt16(bytes[i+1])<<8 }
        func f32(_ i:Int)->Float {
            let n=UInt32(bytes[i]) | UInt32(bytes[i+1])<<8 | UInt32(bytes[i+2])<<16 | UInt32(bytes[i+3])<<24
            return Float(bitPattern:n)
        }
        let w=Int(u16(8)), h=Int(u16(10))
        guard w>0 && h>0 && w*h<=250000 && bytes.count==24+w*h*6 else {return nil}
        let cellSize=f32(20)
        guard cellSize.isFinite && cellSize>=0.3 && cellSize<=3 else {return nil}
        width=w
        height=h
        originX=f32(12)
        originZ=f32(16)
        guard originX.isFinite && originZ.isFinite else { return nil }
        resolution=cellSize
        var heights=[Int16](), low=[Int16](), high=[Int16]()
        heights.reserveCapacity(w*h)
        low.reserveCapacity(w*h)
        high.reserveCapacity(w*h)
        for i in 0..<(w*h) {
            let j=24+6*i
            heights.append(Int16(bitPattern:u16(j)))
            low.append(Int16(bitPattern:u16(j+2)))
            high.append(Int16(bitPattern:u16(j+4)))
        }
        floors=heights
        wallBottoms=low
        wallTops=high
    }

    static func load() -> NativeCollision? {
        guard NativeMap.isPresent,
              let url=Bundle.main.url(forResource:NativeLevel.selected.resource("MerkCollision"),withExtension:"bin"),
              let data=try? Data(contentsOf:url) else {return nil}
        return NativeCollision(data:data)
    }

    private func index(_ x:Float,_ z:Float)->Int? {
        guard x.isFinite && z.isFinite else {return nil}
        let i=Int(floor((x-originX)/resolution))
        let j=Int(floor((z-originZ)/resolution))
        guard i>=0 && j>=0 && i<width && j<height else {return nil}
        return j*width+i
    }

    func floorHeight(x:Float,z:Float)->Float? {
        guard let i=index(x,z),floors[i] != absent else {return nil}
        return Float(floors[i])*0.01
    }

    func canOccupy(x:Float,z:Float,feetY:Float,bodyHeight:Float)->Bool {
        guard let i=index(x,z),floors[i] != absent else {return false}
        let floor=Float(floors[i])*0.01
        if floor>feetY+0.55 {return false}
        if wallBottoms[i] != absent && wallTops[i] != absent {
            let lo=Float(wallBottoms[i])*0.01
            let hi=Float(wallTops[i])*0.01
            if lo<feetY+bodyHeight-0.1 && hi>feetY+0.1 {return false}
        }
        return true
    }

    /// Conservative wall occlusion along a ray. Used by native hitscan and bots.
    /// True mesh ray-casting against triangle BVHs will supersede this.
    func rayHitsWall(from origin:SIMD3<Float>,direction:SIMD3<Float>,distance:Float)->Bool {
        guard distance.isFinite && distance>0 else {return false}
        let step=max(0.15,resolution*0.45)
        let increments=min(1500,Int(ceil(distance/step)))
        guard increments>1 else {return false}
        for i in 1..<increments {
            let progress=Float(i)*distance/Float(increments)
            let p=origin+direction*progress
            guard let k=index(p.x,p.z) else {continue}
            if wallBottoms[k] != absent && wallTops[k] != absent {
                let lo=Float(wallBottoms[k])*0.01
                let hi=Float(wallTops[k])*0.01
                if p.y>=lo && p.y<=hi {return true}
            }
        }
        return false
    }

    /// Avoid the old "first nonempty cell near map center" spawn. That often
    /// selected a roof/isolated elevated brush from the imported GLB.
    /// These ground-sector anchors are calibrated to the shipped Nuketown 2025
    /// MERKCOL1 grid. Every anchor is still validated against floor and wall
    /// clearance so other builds fail over to a scored walkable cell.
    func preferredSpawn(eyeHeight: Float = 1.65) -> SIMD3<Float>? {
        let anchors: [SIMD2<Float>] = [
            SIMD2<Float>(39, -14),    // broad, low ground on east approach
            SIMD2<Float>(-20, -61),   // west spawn-side paved corridor
            SIMD2<Float>(-1, 31),    // central low approach
            SIMD2<Float>(-19, 34)
        ]
        for anchor in anchors {
            if let candidate = safeSpawn(nearX: anchor.x, z: anchor.y,
                                         searchRadius: 10, eyeHeight: eyeHeight,
                                         maxGroundY: 14, minimumSupport: 12) {
                return candidate
            }
        }
        let centerX = originX + Float(width) * resolution * 0.5
        let centerZ = originZ + Float(height) * resolution * 0.5
        return safeSpawn(nearX: centerX, z: centerZ, searchRadius: 90,
                         eyeHeight: eyeHeight, maxGroundY: 16, minimumSupport: 7)
            ?? spawn(nearX: centerX, z: centerZ, eyeHeight: eyeHeight)
    }

    /// Sample neighboring cells for a broad contiguous floor at the same
    /// elevation. Roof strips and isolated one-cell brush fragments score low.
    private func supportCount(i: Int, j: Int, floorY: Float, eyeHeight: Float) -> Int {
        var support = 0
        for dz in -3...3 {
            for dx in -3...3 {
                let x = i + dx, z = j + dz
                guard x >= 0, z >= 0, x < width, z < height else { continue }
                let px = originX + (Float(x) + 0.5) * resolution
                let pz = originZ + (Float(z) + 0.5) * resolution
                if let y = floorHeight(x: px, z: pz), abs(y - floorY) <= 0.55,
                   canOccupy(x: px, z: pz, feetY: y, bodyHeight: eyeHeight) {
                    support += 1
                }
            }
        }
        return support
    }

    func safeSpawn(nearX: Float, z: Float, searchRadius: Float,
                   eyeHeight: Float = 1.65, maxGroundY: Float = 16,
                   minimumSupport: Int = 10) -> SIMD3<Float>? {
        guard nearX.isFinite, z.isFinite, searchRadius > 0 else { return nil }
        let cx = max(0, min(width-1, Int(floor((nearX-originX)/resolution))))
        let cz = max(0, min(height-1, Int(floor((z-originZ)/resolution))))
        let range = Int(ceil(searchRadius/resolution))
        var bestScore: Float = -.infinity
        var best: SIMD3<Float>?
        for j in max(0,cz-range)...min(height-1,cz+range) {
            for i in max(0,cx-range)...min(width-1,cx+range) {
                let x = originX + (Float(i)+0.5)*resolution
                let zz = originZ + (Float(j)+0.5)*resolution
                let distance = hypot(x-nearX, zz-z)
                guard distance <= searchRadius,
                      let y = floorHeight(x:x,z:zz), y <= maxGroundY,
                      canOccupy(x:x,z:zz,feetY:y,bodyHeight:eyeHeight) else {continue}
                let support = supportCount(i:i,j:j,floorY:y,eyeHeight:eyeHeight)
                guard support >= minimumSupport else {continue}
                // Nearby broad floors win; tall isolated shelves lose.
                let score = Float(support)*1.6 - distance*2.6 - max(0,y-9)*1.1
                if score > bestScore {
                    bestScore = score
                    best = SIMD3<Float>(x,y+eyeHeight,zz)
                }
            }
        }
        return best
    }

    func spawn(nearX:Float,z:Float,eyeHeight:Float=1.65)->SIMD3<Float>? {
        guard nearX.isFinite && z.isFinite else {return nil}
        let cx=max(0,min(width-1,Int((nearX-originX)/resolution)))
        let cz=max(0,min(height-1,Int((z-originZ)/resolution)))
        for radius in 0..<max(width,height) {
            let x0=max(0,cx-radius), x1=min(width-1,cx+radius)
            let z0=max(0,cz-radius), z1=min(height-1,cz+radius)
            for j in z0...z1 {
                for i in x0...x1 where radius==0 || j==z0 || j==z1 || i==x0 || i==x1 {
                    let x=originX+(Float(i)+0.5)*resolution
                    let z=originZ+(Float(j)+0.5)*resolution
                    if let y=floorHeight(x:x,z:z),canOccupy(x:x,z:z,feetY:y,bodyHeight:eyeHeight) {
                        return SIMD3<Float>(x,y+eyeHeight,z)
                    }
                }
            }
        }
        return nil
    }

    /// Snap an original web spawn marker to the closest authored collision floor.
    /// The web game raycasts downward from each marker; this is the bounded
    /// 2.5D-grid equivalent, not a projection onto arbitrary render geometry.
    func nearestAuthoredSpawnGround(at authored: SIMD3<Float>,
                                    eyeHeight: Float = 0.60,
                                    radius: Float = 7.5,
                                    maxFloorDifference: Float = 1.25) -> SIMD3<Float>? {
        guard authored.x.isFinite, authored.y.isFinite, authored.z.isFinite,
              radius > 0, radius <= 25 else { return nil }
        let bodyHeight: Float = 0.72
        let nearest: (Float, Float, Float) -> SIMD3<Float>? = { x, z, y in
            guard abs(y - authored.y) <= maxFloorDifference,
                  y <= authored.y + 0.32,
                  self.canOccupy(x: x, z: z, feetY: y, bodyHeight: bodyHeight)
            else { return nil }
            return SIMD3<Float>(x, y + eyeHeight, z)
        }
        if let y = floorHeight(x: authored.x, z: authored.z),
           let exact = nearest(authored.x, authored.z, y) { return exact }
        let steps = Int(ceil(radius / resolution))
        var best: SIMD3<Float>?
        var bestCost = Float.infinity
        for dz in -steps...steps {
            for dx in -steps...steps {
                let x = authored.x + Float(dx) * resolution
                let z = authored.z + Float(dz) * resolution
                let distance = hypot(x - authored.x, z - authored.z)
                guard distance <= radius, let y = floorHeight(x: x, z: z),
                      let spot = nearest(x,z,y) else { continue }
                let cost = distance + 3 * abs(y - authored.y)
                if cost < bestCost { bestCost = cost; best = spot }
            }
        }
        return best
    }

}
