import SwiftUI
import AVKit

struct VideoPlayerView: UIViewControllerRepresentable {
    let videoURL: URL
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: videoURL)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        
        // Use resizeAspect to maintain original aspect ratio without cropping
        controller.videoGravity = .resizeAspect
        
        // Start playing automatically
        player.play()
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Check if the player's URL is different from the current video URL
        if let currentItem = uiViewController.player?.currentItem,
           let currentURL = (currentItem.asset as? AVURLAsset)?.url,
           currentURL != videoURL {
            // Replace the player item if URLs are different
            let newPlayer = AVPlayer(url: videoURL)
            uiViewController.player = newPlayer
            newPlayer.play()
        } else if uiViewController.player?.currentItem == nil {
            // Create a new player if no item exists
            let newPlayer = AVPlayer(url: videoURL)
            uiViewController.player = newPlayer
            newPlayer.play()
        }
    }
}

struct VideoPlayerContainerView: View {
    @ObservedObject var manager: AudioVideoManager
    @Environment(\.presentationMode) var presentationMode
    @State private var isPlaying = true
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if let videoURL = manager.selectedVideoURL {
                VideoPlayerView(videoURL: videoURL)
                    .edgesIgnoringSafeArea(.all) // Make the video player full screen
            } else {
                Text("No video selected")
                    .foregroundColor(.white)
            }
            
            VStack {
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    .padding()
                    
                    Spacer()
                }
                
                Spacer()
            }
        }
    }
} 