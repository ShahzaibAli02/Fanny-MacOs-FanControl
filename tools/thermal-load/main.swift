import Foundation
import Metal

struct LoadStep {
    let label: String
    let duration: TimeInterval
    let cpuPercent: Int
    let gpuPercent: Int
}

final class LoadController {
    private let lock = NSLock()
    private var cpuPercent = 0
    private var gpuPercent = 0
    private var isRunning = true

    func set(cpu: Int, gpu: Int) {
        lock.lock()
        cpuPercent = cpu
        gpuPercent = gpu
        lock.unlock()
    }

    func snapshot() -> (cpu: Int, gpu: Int, isRunning: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (cpuPercent, gpuPercent, isRunning)
    }

    func stop() {
        lock.lock()
        isRunning = false
        cpuPercent = 0
        gpuPercent = 0
        lock.unlock()
    }
}

final class CPUBurner {
    private let controller: LoadController
    private let workerCount: Int

    init(controller: LoadController) {
        self.controller = controller
        self.workerCount = ProcessInfo.processInfo.activeProcessorCount
    }

    func start() {
        for worker in 0..<workerCount {
            Thread.detachNewThread { [controller] in
                var value = UInt64(worker + 1)
                let period: TimeInterval = 0.1

                while controller.snapshot().isRunning {
                    let percent = controller.snapshot().cpu
                    guard percent > 0 else {
                        Thread.sleep(forTimeInterval: period)
                        continue
                    }

                    let started = Date()
                    let busyUntil = started.addingTimeInterval(period * Double(percent) / 100.0)
                    while Date() < busyUntil {
                        // Keep a data dependency so the compiler cannot remove the work.
                        value = value &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    }

                    let remaining = period - Date().timeIntervalSince(started)
                    if remaining > 0 {
                        Thread.sleep(forTimeInterval: remaining)
                    }
                }
            }
        }
    }
}

final class GPUBurner {
    private let controller: LoadController
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let outputBuffer: MTLBuffer
    private let iterationBuffer: MTLBuffer

    init?(controller: LoadController) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }

        let source = """
        #include <metal_stdlib>
        using namespace metal;

        kernel void thermalLoad(device uint *output [[buffer(0)]],
                                constant uint &iterations [[buffer(1)]],
                                uint id [[thread_position_in_grid]]) {
            float value = float(id) * 0.0001f + 0.1234f;
            for (uint i = 0; i < iterations; ++i) {
                value = sin(value * 1.6180339f + float(i) * 0.00001f);
            }
            output[id] = as_type<uint>(value);
        }
        """

        do {
            let library = try device.makeLibrary(source: source, options: nil)
            guard let function = library.makeFunction(name: "thermalLoad") else {
                return nil
            }
            pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            print("Metal workload unavailable: \(error.localizedDescription)")
            return nil
        }

        guard let outputBuffer = device.makeBuffer(
            length: 4_096 * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ), let iterationBuffer = device.makeBuffer(
            length: MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        self.controller = controller
        self.device = device
        self.commandQueue = commandQueue
        self.outputBuffer = outputBuffer
        self.iterationBuffer = iterationBuffer
    }

    func start() {
        Thread.detachNewThread { [self] in
            while controller.snapshot().isRunning {
                let gpuPercent = controller.snapshot().gpu
                guard gpuPercent > 0 else {
                    Thread.sleep(forTimeInterval: 0.1)
                    continue
                }

                let started = Date()
                runOneWorkload()
                let elapsed = Date().timeIntervalSince(started)
                let targetCycle = elapsed / (Double(gpuPercent) / 100.0)
                let remaining = targetCycle - elapsed
                if remaining > 0 {
                    Thread.sleep(forTimeInterval: remaining)
                }
            }
        }
    }

    private func runOneWorkload() {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        iterationBuffer.contents().assumingMemoryBound(to: UInt32.self).pointee = 20_000
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(outputBuffer, offset: 0, index: 0)
        encoder.setBuffer(iterationBuffer, offset: 0, index: 1)

        let threadsPerGroup = min(256, pipeline.maxTotalThreadsPerThreadgroup)
        encoder.dispatchThreads(
            MTLSize(width: 4_096, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadsPerGroup, height: 1, depth: 1)
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}

func defaultPlan() -> [LoadStep] {
    [
        LoadStep(label: "Warm-up", duration: 30, cpuPercent: 15, gpuPercent: 0),
        LoadStep(label: "CPU", duration: 60, cpuPercent: 60, gpuPercent: 0),
        LoadStep(label: "CPU + GPU", duration: 60, cpuPercent: 65, gpuPercent: 45),
        LoadStep(label: "Cooling", duration: 90, cpuPercent: 15, gpuPercent: 0)
    ]
}

func parsePlan(_ text: String) -> [LoadStep]? {
    let parts = text.split(separator: ",")
    var steps: [LoadStep] = []

    for (index, part) in parts.enumerated() {
        let values = part.split(separator: ":")
        guard values.count == 3,
              let seconds = TimeInterval(values[0]),
              let cpu = Int(values[1]),
              let gpu = Int(values[2]),
              seconds > 0,
              (0...80).contains(cpu),
              (0...70).contains(gpu) else {
            return nil
        }
        steps.append(LoadStep(label: "Step \(index + 1)", duration: seconds, cpuPercent: cpu, gpuPercent: gpu))
    }
    return steps.isEmpty ? nil : steps
}

func printUsage() {
    print("""
    Usage: thermal-load [--plan seconds:cpu:gpu,...]

    The default plan lasts four minutes: warm-up, CPU, CPU+GPU, and cooling.
    CPU is limited to 80% and GPU to 70% for a controlled test.

    Example:
      ./thermal-load --plan "30:15:0,60:60:0,60:65:45,90:15:0"

    Press Control-C at any time to stop immediately.
    """)
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--help") || arguments.contains("-h") {
    printUsage()
    exit(EXIT_SUCCESS)
}

let plan: [LoadStep]
if let planIndex = arguments.firstIndex(of: "--plan") {
    guard planIndex + 1 < arguments.count,
          let parsedPlan = parsePlan(arguments[planIndex + 1]) else {
        print("Invalid plan. Each step must be seconds:cpu:gpu, with CPU ≤ 80 and GPU ≤ 70.")
        printUsage()
        exit(EXIT_FAILURE)
    }
    plan = parsedPlan
} else {
    plan = defaultPlan()
}

let controller = LoadController()
let cpuBurner = CPUBurner(controller: controller)
let gpuBurner = GPUBurner(controller: controller)
cpuBurner.start()
gpuBurner?.start()

print("Thermal load test started. Press Control-C to stop immediately.")
if gpuBurner == nil {
    print("Metal is not available; the test will run CPU-only.")
}

for step in plan {
    controller.set(cpu: step.cpuPercent, gpu: step.gpuPercent)
    print("\(step.label): \(Int(step.duration)) s — CPU \(step.cpuPercent)% / GPU \(step.gpuPercent)%")
    Thread.sleep(forTimeInterval: step.duration)
}

controller.stop()
print("Thermal load test completed. Fan Control can now return to Auto.")
