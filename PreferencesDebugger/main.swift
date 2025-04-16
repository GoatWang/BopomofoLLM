import Cocoa

NSLog("main.swift: Starting.")

// This will use the NSApplicationDelegateClassName from Info.plist
NSLog("main.swift: Calling NSApplicationMain...")
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

// This line should never be reached as NSApplicationMain doesn't return until app termination
NSLog("main.swift: Application terminated (unexpected).")
