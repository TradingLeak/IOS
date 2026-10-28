import SwiftUI
import MapKit
import UIKit

final class PinAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?
    let kind: MapPin.Kind
    let pinID: String
    /// Riêng cho ghim cảnh báo giao thông (biển tốc độ, camera…).
    var alertKind: AlertKind?
    var limit: Int?
    var severity: Int

    init(pin: MapPin) {
        coordinate = pin.coordinate
        title = pin.title
        subtitle = pin.subtitle
        kind = pin.kind
        pinID = pin.id
        alertKind = pin.alertKind
        limit = pin.limit
        severity = pin.severity
        super.init()
    }

    /// Cùng một điểm ghim (không đổi toạ độ) → cập nhật tại chỗ, không xoá/thêm lại.
    func isSamePlace(as pin: MapPin) -> Bool {
        abs(coordinate.latitude - pin.coordinate.latitude) < 1e-6
            && abs(coordinate.longitude - pin.coordinate.longitude) < 1e-6
    }

    /// Màu/hình/nhãn có cần vẽ lại không (khoảng cách đổi liên tục, chỉ vẽ lại khi đổi mức).
    func needsRestyle(as pin: MapPin) -> Bool {
        severity != pin.severity
            || limit != pin.limit
            || alertKind != pin.alertKind
            || kind != pin.kind
    }

    func apply(_ pin: MapPin) {
        title = pin.title
        subtitle = pin.subtitle
        alertKind = pin.alertKind
        limit = pin.limit
        severity = pin.severity
    }
}

// MARK: - Kiểu vẽ marker cảnh báo

/// Màu + hình cho marker cảnh báo hiển thị **trực tiếp trên bản đồ** (không cần HUD):
/// mức nguy hiểm quyết định màu, loại cảnh báo quyết định hình, biển tốc độ vẽ số km/h.
enum AlertMapStyle {

    private static let cache = NSCache<NSString, UIImage>()

    /// 0 xám (tham khảo) · 1 màu theo loại · 2 cam (sắp tới) · 3 đỏ (rất gần / nguy hiểm).
    static func color(severity: Int, kind: AlertKind?) -> UIColor {
        switch severity {
        case 3: return UIColor(red: 0.86, green: 0.16, blue: 0.18, alpha: 1)
        case 2: return UIColor(red: 0.94, green: 0.48, blue: 0.10, alpha: 1)
        case 1: return UIColor(kind?.tint ?? AppTheme.warning)
        default: return UIColor(red: 0.42, green: 0.47, blue: 0.55, alpha: 1)
        }
    }

    /// Ảnh glyph: biển tròn có số km/h nếu có giới hạn, ngược lại icon theo loại cảnh báo.
    static func glyph(for pin: PinAnnotation) -> UIImage? {
        if let limit = pin.limit,
           pin.alertKind?.carriesSpeedLimit ?? false,
           let sign = signImage(limit: limit) {
            return sign
        }
        let symbol = pin.alertKind?.symbol ?? (pin.kind == .camera ? "exclamationmark.triangle.fill" : "mappin")
        return UIImage(systemName: symbol)
    }

    /// Biển P.127 thu nhỏ: nền trắng, viền đỏ, số đen — nhìn ra ngay trên bản đồ.
    static func signImage(limit: Int, size: CGFloat = 26) -> UIImage? {
        let key = "sign-\(limit)-\(Int(size))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { _ in
            let rect = CGRect(x: 1, y: 1, width: size - 2, height: size - 2)
            let circle = UIBezierPath(ovalIn: rect)
            UIColor.white.setFill()
            circle.fill()
            UIColor(red: 0.83, green: 0.10, blue: 0.14, alpha: 1).setStroke()
            circle.lineWidth = max(2.4, size * 0.11)
            circle.stroke()

            let text = "\(limit)" as NSString
            let font = UIFont.systemFont(ofSize: size * 0.52, weight: .heavy)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.black
            ]
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (size - textSize.width) / 2,
                                  y: (size - textSize.height) / 2))
        }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Bọc MKMapView (Apple Maps) cho SwiftUI: vẽ tuyến, ghim, nhấn giữ để chọn điểm,
/// và **camera dẫn đường thời gian thực** (3D nghiêng + xoay theo hướng đi, hoặc 2D).
struct MapContainer: UIViewRepresentable {
    var pins: [MapPin] = []
    var polylines: [MapPolyline] = []
    var focusCoordinate: CLLocationCoordinate2D? = nil
    var focusToken: Int = 0
    var fitToken: Int = 0
    var mapTypeIndex: Int = 0
    var showTraffic: Bool = false
    var showPOIs: Bool = true

    // MARK: Camera dẫn đường

    /// Đang dẫn đường → camera bám vị trí thay vì hiển thị toàn tuyến.
    var isNavigating: Bool = false
    /// Vị trí hiện tại dùng cho camera.
    var navigationCoordinate: CLLocationCoordinate2D? = nil
    /// Hướng đi (độ) để xoay bản đồ.
    var navigationHeading: Double = 0
    /// Khoảng cách camera → điểm nhìn (mét), do tốc độ quyết định.
    var navigationDistance: Double = 600
    /// `true` = nghiêng 3D, `false` = nhìn từ trên xuống (2D).
    var navigationPitch3D: Bool = true
    /// Còn bám theo vị trí hay người dùng đã kéo bản đồ.
    var isFollowingUser: Bool = true
    /// Tăng lên khi người dùng bấm "bám lại" để camera nhảy về vị trí.
    var followToken: Int = 0
    /// Người dùng vừa kéo bản đồ → tạm dừng bám theo.
    var onFollowBroken: (() -> Void)? = nil

    var onSelectPin: ((MapPin) -> Void)? = nil
    var onLongPress: ((CLLocationCoordinate2D) -> Void)? = nil

    // MARK: - Lifecycle

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsBuildings = true
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        mapView.showsBuildings = true
        // Cho phép nghiêng sâu như chế độ 3D của app dẫn đường.
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 120,
                                                           maxCenterCoordinateDistance: 120_000)
        mapView.pointOfInterestFilter = .includingAll
        mapView.setRegion(MapPreset.vietnam.region, animated: false)

        let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.handleLongPress(_:)))
        press.minimumPressDuration = 0.4
        press.delegate = context.coordinator
        mapView.addGestureRecognizer(press)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        let type = Self.mapType(for: mapTypeIndex)
        if mapView.mapType != type { mapView.mapType = type }
        if mapView.showsTraffic != showTraffic { mapView.showsTraffic = showTraffic }

        if context.coordinator.lastPOISetting != showPOIs {
            context.coordinator.lastPOISetting = showPOIs
            mapView.pointOfInterestFilter = showPOIs ? .includingAll : .excludingAll
        }

        updatePins(mapView, context: context)
        updateOverlays(mapView, context: context)
        updateNavigationCamera(mapView, context: context)

        if isNavigating {
            // Đang dẫn đường: camera do updateNavigationCamera quản lý, bỏ qua focus/fit.
            context.coordinator.lastFocusToken = focusToken
            context.coordinator.lastFitToken = fitToken
            return
        }

        if context.coordinator.lastFocusToken != focusToken, let coordinate = focusCoordinate {
            context.coordinator.lastFocusToken = focusToken
            let region = MKCoordinateRegion(center: coordinate,
                                            latitudinalMeters: 1800,
                                            longitudinalMeters: 1800)
            mapView.setRegion(mapView.regionThatFits(region), animated: true)
        }

        if context.coordinator.lastFitToken != fitToken {
            context.coordinator.lastFitToken = fitToken
            if let rect = Self.boundingRect(pins: pins, polylines: polylines) {
                mapView.setVisibleMapRect(rect,
                                          edgePadding: UIEdgeInsets(top: 170, left: 56, bottom: 320, right: 56),
                                          animated: true)
            }
        }
    }

    // MARK: - Camera dẫn đường

    /// Cập nhật camera theo vị trí + hướng đi thật. Chỉ nhảy khi cần thiết để không giật.
    private func updateNavigationCamera(_ mapView: MKMapView, context: Context) {
        guard isNavigating, isFollowingUser, let coordinate = navigationCoordinate else { return }

        let heading = navigationPitch3D ? navigationHeading : 0
        let pitch: CGFloat = navigationPitch3D ? 55 : 0
        let distance = max(160, min(1_200, navigationDistance))

        guard context.coordinator.shouldUpdateCamera(coordinate: coordinate,
                                                     heading: heading,
                                                     distance: distance,
                                                     pitch: pitch,
                                                     pitch3D: navigationPitch3D,
                                                     token: followToken) else { return }

        let camera = MKMapCamera(lookingAtCenter: coordinate,
                                 fromDistance: distance,
                                 pitch: pitch,
                                 heading: heading)
        mapView.setCamera(camera, animated: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Pins & overlays

    /// Ghim được cập nhật **tại chỗ**: khi bạn tiến lại gần một biển báo, marker đổi màu
    /// (xa → cam → đỏ) ngay lập tức mà không xoá/thêm lại cả bản đồ (không nháy, không mất gom cụm).
    private func updatePins(_ mapView: MKMapView, context: Context) {
        let wanted = Set(pins.map(\.id))
        let stale = mapView.annotations
            .compactMap { $0 as? PinAnnotation }
            .filter { !wanted.contains($0.pinID) }
        if !stale.isEmpty {
            mapView.removeAnnotations(stale)
        }

        var index: [String: PinAnnotation] = [:]
        for annotation in mapView.annotations.compactMap({ $0 as? PinAnnotation }) {
            index[annotation.pinID] = annotation
        }

        var toAdd: [PinAnnotation] = []
        for pin in pins {
            guard let annotation = index[pin.id] else {
                toAdd.append(PinAnnotation(pin: pin))
                continue
            }
            guard annotation.isSamePlace(as: pin) else {
                // Toạ độ đổi (hiếm) → thay ghim.
                mapView.removeAnnotation(annotation)
                toAdd.append(PinAnnotation(pin: pin))
                continue
            }
            let restyle = annotation.needsRestyle(as: pin)
            annotation.apply(pin)
            if restyle, let view = mapView.view(for: annotation) as? MKMarkerAnnotationView {
                style(view, with: annotation)
            }
        }
        if !toAdd.isEmpty {
            mapView.addAnnotations(toAdd)
        }
    }

    private func updateOverlays(_ mapView: MKMapView, context: Context) {
        let signature = polylines
            .map { "\($0.id)|\($0.style.rawValue)|\($0.coordinates.count)" }
            .joined(separator: ";")
        guard signature != context.coordinator.lastOverlaySignature else { return }
        context.coordinator.lastOverlaySignature = signature

        mapView.removeOverlays(mapView.overlays)
        for line in polylines where line.coordinates.count > 1 {
            var coordinates = line.coordinates
            let polyline = MKPolyline(coordinates: &coordinates, count: coordinates.count)
            polyline.title = line.style.rawValue
            mapView.addOverlay(polyline, level: .aboveRoads)
        }
    }

    // MARK: - Helpers

    static func mapType(for index: Int) -> MKMapType {
        switch index {
        case 1: return .hybrid
        case 2: return .satellite
        case 3: return .mutedStandard
        default: return .standard
        }
    }

    static func boundingRect(pins: [MapPin], polylines: [MapPolyline]) -> MKMapRect? {
        var rect = MKMapRect.null

        func add(_ coordinate: CLLocationCoordinate2D) {
            guard CLLocationCoordinate2DIsValid(coordinate) else { return }
            let point = MKMapPoint(coordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
            rect = rect.isNull ? pointRect : rect.union(pointRect)
        }

        for pin in pins { add(pin.coordinate) }
        for line in polylines { for coordinate in line.coordinates { add(coordinate) } }

        guard !rect.isNull else { return nil }
        let paddingX = max(rect.size.width * 0.15, 400)
        let paddingY = max(rect.size.height * 0.15, 400)
        return rect.insetBy(dx: -paddingX, dy: -paddingY)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: MapContainer
        var lastOverlaySignature = ""
        var lastFocusToken = -1
        var lastFitToken = -1
        var lastPOISetting: Bool?

        // Camera dẫn đường
        private var lastCameraCoordinate: CLLocationCoordinate2D?
        private var lastCameraHeading: Double = 0
        private var lastCameraDistance: Double = 0
        private var lastCameraPitch: CGFloat = -1
        private var lastCameraToken = -1

        /// Giới hạn tần suất cập nhật camera: bỏ qua thay đổi quá nhỏ.
        func shouldUpdateCamera(coordinate: CLLocationCoordinate2D,
                                heading: Double,
                                distance: Double,
                                pitch: CGFloat,
                                pitch3D: Bool,
                                token: Int) -> Bool {
            defer {
                lastCameraCoordinate = coordinate
                lastCameraHeading = heading
                lastCameraDistance = distance
                lastCameraPitch = pitch
                lastCameraToken = token
            }

            if token != lastCameraToken { return true }
            if abs(pitch - lastCameraPitch) > 0.5 { return true }
            guard let previous = lastCameraCoordinate else { return true }

            let moved = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            if moved > 5 { return true }
            if pitch3D, abs(Self.angleDelta(lastCameraHeading, heading)) > 4 { return true }
            if abs(distance - lastCameraDistance) > max(40, lastCameraDistance * 0.15) { return true }
            return false
        }

        static func angleDelta(_ a: Double, _ b: Double) -> Double {
            var delta = b - a
            while delta > 180 { delta -= 360 }
            while delta < -180 { delta += 360 }
            return delta
        }

        /// Người dùng đang kéo / zoom bản đồ bằng tay hay không.
        static func isUserInteracting(_ mapView: MKMapView) -> Bool {
            let recognizers = (mapView.subviews.first?.gestureRecognizers ?? []) + (mapView.gestureRecognizers ?? [])
            for recognizer in recognizers {
                switch recognizer.state {
                case .began, .changed:
                    return true
                default:
                    continue
                }
            }
            return false
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            guard parent.isNavigating, parent.isFollowingUser else { return }
            guard Self.isUserInteracting(mapView) else { return }
            parent.onFollowBroken?()
        }

        init(_ parent: MapContainer) {
            self.parent = parent
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onLongPress?(coordinate)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? PinAnnotation else { return nil }

            let identifier = "pin-\(pin.kind.rawValue)"
            var reusable = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
            if reusable == nil {
                reusable = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            }
            guard let view = reusable else { return nil }

            view.annotation = annotation
            view.canShowCallout = true
            view.animatesWhenAdded = true
            style(view, with: pin)
            return view
        }

        /// Áp màu, hình, độ ưu tiên cho marker — gọi cả khi tạo mới và khi cập nhật tại chỗ.
        func style(_ view: MKMarkerAnnotationView, with pin: PinAnnotation) {
            view.transform = .identity
            view.titleVisibility = .hidden
            view.subtitleVisibility = .hidden
            view.glyphTintColor = UIColor.white
            view.displayPriority = pin.kind == .poi ? .defaultLow : .required
            view.clusteringIdentifier = pin.kind == .poi ? "poi" : nil

            switch pin.kind {
            case .origin:
                view.markerTintColor = UIColor(AppTheme.success)
                view.glyphImage = UIImage(systemName: "arrow.up.circle.fill")
            case .destination:
                view.markerTintColor = UIColor(AppTheme.danger)
                view.glyphImage = UIImage(systemName: "flag.fill")
            case .waypoint:
                view.markerTintColor = UIColor(AppTheme.accent)
                view.glyphImage = UIImage(systemName: "circle.fill")
            case .favorite:
                view.markerTintColor = UIColor(AppTheme.accentDeep)
                view.glyphImage = UIImage(systemName: "star.fill")
            case .poi:
                view.markerTintColor = UIColor(AppTheme.warning)
                view.glyphImage = UIImage(systemName: "mappin")
            case .camera:
                // Biển báo / camera hiện ngay trên bản đồ: màu theo mức nguy hiểm,
                // hình theo loại, số km/h nếu là biển giới hạn tốc độ.
                view.markerTintColor = AlertMapStyle.color(severity: pin.severity, kind: pin.alertKind)
                view.glyphImage = AlertMapStyle.glyph(for: pin)
                view.glyphTintColor = pin.limit == nil ? UIColor.white : nil
                view.displayPriority = pin.severity >= 2 ? .required : .defaultHigh
                view.clusteringIdentifier = pin.severity >= 3 ? nil : "alert"
                view.titleVisibility = .adaptive
                view.subtitleVisibility = .adaptive
                view.transform = pin.severity >= 3
                    ? CGAffineTransform(scaleX: 1.18, y: 1.18)
                    : .identity
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            switch polyline.title {
            case MapPolyline.Style.casing.rawValue:
                renderer.strokeColor = UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor(white: 0.06, alpha: 0.9)
                        : UIColor(white: 1.0, alpha: 0.95)
                }
                renderer.lineWidth = 12
            case MapPolyline.Style.alternate.rawValue:
                renderer.strokeColor = UIColor.systemGray.withAlphaComponent(0.7)
                renderer.lineWidth = 6
                renderer.lineDashPattern = [NSNumber(value: 12), NSNumber(value: 8)]
            default:
                renderer.strokeColor = UIColor(AppTheme.accent)
                renderer.lineWidth = 7
            }
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let pin = view.annotation as? PinAnnotation else { return }
            mapView.deselectAnnotation(view.annotation, animated: false)
            parent.onSelectPin?(MapPin(id: pin.pinID,
                                       coordinate: pin.coordinate,
                                       title: pin.title ?? "",
                                       subtitle: pin.subtitle ?? "",
                                       kind: pin.kind,
                                       alertKind: pin.alertKind,
                                       limit: pin.limit,
                                       severity: pin.severity,
                                       distance: nil))
        }
    }
}
