import CoreText
import Foundation

enum FontRegistrar {
    private static var didRegister = false

    static func registerFontsIfNeeded() {
        guard !didRegister else { return }
        didRegister = true

        registerFont(named: "BebasNeue-Regular", ext: "ttf")
    }

    private static func registerFont(named name: String, ext: String) {
        let candidateURLs: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: ext),
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/Fonts"),
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Fonts"),
        ]

        guard let url = candidateURLs.compactMap({ $0 }).first else {
            // If UIAppFonts is configured correctly, this registration isn't required.
            return
        }

        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }
}

