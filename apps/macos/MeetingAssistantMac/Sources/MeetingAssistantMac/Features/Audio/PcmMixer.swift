import Foundation

struct PcmMixer {
    static func mix(system: [Int16], microphone: [Int16]) -> [Int16] {
        if system.isEmpty { return microphone }
        if microphone.isEmpty { return system }

        let count = min(system.count, microphone.count)
        var mixed = [Int16]()
        mixed.reserveCapacity(count)

        for index in 0 ..< count {
            let sample = Int32(system[index]) + Int32(microphone[index])
            let averaged = sample / 2
            mixed.append(Int16(clamping: averaged))
        }

        return mixed
    }
}

extension Int16 {
    init(clamping value: Int32) {
        if value > Int32(Int16.max) {
            self = Int16.max
        } else if value < Int32(Int16.min) {
            self = Int16.min
        } else {
            self = Int16(value)
        }
    }
}
