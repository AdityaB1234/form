import Foundation
import AVFoundation
import Photos
import SwiftUI
import Combine
import AVKit

class AudioVideoManager: NSObject, ObservableObject {
    // Published properties for UI updates
    @Published var isRecording = false
    @Published var audioURL: URL?
    @Published var audioPlayer: AVAudioPlayer?
    @Published var isAudioPlaying = false
    @Published var recordedVideos: [URL] = []
    @Published var previewImage: UIImage?
    @Published var selectedVideoURL: URL?
    @Published var isProcessingVideo = false
    
    // Backend processing properties
    @Published var isUploadingToBackend = false
    @Published var isProcessingOnBackend = false
    @Published var processedVideoURL: URL?
    @Published var uploadProgress: Double = 0
    @Published var backendError: String?
    @Published var secondVideoURL: URL?
    
    // Backend URL - change this to your actual Python backend URL
    private let backendURL = "http://localhost:8000/process_videos"
    
    // Camera and recording components
    var captureSession: AVCaptureSession?
    var videoOutput: AVCaptureMovieFileOutput?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var recordingDelegate: VideoRecordingDelegate?
    
    // File management
    private let fileManager = FileManager.default
    private var videosDirectory: URL? {
        return try? fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("RecordedVideos", isDirectory: true)
    }
    
    // Document picker coordinator for second video selection
    private var coordinator: DocumentPickerCoordinator?
    
    override init() {
        super.init()
        setupVideosDirectory()
        loadSavedVideos()
    }
    
    // MARK: - Setup Methods
    
    private func setupVideosDirectory() {
        guard let directory = videosDirectory else { return }
        
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                print("Error creating videos directory: \(error)")
            }
        }
    }
    
    private func loadSavedVideos() {
        guard let directory = videosDirectory else { return }
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            recordedVideos = fileURLs.filter { $0.pathExtension == "mov" || $0.pathExtension == "mp4" }
        } catch {
            print("Error loading saved videos: \(error)")
        }
    }
    
    // MARK: - Backend Processing Methods
    
    /// Select a second video from the Photos library or Files app
    func selectSecondVideo(completion: @escaping (Bool) -> Void) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            completion(false)
            return
        }
        
        self.coordinator = DocumentPickerCoordinator(completion: { [weak self] url in
            guard let self = self else { return }
            self.secondVideoURL = url
            completion(true)
        }, failure: {
            completion(false)
        })
        
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie, .video])
        picker.delegate = coordinator
        picker.allowsMultipleSelection = false
        
        rootViewController.present(picker, animated: true, completion: nil)
    }
    
    /// Process videos with Python backend
    func processVideosWithBackend(firstVideoURL: URL, secondVideoURL: URL, completion: @escaping (Bool, String?) -> Void) {
        guard let backendURL = URL(string: self.backendURL) else {
            DispatchQueue.main.async { [weak self] in
                self?.backendError = "Invalid backend URL"
                completion(false, "Invalid backend URL")
            }
            return
        }
        
        // Reset state
        self.backendError = nil
        self.uploadProgress = 0
        self.isUploadingToBackend = true
        
        // Create a URL session with delegate to track upload progress
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0
        config.timeoutIntervalForResource = 600.0
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCache = nil
        
        // Add additional headers for better compatibility
        config.httpAdditionalHeaders = [
            "Accept": "*/*",
            "Connection": "keep-alive",
            "Cache-Control": "no-cache",
            "User-Agent": "VideoAudioApp/1.0"
        ]
        
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        // Create multipart form data request
        var request = URLRequest(url: backendURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Create multipart form data
        let dataBody = createDataBody(
            withParameters: [:],
            videos: [
                ["name": "first_video", "url": firstVideoURL],
                ["name": "second_video", "url": secondVideoURL]
            ],
            boundary: boundary
        )
        
        // Start the upload task
        let task = session.uploadTask(with: request, from: dataBody) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isUploadingToBackend = false
                
                if let error = error {
                    self.backendError = "Upload error: \(error.localizedDescription)"
                    completion(false, error.localizedDescription)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.backendError = "Invalid server response"
                    completion(false, "Invalid server response")
                    return
                }
                
                if httpResponse.statusCode != 200 {
                    self.backendError = "Server error: \(httpResponse.statusCode)"
                    completion(false, "Server error: \(httpResponse.statusCode)")
                    return
                }
                
                guard let data = data else {
                    self.backendError = "No data returned from server"
                    completion(false, "No data returned from server")
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let videoId = json["video_id"] as? String {
                        self.isProcessingOnBackend = true
                        self.checkProcessingStatus(videoId: videoId, completion: completion)
                    } else {
                        self.backendError = "Invalid response format"
                        completion(false, "Invalid response format")
                    }
                } catch {
                    self.backendError = "Failed to parse response: \(error.localizedDescription)"
                    completion(false, "Failed to parse response: \(error.localizedDescription)")
                }
            }
        }
        
        task.resume()
    }
    
    /// Check processing status on the backend
    private func checkProcessingStatus(videoId: String, maxAttempts: Int = 30, completion: @escaping (Bool, String?) -> Void) {
        var attemptCount = 0
        let statusCheckInterval: TimeInterval = 2.0 // Check every 2 seconds
        
        func checkStatus() {
            attemptCount += 1
            
            guard let statusURL = URL(string: "http://localhost:8000/status/\(videoId)") else {
                DispatchQueue.main.async { [weak self] in
                    self?.backendError = "Invalid status URL"
                    self?.isProcessingOnBackend = false
                    completion(false, "Invalid status URL")
                }
                return
            }
            
            let task = URLSession.shared.dataTask(with: statusURL) { [weak self] data, response, error in
                guard let self = self else { return }
                
                if let error = error {
                    DispatchQueue.main.async {
                        if attemptCount >= maxAttempts {
                            self.backendError = "Status check failed: \(error.localizedDescription)"
                            self.isProcessingOnBackend = false
                            completion(false, error.localizedDescription)
                        } else {
                            // Try again after delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + statusCheckInterval) {
                                checkStatus()
                            }
                        }
                    }
                    return
                }
                
                guard let data = data else {
                    DispatchQueue.main.async {
                        if attemptCount >= maxAttempts {
                            self.backendError = "No data in status response"
                            self.isProcessingOnBackend = false
                            completion(false, "No data in status response")
                        } else {
                            // Try again after delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + statusCheckInterval) {
                                checkStatus()
                            }
                        }
                    }
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let status = json["status"] as? String {
                        
                        if status == "completed" {
                            // Video processing is complete, display it
                            DispatchQueue.main.async {
                                self.isProcessingOnBackend = false
                                self.displayProcessedVideo(videoId: videoId)
                                completion(true, nil)
                            }
                        } else if status == "failed" {
                            DispatchQueue.main.async {
                                self.backendError = "Processing failed on server"
                                self.isProcessingOnBackend = false
                                completion(false, "Processing failed on server")
                            }
                        } else if attemptCount >= maxAttempts {
                            // Timeout reached
                            DispatchQueue.main.async {
                                self.backendError = "Processing timed out"
                                self.isProcessingOnBackend = false
                                completion(false, "Processing timed out")
                            }
                        } else {
                            // Still processing, check again after delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + statusCheckInterval) {
                                checkStatus()
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            if attemptCount >= maxAttempts {
                                self.backendError = "Invalid status format"
                                self.isProcessingOnBackend = false
                                completion(false, "Invalid status format")
                            } else {
                                // Try again after delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + statusCheckInterval) {
                                    checkStatus()
                                }
                            }
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        if attemptCount >= maxAttempts {
                            self.backendError = "Failed to parse status: \(error.localizedDescription)"
                            self.isProcessingOnBackend = false
                            completion(false, "Failed to parse status: \(error.localizedDescription)")
                        } else {
                            // Try again after delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + statusCheckInterval) {
                                checkStatus()
                            }
                        }
                    }
                }
            }
            
            task.resume()
        }
        
        // Start the status check loop
        checkStatus()
    }
    
    /// Create multipart form data body for upload
    private func createDataBody(withParameters params: [String: String], videos: [[String: Any]], boundary: String) -> Data {
        var body = Data()
        
        // Add parameters
        for (key, value) in params {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        // Add videos
        for video in videos {
            if let name = video["name"] as? String, let url = video["url"] as? URL {
                let fileName = url.lastPathComponent
                let mimeType = "video/mp4"
                
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
                
                do {
                    let videoData = try Data(contentsOf: url)
                    body.append(videoData)
                    body.append("\r\n".data(using: .utf8)!)
                } catch {
                    print("Error reading video data: \(error)")
                }
            }
        }
        
        // Close the body
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
    
    /// Download the processed video from the backend
    private func downloadProcessedVideo(videoId: String, completion: @escaping (Bool, String?) -> Void) {
        guard let downloadURL = URL(string: "http://localhost:8000/download/\(videoId)") else {
            DispatchQueue.main.async { [weak self] in
                self?.backendError = "Invalid download URL"
                self?.isProcessingOnBackend = false
                completion(false, "Invalid download URL")
            }
            return
        }
        
        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: downloadURL) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isProcessingOnBackend = false
                
                if let error = error {
                    self.backendError = "Download error: \(error.localizedDescription)"
                    completion(false, error.localizedDescription)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    self.backendError = "Server error during download"
                    completion(false, "Server error during download")
                    return
                }
                
                guard let data = data else {
                    self.backendError = "No video data received"
                    completion(false, "No video data received")
                    return
                }
                
                // Save the processed video
                let processedVideoURL = self.videosDirectory?.appendingPathComponent("processed_\(videoId).mp4")
                
                do {
                    try data.write(to: processedVideoURL!)
                    self.processedVideoURL = processedVideoURL
                    completion(true, nil)
                } catch {
                    self.backendError = "Failed to save processed video: \(error.localizedDescription)"
                    completion(false, "Failed to save processed video: \(error.localizedDescription)")
                }
            }
        }
        
        task.resume()
    }
    
    // MARK: - Camera Setup
    
    func setupCamera() -> Bool {
        captureSession = AVCaptureSession()
        
        guard let captureSession = captureSession else { return false }
        
        captureSession.beginConfiguration()
        
        // Set quality level
        if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        }
        
        // Add video input - use front camera
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoInput) else {
            return false
        }
        captureSession.addInput(videoInput)
        
        // Add audio input
        guard let audioDevice = AVCaptureDevice.default(for: .audio),
              let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
              captureSession.canAddInput(audioInput) else {
            return false
        }
        captureSession.addInput(audioInput)
        
        // Add video output
        let movieOutput = AVCaptureMovieFileOutput()
        if captureSession.canAddOutput(movieOutput) {
            captureSession.addOutput(movieOutput)
            self.videoOutput = movieOutput
            
            // Important: Fix the connection settings for proper orientation
            if let connection = movieOutput.connection(with: .video) {
                // Lock the orientation to portrait
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                
                // Mirror the front camera - TikTok style
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }
        } else {
            return false
        }
        
        captureSession.commitConfiguration()
        
        // Start the session on a background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
        
        return true
    }
    
    func setupPreviewLayer(in view: UIView) {
        guard let captureSession = captureSession else { return }
        
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer?.videoGravity = .resizeAspectFill // Fill the screen
        videoPreviewLayer?.frame = view.bounds
        
        // Lock preview to portrait orientation
        videoPreviewLayer?.connection?.videoOrientation = .portrait
        
        if let previewLayer = videoPreviewLayer {
            view.layer.addSublayer(previewLayer)
        }
    }
    
    // MARK: - Audio Methods
    
    func setAudioFile(url: URL) {
        audioURL = url
        prepareAudioPlayer()
    }
    
    private func prepareAudioPlayer() {
        guard let url = audioURL else { return }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.numberOfLoops = -1 // Loop indefinitely
        } catch {
            print("Error preparing audio player: \(error)")
        }
    }
    
    func playAudio() {
        guard let player = audioPlayer, !isAudioPlaying else { return }
        
        player.play()
        isAudioPlaying = true
    }
    
    func stopAudio() {
        guard let player = audioPlayer, isAudioPlaying else { return }
        
        player.stop()
        player.currentTime = 0
        isAudioPlaying = false
    }
    
    // MARK: - Video Recording Methods
    
    func startRecording() {
        guard let output = videoOutput, !isRecording else { return }
        
        // Create a unique filename for the video
        let fileName = "video_\(Date().timeIntervalSince1970).mov"
        guard let videosDir = videosDirectory else { return }
        let tempFileURL = videosDir.appendingPathComponent("temp_\(fileName)")
        
        // Play the audio in the background if available
        playAudio()
        
        // Start recording video
        recordingDelegate = VideoRecordingDelegate { [weak self] success in
            DispatchQueue.main.async {
                self?.isRecording = false
                
                if success, let strongSelf = self {
                    // Process the video with the background audio
                    strongSelf.isProcessingVideo = true
                    
                    if let audioUrl = strongSelf.audioURL {
                        // Final output URL
                        let finalFileURL = videosDir.appendingPathComponent(fileName)
                        
                        // Merge the recorded video with the background audio
                        strongSelf.mergeVideoWithAudio(videoURL: tempFileURL, audioURL: audioUrl, outputURL: finalFileURL) { success, outputURL in
                            DispatchQueue.main.async {
                                if success, let outputURL = outputURL {
                                    // Add the processed video to the collection
                                    strongSelf.recordedVideos.append(outputURL)
                                    strongSelf.selectedVideoURL = outputURL
                                    strongSelf.createThumbnail(for: outputURL)
                                    strongSelf.saveToPhotoLibrary(fileURL: outputURL)
                                    
                                    // Clean up temp file
                                    try? FileManager.default.removeItem(at: tempFileURL)
                                } else {
                                    // If merging fails, use the original video
                                    do {
                                        try FileManager.default.moveItem(at: tempFileURL, to: finalFileURL)
                                        strongSelf.recordedVideos.append(finalFileURL)
                                        strongSelf.selectedVideoURL = finalFileURL
                                        strongSelf.createThumbnail(for: finalFileURL)
                                        strongSelf.saveToPhotoLibrary(fileURL: finalFileURL)
                                    } catch {
                                        print("Error moving temp file: \(error)")
                                    }
                                }
                                strongSelf.isProcessingVideo = false
                            }
                        }
                    } else {
                        // No audio file, just use the recorded video
                        let finalFileURL = videosDir.appendingPathComponent(fileName)
                        do {
                            try FileManager.default.moveItem(at: tempFileURL, to: finalFileURL)
                            strongSelf.recordedVideos.append(finalFileURL)
                            strongSelf.selectedVideoURL = finalFileURL
                            strongSelf.createThumbnail(for: finalFileURL)
                            strongSelf.saveToPhotoLibrary(fileURL: finalFileURL)
                        } catch {
                            print("Error moving temp file: \(error)")
                        }
                        strongSelf.isProcessingVideo = false
                    }
                }
            }
        }
        
        output.startRecording(to: tempFileURL, recordingDelegate: recordingDelegate!)
        isRecording = true
    }
    
    func stopRecording() {
        guard let output = videoOutput, isRecording else { return }
        
        output.stopRecording()
        stopAudio()
    }
    
    // MARK: - Video Processing Methods
    
    private func mergeVideoWithAudio(videoURL: URL, audioURL: URL, outputURL: URL, completion: @escaping (Bool, URL?) -> Void) {
        // Absolute simplest approach: keep the video untouched and just add audio
        
        do {
            // Load assets
            let videoAsset = AVURLAsset(url: videoURL)
            let audioAsset = AVURLAsset(url: audioURL)
            
            // Create composition
            let composition = AVMutableComposition()
            
            // Get source tracks
            guard let videoTrack = videoAsset.tracks(withMediaType: .video).first else {
                print("No video track found")
                completion(false, nil)
                return
            }
            
            guard let audioTrack = audioAsset.tracks(withMediaType: .audio).first else {
                print("No audio track found")
                completion(false, nil)
                return
            }
            
            // Create composition tracks
            guard let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid) else {
                print("Couldn't create video composition track")
                completion(false, nil)
                return
            }
            
            guard let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid) else {
                print("Couldn't create audio composition track")
                completion(false, nil)
                return
            }
            
            // STEP 1: Copy the video track without ANY modifications
            let videoTimeRange = CMTimeRange(start: CMTime.zero, duration: videoAsset.duration)
            try compositionVideoTrack.insertTimeRange(videoTimeRange, of: videoTrack, at: CMTime.zero)
            
            // CRITICAL: Copy the original transform exactly
            compositionVideoTrack.preferredTransform = videoTrack.preferredTransform
            
            // STEP 2: Add audio track (loop if needed)
            var audioTime = CMTime.zero
            let audioDuration = audioAsset.duration
            
            while audioTime < videoAsset.duration {
                let durationToAdd = min(videoAsset.duration - audioTime, audioDuration)
                let audioRange = CMTimeRange(start: CMTime.zero, duration: durationToAdd)
                try compositionAudioTrack.insertTimeRange(audioRange, of: audioTrack, at: audioTime)
                audioTime = CMTimeAdd(audioTime, durationToAdd)
            }
            
            // Clean up existing file
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            
            // STEP 3: Export with HIGH quality preset and NO additional processing
            guard let exporter = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality) else {
                print("Could not create export session")
                completion(false, nil)
                return
            }
            
            exporter.outputURL = outputURL
            exporter.outputFileType = .mp4
            
            // CRITICAL: Don't modify the video in any way
            exporter.shouldOptimizeForNetworkUse = false
            
            // Export
            exporter.exportAsynchronously {
                DispatchQueue.main.async {
                    if exporter.status == .completed {
                        print("Export successful")
                        completion(true, outputURL)
                    } else {
                        print("Export failed: \(exporter.error?.localizedDescription ?? "Unknown error")")
                        
                        // If export fails, try the direct copy approach as last resort
                        self.directCopyApproach(videoURL: videoURL, audioURL: audioURL, outputURL: outputURL, completion: completion)
                    }
                }
            }
        } catch {
            print("Error processing video: \(error)")
            
            // If standard approach fails, try the direct copy approach
            directCopyApproach(videoURL: videoURL, audioURL: audioURL, outputURL: outputURL, completion: completion)
        }
    }
    
    // A more direct approach that uses lower-level AVFoundation APIs
    private func directCopyApproach(videoURL: URL, audioURL: URL, outputURL: URL, completion: @escaping (Bool, URL?) -> Void) {
        print("Trying direct copy approach...")
        
        do {
            // Just use the original video if audio merging fails
            let videoData = try Data(contentsOf: videoURL)
            try videoData.write(to: outputURL)
            print("Copied original video as fallback")
            completion(true, outputURL)
        } catch {
            print("Direct copy failed: \(error)")
            completion(false, nil)
        }
    }
    
    // MARK: - Utility Methods
    
    func createThumbnail(for videoURL: URL) {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let time = CMTimeMake(value: 1, timescale: 2) // Get thumbnail from first half second
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            let thumbnail = UIImage(cgImage: cgImage)
            DispatchQueue.main.async {
                self.previewImage = thumbnail
            }
        } catch {
            print("Error generating thumbnail: \(error)")
        }
    }
    
    func saveToPhotoLibrary(fileURL: URL) {
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                }) { success, error in
                    if let error = error {
                        print("Error saving video to photo library: \(error)")
                    }
                }
            }
        }
    }
    
    func displayProcessedVideo(videoId: String) {
        // First check the status
        checkVideoStatus(videoId: videoId) { status in
            if status == "completed" {
                // Get the video URL
                let url = URL(string: "http://127.0.0.1:8000/download/\(videoId)")!
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                
                URLSession.shared.dataTask(with: request) { data, response, error in
                    if let error = error {
                        print("Error downloading video info: \(error)")
                        return
                    }
                    
                    guard let data = data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let videoUrl = json["video_url"] as? String else {
                        print("Error parsing video info")
                        return
                    }
                    
                    // Create the full video URL
                    let fullVideoUrl = URL(string: "http://127.0.0.1:8000\(videoUrl)")!
                    
                    // Update UI on main thread
                    DispatchQueue.main.async {
                        // Create and configure AVPlayer
                        let player = AVPlayer(url: fullVideoUrl)
                        let playerViewController = AVPlayerViewController()
                        playerViewController.player = player
                        
                        // Present the video player
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let rootViewController = windowScene.windows.first?.rootViewController {
                            rootViewController.present(playerViewController, animated: true) {
                                player.play()
                            }
                        }
                    }
                }.resume()
            } else {
                print("Video processing not complete. Current status: \(status)")
            }
        }
    }
    
    // Helper function to check video status
    private func checkVideoStatus(videoId: String, completion: @escaping (String) -> Void) {
        let url = URL(string: "http://127.0.0.1:8000/status/\(videoId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error checking status: \(error)")
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else {
                print("Error parsing status")
                return
            }
            
            completion(status)
        }.resume()
    }
}

// MARK: - URLSessionTaskDelegate Extension
extension AudioVideoManager: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        DispatchQueue.main.async { [weak self] in
            self?.uploadProgress = progress
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("URLSession task failed with error: \(error.localizedDescription)")
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    print("Network connection lost")
                    DispatchQueue.main.async { [weak self] in
                        self?.backendError = "No internet connection"
                    }
                case .timedOut:
                    print("Request timed out")
                    DispatchQueue.main.async { [weak self] in
                        self?.backendError = "Request timed out"
                    }
                case .cannotConnectToHost:
                    print("Cannot connect to host")
                    DispatchQueue.main.async { [weak self] in
                        self?.backendError = "Cannot connect to server. Please check if the backend is running."
                    }
                case .networkConnectionLost:
                    print("Network connection lost during transfer")
                    DispatchQueue.main.async { [weak self] in
                        self?.backendError = "Connection lost during transfer"
                    }
                case .dnsLookupFailed:
                    print("DNS lookup failed")
                    DispatchQueue.main.async { [weak self] in
                        self?.backendError = "Cannot resolve server address"
                    }
                default:
                    print("URL error: \(urlError.code.rawValue)")
                    DispatchQueue.main.async { [weak self] in
                        self?.backendError = "Connection error: \(urlError.localizedDescription)"
                    }
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        if let error = error {
            print("URLSession became invalid with error: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                self?.backendError = "Session error: \(error.localizedDescription)"
            }
        }
    }
    
    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        print("Task is waiting for connectivity...")
        DispatchQueue.main.async { [weak self] in
            self?.backendError = "Waiting for network connection..."
        }
    }
}

// MARK: - Document Picker Coordinator
class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
    private let completion: (URL) -> Void
    private let failure: () -> Void
    
    init(completion: @escaping (URL) -> Void, failure: @escaping () -> Void) {
        self.completion = completion
        self.failure = failure
        super.init()
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            failure()
            return
        }
        
        // Start accessing the security-scoped resource
        let canAccess = url.startAccessingSecurityScopedResource()
        
        if canAccess {
            // Create a local copy of the video
            let fileManager = FileManager.default
            let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destinationURL = documentsDirectory.appendingPathComponent(url.lastPathComponent)
            
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                
                try fileManager.copyItem(at: url, to: destinationURL)
                
                // Stop accessing the security-scoped resource
                url.stopAccessingSecurityScopedResource()
                
                // Call the completion handler with the local copy
                completion(destinationURL)
            } catch {
                print("Error copying file: \(error)")
                url.stopAccessingSecurityScopedResource()
                failure()
            }
        } else {
            print("Failed to access the selected file")
            failure()
        }
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        failure()
    }
}

// MARK: - Video Recording Delegate
class VideoRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let completionHandler: (Bool) -> Void
    
    init(completionHandler: @escaping (Bool) -> Void) {
        self.completionHandler = completionHandler
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        // Recording started
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let success = error == nil
        completionHandler(success)
    }
} 