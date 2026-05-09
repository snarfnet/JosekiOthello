import GoogleMobileAds

class InterstitialAdManager: NSObject, ObservableObject, FullScreenContentDelegate {
    private var interstitial: InterstitialAd?

    override init() {
        super.init()
        loadAd()
    }

    func loadAd() {
        InterstitialAd.load(with: "ca-app-pub-9404799280370656/6885458222", request: GADRequest()) { [weak self] ad, error in
            if let error = error {
                print("Interstitial load error: \(error.localizedDescription)")
                return
            }
            self?.interstitial = ad
            self?.interstitial?.fullScreenContentDelegate = self
        }
    }

    func showAd() {
        guard let interstitial = interstitial else { return }
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = windowScene.windows.first?.rootViewController {
            interstitial.present(from: root)
        }
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        loadAd()
    }
}
