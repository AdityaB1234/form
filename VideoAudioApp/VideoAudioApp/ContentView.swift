import SwiftUI
import AVFoundation
import Photos

struct ContentView: View {
    @StateObject private var audioVideoManager = AudioVideoManager()
    @State private var showingVideoPlayer = false
    @State private var lastSelectedVideo: URL?
    @State private var showingBackendOptions = false
    @State private var showingProcessedVideo = false
    @State private var processingComplete = false
    
    var body: some View {
        ZStack {
            // Camera view background (full screen)
            CameraView(manager: audioVideoManager)
                .edgesIgnoringSafeArea(.all)
            
            // Controls overlay
            CameraControlsView(manager: audioVideoManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.2))
            
            // Processing Button at bottom of screen
            VStack {
                Spacer()
                
                if !audioVideoManager.recordedVideos.isEmpty {
                    Button(action: {
                        if processingComplete {
                            // Show the processed video
                            showingProcessedVideo = true
                        } else {
                            // Show the video selection screen
                            showingBackendOptions = true
                        }
                    }) {
                        Text(processingComplete ? "See Processed" : "Process Videos")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(processingComplete ? Color.green : Color.blue)
                            .cornerRadius(10)
                    }
                    .padding(.bottom, 100) // Position above camera controls
                }
            }
            
            // Backend processing UI overlay
            if showingBackendOptions {
                BackendProcessingView(manager: audioVideoManager, isShowing: $showingBackendOptions) { success in
                    if success {
                        processingComplete = true
                        showingProcessedVideo = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingVideoPlayer, onDismiss: {
            // Store the last selected video so we can select it again
            lastSelectedVideo = audioVideoManager.selectedVideoURL
            // Reset selection to allow selecting the same video again
            audioVideoManager.selectedVideoURL = nil
        }) {
            VideoPlayerContainerView(manager: audioVideoManager)
        }
        .sheet(isPresented: $showingProcessedVideo) {
            if let processedURL = audioVideoManager.processedVideoURL {
                ProcessedVideoPlayerView(videoURL: processedURL, onDismiss: {
                    showingProcessedVideo = false
                })
            }
        }
        .onChange(of: audioVideoManager.selectedVideoURL) { newValue in
            // Show video player when a video is selected from the bottom gallery
            if let newURL = newValue {
                // Only show if it's a new URL or the same URL we previously watched
                if lastSelectedVideo != newURL || lastSelectedVideo == newURL {
                    showingVideoPlayer = true
                }
            }
        }
    }
}

// Backend processing UI
struct BackendProcessingView: View {
    @ObservedObject var manager: AudioVideoManager
    @Binding var isShowing: Bool
    var onProcessingComplete: (Bool) -> Void
    
    @State private var firstSelectedVideoIndex: Int?
    @State private var secondSelectedVideoIndex: Int?
    @State private var processingStarted = false
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.85)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                // Header
                Text("Process Videos")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding(.top, 20)
                
                if manager.isUploadingToBackend || manager.isProcessingOnBackend {
                    // Progress view
                    VStack(spacing: 15) {
                        ProgressView(value: manager.isUploadingToBackend ? manager.uploadProgress : nil)
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(width: 250)
                        
                        Text(
                            manager.isUploadingToBackend 
                            ? "Uploading videos: \(Int(manager.uploadProgress * 100))%" 
                            : "Processing on backend server..."
                        )
                        .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(15)
                } else if let error = manager.backendError {
                    // Error view
                    VStack {
                        Text("Error")
                            .font(.headline)
                            .foregroundColor(.red)
                        
                        Text(error)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(15)
                } else if !processingStarted {
                    // Select videos view
                    VStack(spacing: 15) {
                        Text("Select two videos to process")
                            .foregroundColor(.white)
                        
                        Text("First video:")
                            .foregroundColor(.gray)
                        
                        // First video selection (recorded videos)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(manager.recordedVideos.indices, id: \.self) { index in
                                    BackendVideoThumbnail(
                                        url: manager.recordedVideos[index],
                                        isSelected: firstSelectedVideoIndex == index
                                    )
                                    .frame(width: 100, height: 150)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(firstSelectedVideoIndex == index ? Color.green : Color.clear, lineWidth: 2)
                                    )
                                    .onTapGesture {
                                        if secondSelectedVideoIndex == index {
                                            // Can't select the same video twice
                                            return
                                        }
                                        firstSelectedVideoIndex = index
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(height: 150)
                        
                        Text("Second video:")
                            .foregroundColor(.gray)
                        
                        // Second video selection (also from recorded videos)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(manager.recordedVideos.indices, id: \.self) { index in
                                    BackendVideoThumbnail(
                                        url: manager.recordedVideos[index],
                                        isSelected: secondSelectedVideoIndex == index
                                    )
                                    .frame(width: 100, height: 150)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(secondSelectedVideoIndex == index ? Color.blue : Color.clear, lineWidth: 2)
                                    )
                                    .onTapGesture {
                                        if firstSelectedVideoIndex == index {
                                            // Can't select the same video twice
                                            return
                                        }
                                        secondSelectedVideoIndex = index
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(height: 150)
                        
                        // Process button
                        Button(action: {
                            guard let firstIndex = firstSelectedVideoIndex,
                                  let secondIndex = secondSelectedVideoIndex else { return }
                            
                            let firstURL = manager.recordedVideos[firstIndex]
                            let secondURL = manager.recordedVideos[secondIndex]
                            
                            processingStarted = true
                            
                            manager.processVideosWithBackend(
                                firstVideoURL: firstURL,
                                secondVideoURL: secondURL
                            ) { success, _ in
                                processingStarted = false
                                if success {
                                    onProcessingComplete(true)
                                    isShowing = false  // Dismiss this view when processing succeeds
                                }
                            }
                        }) {
                            Text("Process Videos")
                                .padding()
                                .frame(width: 200)
                                .background(firstSelectedVideoIndex != nil && secondSelectedVideoIndex != nil ? Color.green : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .disabled(firstSelectedVideoIndex == nil || secondSelectedVideoIndex == nil)
                    }
                }
                
                // Close button
                Button(action: {
                    isShowing = false
                }) {
                    Text("Close")
                        .padding(.horizontal, 30)
                        .padding(.vertical, 10)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.bottom, 20)
            }
            .padding()
            .background(Color.black.opacity(0.7))
            .cornerRadius(20)
            .padding()
        }
    }
}

// Backend video thumbnail
struct BackendVideoThumbnail: View {
    let url: URL
    let isSelected: Bool
    @State private var thumbnail: UIImage?
    
    var body: some View {
        ZStack {
            if let image = thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.5))
                    .overlay(
                        ProgressView()
                    )
            }
        }
        .onAppear {
            generateThumbnail()
        }
    }
    
    private func generateThumbnail() {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let time = CMTimeMake(value: 1, timescale: 2)
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            self.thumbnail = UIImage(cgImage: cgImage)
        } catch {
            print("Error generating thumbnail: \(error)")
        }
    }
}

// Processed video player
struct ProcessedVideoPlayerView: View {
    let videoURL: URL
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VideoPlayerView(videoURL: videoURL)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    .padding()
                    
                    Spacer()
                    
                    Button(action: {
                        saveToPhotoLibrary()
                    }) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    .padding()
                }
                
                Spacer()
                
                Text("Processed Video")
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(20)
                    .padding(.bottom, 20)
            }
        }
    }
    
    private func saveToPhotoLibrary() {
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                }) { success, error in
                    if let error = error {
                        print("Error saving processed video to library: \(error)")
                    }
                }
            }
        }
    }
} 