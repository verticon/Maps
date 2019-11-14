//
//  MapView.swift
//  DualMaps
//
//  Created by Robert Vaessen on 11/2/19.
//  Copyright © 2019 Robert Vaessen. All rights reserved.
//

import UIKit
import MapKit
import VerticonsToolbox

class DualMapsManager : NSObject {

    private class DetailAnnotationView : MKAnnotationView {
        static let reuseIdentifier = "Detail"

        private func setColors() {
            if self.traitCollection.userInterfaceStyle == .light {
                backgroundColor = UIColor.darkGray
                layer.borderColor = UIColor.black.cgColor
            }
            else {
                backgroundColor = UIColor.white
                layer.borderColor = UIColor.blue.cgColor
            }
        }

        init(annotation: MKAnnotation?) {
            super.init(annotation: annotation, reuseIdentifier: DetailAnnotationView.reuseIdentifier)
            alpha = 0.2
            layer.borderWidth = 1
            setColors()
        }
        
        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            if self.traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle { setColors() }
        }

        func updateBounds(_ dualMaps: DualMapsManager) {
            var newBounds = dualMaps.overview.convert(dualMaps.detail.region, toRectTo: dualMaps.overview)
            newBounds.size = CGSize(width: max(newBounds.width, 20), height: max(newBounds.height, 20))
            bounds = newBounds
        }
    }

    private static let spanRatio = 10.0

    let overview = MKMapView()
    let detail = MKMapView()

    private let detailAnnotation = MKPointAnnotation(__coordinate: CLLocationCoordinate2D.zero)

    private var observers = [NSKeyValueObservation]()

    init(initialOverviewRegion: MKCoordinateRegion) {

        super.init()

        func setup(map: MKMapView) {
            map.delegate = self
            map.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapGestureHandler(_:))))
            observers.append(map.observe(\.bounds, options: [.new]) { mapView, change in self.updateAnnotation() })
        }

        setup(map: overview)
        setup(map: detail)

        overview.region = initialOverviewRegion
        detail.region = initialOverviewRegion / DualMapsManager.spanRatio

        detailAnnotation.coordinate = detail.region.center
        overview.addAnnotation(detailAnnotation)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateAnnotation() { // Update the annotation's center and bounds to match the detail view.
        detailAnnotation.coordinate = detail.region.center
        if let annotationView = overview.view(for: detailAnnotation) as? DetailAnnotationView { annotationView.updateBounds(self) }
    }

    @objc func tapGestureHandler(_ recognizer: UITapGestureRecognizer) {
        guard let mapView = recognizer.view as? MKMapView else { return }
        
        if mapView == overview {
            let touchPoint = recognizer.location(in: overview)
            let touchCoordinate = overview.convert(touchPoint, toCoordinateFrom: overview)
            overview.region.center = touchCoordinate
            detail.region = overview.region / DualMapsManager.spanRatio
        }
        else {
            overview.region = DualMapsManager.spanRatio * detail.region
        }
    }
}

extension DualMapsManager : MKMapViewDelegate {
    
    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) { updateAnnotation() }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        var annotationView = overview.dequeueReusableAnnotationView(withIdentifier: DetailAnnotationView.reuseIdentifier) as? DetailAnnotationView
        if annotationView == nil { annotationView = DetailAnnotationView(annotation: nil) }
        annotationView!.updateBounds(self)
        return annotationView
    }
}
