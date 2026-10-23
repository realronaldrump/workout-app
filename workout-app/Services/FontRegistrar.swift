import CoreText
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum FontRegistrar {
    private static var didRegister = false

    private static let bundledFonts = [
        "BigShouldersDisplay-SemiBold",
        "BigShouldersDisplay-Bold",
        "BigShouldersDisplay-ExtraBold",
        "BigShouldersDisplay-Black",
        "Barlow-Regular",
        "Barlow-Medium",
        "Barlow-SemiBold",
        "Barlow-Bold"
    ]

    static func registerFontsIfNeeded() {
        guard !didRegister else { return }
        didRegister = true

        // If the bundled fonts are already available (e.g. via UIAppFonts in
        // Info.plist), don't re-register them and produce duplicate logs.
        #if canImport(UIKit)
        if bundledFonts.allSatisfy({ UIFont(name: $0, size: 12) != nil }) {
            return
        }
        #endif

        bundledFonts.forEach { registerFont(named: $0, ext: "ttf") }
    }

    private static func registerFont(named name: String, ext: String) {
        let candidateURLs: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: ext),
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/Fonts"),
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Fonts")
        ]

        guard let url = candidateURLs.compactMap({ $0 }).first else {
            // If UIAppFonts is configured correctly, this registration isn't required.
            return
        }

        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }
}
