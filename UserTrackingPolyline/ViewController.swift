//
//  ViewController.swift
//  Maps
//
//  Created by Robert Vaessen on 10/24/17.
//  Copyright © 2017 Robert Vaessen. All rights reserved.
//

import UIKit
import MapKit
import VerticonsToolbox

// TODO: Start fresh, disallow location updates, and see what happens.
class ViewController: UIViewController {

    @IBOutlet private weak var mapView: MKMapView!
 
    private var userTrackingPolyline: UserTrackingPolyline?
    private let polylineWidth = 4.0 // meters

    private var userIsOnAnnotation = MKPointAnnotation()
    private var userIsOnAnnotationAnimator: UIViewPropertyAnimator?

    private var tapAnnotation = MKPointAnnotation()
    private var pathAnnotation = MKPointAnnotation()

    private var debugConsole: DebugLayer?

    override func viewDidLoad() {
        super.viewDidLoad()

        debugConsole = DebugLayer.add(to: view)

        do {
            let userTrackingButton = UserTrackingButton(mapView: mapView, stateChangeHandler: setUserTracking(_:))
            userTrackingButton.translatesAutoresizingMaskIntoConstraints = false
            mapView.addSubview(userTrackingButton)
            NSLayoutConstraint.activate([
                userTrackingButton.topAnchor.constraint(equalTo: mapView.topAnchor, constant: 32),
                userTrackingButton.leftAnchor.constraint(equalTo: mapView.leftAnchor, constant: 32),
                userTrackingButton.heightAnchor.constraint(equalToConstant: 32),
                userTrackingButton.widthAnchor.constraint(equalToConstant: 32)])
 
            trackingUser = userTrackingButton.trackingUser
        }


        do {

            enum LoadStatus {
                case success(UserTrackingPolyline)
                case error(String)
            }

            let loadStatus = { () -> LoadStatus in

                let bundledPolylinesFileName = "Polylines"
                //let polylineName = "LittleSugarCreek"
                let polylineName = "RobertsNeighborhood"

                guard let jsonFilePath = Bundle.main.path(forResource: bundledPolylinesFileName, ofType: "json") else {
                    return .error("Cannot find \(bundledPolylinesFileName).json in bundle.")
                }
                
                let jsonFileUrl = URL(fileURLWithPath: jsonFilePath)
                
                do {
                    let jsonData = try Data(contentsOf: jsonFileUrl)
                    let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
                    
                    if  let jsonContainer = jsonObject as? [String : [String: Any]],
                        let jsonCoordinates = jsonContainer["Polylines"]?[polylineName] as? [String : [String : Double]] {
                        
                        guard jsonCoordinates.count >= 2 else {
                            return .error("\(bundledPolylinesFileName).json has \(jsonCoordinates.count) coordinates; there need to be at least 2.")
                        }
                        
                        var coordinates = Array<CLLocationCoordinate2D>(repeating: CLLocationCoordinate2D(), count: jsonCoordinates.count)
                        for (key, value) in jsonCoordinates {
                            coordinates[Int(key)! - 1] = CLLocationCoordinate2D(latitude: value["latitude"]!, longitude: value["longitude"]!)
                        }
                        
                        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
                        polyline.title = polylineName
                        
                        return .success(UserTrackingPolyline(polyline: polyline, mapView: mapView))
                    }
                    else {
                        return .error("The json object does not contain the expected types and/or keys:\n\(jsonObject)")
                    }
                }
                catch {
                    return .error("Error reading/parsing \(bundledPolylinesFileName).json: \(error)")
                }
            }()

            switch loadStatus {
            case .success(let tracker):
                self.userTrackingPolyline = tracker
                userIsOnAnnotation.title = mapView.userLocation.title
                _ = tracker.addListener(self, handlerClassMethod: ViewController.trackngPolylineEventHandler)

            case .error(let error):
                print(error)
            }
        }

        mapView.delegate = self
        
        _ = UserLocation.instance.addListener(self, handlerClassMethod: ViewController.userLocationEventHandler)
        
       mapView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(mapTapped(_:))))
        
    }

    private func userLocationEventHandler(event: UserLocationEvent) {

        switch event {

        case .locationUpdate(let location):
            mapView.userLocation.subtitle = location.coordinate.description
            if location.horizontalAccuracy < 20 { userTrackingPolyline?.enableTracking(withTolerence: polylineWidth) }
            if trackingUser { self.mapView.setCenter(location.coordinate, animated: false) }

            if let data = userTrackingPolyline?.userTrackingData { debugConsole?.update(line: 6, with: String(format: "Distance = %.1f meters", data.distance)) }
            debugConsole?.update(line: 7, with: String(format: "Accuracy = %.1f meters", location.horizontalAccuracy))

        case .headingUpdate(let heading):
            if trackingUser { self.mapView.camera.heading = heading.trueHeading }

        default:
            break
        }
    }

    private func setUserTracking(_ state: Bool) {
        trackingUser = state
    }
    
    private var trackingUser: Bool = false {
        didSet {
            if trackingUser {
                if let location = mapView.userLocation.location { mapView.setCenter(location.coordinate, animated: false) }
                if let heading = mapView.userLocation.heading { mapView.camera.heading = heading.trueHeading }
            }
        }
    }

    private func trackngPolylineEventHandler(event: UserTrackingPolylineEvent) {

        guard let userLocation = UserLocation.instance.currentLocation, let userIsOn = userTrackingPolyline?.userIsOn, let trackingData = userTrackingPolyline?.userTrackingData else {
            fatalError("User Location and/or Polyline Tracking data is nil. Huh?! How did the event handler even get called?")
        }

        debugConsole?.update(line: 5, with: "\(userIsOn ? "On" : "Off"), tol. = \(String(format: "%.1f", userTrackingPolyline!.trackingTolerence))")

        switch event {

        case .userIsOnChanged:
            userIsOnAnnotationAnimator = UIViewPropertyAnimator(duration: 2, curve: .linear, animations: nil)
            if userIsOn {
                userIsOnAnnotation.coordinate = userLocation.coordinate
                mapView.addAnnotation(userIsOnAnnotation) // The MKMapViewDelegate's didAdd method will animate it into positon (we have to wait for the view to be created and displayed).
                mapView.showsUserLocation = false
            }
            else {
                userIsOnAnnotationAnimator!.addAnimations { // Animate the move from the closest point on the polyline to the user's actual location
                    self.userIsOnAnnotation.coordinate = userLocation .coordinate
                }
                userIsOnAnnotationAnimator!.addCompletion() { animatingPosition in
                    self.mapView.removeAnnotation(self.userIsOnAnnotation)
                    self.mapView.showsUserLocation = true
                    self.userIsOnAnnotationAnimator = nil
                }
                userIsOnAnnotationAnimator!.startAnimation()
            }


        case .userPositionChanged:
            guard userIsOnAnnotationAnimator == nil else { return }
            userIsOnAnnotation.coordinate = MKCoordinateForMapPoint(trackingData.point)
            userIsOnAnnotation.subtitle = userIsOnAnnotation.coordinate.description
            
        case .trackingDisabled:
            break
        }
    }

    @objc func mapTapped(_ recognizer: UITapGestureRecognizer) {
        guard let tracker = userTrackingPolyline, recognizer.state == .recognized else { return }
        
        let tapCoordinate = mapView.convert(recognizer.location(in: mapView), toCoordinateFrom: mapView)
        let closest = tracker.polyline.closestPoint(to: MKMapPointForCoordinate(tapCoordinate))
        let distanceText = "\(String(format: "%.1f", closest.distance)) meters"
        
        tapAnnotation.coordinate = tapCoordinate
        tapAnnotation.title = distanceText
        tapAnnotation.subtitle = tapAnnotation.coordinate.description
        
        pathAnnotation.coordinate = MKCoordinateForMapPoint(closest.point)
        pathAnnotation.title = distanceText
        pathAnnotation.subtitle = pathAnnotation.coordinate.description
        
        if !mapView.annotations.reduce(false){ $0 || $1 === tapAnnotation } {
            mapView.addAnnotation(tapAnnotation)
            mapView.addAnnotation(pathAnnotation)
        }
    }
}

extension ViewController : MKMapViewDelegate {

    func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
        if let tracker = self.userTrackingPolyline, mapView.overlays.count == 0 {
            mapView.add(tracker.polyline)
            mapView.region = 1.25 * tracker.polyline.boundingRegion
        }
    }

    func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
        views.forEach() { view in
            guard let annotation = view.annotation as? MKPointAnnotation, annotation === userIsOnAnnotation else { return }
 
            if userIsOnAnnotationAnimator != nil, let data = userTrackingPolyline?.userTrackingData {
                let finalCoordinate = MKCoordinateForMapPoint(data.point)
                userIsOnAnnotationAnimator!.addAnimations {
                    annotation.coordinate = finalCoordinate
                }
                userIsOnAnnotationAnimator!.addCompletion() { position in
                    self.userIsOnAnnotationAnimator = nil
                    annotation.subtitle = finalCoordinate.description
                }
                userIsOnAnnotationAnimator!.startAnimation()
            }
        }
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        
        var annotationView: MKAnnotationView? = nil

        if annotation is MKPointAnnotation {
            if annotation === userIsOnAnnotation {
                let reuseID = "UserView"
                annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID)
                if annotationView == nil {
                    annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
                    annotationView!.image = UIImage(named: "UserLocation")
                    annotationView!.bounds.size = CGSize(width: 32, height: 32)
                    annotationView!.centerOffset = CGPoint(x: 0, y: -annotationView!.bounds.height / 2);
                    annotationView!.canShowCallout = true
                }
            }
            else {
                let reuseID = "PinView"
                annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID)
                if annotationView == nil {
                    annotationView = MKPinAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
                    annotationView!.canShowCallout = true
                }
                annotationView!.annotation = annotation
           }
        }

        return annotationView
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let renderer = userTrackingPolyline!.renderer
        renderer.width = polylineWidth
        return renderer
    }
}

