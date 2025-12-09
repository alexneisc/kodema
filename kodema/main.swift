import Foundation

// Top-level await requires Swift 5.5+ and is supported in executable targets
await runMain()

func runMain() async {
    setupSignalHandlers()

    let args = CommandLine.arguments

    // Get command (first argument after program name)
    let command = args.count > 1 ? args[1] : "help"

    switch command {
    case "help", "-h", "--help":
        printHelp()
        return

    case "version", "-v", "--version":
        printVersion()
        return

    case "list":
        listICloudFolders()
        return

    case "test-config":
        do {
            let configURL = readConfigURL(from: args)
            let config = try loadConfig(from: configURL)
            try await testConfig(config: config, configURL: configURL)
        } catch {
            print("\n\(errorColor)Fatal error:\(resetColor) \(error)")
            exit(1)
        }
        return

    case "backup":
        do {
            let configURL = readConfigURL(from: args)
            let config = try loadConfig(from: configURL)
            let dryRun = hasDryRunFlag(from: args)
            try await runIncrementalBackup(config: config, dryRun: dryRun)
        } catch {
            print("\u{001B}[?25h", terminator: "")
            fflush(stdout)
            print("\n\(errorColor)Fatal error:\(resetColor) \(error)")
            exit(1)
        }
        return

    case "mirror":
        do {
            let configURL = readConfigURL(from: args)
            let config = try loadConfig(from: configURL)
            try await runMirror(config: config)
        } catch {
            print("\u{001B}[?25h", terminator: "")
            fflush(stdout)
            print("\n\(errorColor)Fatal error:\(resetColor) \(error)")
            exit(1)
        }
        return

    case "cleanup":
        do {
            let configURL = readConfigURL(from: args)
            let config = try loadConfig(from: configURL)
            let dryRun = hasDryRunFlag(from: args)
            try await runCleanup(config: config, dryRun: dryRun)
        } catch {
            print("\u{001B}[?25h", terminator: "")
            fflush(stdout)
            print("\n\(errorColor)Fatal error:\(resetColor) \(error)")
            exit(1)
        }
        return

    case "restore":
        do {
            let configURL = readConfigURL(from: args)
            let config = try loadConfig(from: configURL)
            let options = try parseRestoreOptions(from: args)
            let dryRun = hasDryRunFlag(from: args)

            if options.listSnapshots {
                try await listSnapshotsCommand(config: config, options: options)
                return
            }

            try await runRestore(config: config, options: options, dryRun: dryRun)
        } catch {
            print("\u{001B}[?25h", terminator: "")
            fflush(stdout)
            print("\n\(errorColor)Fatal error:\(resetColor) \(error)")
            exit(1)
        }
        return

    default:
        print("\(errorColor)❌ Unknown command: '\(command)'\(resetColor)")
        print("Run 'kodema help' for usage information.\n")
        exit(1)
    }
}
