// Copyright (c) 2022 and onwards The McBopomofo Authors.
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.

import Cocoa
import Carbon

fileprivate extension NSToolbarItem.Identifier {
    static let basic = NSToolbarItem.Identifier(rawValue: "basic")
    static let userPhrases = NSToolbarItem.Identifier(rawValue: "user_phrases")
    static let advanced = NSToolbarItem.Identifier(rawValue: "advanced")
}

fileprivate let kWindowTitleHeight: CGFloat = 78


// Please note that the class should be exposed as "PreferencesWindowController"
// in Objective-C in order to let IMK to see the same class name as
// the "InputMethodServerPreferencesWindowControllerClass" in Info.plist.
@objc(PreferencesWindowController) class PreferencesWindowController: NSWindowController {
    @IBOutlet weak var fontSizePopUpButton: NSPopUpButton!
    @IBOutlet weak var basisKeyboardLayoutButton: NSPopUpButton!
    @IBOutlet weak var selectionKeyComboBox: NSComboBox!

    @IBOutlet weak var customUserPhraseLocationEnabledButton: NSPopUpButton!
    @IBOutlet weak var userPhrasesTextField: NSTextField!
    @IBOutlet weak var chooseUserPhrasesFolderButton: NSButton!
    @IBOutlet weak var openUserPhrasesFolderButton: NSButton!

    @IBOutlet weak var basicSettingsView: NSView!
    @IBOutlet weak var userPhrasesSettingsView: NSView!
    @IBOutlet weak var advancedSettingsView: NSView!

    @IBOutlet weak var addPhraseHookPathField: NSTextField!
    
    // Autocomplete UI controls
    private var autocompleteEnabledButton: NSButton!
    private var autocompleteModelTextField: NSTextField!
    private var autocompleteModelLabel: NSTextField!

    override func awakeFromNib() {
        let toolbar = NSToolbar(identifier: "preference toolbar")
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.sizeMode = .default
        toolbar.delegate = self
        toolbar.selectedItemIdentifier = .basic
        toolbar.showsBaselineSeparator = true
        window?.titlebarAppearsTransparent = false
        if #available(macOS 11.0, *) {
            window?.toolbarStyle = .preference
        }
        window?.toolbar = toolbar
        window?.title = NSLocalizedString("Basic", comment: "")
        use(view: basicSettingsView)

        // When the `CandidateListTextSize` is not yet populated, the pop up
        // button adds an empty item and selects that empty item. This code
        // correctly sets the default text size, and removes the empty item
        // at the end.
        let selectedSizeTitle = fontSizePopUpButton.selectedItem?.title ?? ""
        if selectedSizeTitle.isEmpty {
            let intFontSize = Int(Preferences.candidateListTextSize)
            let intFontSizeStr = String.init(format: "%d", intFontSize)

            var selected = false
            for item in fontSizePopUpButton.itemArray {
                if item.title == intFontSizeStr {
                    fontSizePopUpButton.select(item)
                    selected = true
                    break
                }
            }

            // If not selected, Preferences.candidateListTextSize is not set to
            // one of the options provided in the pop up button. Let's list the
            // option for the user.
            if !selected {
                var insertIndex = 0

                // Place the item in the right place. We take advantage of the
                // fact that Int("") returns nil, and so if the custom font size
                // is larger than the largest item in the list (say 96), this
                // code guarantees to place the custom font size item right below
                // that largest item and before the empty item (which will then
                // be removed by the code below).
                for (index, item) in fontSizePopUpButton.itemArray.enumerated() {
                    if intFontSize < (Int(item.title) ?? Int.max) {
                        insertIndex = index
                        break
                    }
                }
                fontSizePopUpButton.insertItem(withTitle: intFontSizeStr, at: insertIndex)
                fontSizePopUpButton.selectItem(at: insertIndex)
            }

            // Remove the last item if it's empty
            let items = fontSizePopUpButton.itemArray
            if let lastItem = items.last {
                if lastItem.title.isEmpty {
                    fontSizePopUpButton.removeItem(at: items.count - 1)
                }
            }
        }

        let list = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
        var usKeyboardLayoutItem: NSMenuItem? = nil
        var chosenItem: NSMenuItem? = nil

        basisKeyboardLayoutButton.menu?.removeAllItems()

        let basisKeyboardLayoutID = Preferences.basisKeyboardLayout
        for source in list {

            func getString(_ key: CFString) -> String? {
                if let ptr = TISGetInputSourceProperty(source, key) {
                    return String(Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue())
                }
                return nil
            }

            func getBool(_ key: CFString) -> Bool? {
                if let ptr = TISGetInputSourceProperty(source, key) {
                    return Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue() == kCFBooleanTrue
                }
                return nil
            }

            if let category = getString(kTISPropertyInputSourceCategory) {
                if category != String(kTISCategoryKeyboardInputSource) {
                    continue
                }
            } else {
                continue
            }

            if let asciiCapable = getBool(kTISPropertyInputSourceIsASCIICapable) {
                if !asciiCapable {
                    continue
                }
            } else {
                continue
            }

            if let sourceType = getString(kTISPropertyInputSourceType) {
                if sourceType != String(kTISTypeKeyboardLayout) {
                    continue
                }
            } else {
                continue
            }

            guard let sourceID = getString(kTISPropertyInputSourceID),
                  let localizedName = getString(kTISPropertyLocalizedName) else {
                continue
            }

            let menuItem = NSMenuItem()
            menuItem.title = localizedName
            menuItem.representedObject = sourceID

            if sourceID == "com.apple.keylayout.US" {
                usKeyboardLayoutItem = menuItem
            }
            if basisKeyboardLayoutID == sourceID {
                chosenItem = menuItem
            }
            basisKeyboardLayoutButton.menu?.addItem(menuItem)
        }

        basisKeyboardLayoutButton.select(chosenItem ?? usKeyboardLayoutItem)
        selectionKeyComboBox.usesDataSource = false
        selectionKeyComboBox.removeAllItems()
        selectionKeyComboBox.addItems(withObjectValues: Preferences.suggestedCandidateKeys)

        var candidateSelectionKeys = Preferences.candidateKeys
        if candidateSelectionKeys.isEmpty {
            candidateSelectionKeys = Preferences.defaultCandidateKeys
        }
        selectionKeyComboBox.stringValue = candidateSelectionKeys

        if #available(macOS 11.0, *) {
            chooseUserPhrasesFolderButton.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Folder")
        }
        let index = Preferences.useCustomUserPhraseLocation ? 1 : 0
        customUserPhraseLocationEnabledButton.selectItem(at: index)
        updateUserPhraseLocation()
        addPhraseHookPathField.stringValue = Preferences.addPhraseHookPath
        
        // Setup autocomplete UI controls
        setupAutocompleteControls()
    }
    
    // private func setupAutocompleteControls1() {
    //     guard let advancedView = advancedSettingsView else { return }
        
    //     // Find existing controls to position relative to them
    //     let existingControls = advancedView.subviews
        
    //     // Find the punctuation symbols label to position our controls below it
    //     let punctuationLabel = existingControls.first { ($0 as? NSTextField)?.stringValue == "Punctuation Symbols:" }
    //     let yPosition = punctuationLabel?.frame.minY ?? 50
        
    //     // Create the autocomplete section label
    //     let sectionLabel = NSTextField(labelWithString: "Autocomplete:")
    //     sectionLabel.frame = NSRect(x: 134, y: yPosition - 30, width: 103, height: 16)
    //     sectionLabel.alignment = .right
    //     advancedView.addSubview(sectionLabel)
        
    //     // Create the autocomplete enabled checkbox
    //     autocompleteEnabledButton = NSButton(checkboxWithTitle: "Enable autocomplete suggestions", target: self, action: #selector(toggleAutocompleteEnabled(_:)))
    //     autocompleteEnabledButton.frame = NSRect(x: 241, y: yPosition - 30, width: 217, height: 18)
    //     autocompleteEnabledButton.state = Preferences.autocompleteEnabled ? .on : .off
    //     advancedView.addSubview(autocompleteEnabledButton)
        
    //     // Create the model label
    //     autocompleteModelLabel = NSTextField(labelWithString: "Model:")
    //     autocompleteModelLabel.frame = NSRect(x: 134, y: yPosition - 60, width: 103, height: 16)
    //     autocompleteModelLabel.alignment = .right
    //     advancedView.addSubview(autocompleteModelLabel)
        
    //     // Create the model text field
    //     autocompleteModelTextField = NSTextField(frame: NSRect(x: 241, y: yPosition - 60, width: 217, height: 22))
    //     autocompleteModelTextField.stringValue = Preferences.autocompleteModel
    //     autocompleteModelTextField.target = self
    //     autocompleteModelTextField.action = #selector(updateAutocompleteModel(_:))
    //     advancedView.addSubview(autocompleteModelTextField)
        
    //     // Add a description text
    //     let descriptionText = NSTextField(wrappingLabelWithString: "When enabled, autocomplete will suggest completions based on the previous text. Press Enter to accept or Esc to cancel.")
    //     descriptionText.frame = NSRect(x: 241, y: yPosition - 100, width: 217, height: 32)
    //     descriptionText.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    //     advancedView.addSubview(descriptionText)
        
    //     // Update the enabled state of the model controls
    //     updateAutocompleteControlsState()
    // }
    
    private func setupAutocompleteControls() {
        guard let advancedView = advancedSettingsView else { return }
        
        // Find the punctuation description text to position our controls below it
        let existingControls = advancedView.subviews
        let punctuationDescription = existingControls.first { 
            if let textField = $0 as? NSTextField {
                return textField.stringValue.contains("When enabled, if you type")
            }
            return false
        }
        
        // Position below the punctuation description text
        let startY = (punctuationDescription?.frame.minY ?? 150) - 20
        
        let labelX: CGFloat = 101  // Align with "Punctuation Symbols:" label
        let fieldX: CGFloat = 241  // Align with other controls
        let labelWidth: CGFloat = 136  // Same width as "Punctuation Symbols:" label
        let fieldWidth: CGFloat = 217
        let spacing: CGFloat = 24
        
        var y = startY
        
        // Autocomplete Section Label
        let sectionLabel = NSTextField(labelWithString: "Autocomplete:")
        sectionLabel.frame = NSRect(x: labelX, y: y, width: labelWidth, height: 16)
        sectionLabel.alignment = .left
        advancedView.addSubview(sectionLabel)
        
        // Checkbox
        y -= spacing
        autocompleteEnabledButton = NSButton(checkboxWithTitle: "Enable autocomplete suggestions", target: self, action: #selector(toggleAutocompleteEnabled(_:)))
        autocompleteEnabledButton.frame = NSRect(x: fieldX, y: y, width: fieldWidth, height: 18)
        autocompleteEnabledButton.state = Preferences.autocompleteEnabled ? .on : .off
        advancedView.addSubview(autocompleteEnabledButton)
        
        // Model label
        y -= spacing
        autocompleteModelLabel = NSTextField(labelWithString: "Model:")
        autocompleteModelLabel.frame = NSRect(x: labelX, y: y, width: labelWidth, height: 16)
        autocompleteModelLabel.alignment = .right
        advancedView.addSubview(autocompleteModelLabel)
        
        // Model input
        autocompleteModelTextField = NSTextField(frame: NSRect(x: fieldX, y: y, width: fieldWidth, height: 22))
        autocompleteModelTextField.stringValue = Preferences.autocompleteModel
        autocompleteModelTextField.target = self
        autocompleteModelTextField.action = #selector(updateAutocompleteModel(_:))
        advancedView.addSubview(autocompleteModelTextField)
        
        // Description
        y -= spacing + 5
        let descriptionText = NSTextField(wrappingLabelWithString: "When enabled, autocomplete will suggest completions based on the previous text. Press Enter to accept or Esc to cancel.")
        descriptionText.frame = NSRect(x: fieldX, y: y - 10, width: fieldWidth, height: 40)
        descriptionText.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        descriptionText.textColor = .secondaryLabelColor
        advancedView.addSubview(descriptionText)
        
        // Update state
        updateAutocompleteControlsState()
    }
    
    @objc private func toggleAutocompleteEnabled(_ sender: NSButton) {
        Preferences.autocompleteEnabled = (sender.state == .on)
        updateAutocompleteControlsState()
    }
    
    @objc private func updateAutocompleteModel(_ sender: NSTextField) {
        Preferences.autocompleteModel = sender.stringValue
    }
    
    private func updateAutocompleteControlsState() {
        let enabled = Preferences.autocompleteEnabled
        autocompleteModelTextField.isEnabled = enabled
        autocompleteModelLabel.textColor = enabled ? .labelColor : .disabledControlTextColor
    }

    @IBAction func updateBasisKeyboardLayoutAction(_ sender: Any) {
        if let sourceID = basisKeyboardLayoutButton.selectedItem?.representedObject as? String {
            Preferences.basisKeyboardLayout = sourceID
        }
    }

    @IBAction func changeSelectionKeyAction(_ sender: Any) {
        guard let keys = (sender as AnyObject).stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() else {
            return
        }
        do {
            try Preferences.validate(candidateKeys: keys)
            Preferences.candidateKeys = keys
        } catch Preferences.CandidateKeyError.empty {
            selectionKeyComboBox.stringValue = Preferences.candidateKeys
        } catch {
            if let window = window {
                let alert = NSAlert(error: error)
                alert.beginSheetModal(for: window) { response in
                    self.selectionKeyComboBox.stringValue = Preferences.candidateKeys
                }
            }
        }
    }

    func updateUserPhraseLocation() {
        if Preferences.useCustomUserPhraseLocation {
            userPhrasesTextField.stringValue = Preferences.customUserPhraseLocation
            openUserPhrasesFolderButton.title = Preferences.customUserPhraseLocation
        } else {
            userPhrasesTextField.stringValue = ""
            openUserPhrasesFolderButton.title = UserPhraseLocationHelper.defaultUserPhraseLocation
        }
    }

    @IBAction func changeCustomUserPhraseLocationEnabledAction(_ sender: Any) {
        guard let control = sender as? NSPopUpButton else {
            return
        }
        let enabled = control.selectedTag() > 0
        Preferences.useCustomUserPhraseLocation = enabled
        if enabled {
            if Preferences.customUserPhraseLocation.isEmpty {
                Preferences.customUserPhraseLocation = UserPhraseLocationHelper.defaultUserPhraseLocation
            }
        }
        updateUserPhraseLocation()
    }

    @IBAction func changeUserPhraseLocationAction(_ sender: Any) {
        guard let control = sender as? NSControl else {
            return
        }
        let path = control.stringValue.trimmingCharacters(in: .whitespaces)
        if FileManager.default.fileExists(atPath: path) == false {
            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        Preferences.customUserPhraseLocation = path
        updateUserPhraseLocation()
    }

    @IBAction func openUserPhrasedFolderAction(_ sender: Any) {
        let path =
         Preferences.useCustomUserPhraseLocation ?
            Preferences.customUserPhraseLocation :
            UserPhraseLocationHelper.defaultUserPhraseLocation
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }

    @IBAction func changeUserPhraseLocationFromPanelAction(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        let result = panel.runModal()

        if result == .OK, let url = panel.urls.first {
            let path = url.path
            Preferences.customUserPhraseLocation = path
            updateUserPhraseLocation()
        }
    }
}


extension PreferencesWindowController: NSToolbarDelegate {
    func use(view: NSView) {
        guard let window = window else {
            return
        }
        window.contentView?.subviews.first?.removeFromSuperview()
        let viewFrame = view.frame
        var windowRect = window.frame
        windowRect.size.height = kWindowTitleHeight + viewFrame.height
        windowRect.size.width = viewFrame.width
        windowRect.origin.y = window.frame.maxY - (viewFrame.height + kWindowTitleHeight)
        window.setFrame(windowRect, display: true, animate: true)
        window.contentView?.frame = view.bounds
        window.contentView?.addSubview(view)
    }

    @objc func showBasicView(_ sender: Any?) {
        use(view: basicSettingsView)
        window?.toolbar?.selectedItemIdentifier = .basic
        window?.title = NSLocalizedString("Basic", comment: "")
    }

    @objc func showUserPhrasesView(_ sender: Any?) {
        use(view: userPhrasesSettingsView)
        window?.toolbar?.selectedItemIdentifier = .userPhrases
        window?.title = NSLocalizedString("User Phrases", comment: "")
    }

    @objc func showAdvancedView(_ sender: Any?) {
        use(view: advancedSettingsView)
        window?.toolbar?.selectedItemIdentifier = .advanced
        window?.title = NSLocalizedString("Advanced", comment: "")
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.basic, .userPhrases, .advanced]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.basic, .userPhrases, .advanced]
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.basic, .userPhrases, .advanced]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.target = self
        switch itemIdentifier {
        case .basic:
            let title = NSLocalizedString("Basic", comment: "")
            item.label = title
            if #available(macOS 11.0, *) {
                item.image = NSImage(systemSymbolName: "switch.2", accessibilityDescription: title)
            } else {
                item.image = NSImage(named: NSImage.preferencesGeneralName)
            }
            item.action = #selector(showBasicView(_:))
        case .userPhrases:
            let title = NSLocalizedString("User Phrases", comment: "")
            item.label = title
            if #available(macOS 11.0, *) {
                item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: title)
            } else {
                item.image = NSImage(named: NSImage.folderName)
            }
            item.action = #selector(showUserPhrasesView(_:))
        case .advanced:
            let title = NSLocalizedString("Advanced", comment: "")
            item.label = title
            if #available(macOS 11.0, *) {
                item.image = NSImage(systemSymbolName: "gear", accessibilityDescription: title)
            } else {
                item.image = NSImage(named: NSImage.advancedName)
            }
            item.action = #selector(showAdvancedView(_:))
        default:
            return nil
        }
        return item
    }
}
