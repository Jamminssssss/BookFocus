import SwiftUI
import Combine
import StoreKit

// MARK: - App Themes
enum AppTheme: String, CaseIterable {
    case basic = "basic"
    case summer = "summer"
    
    // ⭐️ Localized: 테마 타이틀을 다국어 지원하도록 수정
    var title: String {
        switch self {
        case .basic: return NSLocalizedString("basic.", comment: "Basic theme title")
        case .summer: return NSLocalizedString("summer.", comment: "Summer theme title")
        }
    }
    
    // 💡 실제 StoreKit Product ID 매핑
    var productID: String? {
        switch self {
        case .basic: return nil
        case .summer: return "com.Jaemin.FocusReader.theme.summer"
        }
    }
    
    // 테마별 배경색
    func paperColor(isDark: Bool) -> Color {
        switch self {
        case .basic:
            return isDark ? Color.black : Color(red: 0.98, green: 0.97, blue: 0.95)
        case .summer:
            return isDark ? Color(red: 0.0, green: 0.08, blue: 0.15) : Color(red: 0.88, green: 0.96, blue: 0.98)
        }
    }
    
    // 테마별 펜/테두리 색상
    func inkColor(isDark: Bool) -> Color {
        switch self {
        case .basic:
            return isDark ? Color.white : Color.black
        case .summer:
            return isDark ? Color(red: 0.5, green: 0.85, blue: 0.98) : Color(red: 0.0, green: 0.25, blue: 0.5)
        }
    }
}

// MARK: - Theme Manager
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @Published var currentTheme: AppTheme {
        didSet { UserDefaults.standard.set(currentTheme.rawValue, forKey: "selectedTheme") }
    }
    @Published var unlockedThemes: Set<String> {
        didSet { UserDefaults.standard.set(Array(unlockedThemes), forKey: "unlockedThemes") }
    }
    
    init() {
        let savedTheme = UserDefaults.standard.string(forKey: "selectedTheme") ?? "basic"
        self.currentTheme = AppTheme(rawValue: savedTheme) ?? .basic
        
        let savedUnlocked = UserDefaults.standard.stringArray(forKey: "unlockedThemes") ?? ["basic"]
        self.unlockedThemes = Set(savedUnlocked)
    }
    
    func unlockAndApply(theme: AppTheme) {
        unlockedThemes.insert(theme.rawValue)
        currentTheme = theme
    }
    
    func apply(theme: AppTheme) {
        currentTheme = theme
    }
    
    // 로컬 UserDefaults 또는 StoreKitManager의 영구 구매 기록을 둘 다 확인하여 잠금 해제 여부 판단
    func isUnlocked(theme: AppTheme) -> Bool {
        if theme == .basic { return true }
        if unlockedThemes.contains(theme.rawValue) { return true }
        
        if let productID = theme.productID {
            return StoreKitManager.shared.hasPurchasedTheme(id: productID)
        }
        return false
    }
}

// MARK: - Theme Selection & Purchase View
struct ThemeSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var themeManager = ThemeManager.shared
    
    // 💡 StoreKitManager 연동
    @StateObject private var storeManager = StoreKitManager.shared
    @State private var purchasingTheme: AppTheme? = nil
    
    @State private var showError = false
    @State private var errorMessage = ""
    
    var paperColor: Color { themeManager.currentTheme.paperColor(isDark: colorScheme == .dark) }
    var inkColor: Color { themeManager.currentTheme.inkColor(isDark: colorScheme == .dark) }
    
    var body: some View {
        NavigationStack {
            ZStack {
                paperColor.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.title2).foregroundStyle(inkColor)
                        }
                        Spacer()
                        Text("themes.").font(.custom("ChalkboardSE-Bold", size: 20)).foregroundStyle(inkColor)
                        Spacer()
                        
                        // 복원 버튼 (테마 재설치 시 구매 내역 복원용)
                        Button {
                            Task { await restorePurchases() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.title2)
                                .foregroundStyle(inkColor)
                        }
                        .disabled(storeManager.isLoading)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            ForEach(AppTheme.allCases, id: \.self) { theme in
                                themeCard(for: theme)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarHidden(true)
            // ⭐️ Localized: 알림창 타이틀 및 버튼 로컬라이징
            .alert(NSLocalizedString("Oops", comment: "Error alert title"), isPresented: $showError) {
                Button(NSLocalizedString("OK", comment: "Alert confirm button"), role: .cancel) {}
            } message: {
                Text(errorMessage).font(.custom("ChalkboardSE-Regular", size: 14))
            }
        }
    }
    
    private func themeCard(for theme: AppTheme) -> some View {
        let isDark = colorScheme == .dark
        let cardPaper = theme.paperColor(isDark: isDark)
        let cardInk = theme.inkColor(isDark: isDark)
        let isSelected = themeManager.currentTheme == theme
        let isUnlocked = themeManager.isUnlocked(theme: theme)
        
        return VStack(spacing: 0) {
            ZStack {
                cardPaper
                VStack(spacing: 12) {
                    Text("Aa").font(.custom("ChalkboardSE-Bold", size: 40)).foregroundStyle(cardInk)
                    Text(theme.title).font(.custom("ChalkboardSE-Regular", size: 16)).foregroundStyle(cardInk)
                }
            }
            .frame(height: 120)
            
            HStack {
                Text(theme.title)
                    .font(.custom("ChalkboardSE-Bold", size: 16))
                    .foregroundStyle(inkColor)
                
                Spacer()
                
                Button {
                    handleThemeAction(theme: theme)
                } label: {
                    HStack {
                        if purchasingTheme == theme {
                            ProgressView().tint(inkColor).scaleEffect(0.8)
                        } else {
                            // ⭐️ Localized: 버튼 상태별 텍스트 다국어 처리
                            let buttonText = isSelected ? NSLocalizedString("selected", comment: "Theme selected status") : (isUnlocked ? NSLocalizedString("apply", comment: "Apply theme button") : priceString(for: theme))
                            Text(buttonText)
                                .font(.custom("ChalkboardSE-Bold", size: 14))
                        }
                    }
                    // 가격 텍스트 길이에 맞춰 유연하게 조절되도록 최소 너비 지정
                    .frame(minWidth: 80)
                    .frame(height: 32)
                    .padding(.horizontal, 12)
                    .foregroundStyle(isSelected ? paperColor : inkColor)
                    .background(isSelected ? inkColor : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(inkColor, lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(isSelected || purchasingTheme != nil)
            }
            .padding(16)
            .background(paperColor)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(inkColor, lineWidth: isSelected ? 3 : 1.5))
        .shadow(color: inkColor == .black ? .black.opacity(0.05) : .white.opacity(0.05), radius: 0, x: 4, y: 4)
    }
    
    // 💡 실제 StoreKit에서 불러온 가격 정보 표시 (⭐️ Localized)
    private func priceString(for theme: AppTheme) -> String {
        if theme == .basic { return NSLocalizedString("free", comment: "Free theme price label") }
        guard let productID = theme.productID,
              let product = storeManager.themeProducts.first(where: { $0.id == productID }) else {
            return NSLocalizedString("loading...", comment: "Loading price status")
        }
        return product.displayPrice
    }
    
    // 💡 실제 애플 인앱 결제 연동
    private func handleThemeAction(theme: AppTheme) {
        if themeManager.isUnlocked(theme: theme) {
            withAnimation(.easeInOut(duration: 0.3)) {
                themeManager.apply(theme: theme)
            }
        } else {
            guard let productID = theme.productID,
                  let product = storeManager.themeProducts.first(where: { $0.id == productID }) else {
                // ⭐️ Localized: 에러 메시지
                errorMessage = NSLocalizedString("Theme product not found. Please check your internet connection.", comment: "Product not found error")
                showError = true
                return
            }
            
            purchasingTheme = theme
            
            Task {
                do {
                    try await storeManager.purchase(product)
                    // 결제 완료 후 검증
                    if storeManager.hasPurchasedTheme(id: productID) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            themeManager.unlockAndApply(theme: theme)
                        }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                } catch StoreError.userCancelled {
                    print("사용자가 구매를 취소했습니다.")
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                }
                purchasingTheme = nil
            }
        }
    }
    
    @MainActor private func restorePurchases() async {
        do {
            try await storeManager.restorePurchases()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            // ⭐️ Localized: 복원 실패 에러 메시지 포맷팅
            let formatString = NSLocalizedString("Failed to restore purchases: %@", comment: "Restore purchase error format")
            errorMessage = String(format: formatString, error.localizedDescription)
            showError = true
        }
    }
}
