import Foundation

/// Settings the host app writes and the keyboard reads (shared app group; the keyboard only reads).
enum VKSettings {
    static let group = "group.com.devuap.vikey"
    /// Reads of the shared defaults; the performance tests check typing never reads them.
    static var reads = 0
    static var defaults: UserDefaults { reads += 1; return UserDefaults(suiteName: group) ?? .standard }

    enum Key {
        static let autoSwitch = "AutoSwitchByTyping"
        static let pauseAfterManual = "PauseAutoAfterManual"
        static let modernOrthography = "ModernOrthography"
        static let spelling = "Spelling"
        static let restoreIfInvalid = "RestoreIfInvalidWord"
        static let englishForWebFields = "EnglishForWebFields"
        static let autoCapitalize = "AutoCapitalize"
        static let doubleSpacePeriod = "DoubleSpacePeriod"
    }

    static let defaultValues: [String: Any] = [
        Key.autoSwitch: true, Key.pauseAfterManual: true, Key.modernOrthography: true, Key.spelling: true,
        Key.restoreIfInvalid: true, Key.englishForWebFields: true,
        Key.autoCapitalize: true, Key.doubleSpacePeriod: true,
    ]

    static func register() { defaults.register(defaults: defaultValues) }
    static func bool(_ key: String) -> Bool { register(); return defaults.bool(forKey: key) }
}
