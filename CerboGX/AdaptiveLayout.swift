import SwiftUI

enum AdaptiveLayout {
    static func usesPadConsole(_ horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        horizontalSizeClass == .regular
    }

    static let padSidebarWidth: CGFloat = 96
    static let padDetailMaxWidth: CGFloat = 880
}
