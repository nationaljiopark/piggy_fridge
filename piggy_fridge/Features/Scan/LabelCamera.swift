import AVFoundation
import Foundation
import SwiftUI
import UIKit
import Vision

// Our own label camera: AVFoundation for the live picture, Vision for reading text and barcodes.
// It replaces VisionKit's DataScanner, whose picture stayed black inside this screen on a real iPhone
// even though the camera was on (green dot).

/// Runs the camera and reads about 2 frames a second. Works on a background queue.
nonisolated final class LabelCameraEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "piggyfridge.label-camera")
    private var lastRead = Date.distantPast
    private var configured = false

    var onTexts: ([String]) -> Void = { _ in }
    var onBarcode: (String) -> Void = { _ in }
    var onFail: (String) -> Void = { _ in }
    var onStatus: (String) -> Void = { _ in }

    private var frameCount = 0
    private var lastStatus = Date.distantPast
    private var note = ""
    private var observers: [NSObjectProtocol] = []

    private func watchSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] n in
            let err = (n.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription ?? "unknown"
            self?.note = "error: \(err)"
        })
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] n in
            let raw = (n.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int) ?? -1
            self?.note = "interrupted (reason \(raw))"
        })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
            self?.note = "interruption ended"
        })
    }

    /// Average brightness 0...100 of the camera picture (sampled), to tell "black picture" from "no picture".
    private func brightness(_ pixels: CVPixelBuffer) -> Int {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard CVPixelBufferGetPlaneCount(pixels) > 0,
              let base = CVPixelBufferGetBaseAddressOfPlane(pixels, 0) else { return -1 }
        let w = CVPixelBufferGetWidthOfPlane(pixels, 0)
        let h = CVPixelBufferGetHeightOfPlane(pixels, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0, count = 0
        var y = 0
        while y < h {
            var x = 0
            while x < w { sum += Int(bytes[y * stride + x]); count += 1; x += 32 }
            y += 32
        }
        return count == 0 ? -1 : sum * 100 / (count * 255)
    }

    func start() {
        queue.async { [self] in
            if !configured {
                configured = true
                watchSession()
                session.beginConfiguration()
                session.sessionPreset = .high
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input) else {
                    session.commitConfiguration()
                    let fail = onFail
                    DispatchQueue.main.async { fail("no back camera found (the Simulator has no camera)") }
                    return
                }
                session.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: queue)
                if session.canAddOutput(output) { session.addOutput(output) }
                session.commitConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus), (try? device.lockForConfiguration()) != nil {
                    device.focusMode = .continuousAutoFocus
                    device.unlockForConfiguration()
                }
            }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        frameCount += 1
        if now.timeIntervalSince(lastStatus) > 0.6, let px = CMSampleBufferGetImageBuffer(sampleBuffer) {
            lastStatus = now
            let text = "frames \(frameCount) · light \(brightness(px))% · \(session.isRunning ? "running" : "stopped") \(note)"
            let status = onStatus
            DispatchQueue.main.async { status(text) }
        }
        guard now.timeIntervalSince(lastRead) > 0.45,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastRead = now

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = false
        textRequest.recognitionLanguages = ["en-GB"]
        let codeRequest = VNDetectBarcodesRequest()
        codeRequest.symbologies = [.ean13, .ean8, .upce]

        // Phone held upright: the back camera's picture is rotated, so tell Vision.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .right)
        try? handler.perform([textRequest, codeRequest])

        let lines = (textRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let codes = (codeRequest.results ?? []).compactMap { $0.payloadStringValue }
        let onTexts = onTexts, onBarcode = onBarcode
        DispatchQueue.main.async {
            if !lines.isEmpty { onTexts(lines) }
            for code in codes { onBarcode(code) }
        }
    }
}

final class CameraPictureView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

/// The live camera picture used in "Add food". Reads labels while it is on screen.
struct LabelCameraView: UIViewRepresentable {
    var onTexts: ([String]) -> Void
    var onBarcode: (String) -> Void
    var onFail: (String) -> Void
    var onStatus: (String) -> Void = { _ in }

    func makeCoordinator() -> LabelCameraEngine { LabelCameraEngine() }

    func makeUIView(context: Context) -> CameraPictureView {
        let view = CameraPictureView()
        view.backgroundColor = .black
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = context.coordinator.session
        let engine = context.coordinator
        engine.onTexts = onTexts
        engine.onBarcode = onBarcode
        engine.onFail = onFail
        engine.onStatus = onStatus
        engine.start()
        return view
    }

    func updateUIView(_ view: CameraPictureView, context: Context) {
        let engine = context.coordinator
        engine.onTexts = onTexts
        engine.onBarcode = onBarcode
        engine.onFail = onFail
        engine.onStatus = onStatus
    }

    static func dismantleUIView(_ view: CameraPictureView, coordinator: LabelCameraEngine) {
        coordinator.stop()
    }
}
