import Foundation

// MARK: - Pure DDC/CI helpers (testable, no IOKit side effects)

/// Build the DDC/CI "Set VCP Feature" I²C payload for a monitor control.
/// Layout: [length|opcode 0x84, command 0x03, vcp, valueHi, valueLo, checksum].
/// The checksum XORs the destination address byte 0x6e (0x37<<1) as DDC requires.
func ddcSetVCPPayload(vcp: UInt8, value: UInt16) -> [UInt8] {
    let hi = UInt8(value >> 8)
    let lo = UInt8(value & 0xFF)
    let d0: UInt8 = 0x84
    let d1: UInt8 = 0x03
    let checksum = 0x6e ^ 0x51 ^ d0 ^ d1 ^ vcp ^ hi ^ lo
    return [d0, d1, vcp, hi, lo, checksum]
}

/// Clamp a brightness percentage into the valid 0...100 range.
func clampBrightnessPercent(_ percent: Int) -> Int {
    return min(100, max(0, percent))
}
