import WidgetKit
import SwiftUI

@main
struct FocusReaderWidgetBundle: WidgetBundle {
    var body: some Widget {
        FocusReaderHomeWidget()         // iPhone 홈 화면 위젯
        FocusReaderWidgetLiveActivity() // 💡 라이브 액티비티
        FocusReaderWidgetControl()      // 💡 iOS 18 제어 센터 위젯
    }
}
