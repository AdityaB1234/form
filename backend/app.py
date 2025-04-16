import os
import uuid
import time
import shutil
import threading
from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
from werkzeug.utils import secure_filename
import mediapipe as mp
import cv2
import numpy as np
import subprocess

app = Flask(__name__)
CORS(app, resources={
    r"/*": {
        "origins": "*",  # Allow all origins
        "methods": ["GET", "POST", "OPTIONS"],
        "allow_headers": ["Content-Type", "Accept", "Origin"],
        "expose_headers": ["Content-Type"],
        "supports_credentials": True,
        "max_age": 600
    }
})

# Configuration
UPLOAD_FOLDER = 'uploads'
PROCESSED_FOLDER = 'processed'
ALLOWED_EXTENSIONS = {'mp4', 'mov'}

# Create directories if they don't exist
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(PROCESSED_FOLDER, exist_ok=True)

# In-memory storage for job status
# In a production environment, you would use a database
job_status = {}

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def process_videosREAL(video_id, first_video_path, second_video_path):
    """
    Process videos and return the path to the processed video.
    """
    # Update status to processing
    job_status[video_id] = "processing"
    
    try:
        # Process the videos
        import cv2
        import mediapipe as mp
        import numpy as np
        import json
        import os

        def extract_keypoints(video_path):
            mp_pose = mp.solutions.pose
            pose = mp_pose.Pose()
            cap = cv2.VideoCapture(video_path)
            keypoints_data = []

            while cap.isOpened():
                ret, frame = cap.read()
                if not ret:
                    break
                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                results = pose.process(rgb)

                frame_keypoints = []
                if results.pose_landmarks:
                    for landmark in results.pose_landmarks.landmark:
                        frame_keypoints.append([landmark.x, landmark.y, landmark.z])
                else:
                    frame_keypoints = [[0, 0, 0]] * 33  # Default if no keypoints detected

                keypoints_data.append(frame_keypoints)

            cap.release()
            return np.array(keypoints_data)

        def compute_differences(kp1, kp2, threshold=.5):
            # Get the minimum length between the two videos
            min_length = min(kp1.shape[0], kp2.shape[0])
            
            # Trim both keypoint arrays to the minimum length
            kp1_trimmed = kp1[:min_length]
            kp2_trimmed = kp2[:min_length]
            
            # Compute differences between trimmed arrays
            frame_diffs = np.linalg.norm(kp1_trimmed - kp2_trimmed, axis=2)
            significant_frames = np.where(frame_diffs.mean(axis=1) > threshold)[0]
            print(f"the number of significant frames is{significant_frames.shape} ")
            return significant_frames, min_length

        def identify_significant_body_part(kp1, kp2):
            # Placeholder function to identify the significant body part
            # You will need to implement the logic to compare keypoints and return the body part name
            return "Body Part Name"  # Replace with actual logic

        def save_clips(video1_path, video2_path, significant_frames, output_dir=PROCESSED_FOLDER, context_seconds=1.0, min_length=None):
            
            cap1 = cv2.VideoCapture(video1)
            cap2 = cv2.VideoCapture(video2)
            mean_diffs = []
            frame_indices = []
            while True:
                ret1, frame1 = cap1.read()
                ret2, frame2 = cap2.read()
                if not ret1 or not ret2:
                    break
                gray1 = cv2.cvtColor(frame1, cv2.COLOR_BGR2GRAY)
                gray2 = cv2.cvtColor(frame2, cv2.COLOR_BGR2GRAY)
                if len(mean_diffs) > 0:
                    prev_gray1 = cv2.cvtColor(prev_frame1, cv2.COLOR_BGR2GRAY)
                    prev_gray2 = cv2.cvtColor(prev_frame2, cv2.COLOR_BGR2GRAY)
                    mean_diff = np.mean(np.abs(gray1 - prev_gray1)) + np.mean(np.abs(gray2 - prev_gray2))
                    mean_diffs.append(mean_diff)
                    frame_indices.append(cap1.get(cv2.CAP_PROP_POS_FRAMES))
                prev_frame1 = frame1
                prev_frame2 = frame2

            # Sort mean differences and find top 5%
            sorted_indices = np.argsort(mean_diffs)[-int(0.05 * len(mean_diffs)):]

            # Extract frames with 1-second context
            context_frames = []
            for idx in sorted_indices:
                start_idx = max(0, idx - 30)  # 30 frames = 1 second at 30fps
                end_idx = min(len(frame_indices), idx + 30)
                context_frames.extend(frame_indices[start_idx:end_idx])

            # Write extracted frames to output video
            fourcc = cv2.VideoWriter_fourcc(*'mp4v')
            out = cv2.VideoWriter(os.path.join(output_dir, f"{video_id}.mp4"), fourcc, 30.0, (int(cap1.get(3)), int(cap1.get(4))))
            for idx in context_frames:
                cap1.set(cv2.CAP_PROP_POS_FRAMES, idx)
                ret1, frame1 = cap1.read()
                cap2.set(cv2.CAP_PROP_POS_FRAMES, idx)
                ret2, frame2 = cap2.read()
                if height1 != height2:
                    scale1 = output_height / height1
                    scale2 = output_height / height2
                    new_width1 = int(width1 * scale1)
                    new_width2 = int(width2 * scale2)
                    frame1 = cv2.resize(frame1, (new_width1, output_height))
                    frame2 = cv2.resize(frame2, (new_width2, output_height))
                else:
                    new_width1 = width1
                    new_width2 = width2
                side_by_side = np.hstack((frame1, frame2))
                out.write(side_by_side)
            out.release()
            
            if frames_written == 0:
                raise ValueError("No frames were written to the output video")
            print(f"Total frames written: {frames_written}")

        def process_videos2(video1, video2, output_dir):
            print("Extracting keypoints...")
            try:
                kp1 = extract_keypoints(video1)
                kp2 = extract_keypoints(video2)
            except Exception as e:
                print(f"Error extracting keypoints: {e}")
                raise

            print("Computing differences...")
            try:
                significant_frames, min_length = compute_differences(kp1, kp2)
            except Exception as e:
                print(f"Error computing differences: {e}")
                raise

            print("Saving extracted clips...")
            try:
                save_clips(video1, video2, significant_frames, output_dir, min_length=min_length)
                print("Final video saved at", os.path.join(output_dir, f"{video_id}.mp4"))
            except Exception as e:
                print(f"Error saving clips: {e}")
                raise
        
        # Process the videos
        process_videos2(first_video_path, second_video_path, PROCESSED_FOLDER)
        
        # Get the output path
        output_path = os.path.join(PROCESSED_FOLDER, f"{video_id}.mp4")
        
        # Verify the output video exists
        if not os.path.exists(output_path):
            raise ValueError("Processed video was not created successfully")
        
        # Update status to completed
        job_status[video_id] = "completed"
        
        # Return the path to the processed video
        return output_path
        
    except Exception as e:
        print(f"Error processing videos: {e}")
        job_status[video_id] = "failed"
        raise

@app.route('/process_videos', methods=['POST', 'OPTIONS'])
def process_videos():
    if request.method == 'OPTIONS':
        return '', 204
    
    if 'first_video' not in request.files or 'second_video' not in request.files:
        return jsonify({'error': 'Missing video files'}), 400
    
    first_video = request.files['first_video']
    second_video = request.files['second_video']
    
    if first_video.filename == '' or second_video.filename == '':
        return jsonify({'error': 'No selected files'}), 400
    
    if not (allowed_file(first_video.filename) and allowed_file(second_video.filename)):
        return jsonify({'error': 'Invalid file type'}), 400
    
    # Generate unique IDs for the files
    video_id = str(uuid.uuid4())
    first_filename = secure_filename(f"{video_id}_first.mp4")
    second_filename = secure_filename(f"{video_id}_second.mp4")
    
    # Save the files
    first_path = os.path.join(UPLOAD_FOLDER, first_filename)
    second_path = os.path.join(UPLOAD_FOLDER, second_filename)
    first_video.save(first_path)
    second_video.save(second_path)
    
    # Start processing in a background thread
    job_status[video_id] = "processing"
    thread = threading.Thread(target=process_videosREAL, args=(video_id, first_path, second_path))
    thread.start()
    
    return jsonify({'video_id': video_id, 'status': 'processing'})

@app.route('/status/<video_id>', methods=['GET'])
def check_status(video_id):
    if video_id not in job_status:
        return jsonify({'error': 'Job not found'}), 404
    
    return jsonify({'status': job_status[video_id]})

@app.route('/download/<video_id>', methods=['GET'])
def download_video(video_id):
    if video_id not in job_status:
        return jsonify({'error': 'Job not found'}), 404
    
    if job_status[video_id] != "completed":
        return jsonify({'error': 'Video processing not completed'}), 400
    
    video_path = os.path.join(PROCESSED_FOLDER, f"{video_id}.mp4")
    
    if not os.path.exists(video_path):
        return jsonify({'error': 'Processed video not found'}), 404
    
    # Return the path instead of sending the file
    return jsonify({
        'video_path': video_path,
        'video_url': f'/video/{video_id}'
    })

@app.route('/video/<video_id>', methods=['GET'])
def serve_video(video_id):
    video_path = os.path.join(PROCESSED_FOLDER, f"{video_id}.mp4")
    return send_file(video_path, mimetype='video/mp4')

@app.route('/', methods=['GET'])
def index():
    return jsonify({
        'status': 'online',
        'endpoints': {
            'process_videos': 'POST /process_videos',
            'check_status': 'GET /status/<video_id>',
            'download_video': 'GET /download/<video_id>'
        }
    })

if __name__ == '__main__':
    print("\n=== Video Processing Backend ===")
    print("Starting server on http://0.0.0.0:8000")
    print("Access from your iOS app at http://127.0.0.1:8000")
    print("Press Ctrl+C to stop the server")
    print("===========================\n")
    app.run(host='0.0.0.0', port=8000, debug=True, threaded=True)