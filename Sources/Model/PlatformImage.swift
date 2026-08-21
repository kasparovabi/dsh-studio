import SwiftUI

#if canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

extension Image {
    init(platform image: PlatformImage) {
        #if canImport(AppKit)
        self.init(nsImage: image)
        #else
        self.init(uiImage: image)
        #endif
    }
}
