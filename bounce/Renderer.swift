import Metal
import MetalKit
import simd

let width = 800
let height = 600
let ballC = 1_000
let ballDiam = 5.0
let ballRad = ballDiam / 2
let ballSpeed = 2.0
let maxBuffersInFlight = 3
let dataUnit = MemoryLayout<Float>.stride

class Renderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    let commandQueue: MTLCommandQueue
    var depthState: MTLDepthStencilState
    var drawState: MTLRenderPipelineState
    var vertexBuffer: MTLBuffer
    var ballTexture: MTLTexture
    let vertexData: [Float] = [
        -1, -1,
         1, -1,
        -1,  1,
         1,  1,
         1, -1,
        -1,  1,
    ]

    init?(metalKitView: MTKView) {
        self.device = metalKitView.device!
        self.commandQueue = self.device.makeCommandQueue()!
        
        let library = device.makeDefaultLibrary()!
        let vertexFunction = library.makeFunction(name: "vertexShader")
        let fragmentFunction = library.makeFunction(name: "fragmentShader")
        
        metalKitView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
        let depthStateDesciptor = MTLDepthStencilDescriptor()
        depthStateDesciptor.depthCompareFunction = MTLCompareFunction.less
        depthStateDesciptor.isDepthWriteEnabled = true
        self.depthState = device.makeDepthStencilState(descriptor:depthStateDesciptor)!
        do {
            ballTexture = try Renderer.loadTexture(device: device, textureName: "Circle")
        } catch {
            print("Unable to load texture. Error info: \(error)")
            return nil
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.depthAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        
        drawState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        
        let dataSize = vertexData.count * dataUnit;
        vertexBuffer = device.makeBuffer(bytes: vertexData, length: dataSize, options: [])!
        
        super.init()
        randomizeBalls()
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
        
    }
    
    func addVerticesForPos(x: Float, y: Float) {
        
    }
    
    func updateGameState() {
        
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
                    renderEncoder.setCullMode(.back)
                    renderEncoder.setFrontFacing(.counterClockwise)
                    renderEncoder.setDepthStencilState(depthState)
                    renderEncoder.setFragmentTexture(ballTexture, index: TextureIndex.color.rawValue)
                    renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                    renderEncoder.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: 6)
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
