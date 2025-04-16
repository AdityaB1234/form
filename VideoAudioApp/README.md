# Video Audio App

A TikTok-style iOS app that allows users to record videos with background audio.

## Features

- Upload audio files to use as background music
- Record videos while the selected audio plays in the background
- Preview camera feed while recording
- Save videos to both the app's storage and the device's photo library
- Browse and playback previously recorded videos within the app

## Requirements

- iOS 15.0+
- Xcode 13.0+
- Swift 5.5+

## Getting Started

1. Open the project in Xcode
2. Select your development team in the Signing & Capabilities tab
3. Build and run the app on your iOS device (this app requires camera access, so simulators will have limited functionality)

## Usage

1. When you first launch the app, you'll see the camera view
2. Tap "Select Audio" to choose an audio file from your device
3. Once audio is selected, tap the red record button to start recording your video
4. Tap the stop button when you're done recording
5. Your recorded video will appear in the gallery at the bottom of the screen
6. Tap a video thumbnail to play it back with the background audio

## Permissions

This app requires the following permissions:

- Camera: To record videos
- Microphone: To record audio along with videos
- Photo Library: To access audio files and save recorded videos

## Notes

- The app is designed to work with various audio file formats (MP3, WAV, M4A, etc.)
- For the best experience, use high-quality audio files
- Background audio will loop during recording for longer videos 