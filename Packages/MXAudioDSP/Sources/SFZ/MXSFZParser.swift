import Foundation

/// Parser for the SFZ instrument format.
///
/// Handles the opcode set the engine actually acts on, with correct
/// `<global>` -> `<master>` -> `<group>` -> `<region>` inheritance. Unknown
/// opcodes are collected rather than treated as errors, because real-world SFZ
/// files routinely carry opcodes aimed at other engines.
public struct MXSFZParser {
    public struct Result: Sendable {
        public var regions: [MXSFZRegion]
        public var defaultPath: String
        public var unknownOpcodes: Set<String>
    }

    public init() {}

    public func parse(contentsOf url: URL) throws -> Result {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MXAudioError.resourceNotFound(path: url.path)
        }
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MXAudioError.sfzParseFailed(reason: "unreadable: \(error.localizedDescription)",
                                              line: 0)
        }
        return try parse(text: text)
    }

    public func parse(text: String) throws -> Result {
        var globalOpcodes: [String: String] = [:]
        var masterOpcodes: [String: String] = [:]
        var groupOpcodes: [String: String] = [:]
        var regions: [MXSFZRegion] = []
        var unknown: Set<String> = []
        var defaultPath = ""

        var currentHeader = ""
        var pendingRegion: [String: String] = [:]

        func flushRegion(atLine line: Int) throws {
            guard currentHeader == "region" else { return }
            var merged = globalOpcodes
            merged.merge(masterOpcodes) { _, new in new }
            merged.merge(groupOpcodes) { _, new in new }
            merged.merge(pendingRegion) { _, new in new }

            guard let sample = merged["sample"] else {
                throw MXAudioError.sfzParseFailed(reason: "<region> has no sample opcode",
                                                  line: line)
            }
            var region = MXSFZRegion(samplePath: sample)
            try apply(merged, to: &region, unknown: &unknown, line: line)
            regions.append(region)
            pendingRegion = [:]
        }

        let lines = text.components(separatedBy: .newlines)
        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1

            // Strip comments. SFZ uses // to end of line.
            var line = rawLine
            if let commentRange = line.range(of: "//") {
                line = String(line[line.startIndex..<commentRange.lowerBound])
            }
            line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // A line can hold a header followed by opcodes, and multiple
            // headers can share a line, so scan token by token.
            for token in tokenize(line) {
                switch token {
                case .header(let name):
                    try flushRegion(atLine: lineNumber)
                    currentHeader = name
                    switch name {
                    case "global":
                        globalOpcodes = [:]
                        masterOpcodes = [:]
                        groupOpcodes = [:]
                    case "master":
                        masterOpcodes = [:]
                        groupOpcodes = [:]
                    case "group":
                        groupOpcodes = [:]
                    case "region":
                        pendingRegion = [:]
                    case "control", "curve", "effect":
                        break
                    default:
                        unknown.insert("<\(name)>")
                    }

                case .opcode(let key, let value):
                    if key == "default_path" {
                        defaultPath = value.replacingOccurrences(of: "\\", with: "/")
                        continue
                    }
                    switch currentHeader {
                    case "global": globalOpcodes[key] = value
                    case "master": masterOpcodes[key] = value
                    case "group": groupOpcodes[key] = value
                    case "region": pendingRegion[key] = value
                    case "control": if key == "default_path" { defaultPath = value }
                    default: break
                    }
                }
            }
        }
        try flushRegion(atLine: lines.count)

        guard !regions.isEmpty else {
            throw MXAudioError.sfzParseFailed(reason: "no <region> definitions found", line: 0)
        }

        return Result(regions: regions, defaultPath: defaultPath, unknownOpcodes: unknown)
    }

    // MARK: - Tokenizing

    private enum Token {
        case header(String)
        case opcode(key: String, value: String)
    }

    /// SFZ values may contain spaces (notably file paths), so a value runs until
    /// the next `key=` or `<header>` rather than the next whitespace.
    private func tokenize(_ line: String) -> [Token] {
        var tokens: [Token] = []
        let scalars = Array(line)
        var i = 0

        while i < scalars.count {
            if scalars[i] == "<" {
                var j = i + 1
                var name = ""
                while j < scalars.count, scalars[j] != ">" {
                    name.append(scalars[j])
                    j += 1
                }
                tokens.append(.header(name.lowercased()))
                i = j + 1
                continue
            }

            if scalars[i].isWhitespace {
                i += 1
                continue
            }

            var key = ""
            var j = i
            while j < scalars.count, scalars[j] != "=", !scalars[j].isWhitespace, scalars[j] != "<" {
                key.append(scalars[j])
                j += 1
            }

            guard j < scalars.count, scalars[j] == "=" else {
                i = j + 1
                continue
            }
            j += 1

            var value = ""
            while j < scalars.count {
                if scalars[j] == "<" { break }
                // Look ahead: whitespace followed by `word=` ends this value.
                if scalars[j].isWhitespace, startsNewOpcode(scalars, from: j) { break }
                value.append(scalars[j])
                j += 1
            }

            tokens.append(.opcode(key: key.lowercased(),
                                  value: value.trimmingCharacters(in: .whitespaces)))
            i = j
        }
        return tokens
    }

    private func startsNewOpcode(_ chars: [Character], from index: Int) -> Bool {
        var k = index
        while k < chars.count, chars[k].isWhitespace { k += 1 }
        guard k < chars.count else { return false }
        if chars[k] == "<" { return true }
        var sawChar = false
        while k < chars.count, !chars[k].isWhitespace {
            if chars[k] == "=" { return sawChar }
            sawChar = true
            k += 1
        }
        return false
    }

    // MARK: - Opcode application

    private func apply(_ opcodes: [String: String],
                       to region: inout MXSFZRegion,
                       unknown: inout Set<String>,
                       line: Int) throws {
        for (key, value) in opcodes {
            switch key {
            case "sample":
                region.samplePath = value.replacingOccurrences(of: "\\", with: "/")

            case "lokey": region.loKey = try noteValue(value, line: line)
            case "hikey": region.hiKey = try noteValue(value, line: line)
            case "key":
                let n = try noteValue(value, line: line)
                region.loKey = n
                region.hiKey = n
                region.pitchKeyCenter = n
            case "pitch_keycenter": region.pitchKeyCenter = try noteValue(value, line: line)

            case "lovel": region.loVel = try byteValue(value, line: line)
            case "hivel": region.hiVel = try byteValue(value, line: line)

            case "seq_length": region.seqLength = max(1, Int(value) ?? 1)
            case "seq_position": region.seqPosition = max(1, Int(value) ?? 1)

            case "group": region.group = Int32(value) ?? -1
            case "off_by", "offby": region.offBy = Int32(value) ?? -1

            case "loop_mode", "loopmode":
                region.loopMode = MXSFZRegion.LoopMode(rawValue: value) ?? .noLoop
            case "loop_start", "loopstart": region.loopStart = Int(value) ?? 0
            case "loop_end", "loopend": region.loopEnd = Int(value) ?? 0
            case "offset": region.offset = Int(value) ?? 0

            case "volume": region.volumeDB = Float(value) ?? 0
            case "pan": region.pan = (Float(value) ?? 0) / 100
            case "tune", "pitch": region.tuneCents = Float(value) ?? 0
            case "transpose":
                region.tuneCents += (Float(value) ?? 0) * 100

            case "ampeg_attack": region.ampegAttack = max(0.0001, Float(value) ?? 0.001)
            case "ampeg_decay": region.ampegDecay = Float(value) ?? 0
            case "ampeg_sustain": region.ampegSustain = (Float(value) ?? 100) / 100
            case "ampeg_release": region.ampegRelease = max(0.0001, Float(value) ?? 0.05)

            default:
                unknown.insert(key)
            }
        }

        if region.hiKey < region.loKey {
            throw MXAudioError.sfzParseFailed(
                reason: "hikey (\(region.hiKey)) < lokey (\(region.loKey))", line: line)
        }
        if region.hiVel < region.loVel {
            throw MXAudioError.sfzParseFailed(
                reason: "hivel (\(region.hiVel)) < lovel (\(region.loVel))", line: line)
        }
    }

    private func byteValue(_ raw: String, line: Int) throws -> UInt8 {
        guard let v = Int(raw) else {
            throw MXAudioError.sfzParseFailed(reason: "expected integer, got '\(raw)'", line: line)
        }
        return UInt8(min(max(v, 0), 127))
    }

    /// Accepts either a MIDI number or a note name such as `c4`, `f#3`, `Bb-1`.
    private func noteValue(_ raw: String, line: Int) throws -> UInt8 {
        if let v = Int(raw) {
            return UInt8(min(max(v, 0), 127))
        }
        guard let note = MXSFZParser.midiNote(fromName: raw) else {
            throw MXAudioError.sfzParseFailed(reason: "unparseable note '\(raw)'", line: line)
        }
        return note
    }

    /// `c4` == 60, matching the convention sfizz and most SFZ tooling use.
    public static func midiNote(fromName name: String) -> UInt8? {
        let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard let first = lower.first else { return nil }

        let pitchClasses: [Character: Int] = ["c": 0, "d": 2, "e": 4, "f": 5,
                                              "g": 7, "a": 9, "b": 11]
        guard var semitone = pitchClasses[first] else { return nil }

        var index = lower.index(after: lower.startIndex)
        while index < lower.endIndex {
            let ch = lower[index]
            if ch == "#" {
                semitone += 1
                index = lower.index(after: index)
            } else if ch == "b" {
                semitone -= 1
                index = lower.index(after: index)
            } else {
                break
            }
        }

        guard let octave = Int(lower[index...]) else { return nil }
        let value = (octave + 1) * 12 + semitone
        guard value >= 0, value <= 127 else { return nil }
        return UInt8(value)
    }
}
