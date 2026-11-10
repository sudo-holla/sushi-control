import Foundation

@main struct SensorsTests {
    static func encoded(_ value:Float) -> [UInt8] {
        var bits = value.bitPattern
        return withUnsafeBytes(of:&bits) { Array($0) }
    }
    static func main() {
        let keys = SOCSensorKeys.self
        precondition(keys.byteCount == 80)
        precondition(keys.fourCC("Tg00") == 0x5467_3030 && keys.code(keys.fourCC("Tg00")) == "Tg00")
        precondition(keys.code(keys.fourCC("flt ")) == "flt " && keys.sensorType == keys.fourCC("flt "))
        precondition(keys.code(keys.fourCC("#KEY")) == "#KEY")

        precondition(keys.group(for:"Tg04") == .gpu && keys.group(for:"Tg63a") == .gpu)
        precondition(keys.group(for:"Tp10") == .cpu && keys.group(for:"Te0K") == .cpu)
        precondition(keys.group(for:"TD00") == nil && keys.group(for:"TCHP") == nil && keys.group(for:"F000") == nil && keys.group(for:"T") == nil)

        precondition(keys.temperature(encoded(61.5),0) == 61.5)
        precondition(keys.temperature(encoded(0),0) == nil)
        precondition(keys.temperature(encoded(-4),0) == nil)
        precondition(keys.temperature(encoded(150),0) == nil && keys.temperature(encoded(1_000),0) == nil)
        precondition(keys.temperature(encoded(Float.nan),0) == nil && keys.temperature(encoded(Float.infinity),0) == nil)
        precondition(keys.temperature([UInt8](repeating:0,count:3),0) == nil && keys.temperature([UInt8](repeating:0,count:8),4) == nil)
        precondition(keys.temperature(encoded(29.9),0)! > 29 && keys.temperature(encoded(29.9),0)! < 30)

        precondition(keys.hottest([30,88.5,61]) == 88.5)
        precondition(keys.hottest([88.5,88.5]) == 88.5)
        precondition(keys.hottest([]) == nil)
        precondition(keys.hottest([0,-5,150,200,Double.nan]) == nil)
        precondition(keys.hottest([0,72.5,200,Double.nan]) == 72.5)
        precondition(SOCTemperatures().isEmpty && !SOCTemperatures(gpuC:61,cpuC:nil).isEmpty)

        var buffer = [UInt8](repeating:0,count:keys.byteCount)
        keys.write(&buffer,keys.Offset.key,keys.fourCC("Tg00"))
        keys.write(&buffer,keys.Offset.dataSize,4)
        keys.write(&buffer,keys.Offset.data32,12)
        precondition(keys.read(buffer,keys.Offset.key) == keys.fourCC("Tg00"))
        precondition(keys.read(buffer,keys.Offset.dataSize) == 4 && keys.read(buffer,keys.Offset.data32) == 12)
        precondition(buffer[4...27].allSatisfy { $0 == 0 } && buffer[32...43].allSatisfy { $0 == 0 } && buffer[48...].allSatisfy { $0 == 0 })
        precondition(keys.read(buffer,keys.byteCount) == 0)

        precondition(SystemSnapshot().gpuTempC == nil && SystemSnapshot().cpuTempC == nil)

        let base = Date(timeIntervalSince1970:1_759_996_800)
        var history = TemperatureHistory()
        precondition(history.samples.isEmpty && history.currentGpuC == nil && !history.hasSamples)
        history.record(time:base,gpuC:nil,cpuC:nil)
        precondition(history.samples.isEmpty)
        history.record(time:base,gpuC:57.5,cpuC:52)
        precondition(history.samples.count == 1 && history.samples[0].startsNewSegment)
        history.record(time:base.addingTimeInterval(-1),gpuC:99,cpuC:99)
        precondition(history.samples.count == 1)
        history.record(time:base.addingTimeInterval(3),gpuC:61,cpuC:54)
        precondition(history.samples.count == 2 && !history.samples[1].startsNewSegment)
        history.record(time:base.addingTimeInterval(3+TemperatureHistory.maximumInterval*2),gpuC:66,cpuC:58)
        precondition(history.samples.last?.startsNewSegment == true)
        // Gaps alone do not create samples, so a sensor outage never draws a drop to zero.
        history.record(time:base.addingTimeInterval(3+TemperatureHistory.maximumInterval*2+2),gpuC:nil,cpuC:nil)
        precondition(history.samples.count == 3 && history.currentGpuC == 66 && history.currentCpuC == 58)
        let points = TimelineValue.points(history.samples,value:{$0.gpuC},maximumGap:TemperatureHistory.maximumInterval)
        precondition(points.count == 3 && points.map(\.segment) == [1,1,2])
        history.record(time:base.addingTimeInterval(TemperatureHistory.retention+60),gpuC:40,cpuC:38)
        // Retention keeps everything inside the window (base+63 is within 180 s of base+240),
        // and the 177 s gap opens a fresh segment.
        precondition(history.samples.count == 2 && history.samples.last?.startsNewSegment == true && history.currentGpuC == 40)
        var flooded = TemperatureHistory()
        for second in 0..<400 { flooded.record(time:base.addingTimeInterval(Double(second)),gpuC:50,cpuC:50) }
        precondition(flooded.samples.count <= 120 && flooded.samples.last?.time == base.addingTimeInterval(399))
        flooded.reset()
        precondition(!flooded.hasSamples && flooded.currentCpuC == nil)

        // Live hardware probe: bounded, and tolerant of machines that expose no readable sensors.
        let reader = SOCTemperatureReader()
        reader.beginDiscovery()
        var readings = SOCTemperatures()
        for _ in 0..<60 {
            readings = reader.sample()
            if !readings.isEmpty { break }
            Thread.sleep(forTimeInterval:0.1)
        }
        // The monitor is what the app samples: discovery starts off the main thread, readings land on the snapshot.
        var monitor = SystemMonitor()
        monitor.beginTemperatureDiscovery()
        var snapshot = monitor.sample()
        for _ in 0..<60 {
            snapshot = monitor.sample()
            if snapshot.gpuTempC != nil || snapshot.cpuTempC != nil { break }
            Thread.sleep(forTimeInterval:0.1)
        }
        if let gpu = snapshot.gpuTempC { precondition(SOCSensorKeys.isValid(gpu)) }
        precondition(monitor.sample().physicalBytes == snapshot.physicalBytes)  // sub-500 ms repeats reuse the cached snapshot
        if let gpu = readings.gpuC { precondition(SOCSensorKeys.isValid(gpu)) }
        if let cpu = readings.cpuC { precondition(SOCSensorKeys.isValid(cpu)) }
        func describe(_ value:Double?) -> String { value.map { String(format:"%.1f °C",$0) } ?? "unavailable" }
        print("Sensors passed: key encoding, sensor classification, flt decoding and band filtering, hottest-sensor reduction, temperature history segmentation/retention, live SMC probe (GPU \(describe(readings.gpuC)), CPU \(describe(readings.cpuC)))")
    }
}
