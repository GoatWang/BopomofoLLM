# TODO (Jeremy)

1. Error 1 to fix: Preference UI not aligned
    - UI File: McBopomofo/Source/Base.lproj/preferences.xib
    - Code File: McBopomofo/Source/PreferencesWindowController.swift

2. Error 2 to fix: The way to slice the previously input text (in a length of 10)
    - Code File: McBopomofo/Source/InputMethodController.swift

3. Feature to add:
    1. once backspace can still remove the previous word
    2. Change the prompt to: 你是一個繁體中文輸入法，幫助使用者預測接下來的句子，只要輸出一個句子即可，不要包含使用者輸入的詞彙，例如使用者輸入「我」，你要回答「是老師」，或「要喝水」，不能回答「我是老師」或「我要喝水」。

Change prompt in English/Chinese mode
# OpenVanilla McBopomofo 小麥注音輸入法

## 系統需求

小麥注音輸入法可以在 macOS 10.15 以上版本運作。如果您要自行編譯小麥注音輸入法，或參與開發，您需要：

- macOS 14.7 以上版本
- Xcode 15.3 以上版本
- Python 3.9 (可使用 Xcode 安裝後內附的，或是使用 homebrew 等方式安裝)

## 開發流程

用 Xcode 開啟 `McBopomofo.xcodeproj`，選 "McBopomofo Installer" target，build 完之後直接執行該安裝程式，就可以安裝小麥注音。

第一次安裝完，日後程式碼或詞庫有任何修改，只要重複上述流程，再次安裝小麥注音即可。

要注意的是 macOS 可能會限制同一次 login session 能 kill 同一個輸入法 process 的次數（安裝程式透過 kill input method process 來讓新版的輸入法生效）。如果安裝若干次後，發現程式修改的結果並沒有出現，或甚至輸入法已無法再選用，只要登出目前帳號再重新登入即可。

## 社群公約

歡迎小麥注音用戶回報問題與指教，也歡迎大家參與小麥注音開發。

首先，請參考我們在「[常見問題](https://github.com/openvanilla/McBopomofo/wiki/常見問題)」中所提「[我可以怎麼參與小麥注音？](https://github.com/openvanilla/McBopomofo/wiki/常見問題#我可以怎麼參與小麥注音)」一節的說明。

我們採用了 GitHub 的[通用社群公約](https://github.com/openvanilla/McBopomofo/blob/master/CODE_OF_CONDUCT.md)。公約的中文版請參考[這裡的翻譯](https://www.contributor-covenant.org/zh-tw/version/1/4/code-of-conduct/)。

## 軟體授權

本專案採用 MIT License 釋出，使用者可自由使用、散播本軟體，惟散播時必須完整保留版權聲明及軟體授權（[詳全文](https://github.com/openvanilla/McBopomofo/blob/master/LICENSE.txt)）。
