from flask import Flask, jsonify, request, send_file
import os
import uuid
import time
import threading
import shutil

app = Flask(__name__)

# In-memory storage for job status
job_status = {}

# Create necessary directories
UPLOAD_FOLDER = 'uploads'
PROCESSED_FOLDER = 'processed'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(PROCESSED_FOLDER, exist_ok=True)

@app.route('/')
def home():
    return jsonify({"status": "online"})

@app.route('/test')
def test():
    return jsonify({"message": "Connection successful!"})

@app.route('/process_videos', methods=['POST'])
def process_videos():
    """Endpoint to receive two videos and start processing"""
    # Generate a unique ID for this job
    video_id = str(uuid.uuid4())
    job_status[video_id] = "uploaded"
    
    # Extract the video files
    first_video = request.files.get('first_video')
    second_video = request.files.get('second_video')
    
    if not first_video or not second_video:
        return jsonify({"error": "Missing video files"}), 400
    
    # Create a directory for this job
    job_dir = os.path.join(UPLOAD_FOLDER, video_id)
    os.makedirs(job_dir, exist_ok=True)
    
    # Save the videos
    first_video_path = os.path.join(job_dir, first_video.filename)
    second_video_path = os.path.join(job_dir, second_video.filename)
    
    first_video.save(first_video_path)
    second_video.save(second_video_path)
    
    # Start processing in a background thread
    def process_in_background():
        # Simulate processing
        job_status[video_id] = "processing"
        time.sleep(5)  # Wait 5 seconds
        
        # Create a simple processed video (just copy the first video)
        output_path = os.path.join(PROCESSED_FOLDER, f"{video_id}.mp4")
        shutil.copy(first_video_path, output_path)
        
        # Mark as complete
        job_status[video_id] = "completed"
    
    thread = threading.Thread(target=process_in_background)
    thread.start()
    
    return jsonify({"video_id": video_id, "status": "uploaded"})

@app.route('/status/<video_id>', methods=['GET'])
def check_status(video_id):
    """Check the status of video processing"""
    if video_id not in job_status:
        return jsonify({"error": "Job not found"}), 404
    
    return jsonify({"status": job_status[video_id]})

@app.route('/download/<video_id>', methods=['GET'])
def download_video(video_id):
    """Download the processed video"""
    if video_id not in job_status:
        return jsonify({"error": "Job not found"}), 404
    
    if job_status[video_id] != "completed":
        return jsonify({"error": "Video processing not completed"}), 400
    
    video_path = os.path.join(PROCESSED_FOLDER, f"{video_id}.mp4")
    
    if not os.path.exists(video_path):
        return jsonify({"error": "Processed video not found"}), 404
    
    return send_file(video_path, as_attachment=True, download_name="processed_video.mp4")

if __name__ == '__main__':
    print("\n=== Test Server ===")
    print("Starting test server on http://0.0.0.0:5001")
    print("Access from your iOS app at http://127.0.0.1:5001")
    print("Available endpoints:")
    print("  - GET /                  : Check server status")
    print("  - GET /test              : Test connection")
    print("  - POST /process_videos   : Process two videos")
    print("  - GET /status/<video_id> : Check processing status")
    print("  - GET /download/<video_id>: Download processed video")
    print("Press Ctrl+C to stop the server\n")
    app.run(host='0.0.0.0', port=5001, debug=True) 