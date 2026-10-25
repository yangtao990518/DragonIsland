import SwiftUI
import UIKit

struct ArtworkViewer: View {
    let item: ArtworkSelection
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var darkBackground = true
    @State private var resetToken = 0
    @State private var zoomRatio: CGFloat = 1

    private var foreground: Color { darkBackground ? .white : .black }

    var body: some View {
        ZStack {
            (darkBackground ? Color(red: 0.04, green: 0.035, blue: 0.06) : .white).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .medium)).frame(width: 44, height: 44)
                    }.accessibilityLabel("关闭大图").accessibilityIdentifier("closeArtwork")
                    Text(item.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 4)
                    Button { darkBackground.toggle() } label: {
                        Image(systemName: darkBackground ? "sun.max" : "moon").frame(width: 44, height: 44)
                    }.accessibilityLabel("切换看图背景").accessibilityIdentifier("galleryBackgroundToggle")
                }.padding(.horizontal, 10)
                ZoomableArtwork(asset: item.asset, resetToken: resetToken) { zoomRatio = $0 }
                HStack {
                    Text("双指缩放 · 双击放大 · 拖动查看").font(.system(size: 11))
                    Spacer()
                    Text("\(Int((zoomRatio * 100).rounded()))%")
                        .font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                        .accessibilityIdentifier("zoomPercentage")
                    Button("还原") { resetToken += 1 }.font(.system(size: 12))
                        .accessibilityIdentifier("resetArtworkZoom")
                }.padding(18).foregroundStyle(foreground.opacity(0.65))
            }
        }
        .foregroundStyle(foreground)
        .onAppear { darkBackground = colorScheme == .dark }
        .statusBarHidden()
    }
}

private struct ZoomableArtwork: UIViewRepresentable {
    let asset: String
    let resetToken: Int
    let onZoom: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onZoom: onZoom) }

    func makeUIView(context: Context) -> ArtworkScrollView {
        let view = ArtworkScrollView()
        view.delegate = context.coordinator
        view.imageView.image = UIImage(named: asset)
        view.imageView.accessibilityLabel = "角色大图"
        view.imageView.isAccessibilityElement = true
        view.accessibilityIdentifier = "artworkZoomScroll"
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        tap.numberOfTapsRequired = 2
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: ArtworkScrollView, context: Context) {
        if context.coordinator.resetToken != resetToken {
            context.coordinator.resetToken = resetToken
            view.setZoomScale(view.minimumZoomScale, animated: true)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let onZoom: (CGFloat) -> Void
        var resetToken = 0
        init(onZoom: @escaping (CGFloat) -> Void) { self.onZoom = onZoom }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { (scrollView as? ArtworkScrollView)?.imageView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ArtworkScrollView)?.centerImage()
            let ratio = scrollView.zoomScale / max(scrollView.minimumZoomScale, 0.0001)
            DispatchQueue.main.async { [weak self] in self?.onZoom(ratio) }
        }
        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? ArtworkScrollView else { return }
            if scroll.zoomScale > scroll.minimumZoomScale * 1.05 {
                scroll.setZoomScale(scroll.minimumZoomScale, animated: true)
            } else {
                let scale = min(scroll.minimumZoomScale * 2.5, scroll.maximumZoomScale)
                let point = gesture.location(in: scroll.imageView)
                let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                      width: size.width, height: size.height), animated: true)
            }
        }
    }
}

private final class ArtworkScrollView: UIScrollView {
    let imageView = UIImageView()
    private var fittedSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bouncesZoom = true
        contentInsetAdjustmentBehavior = .never
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, let image = imageView.image else { return }
        if fittedSize != bounds.size {
            fittedSize = bounds.size
            imageView.frame = CGRect(origin: .zero, size: image.size)
            contentSize = image.size
            let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
            minimumZoomScale = fit
            maximumZoomScale = fit * 6
            zoomScale = fit
        }
        centerImage()
    }
    func centerImage() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        let insets = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != insets { contentInset = insets }
    }
}
