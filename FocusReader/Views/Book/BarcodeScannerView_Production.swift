import SwiftUI
import UIKit
import AVFoundation

// MARK: - SwiftUI Overlay View (아날로그 UI 래퍼)
struct BarcodeScannerView: View {
    var onBarcodeDetected: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var paperColor: Color { colorScheme == .dark ? Color.black : Color(red: 0.98, green: 0.97, blue: 0.95) }
    var inkColor: Color { colorScheme == .dark ? Color.white : Color.black }
    
    var body: some View {
        ZStack {
            // 1. 카메라 프리뷰 (기존 UIKit 레이어)
            BarcodeScannerCameraView { isbn in
                onBarcodeDetected(isbn)
            }
            .ignoresSafeArea()
            
            // 2. 아날로그 감성 오버레이 (UI 덮어쓰기)
            VStack(spacing: 0) {
                // 커스텀 헤더
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundStyle(inkColor)
                            .padding(12)
                            .background(paperColor, in: Circle())
                            .overlay(Circle().stroke(inkColor, lineWidth: 1.5))
                    }
                    
                    Spacer()
                    
                    Text("scan barcode.")
                        .font(.custom("ChalkboardSE-Bold", size: 20))
                        .foregroundStyle(inkColor)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(paperColor, in: RoundedRectangle(cornerRadius: 25))
                        .overlay(RoundedRectangle(cornerRadius: 25).stroke(inkColor, lineWidth: 1.5))
                    
                    Spacer()
                    
                    // 대칭용 투명 아이콘
                    Image(systemName: "xmark").font(.title2).padding(12).opacity(0)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                
                Spacer()
                
                // 스캔 영역 타겟 (스케치 느낌의 얇은 점선)
                RoundedRectangle(cornerRadius: 16)
                    .stroke(inkColor, style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                    .frame(width: 250, height: 150)
                    .background(paperColor.opacity(0.05))
                
                Spacer().frame(height: 30)
                
                // 안내 문구 (종이 라벨 스티커 느낌)
                Text("align barcode within the frame.")
                    .font(.custom("ChalkboardSE-Regular", size: 16))
                    .foregroundStyle(inkColor)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(paperColor, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                
                Spacer()
                Spacer()
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - SwiftUI Camera Wrapper
struct BarcodeScannerCameraView: UIViewControllerRepresentable {
    var onBarcodeDetected: (String) -> Void
    
    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let scanner = BarcodeScannerViewController()
        scanner.delegate = context.coordinator
        return scanner
    }
    
    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onBarcodeDetected: onBarcodeDetected)
    }
    
    class Coordinator: NSObject, BarcodeScannerDelegate {
        var onBarcodeDetected: (String) -> Void
        init(onBarcodeDetected: @escaping (String) -> Void) { self.onBarcodeDetected = onBarcodeDetected }
        func didDetectBarcode(_ code: String) { onBarcodeDetected(code) }
    }
}

// MARK: - Delegate Protocol
protocol BarcodeScannerDelegate: AnyObject {
    func didDetectBarcode(_ code: String)
}

// MARK: - UIKit ViewController (UI 요소 제거, 순수 카메라 기능만 남김)
class BarcodeScannerViewController: UIViewController {
    weak var delegate: BarcodeScannerDelegate?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasDetectedBarcode = false
    
    private let supportedCodeTypes = [
        AVMetadataObject.ObjectType.ean8,
        AVMetadataObject.ObjectType.ean13,
        AVMetadataObject.ObjectType.pdf417,
        AVMetadataObject.ObjectType.qr
    ]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black
        captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        guard let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else { return }
        
        if captureSession!.canAddInput(videoInput) { captureSession!.addInput(videoInput) } else { failed(); return }
        
        let metadataOutput = AVCaptureMetadataOutput()
        if captureSession!.canAddOutput(metadataOutput) {
            captureSession!.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = supportedCodeTypes
        } else { failed(); return }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        previewLayer!.frame = view.layer.bounds
        previewLayer!.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer!)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.captureSession?.startRunning() }
    }
    
    func failed() {
        let ac = UIAlertController(title: "Scanning not supported", message: "Your device does not support scanning.", preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        present(ac, animated: true)
        captureSession = nil
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasDetectedBarcode = false
        if captureSession?.isRunning == false { DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.captureSession?.startRunning() } }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession?.isRunning == true { captureSession?.stopRunning() }
    }
    
    override var prefersStatusBarHidden: Bool { return true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { return .portrait }
}

extension BarcodeScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !hasDetectedBarcode else { return }
        if let metadataObject = metadataObjects.first,
           let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
           let stringValue = readableObject.stringValue {
            
            let cleanedISBN = stringValue.filter { $0.isNumber }
            guard cleanedISBN.count == 10 || cleanedISBN.count == 13 else { return }
            
            hasDetectedBarcode = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            captureSession?.stopRunning()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.delegate?.didDetectBarcode(stringValue)
            }
        }
    }
}
