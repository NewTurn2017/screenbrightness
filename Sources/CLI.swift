import Foundation

/// Parse a brightness percentage argument. Returns 0...100 on success, else nil.
func parsePercent(_ s: String) -> Int? {
    guard let n = Int(s), (0...100).contains(n) else { return nil }
    return n
}

/// A parsed command-line intent.
enum Command: Equatable {
    case toggle
    case set(Int)            // 0...100
    case status
    case help
    case agent
    case work
    case away
    case sleep
    case awakeOn
    case awakeOff
    case awakeStatus
    case usageError(String)
}

/// Parse argv (excluding program name) into a Command.
func parseArgs(_ args: [String]) -> Command {
    guard let first = args.first else { return .toggle }
    if first == "awake" {
        guard args.count == 2 else { return .usageError("usage: br awake on|off|status") }
        switch args[1] {
        case "on":     return .awakeOn
        case "off":    return .awakeOff
        case "status": return .awakeStatus
        default:       return .usageError("unknown awake subcommand: \(args[1])")
        }
    }
    if args.count > 1 { return .usageError("too many arguments") }
    switch first {
    case "on":           return .set(100)
    case "off":          return .set(0)
    case "status":       return .status
    case "work":         return .work
    case "away":         return .away
    case "sleep":        return .sleep
    case "agent":        return .agent
    case "-h", "--help": return .help
    default:
        if let n = parsePercent(first) { return .set(n) }
        return .usageError("unknown command or invalid percentage: \(first)")
    }
}

/// Print a line to stderr.
func errPrint(_ s: String) {
    FileHandle.standardError.write(Data((s + "\n").utf8))
}

func usageText() -> String {
    return """
    br — built-in display brightness + power modes

    brightness:
      br            toggle 0% <-> 100%
      br on/off     100% / 0%
      br <0-100>    set that percent
      br status     print current percent

    power modes:
      br work       keep awake + screen on (100%)
      br away       keep awake + screen off now
      br sleep      sleep the Mac now
      br awake on   keep awake only
      br awake off  stop keeping awake
      br awake status

      br agent      run the global-hotkey agent (usually launched by launchd)
      br -h         show this help
    """
}

/// Resolve the built-in display, run `body`, map any error to exit code 1.
func withDisplay(_ body: (BuiltinDisplay) throws -> Void) -> Int32 {
    do {
        try body(BuiltinDisplay())
        return 0
    } catch {
        errPrint("br: \(error)")
        return 1
    }
}

/// Run CLI mode; returns the process exit code.
func runCLI(_ args: [String]) -> Int32 {
    switch parseArgs(args) {
    case .help:
        print(usageText()); return 0
    case .usageError(let msg):
        errPrint("br: \(msg)"); errPrint(usageText()); return 2
    case .agent:
        return runAgent()
    case .status:
        return withDisplay { d in print(Int((try d.getBrightness() * 100).rounded())) }
    case .set(let n):
        return withDisplay { d in
            let v = Float(n) / 100.0
            try d.setBrightness(v)
            applySleepCoupling(forBrightness: v)
        }
    case .toggle:
        return withDisplay { d in
            let v = try d.toggle()
            applySleepCoupling(forBrightness: v)
        }
    case .work:  return runWork()
    case .away:  return runAway()
    case .sleep: return runSleep()
    case .awakeOn:
        if awakeEnsureOn() { return 0 }
        errPrint("br: keep-awake unavailable — run: make hotkey-install"); return 1
    case .awakeOff:
        awakeOff(); return 0
    case .awakeStatus:
        print("awake: \(awakeIsOn() ? "on" : "off")"); return 0
    }
}
