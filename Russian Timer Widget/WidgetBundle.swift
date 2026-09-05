import WidgetKit
import SwiftUI

@main
struct RussianWidgetBundle: WidgetBundle {
    var body: some Widget {
        RussianTimerWidget()
        #if os(iOS)
        RussianTimerLiveActivity()
        #endif
        if #available(iOS 18.0, macOS 26.0, *) {
            RussianTimerControl()
        }
    }
}
