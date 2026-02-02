import cv2
import numpy as np
import torch
from pose.inference import predict_keypoints
from pose.feedback import squat_feedback, lunge_feedback

# Webcam setup
cap = cv2.VideoCapture(0)
if not cap.isOpened():
    print("Cannot open webcam")
    exit()

# Keypoint connections for skeleton drawing
SKELETON_CONNECTIONS = [
    (0, 15), (15, 3), (15, 4),      # Neck & shoulders
    (3, 5), (4, 6),                  # Arms
    (3, 9), (4, 10),                 # Torso to hips
    (9, 11), (10, 12),               # Legs
    (11, 13), (12, 14)               # Ankles
]

KEYPOINT_NAMES = [
    "nose","left_eye","right_eye","left_shoulder","right_shoulder",
    "left_elbow","right_elbow","left_wrist","right_wrist",
    "left_hip","right_hip","left_knee","right_knee",
    "left_ankle","right_ankle","neck"
]

def draw_skeleton(frame, kps):
    """Draw skeleton lines and points"""
    for x, y in kps:
        cv2.circle(frame, (int(x), int(y)), 4, (0,255,0), -1)
    for i, j in SKELETON_CONNECTIONS:
        if i < len(kps) and j < len(kps):
            pt1 = tuple(kps[i].astype(int))
            pt2 = tuple(kps[j].astype(int))
            cv2.line(frame, pt1, pt2, (0,255,255), 2)

while True:
    ret, frame = cap.read()
    if not ret:
        break

    # Predict keypoints
    kps = predict_keypoints(frame)  # shape (16, 2)
    
    # Draw skeleton
    draw_skeleton(frame, kps)

    # Feedback
    squat_msg = squat_feedback(kps)
    lunge_msg = lunge_feedback(kps)

    cv2.putText(frame, squat_msg, (10, 30),
                cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0,255,0), 2)
    cv2.putText(frame, lunge_msg, (10, 60),
                cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0,255,0), 2)

    cv2.imshow("AI GymMate Demo", frame)

    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()
