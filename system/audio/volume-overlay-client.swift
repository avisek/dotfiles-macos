import Foundation

// MARK: - Argument Parsing

struct Arguments {
    var name: String?
    var type: String = "output"
    var volume: String = "1.0"
    var muted: String = "false"
    var showHelp: Bool = false
}

func printHelp() {
    let help = """
    Volume Overlay Client - Display volume overlay for audio devices

    Usage: volume-overlay-client [options]

    Options:
      -n, --name <name>      Device name (required)
      -t, --type <type>      Device type: output | input (default: output)
      -v, --volume <value>   Volume level: 0.0-1.0 | unsupported (default: 1.0)
      -m, --muted <value>    Muted state: true | false | unsupported (default: false)
      -h, --help             Display this help

    Examples:
      volume-overlay-client -n "MacBook Pro Speakers" -v 0.75
      volume-overlay-client -n "MacBook Pro Microphone" -t input -m true
      volume-overlay-client -n "HDMI Display" -v unsupported
      volume-overlay-client -n "USB Headset Mic" -t input -m true -v unsupported
      volume-overlay-client -n "Bluetooth Speaker" -v 0.8 -m unsupported
    """
    print(help)
}

func parseArguments() -> Arguments {
    var args = Arguments()
    let arguments = CommandLine.arguments
    var i = 1
    
    while i < arguments.count {
        let arg = arguments[i]
        
        switch arg {
        case "-h", "--help":
            args.showHelp = true
            return args
            
        case "-n", "--name":
            i += 1
            if i < arguments.count {
                args.name = arguments[i]
            }
            
        case "-t", "--type":
            i += 1
            if i < arguments.count {
                args.type = arguments[i]
            }
            
        case "-v", "--volume":
            i += 1
            if i < arguments.count {
                args.volume = arguments[i]
            }
            
        case "-m", "--muted":
            i += 1
            if i < arguments.count {
                args.muted = arguments[i]
            }
            
        default:
            break
        }
        
        i += 1
    }
    
    return args
}

// MARK: - Socket Client

func sendToSocket(message: String, socketPath: String) -> Bool {
    // Create socket
    let sock = socket(AF_UNIX, SOCK_STREAM, 0)
    guard sock >= 0 else {
        fputs("Error: Failed to create socket\n", stderr)
        return false
    }
    
    defer { close(sock) }
    
    // Connect to server
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    
    _ = withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
        socketPath.withCString { cstr in
            strcpy(ptr, cstr)
        }
    }
    
    let connectResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            connect(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    
    guard connectResult == 0 else {
        fputs("Error: Failed to connect to daemon. Is volume-overlay-daemon running?\n", stderr)
        return false
    }
    
    // Send message
    let data = message.data(using: .utf8)!
    let bytesSent = data.withUnsafeBytes { ptr in
        write(sock, ptr.baseAddress, data.count)
    }
    
    return bytesSent > 0
}

// MARK: - Main

let args = parseArguments()

if args.showHelp {
    printHelp()
    exit(0)
}

guard let name = args.name, !name.isEmpty else {
    fputs("Error: Device name is required. Use -n or --name to specify.\n", stderr)
    fputs("Use -h or --help for usage information.\n", stderr)
    exit(1)
}

// Validate type
guard args.type == "output" || args.type == "input" else {
    fputs("Error: Invalid type '\(args.type)'. Must be 'output' or 'input'.\n", stderr)
    exit(1)
}

// Validate volume
if args.volume != "unsupported" {
    if let value = Float(args.volume) {
        if value < 0 || value > 1 {
            fputs("Error: Volume must be between 0.0 and 1.0, or 'unsupported'.\n", stderr)
            exit(1)
        }
    } else {
        fputs("Error: Invalid volume '\(args.volume)'. Must be a number between 0.0-1.0 or 'unsupported'.\n", stderr)
        exit(1)
    }
}

// Validate muted
guard args.muted == "true" || args.muted == "false" || args.muted == "unsupported" else {
    fputs("Error: Invalid muted state '\(args.muted)'. Must be 'true', 'false', or 'unsupported'.\n", stderr)
    exit(1)
}

// Build message
let message = """
name:\(name)
type:\(args.type)
volume:\(args.volume)
muted:\(args.muted)
"""

// Send to daemon
let socketPath = "/tmp/volume-overlay.sock"

if sendToSocket(message: message, socketPath: socketPath) {
    exit(0)
} else {
    exit(1)
}

