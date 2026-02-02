import numpy as np

def angle(a, b, c):
    ba = a - b
    bc = c - b
    cos = np.dot(ba, bc) / (np.linalg.norm(ba) * np.linalg.norm(bc))
    return np.degrees(np.arccos(np.clip(cos, -1.0, 1.0)))

def squat_feedback(kps):
    hip = kps[9]
    knee = kps[11]
    ankle = kps[13]

    knee_angle = angle(hip, knee, ankle)

    if knee_angle < 90:
        return "Good squat depth"
    else:
        return "Go lower"

def lunge_feedback(kps):
    hip = kps[9]
    knee = kps[11]
    ankle = kps[13]

    knee_angle = angle(hip, knee, ankle)

    if 80 < knee_angle < 100:
        return "Good lunge form"
    else:
        return "Adjust stance"
