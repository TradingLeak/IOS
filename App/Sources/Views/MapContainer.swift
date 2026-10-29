import SwiftUI
import MapKit
import UIKit

final class PinAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
    let kind: MapPin.Kind
    let pinID: String

    init(pin: MapPin) {
        coordinate = pin.coordinate
        title = pin.title
        subtitle = pin.subtitle
        kind = pin.kind
        pinID = pin.id
        super.init()
    }
}

/// Bọc MKMapView (Apple Maps hoặc raster OpenStreetMap) cho SwiftUI: vẽ tuyến, ghim, nhấn giữ để chọn điểm.
struct MapContainer: UIViewRepresentable {
    var pins: [MapPin] = []
    var polylines: [MapPolyline] = []
    var focusCoordinate: CLLocationCoordinate2D? = nil
    var focusToken: Int = 0
    var fitToken: Int = 0
    var mapProvider: MapProvider = .apple
    var offlineDatabase: OfflineMBTiles? = nil
    var mapTypeIndex: Int = 0
    var showTraffic: Bool = false
    var showPOIs: Bool = true
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

        updateBasemap(mapView, context: context)
        let apple = mapProvider == .apple
        let type = apple ? Self.mapType(for: mapTypeIndex) : .standard
        if mapView.mapType != type { mapView.mapType = type }
        let traffic = apple && showTraffic
        if mapView.showsTraffic != traffic { mapView.showsTraffic = traffic }
        mapView.showsBuildings = apple
        mapView.isPitchEnabled = apple

        let pois = apple && showPOIs
        if context.coordinator.lastPOISetting != pois {
            context.coordinator.lastPOISetting = pois
            mapView.pointOfInterestFilter = pois ? .includingAll : .excludingAll
        }

        updatePins(mapView, context: context)
        updateOverlays(mapView, context: context)

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

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Pins & overlays

    /// Thay lớp nền tại chỗ, không reset camera/ghim/tuyến khi đổi nguồn.
    private func updateBasemap(_ mapView: MKMapView, context: Context) {
        context.coordinator.updateBasemap(mapView, provider: mapProvider, database: offlineDatabase)
    }

    private func updatePins(_ mapView: MKMapView, context: Context) {
        let signature = pins
            .map { "\($0.id)|\($0.kind.rawValue)|\(String(format: "%.5f", $0.coordinate.latitude))|\(String(format: "%.5f", $0.coordinate.longitude))" }
            .joined(separator: ";")
        guard signature != context.coordinator.lastPinSignature else { return }
        context.coordinator.lastPinSignature = signature

        let existing = mapView.annotations.compactMap { $0 as? PinAnnotation }
        mapView.removeAnnotations(existing)
        mapView.addAnnotations(pins.map { PinAnnotation(pin: $0) })
    }

    private func updateOverlays(_ mapView: MKMapView, context: Context) {
        let signature = polylines
            .map { "\($0.id)|\($0.style.rawValue)|\($0.coordinates.count)" }
            .joined(separator: ";")
        guard signature != context.coordinator.lastOverlaySignature else { return }
        context.coordinator.lastOverlaySignature = signature

        // Không xoá tile nền OSM khi tuyến thay đổi hoặc kết thúc điều hướng.
        mapView.removeOverlays(mapView.overlays.filter { $0 is MKPolyline })
        for line in polylines where line.coordinates.count > 1 {
            var coordinates = line.coordinates
            let polyline = MKPolyline(coordinates: &coordinates, count: coordinates.count)
            polyline.title = line.style.rawValue
            mapView.addOverlay(polyline, level: .aboveLabels)
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
        var lastOfflineMapID: UUID?
        var lastProvider: MapProvider?
        var tileOverlay: OpenStreetMapOverlay?
        var lastPinSignature = ""
        var lastOverlaySignature = ""
        var lastFocusToken = -1
        var lastFitToken = -1
        var lastPOISetting: Bool?

        init(_ parent: MapContainer) {
            self.parent = parent
        }

        func updateBasemap(_ mapView: MKMapView, provider: MapProvider, database: OfflineMBTiles? = nil) {
            guard lastProvider != provider || (provider == .openStreetMap && lastOfflineMapID != database?.id) else { return }
            lastProvider = provider
            lastOfflineMapID = database?.id
            if let tileOverlay {
                mapView.removeOverlay(tileOverlay)
                self.tileOverlay = nil
            }
            if provider == .openStreetMap {
                let bounds = database?.manifest.bounds ?? [102, 8, 110, 24]
                let northwest = MKMapPoint(CLLocationCoordinate2D(latitude: bounds[3], longitude: bounds[0]))
                let southeast = MKMapPoint(CLLocationCoordinate2D(latitude: bounds[1], longitude: bounds[2]))
                let rect = MKMapRect(x: northwest.x, y: northwest.y,
                                     width: southeast.x - northwest.x, height: southeast.y - northwest.y)
                mapView.setCameraBoundary(MKMapView.CameraBoundary(mapRect: rect), animated: false)
                let overlay = OpenStreetMapOverlay(database: database)
                tileOverlay = overlay
                mapView.insertOverlay(overlay, at: 0, level: .aboveRoads)
            } else {
                mapView.setCameraBoundary(nil, animated: false)
            }
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
            }
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tileOverlay)
            }
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
                                       kind: pin.kind))
        }
    }
}
