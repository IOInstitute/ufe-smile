//
//  Copyright (c) 2018 Google Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AVFoundation
import CoreVideo
import MLKit

@objc(CameraViewController)
class CameraViewController: UIViewController {
 

  private var currentDetector: Detector = .onDeviceFace
  private var isUsingFrontCamera = true
  private var previewLayer: AVCaptureVideoPreviewLayer!
  private lazy var captureSession = AVCaptureSession()
  private lazy var sessionQueue = DispatchQueue(label: Constant.sessionQueueLabel)
  private var lastFrame: CMSampleBuffer?
    let imageView = UIImageView(image: #imageLiteral(resourceName: "UFE Smile"))

  private lazy var previewOverlayView: UIImageView = {

    precondition(isViewLoaded)
    let previewOverlayView = UIImageView(frame: .zero)
    previewOverlayView.contentMode = UIView.ContentMode.scaleAspectFill
    previewOverlayView.translatesAutoresizingMaskIntoConstraints = false
    return previewOverlayView
  }()

  private lazy var annotationOverlayView: UIView = {
    precondition(isViewLoaded)
    let annotationOverlayView = UIView(frame: .zero)
    annotationOverlayView.translatesAutoresizingMaskIntoConstraints = false
    return annotationOverlayView
  }()

    private var cameraView = UIView()

  // MARK: - UIViewController

  override func viewDidLoad() {
    super.viewDidLoad()
     imageView.frame = CGRect(x: 0, y:280, width: 380, height: 380)

    cameraView.frame = self.view.frame
    self.view.addSubview(cameraView)
    
    previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
    setUpPreviewOverlayView()
    setUpAnnotationOverlayView()
    setUpCaptureSessionOutput()
    setUpCaptureSessionInput()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    startSession()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)

    stopSession()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    previewLayer.frame = cameraView.frame
  }



  // MARK: On-Device Detections

  

  private func detectFacesOnDevice(in image: VisionImage, width: CGFloat, height: CGFloat) {
    // When performing latency tests to determine ideal detection settings, run the app in 'release'
    // mode to get accurate performance metrics.
    print("starting face detection")
    let options = FaceDetectorOptions()
    options.landmarkMode = .all
    options.contourMode = .all
    options.classificationMode = .all
    options.performanceMode = .fast
    let faceDetector = FaceDetector.faceDetector(options: options)
    var faces: [Face]
    do {
      faces = try faceDetector.results(in: image)
    } catch let error {
      print("Failed to detect faces with error: \(error.localizedDescription).")
      return
    }
    DispatchQueue.main.sync {
      self.updatePreviewOverlayView()
      self.removeDetectionAnnotations()
    }
    guard !faces.isEmpty else {
      print("On-Device face detector returned no results.")
      return
    }
    DispatchQueue.main.sync {
      for face in faces {
         if face.smilingProbability >= 0.5 {
                   
               
                   view.addSubview(imageView)
               }else{
                   imageView.removeFromSuperview()
               }
        let normalizedRect = CGRect(
          x: face.frame.origin.x / width,
          y: face.frame.origin.y / height,
          width: face.frame.size.width / width,
          height: face.frame.size.height / height
        )
        let standardizedRect = self.previewLayer.layerRectConverted(
          fromMetadataOutputRect: normalizedRect
        ).standardized
        UIUtilities.addRectangle(
          standardizedRect,
          to: self.annotationOverlayView,
          color: UIColor.green
        )
        self.addContours(for: face, width: width, height: height)
      }
    }
  }

  

  // MARK: - Private

  private func setUpCaptureSessionOutput() {
    sessionQueue.async {
      self.captureSession.beginConfiguration()
      // When performing latency tests to determine ideal capture settings,
      // run the app in 'release' mode to get accurate performance metrics
      self.captureSession.sessionPreset = AVCaptureSession.Preset.medium

      let output = AVCaptureVideoDataOutput()
      output.videoSettings = [
        (kCVPixelBufferPixelFormatTypeKey as String): kCVPixelFormatType_32BGRA,
      ]
      let outputQueue = DispatchQueue(label: Constant.videoDataOutputQueueLabel)
      output.setSampleBufferDelegate(self, queue: outputQueue)
      guard self.captureSession.canAddOutput(output) else {
        print("Failed to add capture session output.")
        return
      }
      self.captureSession.addOutput(output)
      self.captureSession.commitConfiguration()
    }
  }

  private func setUpCaptureSessionInput() {
    sessionQueue.async {
      let cameraPosition: AVCaptureDevice.Position = .front
      guard let device = self.captureDevice(forPosition: cameraPosition) else {
        print("Failed to get capture device for camera position: \(cameraPosition)")
        return
      }
      do {
        self.captureSession.beginConfiguration()
        let currentInputs = self.captureSession.inputs
        for input in currentInputs {
          self.captureSession.removeInput(input)
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard self.captureSession.canAddInput(input) else {
          print("Failed to add capture session input.")
          return
        }
        self.captureSession.addInput(input)
        self.captureSession.commitConfiguration()
      } catch {
        print("Failed to create capture device input: \(error.localizedDescription)")
      }
    }
  }

  private func startSession() {
    sessionQueue.async {
      self.captureSession.startRunning()
    }
  }

  private func stopSession() {
    sessionQueue.async {
      self.captureSession.stopRunning()
    }
  }

  private func setUpPreviewOverlayView() {
    cameraView.addSubview(previewOverlayView)
    NSLayoutConstraint.activate([
      previewOverlayView.centerXAnchor.constraint(equalTo: cameraView.centerXAnchor),
      previewOverlayView.centerYAnchor.constraint(equalTo: cameraView.centerYAnchor),
      previewOverlayView.leadingAnchor.constraint(equalTo: cameraView.leadingAnchor),
      previewOverlayView.trailingAnchor.constraint(equalTo: cameraView.trailingAnchor),

    ])
  }

  private func setUpAnnotationOverlayView() {
    cameraView.addSubview(annotationOverlayView)
    NSLayoutConstraint.activate([
      annotationOverlayView.topAnchor.constraint(equalTo: cameraView.topAnchor),
      annotationOverlayView.leadingAnchor.constraint(equalTo: cameraView.leadingAnchor),
      annotationOverlayView.trailingAnchor.constraint(equalTo: cameraView.trailingAnchor),
      annotationOverlayView.bottomAnchor.constraint(equalTo: cameraView.bottomAnchor),
    ])
  }

  private func captureDevice(forPosition position: AVCaptureDevice.Position) -> AVCaptureDevice? {
    if #available(iOS 10.0, *) {
      let discoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera],
        mediaType: .video,
        position: .unspecified
      )
      return discoverySession.devices.first { $0.position == position }
    }
    return nil
  }

    private func removeDetectionAnnotations() {
      for annotationView in annotationOverlayView.subviews {
        annotationView.removeFromSuperview()
      }
    }

  private func updatePreviewOverlayView() {
    guard let lastFrame = lastFrame,
      let imageBuffer = CMSampleBufferGetImageBuffer(lastFrame)
    else {
      return
    }
    let ciImage = CIImage(cvPixelBuffer: imageBuffer)
    let context = CIContext(options: nil)
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
      return
    }
    let rotatedImage = UIImage(cgImage: cgImage, scale: Constant.originalScale, orientation: .right)
    if isUsingFrontCamera {
      guard let rotatedCGImage = rotatedImage.cgImage else {
        return
      }
      let mirroredImage = UIImage(
        cgImage: rotatedCGImage, scale: Constant.originalScale, orientation: .leftMirrored)
      previewOverlayView.image = mirroredImage
    } else {
      previewOverlayView.image = rotatedImage
    }
  }

  private func convertedPoints(
    from points: [NSValue]?,
    width: CGFloat,
    height: CGFloat
  ) -> [NSValue]? {
    return points?.map {
      let cgPointValue = $0.cgPointValue
      let normalizedPoint = CGPoint(x: cgPointValue.x / width, y: cgPointValue.y / height)
      let cgPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: normalizedPoint)
      let value = NSValue(cgPoint: cgPoint)
      return value
    }
  }

  private func normalizedPoint(
    fromVisionPoint point: VisionPoint,
    width: CGFloat,
    height: CGFloat
  ) -> CGPoint {
    let cgPoint = CGPoint(x: point.x, y: point.y)
    var normalizedPoint = CGPoint(x: cgPoint.x / width, y: cgPoint.y / height)
    normalizedPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: normalizedPoint)
    return normalizedPoint
  }

  private func addContours(for face: Face, width: CGFloat, height: CGFloat) {
    // Face
    if let faceContour = face.contour(ofType: .face) {
      for point in faceContour.points {
        let cgPoint = normalizedPoint(fromVisionPoint: point, width: width, height: height)
        UIUtilities.addCircle(
          atPoint: cgPoint,
          to: annotationOverlayView,
          color: UIColor.blue,
          radius: Constant.smallDotRadius
        )
      }
    }

    // Eyebrows
    if let topLeftEyebrowContour = face.contour(ofType: .leftEyebrowTop) {
      for point in topLeftEyebrowContour.points {
        let cgPoint = normalizedPoint(fromVisionPoint: point, width: width, height: height)
        UIUtilities.addCircle(
          atPoint: cgPoint,
          to: annotationOverlayView,
          color: UIColor.orange,
          radius: Constant.smallDotRadius
        )
      }
    }
    if let bottomLeftEyebrowContour = face.contour(ofType: .leftEyebrowBottom) {
      for point in bottomLeftEyebrowContour.points {
        let cgPoint = normalizedPoint(fromVisionPoint: point, width: width, height: height)
        UIUtilities.addCircle(
          atPoint: cgPoint,
          to: annotationOverlayView,
          color: UIColor.orange,
          radius: Constant.smallDotRadius
        )
      }
    }
    if let topRightEyebrowContour = face.contour(ofType: .rightEyebrowTop) {
      for point in topRightEyebrowContour.points {
        let cgPoint = normalizedPoint(fromVisionPoint: point, width: width, height: height)
        UIUtilities.addCircle(
          atPoint: cgPoint,
          to: annotationOverlayView,
          color: UIColor.orange,
          radius: Constant.smallDotRadius
        )
      }
    }
    if let bottomRightEyebrowContour = face.contour(ofType: .rightEyebrowBottom) {
      for point in bottomRightEyebrowContour.points {
        let cgPoint = normalizedPoint(fromVisionPoint: point, width: width, height: height)
        UIUtilities.addCircle(
          atPoint: cgPoint,
          to: annotationOverlayView,
          color: UIColor.orange,
          radius: Constant.smallDotRadius
        )
      }
    }

    // Eyes
    if let leftEyeContour = face.contour(ofType: .leftEye) {
      for point in leftEyeContour.points {
        let cgPoint = normalizedPoint(fromVisionPoint: point, width: width, height: height)
        UIUtilities.addCircle(
          atPoint: cgPoint,
          to: annotationOverlayView,
          color: UIColor.cyan,
          radius: Constant.smallDotRadius
        )
      }
    }
    if let rightEyeContour = face.contour(ofType: .rightEye) {
      for point in rightEyeContour.points {
        let cgPoint = normalizedPoint(fromVisionPoint: point, width: width, height: height)
        UIUtilities.addCircle(
          atPoint: cgPoint,
          to: annotationOverlayView,
          color: UIColor.cyan,
          radius: Constant.smallDotRadius
        )
      }
    }

    // Lips
    if let topUpperLipContour = face.contour(ofType: .upperLipTop) {
      for point in topUpperLipContour.points {
        let cgPoint = normalizedPoint(fromVisionPoint: point, width: width, height: height)
        UIUtilities.addCircle(
          atPoint: cgPoint,
          to: annotationOverlayView,
          color: UIColor.red,
          radius: Constant.smallDotRadius
        )
      }
    }
    if let bottomUpperLipContour = face.contour(ofType: .upperLipBottom) {
      for point in bottomUpperLipContour.points {
        let cgPoint = normalizedPoint(fromVisionPoint: point, width: width, height: height)
        UIUtilities.addCircle(
          atPoint: cgPoint,
          to: annotationOverlayView,
          color: UIColor.red,
          radius: Constant.smallDotRadius
        )
      }
    }
    if let topLowerLipContour = face.contour(ofType: .lowerLipTop) {
      for point in topLowerLipContour.points {
        let cgPoint = normalizedPoint(fromVisionPoint: point, width: width, height: height)
        UIUtilities.addCircle(
          atPoint: cgPoint,
          to: annotationOverlayView,
          color: UIColor.red,
          radius: Constant.smallDotRadius
        )
      }
    }
    if let bottomLowerLipContour = face.contour(ofType: .lowerLipBottom) {
      for point in bottomLowerLipContour.points {
        let cgPoint = normalizedPoint(fromVisionPoint: point, width: width, height: height)
        UIUtilities.addCircle(
          atPoint: cgPoint,
          to: annotationOverlayView,
          color: UIColor.red,
          radius: Constant.smallDotRadius
        )
      }
    }

    // Nose
    if let noseBridgeContour = face.contour(ofType: .noseBridge) {
      for point in noseBridgeContour.points {
        let cgPoint = normalizedPoint(fromVisionPoint: point, width: width, height: height)
        UIUtilities.addCircle(
          atPoint: cgPoint,
          to: annotationOverlayView,
          color: UIColor.yellow,
          radius: Constant.smallDotRadius
        )
      }
    }
    if let noseBottomContour = face.contour(ofType: .noseBottom) {
      for point in noseBottomContour.points {
        let cgPoint = normalizedPoint(fromVisionPoint: point, width: width, height: height)
        UIUtilities.addCircle(
          atPoint: cgPoint,
          to: annotationOverlayView,
          color: UIColor.yellow,
          radius: Constant.smallDotRadius
        )
      }
    }
  }
}

// MARK: AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      print("Failed to get image buffer from sample buffer.")
      return
    }
    lastFrame = sampleBuffer
    let visionImage = VisionImage(buffer: sampleBuffer)
    let orientation = UIUtilities.imageOrientation(
      fromDevicePosition: .front
    )

    visionImage.orientation = orientation
    let imageWidth = CGFloat(CVPixelBufferGetWidth(imageBuffer))
    let imageHeight = CGFloat(CVPixelBufferGetHeight(imageBuffer))
    var shouldEnableClassification = false
    var shouldEnableMultipleObjects = false
    switch currentDetector {
    case .onDeviceObjectProminentWithClassifier, .onDeviceObjectMultipleWithClassifier,
      .onDeviceObjectCustomProminentWithClassifier, .onDeviceObjectCustomMultipleWithClassifier:
      shouldEnableClassification = true
    default:
      break
    }
    switch currentDetector {
    case .onDeviceObjectMultipleNoClassifier, .onDeviceObjectMultipleWithClassifier,
      .onDeviceObjectCustomMultipleNoClassifier, .onDeviceObjectCustomMultipleWithClassifier:
      shouldEnableMultipleObjects = true
    default:
      break
    }

    
    detectFacesOnDevice(in: visionImage, width: imageWidth, height: imageHeight)
    
  }
}

// MARK: - Constants

public enum Detector: String {
  case onDeviceBarcode = "On-Device Barcode Scanner"
  case onDeviceFace = "On-Device Face Detection"
  case onDeviceText = "On-Device Text Recognition"
  case onDeviceObjectProminentNoClassifier = "ODT, single, no labeling"
  case onDeviceObjectProminentWithClassifier = "ODT, single, labeling"
  case onDeviceObjectMultipleNoClassifier = "ODT, multiple, no labeling"
  case onDeviceObjectMultipleWithClassifier = "ODT, multiple, labeling"
  case onDeviceObjectCustomProminentNoClassifier = "ODT, custom, single, no labeling"
  case onDeviceObjectCustomProminentWithClassifier = "ODT, custom, single, labeling"
  case onDeviceObjectCustomMultipleNoClassifier = "ODT, custom, multiple, no labeling"
  case onDeviceObjectCustomMultipleWithClassifier = "ODT, custom, multiple, labeling"
}

private enum Constant {
  static let alertControllerTitle = "Vision Detectors"
  static let alertControllerMessage = "Select a detector"
  static let cancelActionTitleText = "Cancel"
  static let videoDataOutputQueueLabel = "com.google.mlkit.visiondetector.VideoDataOutputQueue"
  static let sessionQueueLabel = "com.google.mlkit.visiondetector.SessionQueue"
  static let noResultsMessage = "No Results"
  static let localModelFile = (name: "bird", type: "tflite")
  static let labelConfidenceThreshold: Float = 0.75
  static let smallDotRadius: CGFloat = 4.0
  static let originalScale: CGFloat = 1.0
  static let padding: CGFloat = 10.0
  static let resultsLabelHeight: CGFloat = 200.0
  static let resultsLabelLines = 5
}
