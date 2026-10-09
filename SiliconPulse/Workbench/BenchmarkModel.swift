import Foundation
import Observation
import Metal
import Darwin

private final class BenchmarkCancellation: @unchecked Sendable {
    private let lock = NSLock(); private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
@MainActor @Observable final class BenchmarkModel {
    var kind = "CPU"
    var isRunning = false
    var progress = ""
    var results: [BenchmarkResult] = []
    var message: String?
    @ObservationIgnored private var cancellation = BenchmarkCancellation()
    @ObservationIgnored private var task: Task<Void, Never>?
    private var historyURL: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SiliconPulse/benchmarks.json") }
    init() { if let data = try? Data(contentsOf: historyURL), let values = try? JSONDecoder().decode([BenchmarkResult].self, from: data) { results = values } }
    func cancel() { cancellation.cancel(); task?.cancel(); progress = "Stopping…" }
    func start() {
        guard !isRunning else { return }
        isRunning = true; progress = "Measuring…"; message = nil
        let kind = kind, token = BenchmarkCancellation(); cancellation = token
        task = Task {
            do {
                let measured = try await Task.detached(priority: .userInitiated) { try await Self.measure(kind, token: token) }.value
                if !token.cancelled {
                    results.insert(measured, at: 0)
                    if results.count > 100 { results.removeLast(results.count - 100) }
                    persist()
                }
            } catch { if !token.cancelled { message = error.localizedDescription } }
            isRunning = false; progress = ""
        }
    }
    func clear() { results = []; persist() }
    private func persist() { try? FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true); if let data = try? JSONEncoder().encode(results) { try? data.write(to: historyURL, options: .atomic) } }
    nonisolated private static func kernel(token: BenchmarkCancellation, seed: UInt64) -> (Double, UInt64) {
        let begin = ProcessInfo.processInfo.systemUptime; var value = seed, operations: Double = 0
        while ProcessInfo.processInfo.systemUptime - begin < 2, !token.cancelled {
            for _ in 0..<500_000 { value = value &* 1_664_525 &+ 1_013_904_223; value ^= value >> 13 }
            operations += 2_000_000
        }
        return (operations / max(0.000001, ProcessInfo.processInfo.systemUptime - begin) / 1_000_000, value)
    }
    nonisolated private static func cpu(token: BenchmarkCancellation) async -> BenchmarkResult {
        let single = kernel(token: token, seed: 12345)
        let multicore = await withTaskGroup(of: (Double, UInt64).self) { group in
            for core in 0..<ProcessInfo.processInfo.activeProcessorCount { group.addTask { kernel(token: token, seed: UInt64(core + 1)) } }
            var rate = 0.0
            var checksum: UInt64 = 0
            for await value in group { rate += value.0; checksum ^= value.1 }
            return (rate, checksum)
        }
        return BenchmarkResult(kind: "CPU", primary: single.0, secondary: multicore.0, unit: "Mops/s", notes: "Single / multicore integer arithmetic (multiply, add, XOR, shift). Checksum: \(single.1 ^ multicore.1). Not comparable to Geekbench.")
    }
    nonisolated private static func gpu(token: BenchmarkCancellation) throws -> BenchmarkResult {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw InspectorFailure.message("Metal is unavailable.") }
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void pulse(device float *output [[buffer(0)]], uint i [[thread_position_in_grid]]) {
            float x = float(i % 1024) * 0.001f;
            for (uint j = 0; j < 512; ++j) { x = fma(x, 0.99991f, 0.00001f); }
            output[i] = x;
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: "pulse") else { throw InspectorFailure.message("Metal kernel is unavailable.") }
        let pipeline = try device.makeComputePipelineState(function: function)
        let count = 1_048_576
        guard let buffer = device.makeBuffer(length: count * MemoryLayout<Float>.stride, options: .storageModeShared) else { throw InspectorFailure.message("Could not allocate Metal output.") }
        let begin = ProcessInfo.processInfo.systemUptime; var batches = 0
        while ProcessInfo.processInfo.systemUptime - begin < 2 && !token.cancelled {
            guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else { throw InspectorFailure.message("Could not encode GPU work.") }
            encoder.setComputePipelineState(pipeline); encoder.setBuffer(buffer, offset: 0, index: 0)
            encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: min(256, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
            encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
            if let error = command.error { throw error }; batches += 1
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - begin
        let checksum = buffer.contents().assumingMemoryBound(to: Float.self)[count - 1]
        return BenchmarkResult(kind: "GPU", primary: Double(batches * count * 512 * 2) / max(0.000001, elapsed) / 1_000_000_000, secondary: nil, unit: "GFLOP/s", notes: "512 FMA operations per thread; 2 FLOPs per FMA. Output checksum: \(checksum). Local Metal workload.")
    }
    nonisolated private static func disk(token: BenchmarkCancellation) throws -> BenchmarkResult {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SiliconPulse-benchmark-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forUpdating: url); defer { try? handle.close() }
        _ = fcntl(handle.fileDescriptor, F_NOCACHE, 1)
        var bytes = [UInt8](repeating: 0, count: 1_048_576)
        var seed: UInt64 = 927
        for index in bytes.indices { seed = seed &* 6_364_136_223_846_793_005 &+ 1; bytes[index] = UInt8(truncatingIfNeeded: seed >> 32) }
        let data = Data(bytes); let total = 64 * data.count
        var begin = ProcessInfo.processInfo.systemUptime
        for _ in 0..<64 { if token.cancelled { throw CancellationError() }; try handle.write(contentsOf: data) }
        try handle.synchronize()
        let write = Double(total) / max(0.000001, ProcessInfo.processInfo.systemUptime - begin) / 1_000_000
        try handle.seek(toOffset: 0); begin = ProcessInfo.processInfo.systemUptime; var read = 0
        while read < total { if token.cancelled { throw CancellationError() }; guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else { break }; read += data.count }
        guard read == total else { throw InspectorFailure.message("Disk read was incomplete.") }
        let rate = Double(read) / max(0.000001, ProcessInfo.processInfo.systemUptime - begin) / 1_000_000
        return BenchmarkResult(kind: "Disk", primary: rate, secondary: write, unit: "MB/s", notes: "64 MB temporary file. Read / write; F_NOCACHE requested, write includes synchronization. APFS and storage caching still affect results.")
    }
    nonisolated private static func internet(token: BenchmarkCancellation) throws -> BenchmarkResult {
        let result = try InspectorCommands.checked("/usr/bin/networkQuality", ["-c", "-s", "-M", "30"], timeout: 45, shouldCancel: { token.cancelled })
        let object = try JSONSerialization.jsonObject(with: result.data) as? [String: Any] ?? [:]
        func number(_ keys: [String]) -> Double? { for key in keys { if let value = object[key] as? NSNumber { return value.doubleValue } }; return nil }
        guard let download = number(["dl_throughput", "download_throughput"]), let upload = number(["ul_throughput", "upload_throughput"]) else { throw InspectorFailure.message("networkQuality did not return throughput measurements.") }
        return BenchmarkResult(kind: "Internet", primary: download / 1_000_000, secondary: upload / 1_000_000, unit: "Mbps", notes: "Download / upload measured by Apple's networkQuality service. Internet data transfer was requested by the user.")
    }
    nonisolated private static func measure(_ kind: String, token: BenchmarkCancellation) async throws -> BenchmarkResult {
        switch kind {
        case "CPU": return await cpu(token: token)
        case "GPU": return try gpu(token: token)
        case "Disk": return try disk(token: token)
        case "Internet": return try internet(token: token)
        default:
            let c = await cpu(token: token); if token.cancelled { throw CancellationError() }
            let g = try gpu(token: token); if token.cancelled { throw CancellationError() }
            let d = try disk(token: token)
            let score = (c.secondary ?? c.primary) + g.primary + d.primary
            return BenchmarkResult(kind: "SiliconPulse Score", primary: score, secondary: nil, unit: "local index", notes: "Local index = multicore Mops/s + GPU GFLOP/s + disk read MB/s. CPU: \(c.primary)/\(c.secondary ?? 0), GPU: \(g.primary), disk: \(d.primary). This is a SiliconPulse-specific index, not a standardized score.")
        }
    }
}
