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
                VStack(spacing: 30) {
                    // 헤더
                    VStack(spacing: 12) {
                        Text("Unlock Premium")
                            .font(.largeTitle).bold()
                        Text("One-time payment, no subscription")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Get unlimited books, notes, and remove ads. Enjoy full reading stats!")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                    .padding(.top, 20)
                    
                    // 무료 vs 프리미엄 비교 (아이콘 제거, 카드 스타일)
                    VStack(spacing: 12) {
                        ComparisonRow(
                            title: "Books you can add",
                            freeValue: "1 book",
                            premiumValue: "Unlimited"
                        )
                        
                        ComparisonRow(
                            title: "Notes and memos",
                            freeValue: "Limited",
                            premiumValue: "Unlimited"
                        )
                        
                        ComparisonRow(
                            title: "Ads",
                            freeValue: "Shown",
                            premiumValue: "Removed"
                        )
                        
                    }
                    .padding(.horizontal, 20)
                    
                    // 구매 버튼
                    VStack(spacing: 16) {
                        // 비소모품 가격 표시
                        if let premiumProduct = storeManager.products.first {
                            Button {
                                guard !storeManager.isPremium else { return }
                                Task {
                                    do {
                                        try await storeManager.purchasePremium()
                                        if storeManager.isPremium {
                                            alertTitle = "Purchase Success"
                                            alertMessage = "Thank you for unlocking premium features!"
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
                                HStack {
                                    if storeManager.isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.9)
                                    } else if storeManager.isPremium {
                                        Text("Purchased")
                                            .fontWeight(.semibold)
                                    } else {
                                        // 🌎 나라별 가격 표시
                                        Text("Unlock Premium (\(premiumProduct.displayPrice))")
                                            .fontWeight(.semibold)
                                    }
                                }
                            }
                            .buttonStyle(GradientButtonStyle())
                            .disabled(storeManager.isLoading)
                        } else {
                            ProgressView("Loading products…")
                        }

                        Button {
                            Task { await restorePurchases() }
                        } label: {
                            Text("Restore Purchases")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(storeManager.isLoading)
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer(minLength: 40)
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

// MARK: - ComparisonRow (아이콘 제거, 카드 스타일)
struct ComparisonRow: View {
    let title: String
    let freeValue: String
    let premiumValue: String
    
    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack {
                VStack(spacing: 2) {
                    Text("Free")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(freeValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                VStack(spacing: 2) {
                    Text("Premium")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    Text(premiumValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - GradientButtonStyle
struct GradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                LinearGradient(gradient: Gradient(colors: [Color.blue, Color.purple]), startPoint: .leading, endPoint: .trailing)
            )
            .foregroundColor(.white)
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}


struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue, lineWidth: 1))
            .foregroundColor(.blue)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
