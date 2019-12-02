import Metal
import MetalKit
import simd

typealias Position = SIMD2<Float>
typealias Color = SIMD4<Float>

let width: Float = 800
let height: Float = 600
let ballC = 2_000
let ballDiam: Float = 8
let ballRad = ballDiam / 2
let maxX = width - ballDiam
let maxY = height - ballDiam
let ballSpeed: Float = 2
let maxBuffersInFlight = 3
let dataUnit = MemoryLayout<Position>.stride
let dataSize = ballC * dataUnit

// TODO: Put balls on GPU; use compute shaders

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

class Renderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    let commandQueue: MTLCommandQueue
    var drawState: MTLRenderPipelineState
    var vertexBuffer: MTLBuffer
    var colorBuffer: MTLBuffer
    var ballTexture: MTLTexture
    var balls: [Ball] = []

    init?(metalKitView: MTKView) {
        self.device = metalKitView.device!
        self.commandQueue = self.device.makeCommandQueue()!
        
        let library = device.makeDefaultLibrary()!
        let vertexFunction = library.makeFunction(name: "vertexShader")
        let fragmentFunction = library.makeFunction(name: "fragmentShader")
        
        do {
            ballTexture = try Renderer.loadTexture(device: device, textureName: "Circle")
        } catch {
            print("Unable to load texture. Error info: \(error)")
            return nil
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        let attachment = pipelineDescriptor.colorAttachments[0]!
        attachment.pixelFormat = metalKitView.colorPixelFormat
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        drawState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        vertexBuffer = device.makeBuffer(length: dataSize)!
        let colors = (0..<ballC).map { _ -> Color in
            var color = Color.random(in: 0..<1)
            color.w = 1
            return color
        }
        colorBuffer = device.makeBuffer(bytes: colors, length: ballC * MemoryLayout<Color>.stride)!
        
        super.init()
        randomizeBalls()
        copyToVertexBuffer()
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

    func randomizeBalls() {
        for _ in 0..<ballC {
            var newX, newY: Float
            
            repeat {
                newX = Float.random(in: 0..<maxX)
                newY = Float.random(in: 0..<maxY)
            } while balls.contains { ball in
                let dx = ball.x - newX
                let dy = ball.y - newY
                return pow(dx, 2) + pow(dy, 2) < pow(ballDiam, 2)
            }
            
            let ball = Ball(x: newX, y: newY)
            balls.append(ball)
        }
    }
    
    func addVerticesForPos(x: Float, y: Float) {
        
    }
    
    func toCoord(_ x: Float, _ max: Float) -> Float {
        return 2*(x+ballRad)/max - 1
    }
    
    func isBounded(_ x: Float, _ max: Float) -> Bool {
        return 0 <= x && x < max
    }
    
    func copyToVertexBuffer() {
        let contents = vertexBuffer.contents()
        for i in 0..<ballC {
            let pos = Position(
                toCoord(balls[i].x, width),
                toCoord(balls[i].y, height))
            
            contents.storeBytes(of: pos,
                                toByteOffset: i * dataUnit,
                                as: Position.self);
        }
    }
    
    func updateGameState() {
        for i in 0..<ballC {
            balls[i].x += balls[i].dx
            balls[i].y += balls[i].dy
            if !isBounded(balls[i].x, maxX) {
                balls[i].dx *= -1
            }
            if !isBounded(balls[i].y, maxY) {
                balls[i].dy *= -1
            }
        }
        copyToVertexBuffer()
    }

    func draw(in view: MTKView) {
        /// Per frame updates hare
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
                semaphore.signal()
            }
            
            self.updateGameState()

            /// Delay getting the currentRenderPassDescriptor until we absolutely need it to avoid
            ///   holding onto the drawable and blocking the display pipeline any longer than necessary
            let renderPassDescriptor = view.currentRenderPassDescriptor
            
            if let renderPassDescriptor = renderPassDescriptor {
                /// Final pass rendering code here
                if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                    renderEncoder.setRenderPipelineState(drawState)
                    renderEncoder.setFragmentTexture(ballTexture, index: 0)
                    renderEncoder.setVertexBuffers([vertexBuffer, colorBuffer], offsets: [0, 0], range: 0..<2)
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
