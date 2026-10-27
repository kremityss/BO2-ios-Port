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
              let url=Bundle.main.url(forResource:"MerkCollision",withExtension:"bin"),
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
}
