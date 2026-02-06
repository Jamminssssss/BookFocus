import SwiftUI
import StoreKit

struct PurchaseView: View {
    @StateObject private var storeManager = StoreKitManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    purchaseFlowView
                }
            }
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: { Text("Close") }
                }
            }
        }
        .onAppear {
            Task { await storeManager.requestProducts() }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }
    
    // MARK: - Purchase Flow View
    private var purchaseFlowView: some View {
        VStack(spacing: 40) {
            // 헤더
            VStack(spacing: 16) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.yellow, Color.orange]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.top, 30)
                
                Text("Unlock Premium")
                    .font(.system(size: 34, weight: .bold))
                
                Text("One-time payment, lifetime access")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // 기능 카드들
            VStack(spacing: 16) {
                FeatureCard(
                    icon: "books.vertical.fill",
                    title: NSLocalizedString("premium.feature.books.title", comment: ""),
                    description: NSLocalizedString("premium.feature.books.description", comment: ""),
                    gradientColors: [Color.blue, Color.cyan]
                )
                
                FeatureCard(
                    icon: "note.text",
                    title: NSLocalizedString("premium.feature.notes.title", comment: ""),
                    description: NSLocalizedString("premium.feature.notes.description", comment: ""),
                    gradientColors: [Color.purple, Color.pink]
                )
                
                FeatureCard(
                    icon: "sparkles",
                    title: NSLocalizedString("premium.feature.adfree.title", comment: ""),
                    description: NSLocalizedString("premium.feature.adfree.description", comment: ""),
                    gradientColors: [Color.orange, Color.red]
                )
                
                FeatureCard(
                    icon: "chart.bar.fill",
                    title: NSLocalizedString("premium.feature.stats.title", comment: ""),
                    description: NSLocalizedString("premium.feature.stats.description", comment: ""),
                    gradientColors: [Color.green, Color.mint]
                )
            }
            .padding(.horizontal, 20)
            
            // 구매 버튼
            VStack(spacing: 16) {
                if storeManager.isPremium {
                    // 결제 완료 버튼
                    Button {} label: {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                            Text("Premium Unlocked")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.green, Color.mint]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(16)
                    }
                    .disabled(true)
                } else if let premiumProduct = storeManager.products.first {
                    // 구매 버튼
                    Button {
                        Task {
                            do {
                                try await storeManager.purchasePremium()
                                if storeManager.isPremium {
                                    alertTitle = "Welcome to Premium!"
                                    alertMessage = "All features are now unlocked."
                                    showAlert = true
                                }
                            } catch StoreError.userCancelled {
                                print("Purchase cancelled")
                            } catch {
                                alertTitle = "Purchase Failed"
                                alertMessage = error.localizedDescription
                                showAlert = true
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            if storeManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "lock.open.fill")
                                    .font(.system(size: 20))
                                Text("Unlock for \(premiumProduct.displayPrice)")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.purple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    .disabled(storeManager.isLoading)
                } else {
                    ProgressView("Loading products…")
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }

                Button {
                    Task { await restorePurchases() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                        Text("Restore Purchases")
                            .font(.system(size: 15, weight: .medium))
                    }
                }
                .foregroundColor(.blue)
                .disabled(storeManager.isLoading)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }
    
    // MARK: - Restore
    @MainActor private func restorePurchases() async {
        do {
            try await storeManager.restorePurchases()
            alertTitle = "Restore Purchases"
            alertMessage = storeManager.isPremium ?
                "Your premium features have been restored!" :
                "No previous purchase found."
            showAlert = true
        } catch {
            alertTitle = "Restore Failed"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
}

// MARK: - Feature Card
struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String
    let gradientColors: [Color]
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: gradientColors),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}
