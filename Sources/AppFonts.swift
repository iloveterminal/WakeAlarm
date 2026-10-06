import AppKit
import CoreText
import Foundation
import SwiftUI

enum AppFonts {
    static func registerBundledFonts() {
        guard let fontsURL = Bundle.main.resourceURL?.appendingPathComponent("Fonts", isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(
                at: fontsURL,
                includingPropertiesForKeys: nil
              )
        else { return }

        for url in files where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func digital(size: CGFloat) -> Font {
        // PostScript name from DSEG7Classic-Bold.ttf
        if NSFont(name: "DSEG7Classic-Bold", size: size) != nil {
            return .custom("DSEG7Classic-Bold", size: size)
        }
        if NSFont(name: "DSEG7 Classic", size: size) != nil {
            return .custom("DSEG7 Classic", size: size)
        }
        return .system(size: size, weight: .bold, design: .monospaced)
    }
}
