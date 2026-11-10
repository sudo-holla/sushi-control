import Foundation
import IOKit

// Die-temperature reader for Apple Silicon, using the unprivileged AppleSMC
// user-client. Sensor *reads* need no root (only SMC writes, i.e. fan control,
// are privileged); keys are discovered once and cached, then sampled cheaply.
//
// The request/response layout and selector set are ported from the MIT-licensed
// swift-soc-metrics project (Sources/CIOReport/CIOReport.h, SMCReader.swift),
// which documents them as the long-standing smcFanControl / macmon / mactop
// interface. See NOTICE. Sensor naming: `Tg*` = GPU die, `Tp*`/`Te*` = CPU
// clusters, all typed `flt ` (little-endian float, degrees Celsius).
//
// IOReport is deliberately not used: its `GPU Stats`/`Temperature` channels are
// absent on M5 and read back zero on M4 Max, so SMC is the only path that
// reports a die temperature on every Apple Silicon generation.

enum SOCSensorGroup { case gpu, cpu }

enum SOCSensorKeys {
    // Byte offsets of the documented SMCKeyData_t layout. Pinned explicitly
    // because Swift struct padding does not match C's (nested structs pack
    // tighter), and IOConnectCallStructMethod requires the driver's 80 bytes.
    static let byteCount = 80
    enum Offset {
        static let key = 0, dataSize = 28, dataType = 32, result = 40, status = 41, data8 = 42, data32 = 44, payload = 48
    }
    enum Selector {
        static let handleYPC:UInt32 = 2
        static let readKey:UInt8 = 5, getKeyInfo:UInt8 = 9, getKeyFromIndex:UInt8 = 8
    }
    static let sensorType = fourCC("flt ")
    static let keyCountKey = "#KEY"
    // Readings at or below zero (and absurd highs) are unreadable payloads, not cold silicon;
    // the bounds are exclusive because Range<Double> includes its lower bound.
    static let validLowerBound:Double = 0
    static let validUpperBound:Double = 150
    static func isValid(_ value:Double) -> Bool { value.isFinite && value > validLowerBound && value < validUpperBound }

    static func fourCC(_ code:String) -> UInt32 {
        var value:UInt32 = 0
        for byte in code.utf8 { value = (value<<8)|UInt32(byte) }
        return value
    }
    static func code(_ value:UInt32) -> String {
        let bytes:[UInt8] = [UInt8(truncatingIfNeeded:value>>24),UInt8(truncatingIfNeeded:value>>16),UInt8(truncatingIfNeeded:value>>8),UInt8(truncatingIfNeeded:value)]
        return String(bytes:bytes,encoding:.ascii) ?? ""
    }
    static func group(for key:String) -> SOCSensorGroup? {
        if key.hasPrefix("Tg") { return .gpu }
        if key.hasPrefix("Tp") || key.hasPrefix("Te") { return .cpu }
        return nil
    }
    static func temperature(_ buffer:[UInt8],_ offset:Int) -> Double? {
        guard offset+4 <= buffer.count else { return nil }
        let bits = read(buffer,offset)
        let value = Double(Float(bitPattern:bits))
        return isValid(value) ? value : nil
    }
    static func hottest(_ values:[Double]) -> Double? { values.filter { isValid($0) }.max() }
    static func write(_ buffer:inout [UInt8],_ offset:Int,_ value:UInt32) {
        withUnsafeBytes(of:value.littleEndian) { raw in for i in 0..<4 { buffer[offset+i] = raw[i] } }
    }
    static func read(_ buffer:[UInt8],_ offset:Int) -> UInt32 {
        guard offset+4 <= buffer.count else { return 0 }
        return UInt32(buffer[offset]) | UInt32(buffer[offset+1])<<8 | UInt32(buffer[offset+2])<<16 | UInt32(buffer[offset+3])<<24
    }
}

struct SOCTemperatures {
    var gpuC:Double?
    var cpuC:Double?
    var isEmpty:Bool { gpuC == nil && cpuC == nil }
}

/// Reads the hottest GPU and CPU die sensor. Opening the service or enumerating
/// keys can legitimately fail (no AppleSMC, sandboxed, key set changed); every
/// failure degrades to a nil temperature, never a trap.
final class SOCTemperatureReader {
    private let lock = NSLock()
    private var connection:io_connect_t?
    private var gpuKeys:[(key:UInt32,size:UInt32)] = []
    private var cpuKeys:[(key:UInt32,size:UInt32)] = []
    private var discoveryStarted = false
    private var discoveryFinished = false

    /// Discovers sensor keys off the main thread; `sample()` returns nil readings until it finishes.
    func beginDiscovery() {
        lock.lock(); defer { lock.unlock() }
        guard !discoveryStarted else { return }
        discoveryStarted = true
        DispatchQueue.global(qos:.utility).async { [weak self] in self?.discover() }
    }

    func sample() -> SOCTemperatures {
        lock.lock(); defer { lock.unlock() }
        guard discoveryFinished, let connection else { return SOCTemperatures() }
        return SOCTemperatures(gpuC:SOCSensorKeys.hottest(read(connection,keys:gpuKeys)),cpuC:SOCSensorKeys.hottest(read(connection,keys:cpuKeys)))
    }

    private func call(_ connection:io_connect_t,_ key:UInt32,_ command:UInt8,_ index:UInt32,_ dataSize:UInt32) -> [UInt8]? {
        var input = [UInt8](repeating:0,count:SOCSensorKeys.byteCount)
        SOCSensorKeys.write(&input,SOCSensorKeys.Offset.key,key)
        SOCSensorKeys.write(&input,SOCSensorKeys.Offset.dataSize,dataSize)
        input[SOCSensorKeys.Offset.data8] = command
        SOCSensorKeys.write(&input,SOCSensorKeys.Offset.data32,index)
        var output = [UInt8](repeating:0,count:SOCSensorKeys.byteCount)
        var written = SOCSensorKeys.byteCount
        let status = input.withUnsafeBytes { inputRaw in
            output.withUnsafeMutableBytes { outputRaw in
                IOConnectCallStructMethod(connection,SOCSensorKeys.Selector.handleYPC,inputRaw.baseAddress,SOCSensorKeys.byteCount,outputRaw.baseAddress,&written)
            }
        }
        guard status == KERN_SUCCESS, written == SOCSensorKeys.byteCount, output[SOCSensorKeys.Offset.result] == 0 else { return nil }
        return output
    }

    private func discover() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var connection:io_connect_t = 0
        guard IOServiceOpen(service,mach_task_self_,0,&connection) == KERN_SUCCESS else { return }
        guard let countReply = call(connection,SOCSensorKeys.fourCC(SOCSensorKeys.keyCountKey),SOCSensorKeys.Selector.readKey,0,4) else {
            IOServiceClose(connection); return
        }
        // "#KEY" is a big-endian `sp78` count, unlike the little-endian `flt ` sensor payloads.
        guard countReply.count >= SOCSensorKeys.Offset.payload+4 else { IOServiceClose(connection); return }
        // Byte-swapped because the SMC reports counts as big-endian `sp78`.
        let payload = Array(countReply[SOCSensorKeys.Offset.payload..<SOCSensorKeys.Offset.payload+4])
        let count = UInt32(payload[0])<<24 | UInt32(payload[1])<<16 | UInt32(payload[2])<<8 | UInt32(payload[3])
        guard count > 0, count < 100_000 else { IOServiceClose(connection); return }
        var gpu:[(key:UInt32,size:UInt32)] = []; var cpu:[(key:UInt32,size:UInt32)] = []
        for index in 0..<count {
            lock.lock()
            guard let indexed = call(connection,0,SOCSensorKeys.Selector.getKeyFromIndex,index,0) else { lock.unlock(); break }
            var key = SOCSensorKeys.read(indexed,SOCSensorKeys.Offset.key)
            if key == 0 { key = SOCSensorKeys.read(indexed,SOCSensorKeys.Offset.payload) }
            guard key != 0, let info = call(connection,key,SOCSensorKeys.Selector.getKeyInfo,0,0), SOCSensorKeys.read(info,SOCSensorKeys.Offset.dataType) == SOCSensorKeys.sensorType else { lock.unlock(); continue }
            let size = SOCSensorKeys.read(info,SOCSensorKeys.Offset.dataSize)
            switch SOCSensorKeys.group(for:SOCSensorKeys.code(key)) {
            case .gpu where size >= 4: gpu.append((key,size))
            case .cpu where size >= 4: cpu.append((key,size))
            default: break
            }
            lock.unlock()
        }
        lock.lock()
        gpuKeys = gpu; cpuKeys = cpu; self.connection = connection; discoveryFinished = !gpu.isEmpty || !cpu.isEmpty
        lock.unlock()
    }

    private func read(_ connection:io_connect_t,keys:[(key:UInt32,size:UInt32)]) -> [Double] {
        var values:[Double] = []
        for (key,size) in keys {
            guard let reply = call(connection,key,SOCSensorKeys.Selector.readKey,0,size) else { continue }
            if let value = SOCSensorKeys.temperature(reply,SOCSensorKeys.Offset.payload) { values.append(value) }
        }
        return values
    }

    deinit { if let connection { IOServiceClose(connection) } }
}
