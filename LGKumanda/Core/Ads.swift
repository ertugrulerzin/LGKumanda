import SwiftUI
import GoogleMobileAds
import UserMessagingPlatform

/// Banner ads (AdMob) with Google's consent form (UMP) for regions that require it.
/// Ads stay off until the build carries an ad unit ID; DEBUG builds use Google's test unit.
@MainActor final class AdsManager: ObservableObject {
    static let shared = AdsManager()
    /// True once consent allows ad requests and the SDK has started.
    @Published private(set) var ready = false
    /// The app shows a "privacy options" entry when the consent form must stay reachable.
    @Published private(set) var privacyOptionsRequired = false
    private var started = false

    nonisolated static let googleTestBannerUnit = "ca-app-pub-3940256099942544/2435281174"
    /// Banner unit from Info.plist (KumandaBannerAdUnitID); nil disables ads.
    nonisolated static var bannerUnitID: String? {
        let configured = (Bundle.main.object(forInfoDictionaryKey: "KumandaBannerAdUnitID") as? String)?
            .trimmingCharacters(in: .whitespaces)
        if let configured, configured.hasPrefix("ca-app-pub-") {
            // TestFlight installs show Google's test ads so testers never generate invalid traffic.
            return isTestFlight ? googleTestBannerUnit : configured
        }
        #if DEBUG
        return googleTestBannerUnit
        #else
        return nil
        #endif
    }
    /// TestFlight builds carry a sandbox App Store receipt.
    nonisolated static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }
    /// Screenshots, UI tests and builds without an ad unit show no ads.
    var enabled: Bool {
        let env = ProcessInfo.processInfo.environment
        if env.keys.contains(where: { $0.hasPrefix("UITEST") }) || ProcessInfo.processInfo.arguments.contains("-uiTesting") { return false }
        return Self.bannerUnitID != nil
    }

    func start() {
        guard enabled, !started else { return }
        started = true
        ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) { [weak self] _ in
            Task { @MainActor in
                // Present the form only where the user's region requires it; failure still allows limited ads.
                try? await ConsentForm.loadAndPresentIfRequired(from: nil)
                self?.consentFinished()
            }
        }
        // Consent from an earlier launch lets ads start without waiting for the update.
        if ConsentInformation.shared.canRequestAds { startSDK() }
    }
    private func consentFinished() {
        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        if ConsentInformation.shared.canRequestAds { startSDK() }
    }
    private func startSDK() {
        guard !ready else { return }
        MobileAds.shared.start { [weak self] _ in Task { @MainActor in self?.ready = true } }
    }
    func showPrivacyOptions() async throws {
        try await ConsentForm.presentPrivacyOptionsForm(from: nil)
        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }
}

/// Adaptive banner pinned above the tab bar; collapses to nothing until an ad loads.
struct AdBanner: View {
    @ObservedObject private var ads = AdsManager.shared
    @State private var loaded = false
    var body: some View {
        if ads.ready, let unit = AdsManager.bannerUnitID {
            GeometryReader { proxy in
                let size = currentOrientationAnchoredAdaptiveBanner(width: proxy.size.width)
                BannerContainer(unitID: unit, size: size, loaded: $loaded)
                    .frame(width: size.size.width, height: size.size.height)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: loaded ? currentOrientationAnchoredAdaptiveBanner(width: UIScreen.main.bounds.width).size.height : 0)
            .clipped()
            .accessibilityLabel("Reklam")
        }
    }
}

private struct BannerContainer: UIViewRepresentable {
    let unitID: String
    let size: AdSize
    @Binding var loaded: Bool
    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: size)
        banner.adUnitID = unitID
        banner.delegate = context.coordinator
        banner.load(Request())
        return banner
    }
    func updateUIView(_ view: BannerView, context: Context) {
        if !isAdSizeEqualToSize(size1: view.adSize, size2: size) { view.adSize = size }
    }
    func makeCoordinator() -> Coordinator { Coordinator(loaded: $loaded) }
    final class Coordinator: NSObject, BannerViewDelegate {
        let loaded: Binding<Bool>
        init(loaded: Binding<Bool>) { self.loaded = loaded }
        func bannerViewDidReceiveAd(_ bannerView: BannerView) { loaded.wrappedValue = true }
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) { loaded.wrappedValue = false }
    }
}

extension View {
    /// Adds the banner at the bottom of a tab, above the tab bar.
    func adBanner() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { AdBanner() }
    }
}
