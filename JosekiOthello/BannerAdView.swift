import SwiftUI
import GoogleMobileAds

struct BannerAdView: UIViewRepresentable {
    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeFromCGSize(CGSize(width: 320, height: 50)))
        banner.adUnitID = "ca-app-pub-9404799280370656/3770613831"
        return banner
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {
        guard uiView.rootViewController == nil else { return }
        DispatchQueue.main.async {
            if let rootVC = uiView.window?.windowScene?.keyWindow?.rootViewController {
                uiView.rootViewController = rootVC
                uiView.load(GADRequest())
            }
        }
    }
}
