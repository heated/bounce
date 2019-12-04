import Metal
import MetalKit
import simd

typealias Color = SIMD4<Float>

let maxX = width - ballDiam
let maxY = height - ballDiam

let targetBallC = Int(TARGET_BALL_C)
let apxAreaPerBall = maxX * maxY / Float(targetBallC)
let apxLengthPerBall = sqrt(apxAreaPerBall)
let xBalls = Int(maxX / apxLengthPerBall)
let yBalls = Int(maxY / apxLengthPerBall)
let gridRows = Int(ceil(maxY / ballDiam))
let gridCols = Int(ceil(maxX / ballDiam))
/// A ball count that's not a multiple of 256 leads to what I assume is some balls updating multiple times per time step.
let ballC = (xBalls * yBalls / 256) * 256
let tileC = gridRows * gridCols

let maxBuffersInFlight = 3
//let threadsPerGroup = Int((ballC - 1)/256 + 1)
let threadsPerGroup = Int(ballC/256)
let gridSize = MTLSizeMake(threadsPerGroup, 1, 1)
let threadGroupSize = MTLSizeMake(256, 1, 1)

struct Ball {
    var x, y, dx, dy: Float
    init(x: Float, y: Float) {
        self.x = x
        self.y = y
        let angle = Float.random(in: 0..<2*Float.pi)
        dx = cos(angle) * ballSpeed
        dy = sin(angle) * ballSpeed
    }
}

struct Tile {
    let bucket: simd_float2x4
    let bucket2: simd_float2x2
}

class Renderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    let commandQueue: MTLCommandQueue
    let moveState: MTLComputePipelineState
    let collideState: MTLComputePipelineState
    var drawState: MTLRenderPipelineState
    var ballBuffer: MTLBuffer
    var colorBuffer: MTLBuffer
    var ballTexture: MTLTexture
    var balls: [Ball] = []

    init?(metalKitView: MTKView) {
        self.device = metalKitView.device!
        self.commandQueue = self.device.makeCommandQueue()!
        
        let library = device.makeDefaultLibrary()!
        let moveBalls = library.makeFunction(name: "moveBalls")!
        let collideBalls = library.makeFunction(name: "collideBalls")!
        let vertexFunction = library.makeFunction(name: "vertexShader")
        let fragmentFunction = library.makeFunction(name: "fragmentShader")
        
        ballTexture = try! Renderer.loadTexture(device: device, textureName: "Circle")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        let attachment = pipelineDescriptor.colorAttachments[0]!
        attachment.pixelFormat = metalKitView.colorPixelFormat
        Renderer.setAlphaBlendSettings(attachment)
        
        moveState = try! device.makeComputePipelineState(function: moveBalls)
        collideState = try! device.makeComputePipelineState(function: collideBalls)
        drawState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        
        ballBuffer = Renderer.makeBallBuffer(device)
        colorBuffer = Renderer.makeColorBuffer(device)
        super.init()
    }
    
    class func loadTexture(device: MTLDevice,
                           textureName: String) throws -> MTLTexture {
        let textureLoader = MTKTextureLoader(device: device)

        let textureLoaderOptions = [
            MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            MTKTextureLoader.Option.textureStorageMode: NSNumber(value: MTLStorageMode.`private`.rawValue)
        ]

        return try textureLoader.newTexture(name: textureName,
                                            scaleFactor: 1.0,
                                            bundle: nil,
                                            options: textureLoaderOptions)
    }
    
    class func setAlphaBlendSettings(_ attachment: MTLRenderPipelineColorAttachmentDescriptor) {
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }

    class func randomBalls() -> [Ball] {
        let areaPerBall = maxX * maxY / Float(ballC)
        let lengthPerBall = sqrt(areaPerBall)
        
        let offset = (lengthPerBall - ballDiam) / 2
        var balls: [Ball] = []
        
        for i in 0..<ballC {
            let x = Float(i % xBalls) * lengthPerBall + offset
            let y = Float(i / xBalls) * lengthPerBall + offset
            
            let ball = Ball(x: x, y: y)
            balls.append(ball)
        }
        
        return balls
    }
    
    class func makeGridBuffer(_ device: MTLDevice) -> MTLBuffer {
        return device.makeBuffer(length: tileC * MemoryLayout<Tile>.stride)!
    }
    
    class func makeBallBuffer(_ device: MTLDevice) -> MTLBuffer {
        let balls = Renderer.randomBalls()
        return device.makeBuffer(bytes: balls, length: ballC * MemoryLayout<Ball>.stride)!
    }
    
    class func makeColorBuffer(_ device: MTLDevice) -> MTLBuffer {
        let colors = (0..<ballC).map { _ -> Color in
            var color = Color.random(in: 0..<1)
            color.w = 1
            return color
        }
        return device.makeBuffer(bytes: colors, length: ballC * MemoryLayout<Color>.stride)!
    }
    
    func updateBalls() {
        let buffer = commandQueue.makeCommandBuffer()!
        let encoder = buffer.makeComputeCommandEncoder()!
        
        let sizeBuffer = device.makeBuffer(length: tileC * MemoryLayout<uint>.stride)!
        let gridBuffer = Renderer.makeGridBuffer(device)
        encoder.setComputePipelineState(moveState)
        encoder.setBuffers([ballBuffer, gridBuffer, sizeBuffer], offsets: [0, 0, 0], range: 0..<3)
        encoder.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadGroupSize)
        encoder.setComputePipelineState(collideState)
        encoder.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        buffer.commit()
    }

    func draw(in view: MTKView) {
        /// Per frame updates hare
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
                semaphore.signal()
            }
            
            for _ in 0..<1 {
                updateBalls()
            }
            
            /// Delay getting the currentRenderPassDescriptor until we absolutely need it to avoid
            ///   holding onto the drawable and blocking the display pipeline any longer than necessary
            let renderPassDescriptor = view.currentRenderPassDescriptor
            
            if let renderPassDescriptor = renderPassDescriptor {
                /// Final pass rendering code here
                if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                    renderEncoder.setRenderPipelineState(drawState)
                    renderEncoder.setFragmentTexture(ballTexture, index: 0)
                    renderEncoder.setVertexBuffers([ballBuffer, colorBuffer], offsets: [0, 0], range: 0..<2)
                    renderEncoder.drawPrimitives(type: MTLPrimitiveType.point, vertexStart: 0, vertexCount: ballC)
                    renderEncoder.endEncoding()
                    
                    if let drawable = view.currentDrawable {
                        commandBuffer.present(drawable)
                    }
                }
            }
            
            commandBuffer.commit()
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here
    }
}
