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
import InputMethodKit
import CandidateUI
import NotifierUI
import TooltipUI
import OpenCCBridge

private extension Bool {
    var state: NSControl.StateValue {
        self ? .on : .off
    }
}

private let kMinKeyLabelSize: CGFloat = 10

private var gCurrentCandidateController: CandidateController?

private extension CandidateController {
    static let horizontal = HorizontalCandidateController()
    static let vertical = VerticalCandidateController()
}

@objc(McBopomofoInputMethodController)
class McBopomofoInputMethodController: IMKInputController {

    private static let tooltipController = TooltipController()

    // MARK: -

    private var currentClient: Any?

    private var keyHandler: KeyHandler = KeyHandler()
    private var state: InputState = InputState.Empty()

    // MARK: - IMKInputController methods

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        keyHandler.delegate = self
    }

    override func menu() -> NSMenu! {
        let menu = NSMenu(title: "Input Method Menu")

        let chineseConversionItem = menu.addItem(withTitle: NSLocalizedString("Chinese Conversion", comment: ""), action: #selector(toggleChineseConverter(_:)), keyEquivalent: "g")
        chineseConversionItem.keyEquivalentModifierMask = [.command, .control]
        chineseConversionItem.state = Preferences.chineseConversionEnabled.state

        let halfWidthPunctuationItem = menu.addItem(withTitle: NSLocalizedString("Use Half-Width Punctuations", comment: ""), action: #selector(toggleHalfWidthPunctuation(_:)), keyEquivalent: "h")
        halfWidthPunctuationItem.keyEquivalentModifierMask = [.command, .control]
        halfWidthPunctuationItem.state = Preferences.halfWidthPunctuationEnabled.state
        let associatedPhrasesItem = menu.addItem(withTitle: NSLocalizedString("Associated Phrases", comment: ""), action: #selector(toggleAssociatedPhrasesEnabled(_:)), keyEquivalent: "")
        associatedPhrasesItem.state = Preferences.associatedPhrasesEnabled.state

        let inputMode = keyHandler.inputMode
        let optionKeyPressed = NSEvent.modifierFlags.contains(.option)
        if inputMode == .bopomofo && optionKeyPressed {
            let phaseReplacementItem = menu.addItem(withTitle: NSLocalizedString("Use Phrase Replacement", comment: ""), action: #selector(togglePhraseReplacement(_:)), keyEquivalent: "")
            phaseReplacementItem.state = Preferences.phraseReplacementEnabled.state
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: NSLocalizedString("User Phrases", comment: ""), action: nil, keyEquivalent: "")

        if inputMode == .plainBopomofo {
            if (Preferences.enableUserPhrasesInPlainBopomofo) {
                menu.addItem(withTitle: NSLocalizedString("Edit User Phrases", comment: ""), action: #selector(openUserPhrasesPlainBopomofo(_:)), keyEquivalent: "")
            }
            menu.addItem(withTitle: NSLocalizedString("Edit Excluded Phrases", comment: ""), action: #selector(openExcludedPhrasesPlainBopomofo(_:)), keyEquivalent: "")
        } else {
            menu.addItem(withTitle: NSLocalizedString("Edit User Phrases", comment: ""), action: #selector(openUserPhrases(_:)), keyEquivalent: "")
            menu.addItem(withTitle: NSLocalizedString("Edit Excluded Phrases", comment: ""), action: #selector(openExcludedPhrasesMcBopomofo(_:)), keyEquivalent: "")
            if optionKeyPressed {
                menu.addItem(withTitle: NSLocalizedString("Edit Phrase Replacement Table", comment: ""), action: #selector(openPhraseReplacementMcBopomofo(_:)), keyEquivalent: "")
            }
        }

        menu.addItem(withTitle: NSLocalizedString("Reload User Phrases", comment: ""), action: #selector(reloadUserPhrases(_:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())

        menu.addItem(withTitle: NSLocalizedString("McBopomofo Preferences", comment: ""), action: #selector(showPreferences(_:)), keyEquivalent: "")
        menu.addItem(withTitle: NSLocalizedString("Check for Updates…", comment: ""), action: #selector(checkForUpdate(_:)), keyEquivalent: "")
        menu.addItem(withTitle: NSLocalizedString("About McBopomofo…", comment: ""), action: #selector(showAbout(_:)), keyEquivalent: "")
        return menu
    }

    // MARK: - IMKStateSetting protocol methods

    override func activateServer(_ client: Any!) {
        UserDefaults.standard.synchronize()

        // Override the keyboard layout. Use US if not set.
        (client as? IMKTextInput)?.overrideKeyboard(withKeyboardNamed: Preferences.basisKeyboardLayout)
        // reset the state
        currentClient = client

        keyHandler.clear()
        keyHandler.syncWithPreferences()

        (NSApp.delegate as? AppDelegate)?.checkForUpdate()
    }

    override func deactivateServer(_ client: Any!) {
        currentClient = nil
        keyHandler.clear()
        self.handle(state: .Deactivated(), client: client)
    }

    override func setValue(_ value: Any!, forTag tag: Int, client: Any!) {
        let newInputMode = InputMode(rawValue: value as? String ?? InputMode.bopomofo.rawValue)
        LanguageModelManager.loadDataModel(newInputMode)
        if keyHandler.inputMode != newInputMode {
            UserDefaults.standard.synchronize()
            // Remember to override the keyboard layout again -- treat this as an activate event.
            (client as? IMKTextInput)?.overrideKeyboard(withKeyboardNamed: Preferences.basisKeyboardLayout)
            keyHandler.clear()
            keyHandler.inputMode = newInputMode
            self.handle(state: .Empty(), client: client)
        }
    }

    // MARK: - IMKServerInput protocol methods

    override func commitComposition(_ client: Any!) {
        keyHandler.handleForceCommit(stateCallback: { newState in
            self.handle(state: newState, client: client)
        })
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        let events: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
        return Int(events.rawValue)
    }

    override func handle(_ maybeEvent: NSEvent!, client: Any!) -> Bool {
        // nil may be passed, applefeedback://FB11472618
        guard let event = maybeEvent else {
            commitComposition(client)
            return false
        }

        if event.type == .flagsChanged {
            if state is InputState.Empty {
                return false
            }
            // Handle key up events during active input state.
            //
            // This prevents double-space from affecting the current input.
            // While macOS may normally insert a period on double space, this
            // should be suppressed when there is an active composing buffer or
            // candidate window.
            return true
        }

        if event.type == .flagsChanged {
            let functionKeyKeyboardLayoutID = Preferences.functionKeyboardLayout
            let basisKeyboardLayoutID = Preferences.basisKeyboardLayout

            if functionKeyKeyboardLayoutID == basisKeyboardLayoutID {
                return false
            }

            let includeShift = Preferences.functionKeyKeyboardLayoutOverrideIncludeShiftKey
            let notShift = NSEvent.ModifierFlags(rawValue: ~(NSEvent.ModifierFlags.shift.rawValue))
            if event.modifierFlags.contains(notShift) ||
                       (event.modifierFlags.contains(.shift) && includeShift) {
                (client as? IMKTextInput)?.overrideKeyboard(withKeyboardNamed: functionKeyKeyboardLayoutID)
                return false
            }
            (client as? IMKTextInput)?.overrideKeyboard(withKeyboardNamed: basisKeyboardLayoutID)
            return false
        }

        var textFrame = NSRect.zero
        let attributes: [AnyHashable: Any]? = (client as? IMKTextInput)?.attributes(forCharacterIndex: 0, lineHeightRectangle: &textFrame)
        let useVerticalMode = (attributes?["IMKTextOrientation"] as? NSNumber)?.intValue == 0 || false
        let input = KeyHandlerInput(event: event, isVerticalMode: useVerticalMode)

        let result = keyHandler.handle(input: input, state: state) { newState in
            self.handle(state: newState, client: client)
        } errorCallback: {
            if (Preferences.beepUponInputError) {
                NSSound.beep()
            }
        }
        return result
    }

    // MARK: - Menu Items

    @objc override func showPreferences(_ sender: Any?) {
        super.showPreferences(sender)
    }

    @objc func toggleChineseConverter(_ sender: Any?) {
        let enabled = Preferences.toggleChineseConversionEnabled()
        NotifierController.notify(message: enabled ? NSLocalizedString("Chinese conversion on", comment: "") : NSLocalizedString("Chinese conversion off", comment: ""))
        if let currentClient = currentClient {
            keyHandler.clear()
            self.handle(state: InputState.Empty(), client: currentClient)
        }
    }

    @objc func toggleHalfWidthPunctuation(_ sender: Any?) {
        let enabled = Preferences.toggleHalfWidthPunctuationEnabled()
        NotifierController.notify(message: enabled ? NSLocalizedString("Half-Width Punctuation On", comment: "") : NSLocalizedString("Half-Width Punctuation Off", comment: ""))
        if let currentClient = currentClient {
            keyHandler.clear()
            self.handle(state: InputState.Empty(), client: currentClient)
        }
    }

    @objc func toggleAssociatedPhrasesEnabled(_ sender: Any?) {
        _ = Preferences.toggleAssociatedPhrasesEnabled()
    }

    @objc func togglePhraseReplacement(_ sender: Any?) {
        let enabled = Preferences.togglePhraseReplacementEnabled()
        LanguageModelManager.phraseReplacementEnabled = enabled
    }

    @objc func checkForUpdate(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.checkForUpdate(forced: true)
    }

    @objc func openUserPhrases(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openUserPhrases(sender)
    }

    @objc func openUserPhrasesPlainBopomofo(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openUserPhrasesPlainBopomofo(sender)
    }

    @objc func openExcludedPhrasesPlainBopomofo(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openExcludedPhrasesPlainBopomofo(sender)
    }

    @objc func openExcludedPhrasesMcBopomofo(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openExcludedPhrasesMcBopomofo(sender)
    }

    @objc func openPhraseReplacementMcBopomofo(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openPhraseReplacementMcBopomofo(sender)
    }

    @objc func reloadUserPhrases(_ sender: Any?) {
        LanguageModelManager.loadUserPhrases(enableForPlainBopomofo: Preferences.enableUserPhrasesInPlainBopomofo)
        LanguageModelManager.loadUserPhraseReplacement()
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

}

// MARK: - State Handling

extension McBopomofoInputMethodController {

    private func handle(state newState: InputState, client: Any?) {
        let previous = state
        state = newState

        switch newState {
        case let newState as InputState.Deactivated:
            handle(state: newState, previous: previous, client: client)
            state = .Empty()
        case let newState as InputState.Empty:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.EmptyIgnoringPreviousState:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.Committing:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.Inputting:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.Marking:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.ChoosingCandidate:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.AssociatedPhrases:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.AssociatedPhrasesPlain:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.SelectingFeature:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.SelectingDateMacro:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.ChineseNumber:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.EnclosedNumber:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.Big5:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.SelectingDictionary:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.ShowingCharInfo:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.Autocomplete:
            handle(state: newState, previous: previous, client: client)
        default:
            break
        }
    }

    private func commit(text: String, client: Any!) {

        func convertToSimplifiedChineseIfRequired(_ text: String) -> String {
            if !Preferences.chineseConversionEnabled {
                return text
            }
            if Preferences.chineseConversionStyle == .model {
                return text
            }
            return OpenCCBridge.shared.convertToSimplified(text) ?? ""
        }

        let buffer = convertToSimplifiedChineseIfRequired(text)
        if buffer.isEmpty {
            return
        }
        (client as? IMKTextInput)?.insertText(buffer, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    private func handle(state: InputState.Deactivated, previous: InputState, client: Any?) {
        currentClient = nil

        gCurrentCandidateController?.delegate = nil
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        if let previous = previous as? InputState.NotEmpty {
            commit(text: previous.composingBuffer, client: client)
        }

        if let _ = previous as? InputState.Big5 {
            client.setMarkedText("", selectionRange: NSMakeRange(0, 0), replacementRange: NSMakeRange(0, 0))
        }
        if let _ = previous as? InputState.ChineseNumber {
            client.setMarkedText("", selectionRange: NSMakeRange(0, 0), replacementRange: NSMakeRange(0, 0))
        }

        // Unlike the Empty state handler, we don't call client.setMarkedText() here:
        // there's no point calling setMarkedText() with an empty string as the session
        // is being deactivated anyway, and we have found issues with how certains app
        // could not handle setMarkedText() at this point (see GitHub issue #346).
    }

    private func handle(state: InputState.Empty, previous: InputState, client: Any?) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        if let previous = previous as? InputState.NotEmpty {
            commit(text: previous.composingBuffer, client: client)
            
            // Trigger autocomplete after committing text if enabled
            if Preferences.autocompleteEnabled && keyHandler.inputMode == .bopomofo {
                triggerAutocomplete(client: client)
            }
        }
        client.setMarkedText("", selectionRange: NSMakeRange(0, 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))
    }

    private func handle(state: InputState.EmptyIgnoringPreviousState, previous: InputState, client: Any!) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        client.setMarkedText("", selectionRange: NSMakeRange(0, 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))
    }

    private func handle(state: InputState.Committing, previous: InputState, client: Any?) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        let poppedText = state.poppedText
        if !poppedText.isEmpty {
            commit(text: poppedText, client: client)
            
            // Trigger autocomplete after committing text if enabled
            if Preferences.autocompleteEnabled && keyHandler.inputMode == .bopomofo && 
               !(previous is InputState.Autocomplete) && 
               !keyHandler.hasComposingText {
                triggerAutocomplete(client: client)
            }
        }
        client.setMarkedText("", selectionRange: NSMakeRange(0, 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))
    }

    private func handle(state: InputState.Inputting, previous: InputState, client: Any?) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        client.setMarkedText(state.attributedString, selectionRange: NSMakeRange(Int(state.cursorIndex), 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        if !state.tooltip.isEmpty {
            show(tooltip: state.tooltip, composingBuffer: state.composingBuffer, cursorIndex: state.cursorIndex, client: client)
        }
    }

    private func handle(state: InputState.Marking, previous: InputState, client: Any?) {
        gCurrentCandidateController?.visible = false
        guard let client = client as? IMKTextInput else {
            hideTooltip()
            return
        }

        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        client.setMarkedText(state.attributedString, selectionRange: NSMakeRange(Int(state.cursorIndex), 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))

        if state.tooltip.isEmpty {
            hideTooltip()
        } else {
            show(tooltip: state.tooltip, composingBuffer: state.composingBuffer, cursorIndex: state.markerIndex, client: client)
        }
    }

    private func handle(state: InputState.ChoosingCandidate, previous: InputState, client: Any?) {
        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }

        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        client.setMarkedText(state.attributedString, selectionRange: NSMakeRange(Int(state.cursorIndex), 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        show(candidateWindowWith: state, client: client)
    }

    private func handle(state: InputState.AssociatedPhrases, previous: InputState, client: Any?) {
        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }

        let previousState = state.previousState
        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        switch previousState {
        case let previousState as InputState.ChoosingCandidate:
            client.setMarkedText(previousState.attributedString, selectionRange: NSMakeRange(Int(previousState.cursorIndex), 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        case let previousState as InputState.Inputting:
            client.setMarkedText(previousState.attributedString, selectionRange: NSMakeRange(Int(previousState.cursorIndex), 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        default:
            break
        }
        show(candidateWindowWith: state, client: client)
    }

    private func handle(state: InputState.AssociatedPhrasesPlain, previous: InputState, client: Any?) {
        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }
        client.setMarkedText("", selectionRange: NSMakeRange(0, 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        show(candidateWindowWith: state, client: client)
    }

    private func handle(state: InputState.SelectingFeature, previous: InputState, client: Any?) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        if let previous = previous as? InputState.NotEmpty {
            commit(text: previous.composingBuffer, client: client)
        }
        client.setMarkedText("", selectionRange: NSMakeRange(0, 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        show(candidateWindowWith: state, client: client)
    }

    private func handle(state: InputState.SelectingDateMacro, previous: InputState, client: Any?) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        if let previous = previous as? InputState.NotEmpty {
            commit(text: previous.composingBuffer, client: client)
        }
        client.setMarkedText("", selectionRange: NSMakeRange(0, 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        show(candidateWindowWith: state, client: client)
    }

    private func handle(state: InputState.ChineseNumber, previous: InputState, client: Any?) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        if let previous = previous as? InputState.NotEmpty {
            commit(text: previous.composingBuffer, client: client)
        }
        client.setMarkedText(state.composingBuffer, selectionRange: NSMakeRange(state.composingBuffer.count, 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))
    }

    private func handle(state: InputState.EnclosedNumber, previous: InputState, client: Any?) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        if let previous = previous as? InputState.NotEmpty {
            commit(text: previous.composingBuffer, client: client)
        }
        client.setMarkedText(state.composingBuffer, selectionRange: NSMakeRange(state.composingBuffer.count, 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))
    }

    private func handle(state: InputState.Big5, previous: InputState, client: Any?) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        if let previous = previous as? InputState.NotEmpty {
            commit(text: previous.composingBuffer, client: client)
        }
        client.setMarkedText(state.composingBuffer, selectionRange: NSMakeRange(state.composingBuffer.count, 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))
    }

    private func handle(state: InputState.SelectingDictionary, previous: InputState, client: Any?) {
        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }
        let previousState = state.previousState
        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer

        if let candidateDate = previousState as? InputState.ChoosingCandidate {
            client.setMarkedText(candidateDate.attributedString, selectionRange: NSMakeRange(Int(candidateDate.cursorIndex), 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        } else if let candidateDate = previousState as? InputState.Marking {
            client.setMarkedText(candidateDate.attributedString, selectionRange: NSMakeRange(Int(candidateDate.cursorIndex), 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        }

        show(candidateWindowWith: state, client: client)
    }

    private func handle(state: InputState.ShowingCharInfo, previous: InputState, client: Any?) {

        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }
        let previousState = state.previousState.previousState
        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        if let candidateDate = previousState as? InputState.ChoosingCandidate {
            client.setMarkedText(candidateDate.attributedString, selectionRange: NSMakeRange(Int(candidateDate.cursorIndex), 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        } else if let candidateDate = previousState as? InputState.Marking {
            client.setMarkedText(candidateDate.attributedString, selectionRange: NSMakeRange(Int(candidateDate.cursorIndex), 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        }
        show(candidateWindowWith: state, client: client)
    }
    
    private func handle(state: InputState.Autocomplete, previous: InputState, client: Any?) {
        hideTooltip()
        
        guard let client = client as? IMKTextInput else {
            return
        }
        
        client.setMarkedText(state.attributedString, selectionRange: NSMakeRange(0, 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))
    }
    
//    // Get the recent context from the client (last 10 characters)
//    private func getRecentContext(client: IMKTextInput) -> String {
//        var lineHeightRect = NSRect.zero
//        var context = ""
//        
//        // Try to get the text before the cursor
//        let range = NSRange(location: 0, length: 10)
//        if let attributedString = client.attributedSubstring(from: range) {
//            context = attributedString.string
//        }
//        
//        // If we couldn't get the text, try another approach
//        if context.isEmpty {
//            // Get the current line
//            var lineRange = NSRange(location: NSNotFound, length: 0)
//            client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineHeightRect, actualRange: &lineRange)
//            
//            if lineRange.location != NSNotFound && lineRange.length > 0 {
//                if let attributedString = client.attributedSubstring(from: lineRange) {
//                    context = attributedString.string
//                    
//                    // Limit to last 10 characters
//                    if context.count > 10 {
//                        context = String(context.suffix(10))
//                    }
//                }
//            }
//        }
//        
//        return context
//    }
    
    private func getRecentContext(client: IMKTextInput) -> String {
        let maxLength = 10
        let selectedRange = client.selectedRange()
        
        // Make sure the cursor is at a valid location
        guard selectedRange.location != NSNotFound else {
            return ""
        }

        // Calculate a safe range up to 10 characters before the cursor
        let location = max(0, selectedRange.location - maxLength)
        let length = min(maxLength, selectedRange.location)
        let range = NSRange(location: location, length: length)
        
        // Attempt to get the attributed substring from the input client
        if let attributedString = client.attributedSubstring(from: range) {
            return attributedString.string
        }

        return ""
    }
    
    // Trigger autocomplete suggestion
    private func triggerAutocomplete(client: Any?) {
        guard Preferences.autocompleteEnabled,
              let client = client as? IMKTextInput,
              !keyHandler.hasComposingText else {
            return
        }
        
        // Get the recent context
        let context = getRecentContext(client: client)
        
        // Only trigger if we have context
        if !context.isEmpty {
            let ollamaService = OllamaService(model: Preferences.autocompleteModel)
            
            ollamaService.generateCompletion(context: context) { [weak self] suggestion, error in
                guard let self = self, let suggestion = suggestion, !suggestion.isEmpty, error == nil else {
                    return
                }
                
                // Switch to main thread to update UI
                DispatchQueue.main.async {
                    let autocompleteState = InputState.Autocomplete(suggestion: suggestion, previousText: context)
                    self.handle(state: autocompleteState, client: client)
                }
            }
        }
    }
}

// MARK: -

extension McBopomofoInputMethodController {

    private func show(candidateWindowWith state: InputState, client: Any!) {
        let useVerticalMode: Bool = {
            var useVerticalMode = false
            var candidates: [InputState.Candidate] = []
            switch state {
            case let state as InputState.ChoosingCandidate:
                useVerticalMode = state.useVerticalMode
                candidates = state.candidates
            case let state as InputState.AssociatedPhrasesPlain:
                useVerticalMode = state.useVerticalMode
                candidates = state.candidates
            case let state as InputState.AssociatedPhrases:
                useVerticalMode = state.useVerticalMode
                candidates = state.candidates
            case _ as InputState.SelectingFeature:
                return true
            case _ as InputState.SelectingDateMacro:
                return true
            case _ as InputState.SelectingDictionary:
                return true
            case _ as InputState.ShowingCharInfo:
                return true
            default:
                break
            }

            if useVerticalMode == true {
                return true
            }
            candidates.sort {
                return $0.displayText.count > $1.displayText.count
            }
            // If there is a candidate which is too long, we use the vertical
            // candidate list window automatically.
            if candidates.first?.displayText.count ?? 0 > 8 {
                return true
            }
            return false
        }()

        gCurrentCandidateController?.delegate = nil
        gCurrentCandidateController?.visible = false

        if useVerticalMode {
            gCurrentCandidateController = .vertical
        } else if Preferences.useHorizontalCandidateList {
            gCurrentCandidateController = .horizontal
        } else {
            gCurrentCandidateController = .vertical
        }

        gCurrentCandidateController?.tooltip = switch state {
        case let state as InputState.SelectingDictionary:
            String(format:NSLocalizedString("Look up %@", comment: ""), state.selectedPhrase)
        case let state as InputState.AssociatedPhrases:
            String(format:NSLocalizedString("%@…", comment: ""), state.prefixValue)
        default:
            ""
        }

        // set the attributes for the candidate panel (which uses NSAttributedString)
        let textSize = Preferences.candidateListTextSize
        let keyLabelSize = max(textSize / 2, kMinKeyLabelSize)

        func font(name: String?, size: CGFloat) -> NSFont {
            if let name = name {
                return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
            }
            return NSFont.systemFont(ofSize: size)
        }

        gCurrentCandidateController?.keyLabelFont = font(name: Preferences.candidateKeyLabelFontName, size: keyLabelSize)
        gCurrentCandidateController?.candidateFont = font(name: Preferences.candidateTextFontName, size: textSize)

        let candidateKeys = Preferences.candidateKeys
        let keyLabels = candidateKeys.count >= 4 ? Array(candidateKeys) : Array(Preferences.defaultCandidateKeys)
        let shouldUseShift = {
            if let state = state as? InputState.AssociatedPhrases {
                return state.useShiftKey
            }
            if state is InputState.AssociatedPhrasesPlain {
                return true
            }
            return false
        }()
        let keyLabelPrefix = shouldUseShift ? "⇧ " : ""
        gCurrentCandidateController?.keyLabels = keyLabels.map {
            CandidateKeyLabel(key: String($0), displayedText: keyLabelPrefix + String($0))
        }

        gCurrentCandidateController?.delegate = self
        gCurrentCandidateController?.reloadData()
        currentClient = client

        gCurrentCandidateController?.visible = true

        var lineHeightRect = NSMakeRect(0.0, 0.0, 16.0, 16.0)
        var cursor: Int = 0

        if let state = state as? InputState.NotEmpty {
            cursor = Int(state.cursorIndex)
            if cursor == state.composingBuffer.count && cursor != 0 {
                cursor -= 1
            }
        }

        while lineHeightRect.origin.x == 0 && lineHeightRect.origin.y == 0 && cursor >= 0 {
            (client as? IMKTextInput)?.attributes(forCharacterIndex: cursor, lineHeightRectangle: &lineHeightRect)
            cursor -= 1
        }

        if useVerticalMode {
            gCurrentCandidateController?.set(windowTopLeftPoint: NSMakePoint(lineHeightRect.origin.x + lineHeightRect.size.width + 4.0, lineHeightRect.origin.y - 4.0), bottomOutOfScreenAdjustmentHeight: lineHeightRect.size.height + 4.0)
        } else {
            gCurrentCandidateController?.set(windowTopLeftPoint: NSMakePoint(lineHeightRect.origin.x, lineHeightRect.origin.y - 4.0), bottomOutOfScreenAdjustmentHeight: lineHeightRect.size.height + 4.0)
        }
    }

    private func show(tooltip: String, composingBuffer: String, cursorIndex: UInt, client: Any!) {
        var lineHeightRect = NSMakeRect(0.0, 0.0, 16.0, 16.0)
        var cursor: Int = Int(cursorIndex)
        if cursor == composingBuffer.count && cursor != 0 {
            cursor -= 1
        }
        while lineHeightRect.origin.x == 0 && lineHeightRect.origin.y == 0 && cursor >= 0 {
            (client as? IMKTextInput)?.attributes(forCharacterIndex: cursor, lineHeightRectangle: &lineHeightRect)
            cursor -= 1
        }
        McBopomofoInputMethodController.tooltipController.show(tooltip: tooltip, at: lineHeightRect.origin)
    }

    private func hideTooltip() {
        McBopomofoInputMethodController.tooltipController.hide()
    }
}

// MARK: -

extension McBopomofoInputMethodController: KeyHandlerDelegate {
    func candidateController(for keyHandler: KeyHandler) -> Any {
        gCurrentCandidateController ?? .vertical
    }

    func keyHandler(_ keyHandler: KeyHandler, didSelectCandidateAt index: Int, candidateController controller: Any) {
        if index < 0 {
            return
        }
        if let controller = controller as? CandidateController {
            self.candidateController(controller, didSelectCandidateAtIndex: UInt(index))
        }
    }

    func keyHandler(_ keyHandler: KeyHandler, didRequestWriteUserPhraseWith state: InputState) -> Bool {
        guard let state = state as? InputState.Marking else {
            return false
        }
        if !state.validToWrite {
            return false
        }
        LanguageModelManager.writeUserPhrase(state.userPhrase)

        if !Preferences.addPhraseHookEnabled {
            return true
        }

        func run(_ script: String, arguments: [String]) {
            let process = Process()
            process.launchPath = script
            process.arguments = arguments
            // Some user may sign the git commits with gpg, and gpg is often
            // installed by homebrew, so we add the path of homebrew here.
            process.environment = ["PATH": "/opt/homebrew/bin:/usr/bin:/usr/local/bin:/bin"]

            let path = LanguageModelManager.dataFolderPath
            if #available(macOS 10.13, *) {
                process.currentDirectoryURL = URL(fileURLWithPath: path)
            } else {
                FileManager.default.changeCurrentDirectoryPath(path)
            }

            #if DEBUG
            let pipe = Pipe()
            process.standardError = pipe
            #endif
            process.launch()
            process.waitUntilExit()
            #if DEBUG
            let read = pipe.fileHandleForReading
            let data = read.readDataToEndOfFile()
            let s = String(data: data, encoding: .utf8)
            NSLog("result \(String(describing: s))")
            #endif
        }

        let script = Preferences.addPhraseHookPath

        DispatchQueue.global().async {
            run("/bin/sh", arguments: [script, state.selectedText])
        }

        return true
    }
}

// MARK: -

extension McBopomofoInputMethodController: CandidateControllerDelegate {
    func candidateCountForController(_ controller: CandidateController) -> UInt {
        return if let state = state as? CandidateProvider {
            UInt(state.candidateCount)
        } else {
            0
        }
    }

    func candidateController(_ controller: CandidateController, candidateAtIndex index: UInt) -> String {
        return if let state = state as? CandidateProvider {
            state.candidate(at: Int(index))
        } else {
            ""
        }
    }

    func candidateController(_ controller: CandidateController, didSelectCandidateAtIndex index: UInt) {
        let client = currentClient

        switch state {
        case let state as InputState.ChoosingCandidate:
            let selectedCandidate = state.candidates[Int(index)]
            keyHandler.fixNode(reading: selectedCandidate.reading, value: selectedCandidate.value, originalCursorIndex: Int(state.originalCursorIndex), useMoveCursorAfterSelectionSetting: true)

            guard let inputting = keyHandler.buildInputtingState() as? InputState.Inputting else {
                return
            }

            switch keyHandler.inputMode {
            case .plainBopomofo:
                keyHandler.clear()
                let composingBuffer = inputting.composingBuffer
                handle(state: .Committing(poppedText: composingBuffer), client: client)
                if Preferences.associatedPhrasesEnabled,
                   let associatePhrases = keyHandler.buildAssociatedPhrasePlainState(withReading: selectedCandidate.reading, value: selectedCandidate.value, useVerticalMode: state.useVerticalMode) as? InputState.AssociatedPhrasesPlain {
                    self.handle(state: associatePhrases, client: client)
                } else {
                    handle(state: .Empty(), client: client)
                }
            case .bopomofo:
                handle(state: inputting, client: client)
                if Preferences.associatedPhrasesEnabled {
                    var textFrame = NSRect.zero
                    let attributes: [AnyHashable: Any]? = (client as? IMKTextInput)?.attributes(forCharacterIndex: 0, lineHeightRectangle: &textFrame)
                    let useVerticalMode = (attributes?["IMKTextOrientation"] as? NSNumber)?.intValue == 0 || false

                    let state = keyHandler.buildInputtingState()
                    keyHandler.handleAssociatedPhrase(with: state, useVerticalMode: useVerticalMode, stateCallback: { newState in
                        self.handle(state: newState, client: client)
                    }, errorCallback: {
                        if (Preferences.beepUponInputError) {
                            NSSound.beep()
                        }
                    }, useShiftKey: true)
                }
            default:
                break
            }
        case let state as InputState.AssociatedPhrases:
            let candidate = state.candidates[Int(index)]
            keyHandler.fixNodeForAssociatedPhraseWithPrefix(at: state.prefixCursorIndex, prefixReading: state.prefixReading, prefixValue: state.prefixValue, associatedPhraseReading: candidate.reading, associatedPhraseValue: candidate.value)
            guard let inputting = keyHandler.buildInputtingState() as? InputState.Inputting else {
                return
            }
            handle(state: inputting, client: client)
            break
        case let state as InputState.AssociatedPhrasesPlain:
            let selectedCandidate = state.candidates[Int(index)]
            handle(state: .Committing(poppedText: selectedCandidate.value), client: currentClient)
            if Preferences.associatedPhrasesEnabled,
               let associatePhrases = keyHandler.buildAssociatedPhrasePlainState(withReading: selectedCandidate.reading, value: selectedCandidate.value, useVerticalMode: state.useVerticalMode) as? InputState.AssociatedPhrasesPlain {
                self.handle(state: associatePhrases, client: client)
            } else {
                handle(state: .Empty(), client: client)
            }
        case let state as InputState.SelectingFeature:
            if let nextState = state.nextState(by: Int(index)) {
                handle(state: nextState, client: client)
            }
        case let state as InputState.SelectingDateMacro:
            let candidate = state.candidate(at: Int(index))
            if !candidate.isEmpty {
                let committing = InputState.Committing(poppedText: candidate)
                handle(state: committing, client: client)
            }
        case let state as InputState.SelectingDictionary:
            let handled = state.lookUp(usingServiceAtIndex: Int(index), state: state) { state in
                handle(state: state, client: client)
            }
            if handled {
                let previous = state.previousState
                let candidateIndex = state.selectedIndex
                handle(state: previous, client: client)
                if candidateIndex > 0 {
                    gCurrentCandidateController?.selectedCandidateIndex = UInt(candidateIndex)
                }
            }
        case let state as InputState.ShowingCharInfo:
            let text = state.menuTitleValueMapping[Int(index)].1
            NSPasteboard.general.declareTypes([.string], owner: nil)
            NSPasteboard.general.setString(text, forType: .string)
            NotifierController.notify(message:String(format:NSLocalizedString("%@ has been copied.", comment: ""), text))

            let previous = state.previousState.previousState
            let candidateIndex = state.previousState.selectedIndex
            handle(state: previous, client: client)
            if candidateIndex > 0 {
                gCurrentCandidateController?.selectedCandidateIndex = UInt(candidateIndex)
            }
        default:
            break
        }
    }
}
