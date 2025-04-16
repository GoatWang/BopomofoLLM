// BopomofoLLM/McBopomofo/PreferencesDebugger/AppDelegate.swift

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    // Keep a strong reference to the preferences window controller
    var preferencesWindowController: PreferencesWindowController?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Instantiate the PreferencesWindowController.
        // It should automatically load its interface from preferences.xib
        preferencesWindowController = PreferencesWindowController()

        // Show the preferences window.
        preferencesWindowController?.showWindow(nil)

        // Optional: Bring the debugger app to the front
        NSApp.activate(ignoringOtherApps: true)

        // Note: The default window created by the template is not used here.
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    // Optional: Allow the debugger app to terminate when the preferences window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

}
