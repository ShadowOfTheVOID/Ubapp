import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var ads = AdManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                group(title: "Hosting",
                      footer: "The name other players see when you host. Defaults to “Host” if left blank.") {
                    HStack {
                        Text("Host name")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                        Spacer()
                        TextField("", text: $settings.hostName,
                                  prompt: Text("Host").foregroundColor(UbappTheme.faint))
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 15))
                            .foregroundStyle(UbappTheme.accent)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .ubCard()
                }

                group(title: "Developer",
                      footer: "Shows the host connection log on the hosting screen. Useful for debugging join issues.") {
                    Toggle(isOn: $settings.diagnosticsEnabled) {
                        Text("Diagnostics")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                    }
                    .tint(UbappTheme.accent)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .ubCard()
                }

                group(title: "Upgrade",
                      footer: "One-time purchase. Removes all ad banners and post-game interstitials permanently. No content is locked.") {
                    if ads.isAdFree {
                        HStack {
                            Text("Remove Ads")
                                .font(.system(size: 15)).foregroundStyle(.white)
                            Spacer()
                            Text("Purchased ✓")
                                .font(.system(size: 13)).foregroundStyle(UbappTheme.accent)
                        }
                        .padding(.vertical, 14).padding(.horizontal, 16)
                        .ubCard()
                    } else {
                        VStack(spacing: 10) {
                            Button {
                                ads.purchase()
                            } label: {
                                HStack {
                                    Text("Remove Ads")
                                        .font(.system(size: 15)).foregroundStyle(.white)
                                    Spacer()
                                    if ads.isPurchasing {
                                        ProgressView().tint(UbappTheme.accent)
                                    } else {
                                        Text("$2.99")
                                            .font(.system(size: 13)).foregroundStyle(UbappTheme.accent)
                                    }
                                }
                                .padding(.vertical, 14).padding(.horizontal, 16)
                                .ubCard()
                            }
                            .buttonStyle(.plain)
                            .disabled(ads.isPurchasing)
                            Button("Restore Purchase") { ads.restorePurchases() }
                                .font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
                                .disabled(ads.isPurchasing)
                        }
                        if let err = ads.purchaseError {
                            Text(err)
                                .font(.system(size: 12)).foregroundStyle(UbappTheme.accent)
                        }
                    }
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .ubappChrome()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func group<Content: View>(title: String, footer: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel(title)
            content()
            Text(footer)
                .font(.system(size: 12))
                .foregroundStyle(UbappTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
