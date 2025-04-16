import SwiftUI
import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

struct AudioPickerView: UIViewControllerRepresentable {
    @ObservedObject var manager: AudioVideoManager
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Set the document types to audio files
        let supportedTypes: [UTType] = [.audio, .mp3, .wav, .mpeg4Audio, .appleProtectedMPEG4Audio]
        
        // Create document picker controller
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes)
        controller.allowsMultipleSelection = false
        controller.delegate = context.coordinator
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No update needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: AudioPickerView
        
        init(_ parent: AudioPickerView) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // Get access to the file
            guard url.startAccessingSecurityScopedResource() else {
                print("Failed to access the selected file")
                return
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            // Copy the file to app's document directory for persistent access
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destinationURL = documentsDirectory.appendingPathComponent(url.lastPathComponent)
            
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                
                try FileManager.default.copyItem(at: url, to: destinationURL)
                
                DispatchQueue.main.async {
                    self.parent.manager.setAudioFile(url: destinationURL)
                    self.parent.isPresented = false
                }
            } catch {
                print("Error copying file to app directory: \(error)")
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
} 