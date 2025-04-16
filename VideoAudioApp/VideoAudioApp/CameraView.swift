import SwiftUI
import AVFoundation

struct CameraView: UIViewRepresentable {
    @ObservedObject var manager: AudioVideoManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        
        // Setup the capture session
        if manager.setupCamera() {
            // Setup the preview layer
            manager.setupPreviewLayer(in: view)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update view if needed
        if let previewLayer = manager.videoPreviewLayer {
            previewLayer.frame = uiView.bounds
        }
    }
}

struct CameraControlsView: View {
    @ObservedObject var manager: AudioVideoManager
    @State private var showAudioPicker = false
    
    var body: some View {
        ZStack {
            VStack {
                Spacer()
                
                // Audio selection button
                if manager.audioURL == nil {
                    Button(action: {
                        showAudioPicker = true
                    }) {
                        HStack {
                            Image(systemName: "music.note")
                            Text("Select Audio")
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding(.bottom, 20)
                } else {
                    HStack {
                        Text("Audio: \(manager.audioURL?.lastPathComponent ?? "None")")
                            .foregroundColor(.white)
                            .padding(.horizontal)
                        
                        Button(action: {
                            // Replace audio
                            showAudioPicker = true
                        }) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.bottom, 10)
                }
                
                // Recording controls
                HStack(spacing: 60) {
                    if !manager.isRecording {
                        // Record button
                        Button(action: {
                            manager.startRecording()
                        }) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 70, height: 70)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 4)
                                        .frame(width: 70, height: 70)
                                )
                        }
                        .disabled(manager.audioURL == nil || manager.isProcessingVideo)
                        .opacity((manager.audioURL == nil || manager.isProcessingVideo) ? 0.5 : 1.0)
                    } else {
                        // Stop button
                        Button(action: {
                            manager.stopRecording()
                        }) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.red)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white, lineWidth: 4)
                                        .frame(width: 40, height: 40)
                                )
                        }
                    }
                }
                .padding(.bottom, 30)
                
                // Recently recorded videos thumbnails
                if !manager.recordedVideos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(manager.recordedVideos, id: \.self) { videoURL in
                                VideoThumbnailView(videoURL: videoURL, manager: manager)
                                    .frame(width: 80, height: 120)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(manager.selectedVideoURL == videoURL ? Color.yellow : Color.clear, lineWidth: 2)
                                    )
                                    .onTapGesture {
                                        if !manager.isProcessingVideo {
                                            manager.selectedVideoURL = videoURL
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 120)
                    .padding(.bottom, 20)
                }
            }
            
            // Video processing overlay
            if manager.isProcessingVideo {
                ZStack {
                    Color.black.opacity(0.7)
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        
                        Text("Processing Video...")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("Merging audio with your video")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(30)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(15)
                }
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showAudioPicker) {
            AudioPickerView(manager: manager, isPresented: $showAudioPicker)
        }
        .animation(.default, value: manager.isProcessingVideo)
    }
}

struct VideoThumbnailView: View {
    let videoURL: URL
    @ObservedObject var manager: AudioVideoManager
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
            
            // Play icon
            Image(systemName: "play.fill")
                .foregroundColor(.white)
                .opacity(0.8)
                .shadow(radius: 2)
        }
        .onAppear {
            generateThumbnail()
        }
    }
    
    private func generateThumbnail() {
        let asset = AVAsset(url: videoURL)
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