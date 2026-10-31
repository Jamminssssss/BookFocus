import SwiftUI
import StoreKit

struct PurchaseView: View {
    @StateObject private var storeManager = StoreKitManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedProductID: String?
    @State private var introEligibleProductIDs: Set<String> = []
    @State private var hasCheckedOfferEligibility = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    private var paperColor: Color {
        themeManager.currentTheme.paperColor(isDark: colorScheme == .dark)
    }
    private var inkColor: Color {
        themeManager.currentTheme.inkColor(isDark: colorScheme == .dark)
    }
    private var selectedProduct: Product? {
        storeManager.products.first { $0.id == selectedProductID }
    }
    private var annualProduct: Product? {
        storeManager.products.first { $0.subscription?.subscriptionPeriod.unit == .year }
    }
    private var monthlyProduct: Product? {
        storeManager.products.first { $0.subscription?.subscriptionPeriod.unit == .month }
    }

    var body: some View {
        ZStack {
            paperColor.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    header
                    hero
                    benefits

                    if storeManager.isPremium {
                        premiumActiveCard
                    } else {
                        purchaseSection
                    }
                    footer
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
        }
        .task {
            if storeManager.products.isEmpty { await storeManager.requestProducts() }
            configureDefaultPlan()
            await refreshOfferEligibility()
        }
        .onChange(of: storeManager.products.map(\.id)) { _, _ in
            configureDefaultPlan()
            Task { await refreshOfferEligibility() }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    private var header: some View {
        HStack {
            Text("premium.")
                .font(.custom("ChalkboardSE-Bold", size: 20))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(inkColor.opacity(0.07), in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .foregroundStyle(inkColor)
        .padding(.top, 10)
    }

    private var hero: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(inkColor).frame(width: 72, height: 72)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(paperColor)
                Circle()
                    .stroke(paperColor.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                    .frame(width: 62, height: 62)
                    .rotationEffect(.degrees(-8))
            }
            Text("unlock premium.")
                .font(.custom("ChalkboardSE-Bold", size: 31))
                .foregroundStyle(inkColor)
                .multilineTextAlignment(.center)
            Text(heroSubtitle)
                .font(.custom("ChalkboardSE-Regular", size: 16))
                .foregroundStyle(inkColor.opacity(0.68))
                .multilineTextAlignment(.center)
        }
    }

    private var benefits: some View {
        VStack(spacing: 0) {
            BenefitRow(icon: "books.vertical.fill", title: NSLocalizedString("premium.feature.books.title", value: "Unlimited Books", comment: "Premium benefit"), description: NSLocalizedString("premium.feature.books.description", value: "Add as many books as you want.", comment: "Premium benefit"), inkColor: inkColor)
            divider
            BenefitRow(icon: "shield.lefthalf.filled", title: NSLocalizedString("premium.feature.focus.title", value: "Focus Mode", comment: "Premium benefit"), description: NSLocalizedString("premium.feature.focus.description", value: "Block distracting apps while reading.", comment: "Premium benefit"), inkColor: inkColor)
            divider
            BenefitRow(icon: "square.and.arrow.down.fill", title: NSLocalizedString("premium.feature.goodreads.title", value: "Goodreads Import", comment: "Premium benefit"), description: NSLocalizedString("premium.feature.goodreads.description", value: "Bring your reading history in seconds.", comment: "Premium benefit"), inkColor: inkColor)
            divider
            BenefitRow(icon: "chart.bar.xaxis", title: NSLocalizedString("premium.feature.insights.title", value: "Reading Insights", comment: "Premium benefit"), description: NSLocalizedString("premium.feature.insights.description", value: "Discover your trends, streaks, and reading rhythm.", comment: "Premium benefit"), inkColor: inkColor)
        }
        .padding(.horizontal, 18)
        .background(inkColor.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(inkColor.opacity(0.12), lineWidth: 1) }
    }

    private var divider: some View {
        Rectangle().fill(inkColor.opacity(0.1)).frame(height: 1).padding(.leading, 46)
    }

    private var purchaseSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Choose your plan")
                    .font(.custom("ChalkboardSE-Bold", size: 19))
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(inkColor.opacity(0.45))
            }

            if storeManager.products.isEmpty && storeManager.isLoading {
                ProgressView()
                    .tint(inkColor)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if storeManager.products.isEmpty {
                productLoadError
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else {
                VStack(spacing: 12) {
                    ForEach(storeManager.products.sorted(by: planSort), id: \.id) { product in
                        PlanOptionCard(
                            product: product,
                            isSelected: selectedProductID == product.id,
                            isRecommended: product.id == annualProduct?.id,
                            savingsText: savingsText(for: product),
                            priceText: recurringPrice(for: product),
                            inkColor: inkColor,
                            paperColor: paperColor
                        ) {
                            withAnimation(.easeOut(duration: 0.18)) { selectedProductID = product.id }
                        }
                    }
                }

                Rectangle()
                    .fill(inkColor.opacity(0.12))
                    .frame(height: 1)

                purchaseAction
            }
        }
        .foregroundStyle(inkColor)
        .padding(18)
        .background(inkColor.opacity(0.045), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(inkColor.opacity(0.14), lineWidth: 1.2)
        }
        .animation(.easeOut(duration: 0.2), value: selectedProductID)
    }

    private var premiumActiveCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
            Text("premium active").font(.custom("ChalkboardSE-Bold", size: 18))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .foregroundStyle(inkColor)
        .background(inkColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }

    private var productLoadError: some View {
        VStack(spacing: 10) {
            Text("Plans are temporarily unavailable.")
                .font(.custom("ChalkboardSE-Regular", size: 15))
                .foregroundStyle(inkColor.opacity(0.7))
            Button("try again") { Task { await storeManager.requestProducts() } }
                .font(.custom("ChalkboardSE-Bold", size: 15))
                .foregroundStyle(inkColor)
        }
    }

    private var purchaseAction: some View {
        VStack(spacing: 10) {
            if let product = selectedProduct {
                Button { purchase(product: product) } label: {
                    HStack(spacing: 14) {
                        if storeManager.isLoading {
                            ProgressView().tint(paperColor)
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(isTrialEligible(product) ? "Start 3-Day Free Trial" : "Continue")
                                    .font(.custom("ChalkboardSE-Bold", size: 18))
                                Text("\(product.displayName) · \(recurringPrice(for: product))")
                                    .font(.custom("ChalkboardSE-Regular", size: 12))
                                    .foregroundStyle(paperColor.opacity(0.72))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 32, height: 32)
                                .foregroundStyle(inkColor)
                                .background(paperColor, in: Circle())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .padding(.horizontal, 18)
                    .foregroundStyle(paperColor)
                    .background(inkColor, in: RoundedRectangle(cornerRadius: 17))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17)
                            .stroke(paperColor.opacity(0.25), style: StrokeStyle(lineWidth: 1.1, dash: [7, 4]))
                            .padding(4)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 17)
                            .stroke(inkColor.opacity(0.42), lineWidth: 1)
                            .rotationEffect(.degrees(-0.45))
                    }
                }
                .buttonStyle(.plain)
                .disabled(storeManager.isLoading)
                .opacity(storeManager.isLoading ? 0.72 : 1)
                Text(billingDisclosure(for: product))
                    .font(.custom("ChalkboardSE-Regular", size: 12))
                    .foregroundStyle(inkColor.opacity(0.58))
                    .multilineTextAlignment(.center)
            } else if storeManager.isLoading {
                ProgressView().tint(inkColor).frame(height: 58)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Button { Task { await restorePurchases() } } label: {
                Label("restore purchases", systemImage: "arrow.clockwise")
                    .font(.custom("ChalkboardSE-Regular", size: 15))
            }
            .foregroundStyle(inkColor.opacity(0.75))
            .disabled(storeManager.isLoading)
            Text("cancel anytime in apple ID settings.")
                .font(.custom("ChalkboardSE-Regular", size: 12))
                .foregroundStyle(inkColor.opacity(0.5))
            HStack(spacing: 12) {
                Link("terms of use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Text("•")
                Link("privacy policy", destination: URL(string: "https://www.notion.so")!)
            }
            .font(.custom("ChalkboardSE-Regular", size: 12))
            .foregroundStyle(inkColor.opacity(0.5))
        }
    }

    private var heroSubtitle: String {
        guard hasCheckedOfferEligibility,
              let selectedProduct,
              isTrialEligible(selectedProduct) else {
            return NSLocalizedString("Everything you need to build a lasting reading habit.", comment: "Premium value proposition")
        }
        return NSLocalizedString("start your 3-day free trial, then subscribe.", comment: "")
    }
    private func planSort(_ lhs: Product, _ rhs: Product) -> Bool {
        if lhs.id == annualProduct?.id { return true }
        if rhs.id == annualProduct?.id { return false }
        return lhs.price < rhs.price
    }
    private func configureDefaultPlan() {
        guard !storeManager.products.isEmpty else { return }
        if selectedProduct == nil { selectedProductID = annualProduct?.id ?? storeManager.products.first?.id }
    }

    @MainActor private func refreshOfferEligibility() async {
        var eligibleIDs: Set<String> = []
        for product in storeManager.products {
            guard product.subscription?.introductoryOffer?.paymentMode == .freeTrial,
                  let subscription = product.subscription else { continue }
            if await subscription.isEligibleForIntroOffer { eligibleIDs.insert(product.id) }
        }
        introEligibleProductIDs = eligibleIDs
        hasCheckedOfferEligibility = true
    }
    private func isTrialEligible(_ product: Product) -> Bool {
        introEligibleProductIDs.contains(product.id)
    }
    private func savingsText(for product: Product) -> String? {
        guard product.id == annualProduct?.id, let monthlyProduct else { return nil }
        let fullYearPrice = monthlyProduct.price * Decimal(12)
        guard fullYearPrice > product.price else { return nil }
        let savings = (fullYearPrice - product.price) / fullYearPrice * Decimal(100)
        let monthlyEquivalent = (product.price / Decimal(12)).formatted(product.priceFormatStyle)
        return String(
            format: NSLocalizedString("Save %@ · %@/month", comment: "Annual plan savings and monthly equivalent"),
            (Double(NSDecimalNumber(decimal: savings).intValue) / 100).formatted(.percent.precision(.fractionLength(0))),
            monthlyEquivalent
        )
    }
    private func billingDisclosure(for product: Product) -> String {
        if isTrialEligible(product) {
            return String(format: NSLocalizedString("Free for 3 days, then %@. Renews automatically.", comment: "Trial billing disclosure"), recurringPrice(for: product))
        }
        return String(format: NSLocalizedString("%@. Renews automatically until canceled.", comment: "Subscription billing disclosure"), recurringPrice(for: product))
    }
    private func recurringPrice(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return product.displayPrice }
        return "\(product.displayPrice)/\(periodLabel(period))"
    }
    private func periodLabel(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day: return period.value == 1 ? NSLocalizedString("day", comment: "") : String(localized: "\(period.value) days")
        case .week: return period.value == 1 ? NSLocalizedString("week", comment: "") : String(localized: "\(period.value) weeks")
        case .month: return period.value == 1 ? NSLocalizedString("month", comment: "") : String(localized: "\(period.value) months")
        case .year: return period.value == 1 ? NSLocalizedString("year", comment: "") : String(localized: "\(period.value) years")
        @unknown default: return ""
        }
    }

    private func purchase(product: Product) {
        Task {
            do {
                try await storeManager.purchase(product)
                if storeManager.isPremium {
                    alertTitle = NSLocalizedString("Welcome!", comment: "")
                    alertMessage = NSLocalizedString("Premium features are now unlocked.", comment: "")
                    showAlert = true
                }
            } catch StoreError.userCancelled {
                // Cancellation is intentional and does not need an error alert.
            } catch {
                alertTitle = NSLocalizedString("Purchase Failed", comment: "")
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }

    @MainActor private func restorePurchases() async {
        do {
            try await storeManager.restorePurchases()
            alertTitle = NSLocalizedString("Restore Purchases", comment: "")
            alertMessage = storeManager.isPremium
                ? NSLocalizedString("Your premium subscription has been restored!", comment: "")
                : NSLocalizedString("No active subscription found.", comment: "")
            showAlert = true
        } catch {
            alertTitle = NSLocalizedString("Restore Failed", comment: "")
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
}

private struct BenefitRow: View {
    let icon: String
    let title: String
    let description: String
    let inkColor: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 19, weight: .medium)).frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.custom("ChalkboardSE-Bold", size: 16))
                Text(description)
                    .font(.custom("ChalkboardSE-Regular", size: 13))
                    .foregroundStyle(inkColor.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(inkColor)
        .padding(.vertical, 14)
    }
}

private struct PlanOptionCard: View {
    let product: Product
    let isSelected: Bool
    let isRecommended: Bool
    let savingsText: String?
    let priceText: String
    let inkColor: Color
    let paperColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(product.displayName).font(.custom("ChalkboardSE-Bold", size: 17))
                        if isRecommended {
                            Text("BEST VALUE")
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .tracking(0.5)
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .foregroundStyle(isSelected ? inkColor : paperColor)
                                .background(isSelected ? paperColor.opacity(0.9) : inkColor, in: Capsule())
                        }
                    }
                    if let savingsText {
                        Text(savingsText).font(.custom("ChalkboardSE-Regular", size: 13)).opacity(0.68)
                    }
                }
                Spacer(minLength: 8)
                Text(priceText)
                    .font(.custom("ChalkboardSE-Bold", size: 17))
                    .multilineTextAlignment(.trailing)
            }
            .foregroundStyle(isSelected ? paperColor : inkColor)
            .padding(17)
            .background(isSelected ? inkColor : Color.clear, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(inkColor.opacity(isSelected ? 1 : 0.22), lineWidth: isSelected ? 2 : 1.3) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
