# Video Processing Backend

This is a simple Flask-based backend for processing videos. It receives two videos from the iOS app, processes them, and provides the result for download.

## Setup

1. Install the required dependencies:

```bash
pip install -r requirements.txt
```

2. Run the server:

```bash
python app.py
```

The server will start on http://localhost:8000.

## API Endpoints

### Upload Videos for Processing
- **URL:** `/process_videos`
- **Method:** `POST`
- **Content-Type:** `multipart/form-data`
- **Form Parameters:**
  - `first_video`: The first video file
  - `second_video`: The second video file
- **Response:**
  - `video_id`: A unique ID for tracking the processing job
  - `status`: Initial status ("uploaded")

### Check Processing Status
- **URL:** `/status/<video_id>`
- **Method:** `GET`
- **Response:**
  - `status`: Current status ("uploaded", "processing", "completed", or "failed")

### Download Processed Video
- **URL:** `/download/<video_id>`
- **Method:** `GET`
- **Response:**
  - The processed video file (when completed)
  - Error message (if not completed or not found)

## Folder Structure

- `uploads/`: Temporary storage for uploaded videos
- `processed/`: Storage for processed video files

## Notes

This is a simplified implementation that simulates video processing. In a production environment, you would:

1. Use a proper database to track job status
2. Implement actual video processing logic
3. Add authentication and security measures
4. Implement error handling and cleanup of temporary files 