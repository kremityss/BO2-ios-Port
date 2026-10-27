import Metal
import MetalKit
import QuartzCore
import simd

final class GameRenderer: NSObject, MTKViewDelegate {
    let world = GameWorld()
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    let depthState: MTLDepthStencilState
    let cubeBuffer: MTLBuffer
    let mapBuffer: MTLBuffer?
    let atlasTexture: MTLTexture
    let mapVertexCount: Int
    let instancedScenery: [(mesh: MTLBuffer, count: Int, transforms: MTLBuffer, instances: Int)]
    let weaponBuffers: [MTLBuffer?]
    let weaponVertexCounts: [Int]
    let weaponTextures: [MTLTexture]
    var onHUD: ((String) -> Void)?
    private var previousTime = CACurrentMediaTime()
    private var hudAccum: Double = 0
    private var smoothedFPS: Double = 60
    private var frameIndex = 0
    private var storedWidth = 1
    private var storedHeight = 1

    init?(view: MTKView) {
        guard let d = MTLCreateSystemDefaultDevice(),
              let q = d.makeCommandQueue(),
              let lib = d.makeDefaultLibrary(),
              let vertex = lib.makeFunction(name: "sceneVertex"),
              let fragment = lib.makeFunction(name: "sceneFragment") else { return nil }
        device = d
        commandQueue = q
        let config = MTLRenderPipelineDescriptor()
        config.vertexFunction = vertex
        config.fragmentFunction = fragment
        config.colorAttachments[0].pixelFormat = .bgra8Unorm
        config.depthAttachmentPixelFormat = .depth32Float
        guard let pipe = try? d.makeRenderPipelineState(descriptor: config) else { return nil }
        pipeline = pipe
        let stencil = MTLDepthStencilDescriptor()
        stencil.depthCompareFunction = .less
        stencil.isDepthWriteEnabled = true
        guard let depth = d.makeDepthStencilState(descriptor: stencil) else { return nil }
        depthState = depth
        let vertices = Self.cubeVertices()
        guard let vb = d.makeBuffer(bytes: vertices, length: MemoryLayout<GPUVertex>.stride * vertices.count, options: .storageModeShared) else { return nil }
        cubeBuffer = vb
        // The white fallback makes primitive cube/bot geometry and untextured
        // map materials work with the same fragment shader.
        let whiteDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb,
                                                                 width: 1, height: 1, mipmapped: false)
        whiteDesc.usage = .shaderRead
        guard let white = d.makeTexture(descriptor: whiteDesc) else { return nil }
        var whitePixel: [UInt8] = [255,255,255,255]
        whitePixel.withUnsafeBytes { ptr in
            white.replace(region: MTLRegionMake2D(0,0,1,1), mipmapLevel: 0,
                          withBytes: ptr.baseAddress!, bytesPerRow: 4)
        }
        if let atlasURL = Bundle.main.url(forResource: "MerkAtlas", withExtension: "png"),
           let texture = try? MTKTextureLoader(device:d).newTexture(URL:atlasURL,
                  options:[.SRGB:true,.origin:MTKTextureLoader.Origin.topLeft]) {
            atlasTexture = texture
        } else {
            atlasTexture = white
        }
        if world.hasImportedLevel, let map = NativeMap.load(), !map.isEmpty {
            mapBuffer = d.makeBuffer(bytes: map, length: map.count * MemoryLayout<GPUVertex>.stride, options: .storageModeShared)
            mapVertexCount = map.count
        } else {
            mapBuffer = nil
            mapVertexCount = 0
        }
        var scenery: [(mesh: MTLBuffer, count: Int, transforms: MTLBuffer, instances: Int)] = []
        if world.hasImportedLevel {
            for group in NativeInstancedMap.load() {
                guard let mesh = d.makeBuffer(bytes: group.vertices,
                       length: group.vertices.count * MemoryLayout<GPUVertex>.stride, options: .storageModeShared),
                      let instance = d.makeBuffer(bytes: group.instances,
                       length: group.instances.count * MemoryLayout<GPUInstance>.stride, options: .storageModeShared) else { continue }
                scenery.append((mesh: mesh, count: group.vertices.count,
                                transforms: instance, instances: group.instances.count))
            }
        }
        instancedScenery = scenery
        let weaponNames = ["M27", "AN94", "DSR50", "FiveSeven"]
        var loadedBuffers: [MTLBuffer?] = []
        var loadedCounts: [Int] = []
        var loadedTextures: [MTLTexture] = []
        let loader = MTKTextureLoader(device:d)
        for name in weaponNames {
            if let mesh = NativeMap.load(resource: "MerkWeapon" + name), !mesh.isEmpty,
               let buffer = d.makeBuffer(bytes:mesh,
                                  length:mesh.count * MemoryLayout<GPUVertex>.stride,
                                  options:.storageModeShared) {
                loadedBuffers.append(buffer)
                loadedCounts.append(mesh.count)
                if let textureURL = Bundle.main.url(forResource:"MerkWeapon" + name + "Atlas", withExtension:"png"),
                   let tex = try? loader.newTexture(URL:textureURL,
                               options:[.SRGB:true, .origin: MTKTextureLoader.Origin.topLeft]) {
                    loadedTextures.append(tex)
                } else {
                    loadedTextures.append(white)
                }
            } else {
                loadedBuffers.append(nil)
                loadedCounts.append(0)
                loadedTextures.append(white)
            }
        }
        weaponBuffers = loadedBuffers
        weaponVertexCounts = loadedCounts
        weaponTextures = loadedTextures
        super.init()
        view.device = d
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.46, green: 0.61, blue: 0.70, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.delegate = self
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        storedWidth = max(1, Int(size.width))
        storedHeight = max(1, Int(size.height))
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let frameDuration = max(0.001, now - previousTime)
        let dt = min(0.033, Float(frameDuration))
        smoothedFPS = smoothedFPS * 0.85 + min(120, 1.0 / frameDuration) * 0.15
        previousTime = now
        world.update(dt)
        hudAccum += Double(dt)
        if hudAccum > 0.12 {
            hudAccum = 0
            let w = world
            let status = w.health <= 0 ? "RESPAWNING" : (w.reloading ? "RELOADING" : "")
            onHUD?("\(w.weapon.name) \(w.ammo)/\(w.reserveAmmo)  \(Int(w.health))HP  \(Int(smoothedFPS))FPS\nK\(w.kills) D\(w.deaths)  \(status)")
        }
        guard let renderPass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let command = commandQueue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: renderPass) else { return }
        let size = view.drawableSize
        let aspect = Float(max(1, size.width)) / Float(max(1, size.height))
        let fov: Float = world.controls.ads ? (world.weaponIndex == 2 ? 0.262 : 0.71) : 1.17
        let projection = simd_float4x4.perspective(fov: fov, aspect: aspect, near: 0.035, far: 180)
        let camera = world.cameraPosition
        let viewMatrix = simd_float4x4.rotateX(-world.pitch) * simd_float4x4.rotateY(world.yaw) * simd_float4x4.translation(-camera)
        var u = GPUUniforms(viewProjection: projection * viewMatrix, sunDirection: SIMD4<Float>(0.5,1,0.7,0))
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setFragmentBytes(&u, length: MemoryLayout<GPUUniforms>.stride, index: 1)
        encoder.setVertexBytes(&u, length: MemoryLayout<GPUUniforms>.stride, index: 1)
        encoder.setFragmentTexture(atlasTexture, index: 0)
        if let map = mapBuffer, mapVertexCount > 0 {
            var identity = GPUInstance(model: matrix_identity_float4x4, tint: SIMD4<Float>(repeating: 1))
            encoder.setVertexBuffer(map, offset: 0, index: 0)
            encoder.setVertexBytes(&identity, length: MemoryLayout<GPUInstance>.stride, index: 2)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mapVertexCount)
        }
        // Repeated props and vegetation are drawn with native GPU instancing.
        // Prototypes are absent from the main scene mesh, avoiding stray copies.
        for group in instancedScenery {
            encoder.setVertexBuffer(group.mesh, offset: 0, index: 0)
            encoder.setVertexBuffer(group.transforms, offset: 0, index: 2)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0,
                                   vertexCount: group.count, instanceCount: group.instances)
        }
        let importedGun = weaponBuffers.indices.contains(world.weaponIndex)
                          && weaponBuffers[world.weaponIndex] != nil
        let props = makeInstances(importedGun: importedGun)
        guard let instances = device.makeBuffer(bytes: props, length: props.count * MemoryLayout<GPUInstance>.stride, options: .storageModeShared) else {
            encoder.endEncoding()
            command.commit()
            return
        }
        encoder.setVertexBuffer(cubeBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(instances, offset: 0, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: props.count)
        // Imported weapon GLBs have their own packed albedo atlases and a
        // pre-aligned axis. Fallback blocks remain for unavailable models.
        if importedGun, let gun = weaponBuffers[world.weaponIndex] {
            let camera = world.cameraPosition
            let forward = world.forward
            let right = world.right
            let up = simd_normalize(simd_cross(right,forward))
            let ads: Float = world.controls.ads ? 0.35 : 1.0
            let anchor = camera + forward * 0.72 + right * (0.22 * ads) - up * (0.18 * ads)
            let basis = simd_float4x4.rotateY(-world.yaw) * simd_float4x4.rotateX(world.pitch)
            var instance = GPUInstance(model:simd_float4x4.translation(anchor) * basis,
                                       tint:SIMD4<Float>(repeating:1))
            encoder.setVertexBuffer(gun, offset:0, index:0)
            encoder.setVertexBytes(&instance, length:MemoryLayout<GPUInstance>.stride, index:2)
            encoder.setFragmentTexture(weaponTextures[world.weaponIndex], index:0)
            encoder.drawPrimitives(type:.triangle,vertexStart:0,
                                   vertexCount:weaponVertexCounts[world.weaponIndex])
        }
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
        frameIndex += 1
    }

    private func makeInstances(importedGun: Bool) -> [GPUInstance] {
        var instances: [GPUInstance] = []
        instances.reserveCapacity(world.blocks.count + world.bots.count * 5 + 12)
        func box(_ position: SIMD3<Float>, _ size: SIMD3<Float>, _ color: SIMD4<Float>) {
            let m = simd_float4x4.translation(position) * simd_float4x4.scale(size)
            instances.append(GPUInstance(model: m, tint: color))
        }
        for b in world.blocks { box(b.center, b.size, b.color) }
        for b in world.bots where b.alive {
            let p = b.position
            box(p + SIMD3<Float>(0, 1.07, 0), SIMD3<Float>(0.56,0.87,0.35), SIMD4<Float>(0.24,0.30,0.32,1))
            box(p + SIMD3<Float>(0, 1.65, 0), SIMD3<Float>(0.36,0.39,0.34), SIMD4<Float>(0.58,0.44,0.34,1))
            box(p + SIMD3<Float>(-0.17, 0.42, 0), SIMD3<Float>(0.20,0.79,0.28), SIMD4<Float>(0.17,0.22,0.23,1))
            box(p + SIMD3<Float>(0.17, 0.42, 0), SIMD3<Float>(0.20,0.79,0.28), SIMD4<Float>(0.17,0.22,0.23,1))
            box(p + SIMD3<Float>(0, 1.9, 0), SIMD3<Float>(0.55,0.06,0.12), SIMD4<Float>(0.48,0.08,0.07,1))
        }
        // First-person weapon geometry is truly in the 3D world. No 2D gun sprite.
        let camera = world.cameraPosition
        let f = world.forward
        let r = world.right
        let up = normalize(simd_cross(r, f))
        let t: Float = world.controls.ads ? 0.25 : 1
        let anchor = camera + f * 0.68 + r * (0.27 * t) - up * (0.25 * t)
        let basis = simd_float4x4.rotateY(-world.yaw) * simd_float4x4.rotateX(world.pitch)
        let steel = world.weapon.color
        func gunPiece(_ offset: SIMD3<Float>, _ extent: SIMD3<Float>, _ tint: SIMD4<Float>) {
            let model = simd_float4x4.translation(anchor) * basis * simd_float4x4.translation(offset) * simd_float4x4.scale(extent)
            instances.append(GPUInstance(model: model, tint: tint))
        }
        if !importedGun {
            gunPiece(SIMD3<Float>(0,0,-0.13), SIMD3<Float>(0.14,0.13,0.60), steel)
            gunPiece(SIMD3<Float>(0,0,-0.48), SIMD3<Float>(0.065,0.07,0.39), SIMD4<Float>(0.12,0.13,0.14,1))
            gunPiece(SIMD3<Float>(0,-0.13,0.02), SIMD3<Float>(0.09,0.27,0.14), steel)
            gunPiece(SIMD3<Float>(0,0.13,-0.07), SIMD3<Float>(0.10,0.045,0.17), SIMD4<Float>(0.10,0.12,0.13,1))
        }
        if world.muzzleFlash > 0 {
            gunPiece(SIMD3<Float>(0,0,-0.74), SIMD3<Float>(0.23,0.23,0.19), SIMD4<Float>(1,0.69,0.1,1))
        }
        return instances
    }

    static func cubeVertices() -> [GPUVertex] {
        let white = SIMD4<Float>(repeating: 1)
        var v: [GPUVertex] = []
        // Each face with CCW winding viewed from outside.
        let faces: [(SIMD3<Float>, [SIMD3<Float>])] = [
            (SIMD3<Float>(0,0,1), [SIMD3<Float>(-0.5,-0.5,0.5),SIMD3<Float>(0.5,-0.5,0.5),SIMD3<Float>(0.5,0.5,0.5),SIMD3<Float>(-0.5,0.5,0.5)]),
            (SIMD3<Float>(0,0,-1), [SIMD3<Float>(0.5,-0.5,-0.5),SIMD3<Float>(-0.5,-0.5,-0.5),SIMD3<Float>(-0.5,0.5,-0.5),SIMD3<Float>(0.5,0.5,-0.5)]),
            (SIMD3<Float>(1,0,0), [SIMD3<Float>(0.5,-0.5,0.5),SIMD3<Float>(0.5,-0.5,-0.5),SIMD3<Float>(0.5,0.5,-0.5),SIMD3<Float>(0.5,0.5,0.5)]),
            (SIMD3<Float>(-1,0,0), [SIMD3<Float>(-0.5,-0.5,-0.5),SIMD3<Float>(-0.5,-0.5,0.5),SIMD3<Float>(-0.5,0.5,0.5),SIMD3<Float>(-0.5,0.5,-0.5)]),
            (SIMD3<Float>(0,1,0), [SIMD3<Float>(-0.5,0.5,0.5),SIMD3<Float>(0.5,0.5,0.5),SIMD3<Float>(0.5,0.5,-0.5),SIMD3<Float>(-0.5,0.5,-0.5)]),
            (SIMD3<Float>(0,-1,0), [SIMD3<Float>(-0.5,-0.5,-0.5),SIMD3<Float>(0.5,-0.5,-0.5),SIMD3<Float>(0.5,-0.5,0.5),SIMD3<Float>(-0.5,-0.5,0.5)])
        ]
        for (normal, quad) in faces {
            for i in [0,1,2,0,2,3] { v.append(GPUVertex(position: quad[i], normal: normal, color: white,
                                                              uv: SIMD2<Float>(0.5,0.5), atlasRect: SIMD4<Float>(0.5,0.5,0,0))) }
        }
        return v
    }
}
