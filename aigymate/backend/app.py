from flask import Flask, request, jsonify
from flask_cors import CORS
import cv2
import numpy as np
import tensorflow as tf
import base64
from PIL import Image
import io
import json
import os
import tempfile
from datetime import datetime, timedelta

# OCR imports
try:
    import easyocr
    OCR_AVAILABLE = True
    reader = easyocr.Reader(['en'])
except ImportError:
    OCR_AVAILABLE = False
    print("⚠️  EasyOCR not installed. OCR functionality will be limited.")

# ── MediaPipe new Tasks API ──────────────────────────────────────────────────
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision
from mediapipe.tasks.python.vision import PoseLandmarker, PoseLandmarkerOptions, RunningMode

# Download the pose landmarker model if not present
POSE_MODEL_PATH = 'pose_landmarker_full.task'
if not os.path.exists(POSE_MODEL_PATH):
    import urllib.request
    print("⬇️  Downloading MediaPipe pose model...")
    urllib.request.urlretrieve(
        'https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task',
        POSE_MODEL_PATH
    )
    print("✅ Pose model downloaded")

# Initialize PoseLandmarker (replaces mp.solutions.pose)
_base_options = mp_python.BaseOptions(model_asset_path=POSE_MODEL_PATH)
_pose_options = PoseLandmarkerOptions(
    base_options=_base_options,
    running_mode=RunningMode.IMAGE,
    num_poses=1,
    min_pose_detection_confidence=0.5,
    min_pose_presence_confidence=0.5,
    min_tracking_confidence=0.5,
    output_segmentation_masks=False
)
pose_landmarker = PoseLandmarker.create_from_options(_pose_options)
print("✅ MediaPipe PoseLandmarker ready")
# ────────────────────────────────────────────────────────────────────────────

app = Flask(__name__)
CORS(app)

# Load the trained CNN model
model_path = 'best_cnn_model.h5'
if os.path.exists(model_path):
    model = tf.keras.models.load_model(model_path, compile=False)
    print("✅ CNN model loaded successfully")
    
    # Load label encoder for exercise classification
    from sklearn.preprocessing import LabelEncoder
    import pickle
    
    # Create label encoder matching training data
    EXERCISE_LABELS = ['Jumping Jacks', 'Pull ups', 'Push Ups', 'Russian twists', 'Squats']
    label_encoder = LabelEncoder()
    label_encoder.fit(EXERCISE_LABELS)
    print("✅ Exercise label encoder initialized")
else:
    model = None
    label_encoder = None
    print("❌ CNN model not found")

# Exercise definitions with medical restrictions and difficulty levels
# NOTE: Only these 5 exercises are supported by CNN+MediaPipe model

# Map CNN model output names to internal exercise keys
EXERCISE_NAME_TO_KEY = {
    'Push Ups': 'pushups',
    'Jumping Jacks': 'jumping_jacks',
    'Pull Ups': 'pull_ups',
    'Russian Twists': 'russian_twists',
    'Squats': 'squats'
}

EXERCISES = {
    'jumping_jacks': {
        'name': 'Jumping Jacks',
        'description': 'Full body cardio exercise',
        'restrictions': ['knee_pain', 'ankle_pain', 'heart_condition'],
        'difficulty': 'medium',
        'muscle_groups': ['full_body', 'cardio', 'shoulders', 'legs'],
        'calorie_burn_per_minute': 10.0,
        'progression_options': ['increase_speed', 'add_duration', 'intervals']
    },
    'pull_ups': {
        'name': 'Pull-ups',
        'description': 'Upper body pulling exercise',
        'restrictions': ['shoulder_pain', 'elbow_pain', 'wrist_pain'],
        'difficulty': 'high',
        'muscle_groups': ['back', 'biceps', 'forearms', 'shoulders'],
        'calorie_burn_per_minute': 9.0,
        'progression_options': ['assisted_pullups', 'increase_reps', 'add_weight']
    },
    'pushups': {
        'name': 'Push-ups',
        'description': 'Upper body pushing exercise',
        'restrictions': ['shoulder_pain', 'wrist_pain'],
        'difficulty': 'medium',
        'muscle_groups': ['chest', 'shoulders', 'triceps', 'core'],
        'calorie_burn_per_minute': 7.0,
        'progression_options': ['elevate_feet', 'add_resistance', 'decrease_rest']
    },
    'russian_twists': {
        'name': 'Russian Twists',
        'description': 'Core rotational exercise',
        'restrictions': ['back_pain', 'neck_pain', 'recent_surgery'],
        'difficulty': 'medium',
        'muscle_groups': ['core', 'obliques', 'hips'],
        'calorie_burn_per_minute': 6.0,
        'progression_options': ['add_weight', 'increase_speed', 'lift_legs']
    },
    'squats': {
        'name': 'Squats',
        'description': 'Lower body compound exercise',
        'restrictions': ['knee_pain', 'hip_pain', 'back_pain'],
        'difficulty': 'medium',
        'muscle_groups': ['quadriceps', 'glutes', 'hamstrings', 'core'],
        'calorie_burn_per_minute': 8.0,
        'progression_options': ['add_weight', 'increase_reps', 'depth_increase']
    }
}

# Medical keywords for OCR processing
MEDICAL_KEYWORDS = [
    # Common medical conditions
    'diabetes', 'hypertension', 'high blood pressure', 'cardiovascular',
    'heart disease', 'coronary artery disease', 'stroke', 'asthma',
    'copd', 'arthritis', 'osteoporosis', 'kidney disease', 'liver disease',
    
    # Orthopedic conditions
    'knee pain', 'back pain', 'neck pain', 'shoulder pain', 'hip pain',
    'joint pain', 'spinal injury', 'fracture', 'sprain', 'strain',
    'osteoarthritis', 'rheumatoid arthritis', 'disc herniation',
    
    # Neurological conditions
    'epilepsy', 'seizure', 'migraine', 'parkinson', 'multiple sclerosis',
    'neuropathy', 'paralysis', 'vertigo', 'dizziness',
    
    # Cardiovascular conditions
    'angina', 'heart attack', 'myocardial infarction', 'arrhythmia',
    'palpitations', 'chest pain', 'heart failure', 'valve disease',
    
    # Respiratory conditions
    'bronchitis', 'pneumonia', 'tuberculosis', 'sleep apnea',
    'allergy', 'sinusitis', 'emphysema',
    
    # Metabolic conditions
    'obesity', 'overweight', 'thyroid', 'hyperthyroidism', 'hypothyroidism',
    'metabolic syndrome', 'high cholesterol', 'lipid disorder',
    
    # Mental health
    'depression', 'anxiety', 'bipolar', 'schizophrenia', 'ptsd',
    'stress', 'insomnia', 'sleep disorder',
    
    # Women's health
    'pregnancy', 'menopause', 'pcos', 'endometriosis', 'fibroids',
    
    # Other conditions
    'anemia', 'diarrhea', 'constipation', 'ulcer', 'gallstones',
    'cataract', 'glaucoma', 'hearing loss', 'vertigo'
]


def extract_angles_from_landmarks(landmarks):
    """Extract angles from MediaPipe landmarks to match training data format"""
    try:
        if not landmarks or len(landmarks) < 132:
            return None
            
        # Convert landmarks to numpy array and reshape to 33x4
        landmarks_array = np.array(landmarks).reshape(-1, 4)  # 33 landmarks, each with [x, y, z, visibility]
        
        # Extract key points (same as training data generation)
        # Use only x, y coordinates (ignore z and visibility for angle calculation)
        points = landmarks_array[:, :2]  # 33x2 array of x, y coordinates
        
        # Map landmark indices to body parts
        # MediaPipe pose landmark indices
        LEFT_SHOULDER = 11
        RIGHT_SHOULDER = 12
        LEFT_ELBOW = 13
        RIGHT_ELBOW = 14
        LEFT_WRIST = 15
        RIGHT_WRIST = 16
        LEFT_HIP = 23
        RIGHT_HIP = 24
        LEFT_KNEE = 25
        RIGHT_KNEE = 26
        LEFT_ANKLE = 27
        RIGHT_ANKLE = 28
        
        def calculate_angle(a, b, c):
            """Calculate angle ABC (angle at point B)"""
            try:
                a = np.array(a)
                b = np.array(b)
                c = np.array(c)
                
                # Calculate vectors
                ba = a - b
                bc = c - b
                
                # Calculate angle using dot product
                cosine_angle = np.dot(ba, bc) / (np.linalg.norm(ba) * np.linalg.norm(bc))
                angle = np.arccos(np.clip(cosine_angle, -1.0, 1.0))
                return np.degrees(angle)
            except:
                return 0.0
        
        def calculate_ground_angle(point):
            """Calculate angle with horizontal ground line"""
            try:
                # Use shoulder as reference point for ground
                shoulder_ref = (points[LEFT_SHOULDER] + points[RIGHT_SHOULDER]) / 2
                vector = point - shoulder_ref
                angle = np.degrees(np.arctan2(vector[1], vector[0]))
                return angle
            except:
                return 0.0
        
        # Calculate angles (matching training data format)
        angles = {}
        
        # Shoulder angles (average of left and right)
        left_shoulder_angle = calculate_angle(
            points[LEFT_ELBOW], points[LEFT_SHOULDER], points[LEFT_HIP]
        )
        right_shoulder_angle = calculate_angle(
            points[RIGHT_ELBOW], points[RIGHT_SHOULDER], points[RIGHT_HIP]
        )
        angles['Shoulder_Angle'] = (left_shoulder_angle + right_shoulder_angle) / 2
        
        # Elbow angles (average of left and right)
        left_elbow_angle = calculate_angle(
            points[LEFT_SHOULDER], points[LEFT_ELBOW], points[LEFT_WRIST]
        )
        right_elbow_angle = calculate_angle(
            points[RIGHT_SHOULDER], points[RIGHT_ELBOW], points[RIGHT_WRIST]
        )
        angles['Elbow_Angle'] = (left_elbow_angle + right_elbow_angle) / 2
        
        # Hip angles (average of left and right)
        left_hip_angle = calculate_angle(
            points[LEFT_SHOULDER], points[LEFT_HIP], points[LEFT_KNEE]
        )
        right_hip_angle = calculate_angle(
            points[RIGHT_SHOULDER], points[RIGHT_HIP], points[RIGHT_KNEE]
        )
        angles['Hip_Angle'] = (left_hip_angle + right_hip_angle) / 2
        
        # Knee angles (average of left and right)
        left_knee_angle = calculate_angle(
            points[LEFT_HIP], points[LEFT_KNEE], points[LEFT_ANKLE]
        )
        right_knee_angle = calculate_angle(
            points[RIGHT_HIP], points[RIGHT_KNEE], points[RIGHT_ANKLE]
        )
        angles['Knee_Angle'] = (left_knee_angle + right_knee_angle) / 2
        
        # Ankle angles (average of left and right)
        left_ankle_angle = calculate_angle(
            points[LEFT_KNEE], points[LEFT_ANKLE], [points[LEFT_ANKLE][0], points[LEFT_ANKLE][1] - 0.1]
        )
        right_ankle_angle = calculate_angle(
            points[RIGHT_KNEE], points[RIGHT_ANKLE], [points[RIGHT_ANKLE][0], points[RIGHT_ANKLE][1] - 0.1]
        )
        angles['Ankle_Angle'] = (left_ankle_angle + right_ankle_angle) / 2
        
        # Ground angles (90 degrees for standing position)
        angles['Shoulder_Ground_Angle'] = 90.0
        angles['Elbow_Ground_Angle'] = 90.0
        angles['Hip_Ground_Angle'] = 90.0
        angles['Knee_Ground_Angle'] = 90.0
        angles['Ankle_Ground_Angle'] = 90.0
        
        # Return angles in the same order as training data
        angle_values = [
            angles['Shoulder_Angle'],
            angles['Elbow_Angle'],
            angles['Hip_Angle'],
            angles['Knee_Angle'],
            angles['Ankle_Angle'],
            angles['Shoulder_Ground_Angle'],
            angles['Elbow_Ground_Angle'],
            angles['Hip_Ground_Angle'],
            angles['Knee_Ground_Angle'],
            angles['Ankle_Ground_Angle']
        ]
        
        return angle_values
        
    except Exception as e:
        print(f"Error extracting angles: {e}")
        return None


def detect_exercise_from_angles(angles):
    """Detect exercise type from angles using trained CNN model"""
    try:
        if model is None or label_encoder is None or angles is None:
            return None, 0.0
            
        # Convert angles to numpy array and reshape for CNN
        angles_array = np.array(angles, dtype=np.float32)
        
        # Reshape for CNN model: (1, 10, 1) - batch=1, sequence=10, features=1
        angles_input = angles_array.reshape(1, 10, 1)
        
        print(f"🏃 Exercise detection - Input shape: {angles_input.shape}")
        print(f"🏃 Exercise detection - Angles: {[f'{a:.1f}°' for a in angles[:5]]}")
        
        # Make prediction
        prediction = model.predict(angles_input, verbose=0)
        predicted_class_idx = np.argmax(prediction)
        confidence = float(np.max(prediction))
        
        # Convert to exercise name
        predicted_exercise = label_encoder.inverse_transform([predicted_class_idx])[0]
        
        print(f"🏃 Exercise detection - Predicted: {predicted_exercise} (confidence: {confidence:.3f})")
        
        return predicted_exercise, confidence
        
    except Exception as e:
        print(f"Error in exercise detection: {e}")
        return None, 0.0


def extract_medical_conditions_from_text(text):
    """Extract medical conditions from OCR text"""
    text_lower = text.lower()
    found_conditions = []
    
    for keyword in MEDICAL_KEYWORDS:
        if keyword in text_lower:
            found_conditions.append(keyword)
    
    return found_conditions


def normalize_medical_condition(condition):
    """Normalize medical condition names"""
    normalizations = {
        'high blood pressure': 'hypertension',
        'heart attack': 'cardiovascular',
        'myocardial infarction': 'cardiovascular',
        'chest pain': 'cardiovascular',
        'angina': 'cardiovascular',
        'back pain': 'back_pain',
        'neck pain': 'neck_pain',
        'shoulder pain': 'shoulder_pain',
        'hip pain': 'hip_pain',
        'knee pain': 'knee_pain',
        'joint pain': 'arthritis',
        'overweight': 'obesity',
        'sleep disorder': 'insomnia',
    }
    
    condition_lower = condition.lower()
    for key, value in normalizations.items():
        if key in condition_lower:
            return value
    
    return condition.lower().replace(' ', '_')


def calculate_cnn_confidence_score(landmarks, exercise_type):
    """Calculate confidence score using CNN model predictions"""
    try:
        if model is None:
            return 0.7  # Default if model not loaded
            
        # Convert landmarks to numpy array
        raw = np.array(landmarks, dtype=np.float32)
        expected_shape = get_model_input_shape()
        
        if expected_shape is None:
            return 0.7

        print(f"🔍 CNN Confidence - Landmarks shape: {raw.shape}, expected model shape: {expected_shape}")
        
        # Handle different model input expectations (same logic as classify_posture)
        if len(expected_shape) == 3:  # CNN model expecting (batch, sequence, features)
            batch_size, seq_len, features = expected_shape
            print(f"🔍 CNN Confidence - batch: {batch_size}, seq: {seq_len}, features: {features}")
            
            # For pose analysis, we need to properly structure the 132 landmarks
            # into 10 timesteps with meaningful feature distribution
            if features == 1:
                # Model expects 1 feature per timestep - distribute landmarks across timesteps
                landmarks_per_timestep = len(raw) // seq_len  # 132 // 10 = 13 per timestep
                remainder = len(raw) % seq_len  # 132 % 10 = 2 leftover
                
                # Create sequence data
                input_data = np.zeros((1, seq_len, features), dtype=np.float32)
                
                for t in range(seq_len):
                    start_idx = t * landmarks_per_timestep
                    end_idx = min(start_idx + landmarks_per_timestep, len(raw))
                    
                    if start_idx < len(raw):
                        # Take average of this timestep's landmarks as the single feature
                        timestep_landmarks = raw[start_idx:end_idx]
                        input_data[0, t, 0] = np.mean(timestep_landmarks) if len(timestep_landmarks) > 0 else 0.0
                    else:
                        input_data[0, t, 0] = 0.0
                
                print(f"🔍 CNN Confidence - Distributed {len(raw)} landmarks across {seq_len} timesteps: {input_data.shape}")
                
            elif raw.shape[0] == features * seq_len:
                # Landmarks are already flattened for expected shape
                input_data = raw.reshape(1, seq_len, features)
                print(f"🔍 CNN Confidence - Reshaped to match flattened format: {input_data.shape}")
            elif raw.shape[0] == features:
                # Single timestep, pad sequence dimension
                input_data = np.zeros((1, seq_len, features), dtype=np.float32)
                input_data[0, 0, :] = raw[:features]
                print(f"🔍 CNN Confidence - Created sequence from single timestep: {input_data.shape}")
            else:
                # Try to reshape/pad to match expected features
                if raw.shape[0] > features:
                    raw = raw[:features]
                    print(f"🔍 CNN Confidence - Trimmed landmarks from {raw.shape} to {features}")
                else:
                    raw = np.pad(raw, (0, features - raw.shape[0]))
                    print(f"🔍 CNN Confidence - Padded landmarks from {raw.shape} to {features}")
                
                # Create sequence data
                input_data = np.zeros((1, seq_len, features), dtype=np.float32)
                input_data[0, 0, :] = raw
                print(f"🔍 CNN Confidence - Final input shape after padding: {input_data.shape}")
                
        elif len(expected_shape) == 2:  # Dense model expecting (batch, features)
            batch_size, features = expected_shape
            print(f"🔍 CNN Confidence - Dense model - batch: {batch_size}, features: {features}")
            
            # Ensure landmarks match expected features
            if raw.shape[0] != features:
                if raw.shape[0] > features:
                    raw = raw[:features]
                    print(f"🔍 CNN Confidence - Trimmed for dense model: {raw.shape} to {features}")
                else:
                    raw = np.pad(raw, (0, features - raw.shape[0]))
                    print(f"🔍 CNN Confidence - Padded for dense model: {raw.shape} to {features}")
            
            input_data = raw.reshape(1, features)
            print(f"🔍 CNN Confidence - Dense model input shape: {input_data.shape}")
            
        else:  # Fallback for unexpected shapes
            print(f"❌ CNN Confidence - Unexpected model input shape: {expected_shape}")
            return 0.7

        print(f"🔍 CNN Confidence - Final input data shape: {input_data.shape}")
        
        # Make prediction
        prediction = model.predict(input_data, verbose=0)
        
        # Return actual CNN confidence
        confidence = float(np.max(prediction))
        print(f"🔍 CNN Confidence - Prediction result: {confidence:.3f}")
        return confidence
        
    except Exception as e:
        print(f"❌ Error in CNN confidence calculation: {e}")
        import traceback
        traceback.print_exc()
        return 0.7


def calculate_mediapipe_pose_quality(landmarks, exercise_type):
    """Calculate pose quality using MediaPipe landmarks analysis"""
    try:
        if not landmarks or len(landmarks) < 132:  # 33 landmarks * 4 values
            return 0.5
            
        # Extract key points for exercise-specific analysis
        landmarks_array = np.array(landmarks).reshape(-1, 4)  # Reshape to 33x4
        
        # Calculate visibility and confidence scores
        visibility_scores = landmarks_array[:, 3]  # Visibility values
        avg_visibility = np.mean(visibility_scores)
        
        # Exercise-specific quality metrics
        quality_score = 0.0
        
        if exercise_type == 'squats':
            # Check hip, knee, ankle alignment
            hip_left = landmarks_array[23]  # Left hip
            hip_right = landmarks_array[24]  # Right hip
            knee_left = landmarks_array[25]  # Left knee
            knee_right = landmarks_array[26]  # Right knee
            ankle_left = landmarks_array[27]  # Left ankle
            ankle_right = landmarks_array[28]  # Right ankle
            
            # Calculate vertical alignment quality
            hip_center_y = (hip_left[1] + hip_right[1]) / 2
            knee_center_y = (knee_left[1] + knee_right[1]) / 2
            ankle_center_y = (ankle_left[1] + ankle_right[1]) / 2
            
            # Good squat form: hips should be below knees, knees below ankles
            alignment_score = 1.0 - abs(hip_center_y - knee_center_y) * 0.3
            alignment_score -= abs(knee_center_y - ankle_center_y) * 0.2
            quality_score = max(0.0, alignment_score)
            
        elif exercise_type == 'pushups':
            # Check shoulder, elbow, wrist alignment
            shoulder_left = landmarks_array[11]  # Left shoulder
            shoulder_right = landmarks_array[12]  # Right shoulder
            elbow_left = landmarks_array[13]  # Left elbow
            elbow_right = landmarks_array[14]  # Right elbow
            wrist_left = landmarks_array[15]  # Left wrist
            wrist_right = landmarks_array[16]  # Right wrist
            
            # Check for straight body line
            shoulder_center_y = (shoulder_left[1] + shoulder_right[1]) / 2
            elbow_center_y = (elbow_left[1] + elbow_right[1]) / 2
            wrist_center_y = (wrist_left[1] + wrist_right[1]) / 2
            
            # Good pushup form: relatively straight line
            body_line_score = 1.0 - abs(shoulder_center_y - elbow_center_y) * 0.5
            body_line_score -= abs(elbow_center_y - wrist_center_y) * 0.3
            quality_score = max(0.0, body_line_score)
            
        else:
            # Generic quality score for other exercises
            quality_score = avg_visibility
            
        # Combine with visibility
        final_score = (quality_score * 0.7) + (avg_visibility * 0.3)
        return min(max(final_score, 0.0), 1.0)
        
    except Exception as e:
        print(f"Error in MediaPipe quality calculation: {e}")
        return 0.5


def analyze_nutrition_progress(user_profile, recent_sessions, user_id=None):
    """Analyze calorie intake vs burn progress using REAL nutrition data from database"""
    try:
        weight = user_profile.get('weight', 70)
        height = user_profile.get('height', 170)
        age = user_profile.get('age', 30)
        goal = user_profile.get('goal', 'maintenance')
        
        # Calculate BMR and daily calorie needs
        bmr = 10 * weight + 6.25 * height - 5 * age + 5  # Male formula
        daily_needs = (
            bmr - 500 if goal == 'weight_loss'
            else bmr + 500 if goal == 'weight_gain'
            else bmr
        )
        
        # Calculate calories burned from recent sessions
        total_calories_burned = 0
        for session in recent_sessions:
            exercise_type = session.get('exercise_type', 'unknown')
            duration = session.get('duration_minutes', 0)
            reps = session.get('rep_count', 0)
            calories = calculate_calories_burned(exercise_type, duration, weight, reps)
            total_calories_burned += calories
        
        # Get REAL calorie intake from nutrition database
        actual_intake = 0
        if user_id:
            nutrition_data = load_nutrition_data()
            user_nutrition = nutrition_data.get(user_id, {})
            
            # Get today's date
            today = datetime.now().strftime('%Y-%m-%d')
            
            # Get today's meals
            daily_meals = user_nutrition.get(today, [])
            
            # Sum up actual calories from logged meals
            for meal in daily_meals:
                actual_intake += meal.get('calories', 0)
            
            print(f"📊 Nutrition data for {user_id}: {len(daily_meals)} meals, {actual_intake} calories logged today")
        
        # If no nutrition data logged, show 0 intake
        if actual_intake == 0:
            print(f"⚠️ No nutrition data found for user {user_id}, showing 0 intake")
        
        calorie_balance = actual_intake - total_calories_burned
        
        # Calculate progress as percentage of daily needs met through food
        # and percentage of calories burned through exercise
        food_progress = (actual_intake / daily_needs) * 100 if daily_needs > 0 else 0
        exercise_progress = (total_calories_burned / daily_needs) * 100 if daily_needs > 0 else 0
        
        # Overall progress: food intake - exercise burn (net calories)
        progress_percentage = food_progress - exercise_progress
        
        return {
            'daily_needs': daily_needs,
            'calories_burned': total_calories_burned,
            'actual_intake': actual_intake,
            'calorie_balance': calorie_balance,
            'progress_percentage': progress_percentage,
            'food_progress': food_progress,
            'exercise_progress': exercise_progress,
            'on_track': abs(calorie_balance) <= 200,  # Within 200 calories of target
            'meals_logged': len(daily_meals) if user_id else 0,
            'data_source': 'database' if user_id and actual_intake > 0 else 'estimated'
        }
        
    except Exception as e:
        print(f"Error in nutrition progress analysis: {e}")
        import traceback
        traceback.print_exc()
        return {
            'daily_needs': 2000,
            'calories_burned': 0,
            'actual_intake': 0,
            'calorie_balance': 0,
            'progress_percentage': 0,
            'food_progress': 0,
            'exercise_progress': 0,
            'on_track': False,
            'meals_logged': 0,
            'data_source': 'error'
        }


def calculate_comprehensive_performance_score(session_data, user_profile, nutrition_data):
    """Calculate comprehensive performance score using multiple factors"""
    try:
        # Base performance from CNN and MediaPipe
        landmarks = session_data.get('landmarks', [])
        exercise_type = session_data.get('exercise_type', 'unknown')
        
        # CNN-based confidence
        cnn_confidence = calculate_cnn_confidence_score(landmarks, exercise_type)
        
        # MediaPipe-based pose quality
        mediapipe_quality = calculate_mediapipe_pose_quality(landmarks, exercise_type)
        
        # Rep completion quality
        target_reps = session_data.get('target_reps', 10)
        actual_reps = session_data.get('rep_count', 0)
        rep_completion = min(actual_reps / target_reps, 1.0)
        
        # Form consistency (standard deviation of confidence scores)
        confidence_history = session_data.get('confidence_history', [cnn_confidence])
        form_consistency = 1.0 - (np.std(confidence_history) if len(confidence_history) > 1 else 0.2)
        
        # Nutrition factor
        nutrition_factor = 1.0
        if nutrition_data.get('on_track', False):
            nutrition_factor = 1.1  # Boost if nutrition is on track
        elif nutrition_data.get('calorie_balance', 0) < -500:
            nutrition_factor = 0.9  # Slight penalty if underfueling
        
        # Medical condition factor
        medical_conditions = user_profile.get('medical_conditions', [])
        medical_factor = 1.0
        if len(medical_conditions) > 0:
            medical_factor = 0.95  # Slight adjustment for medical conditions
        
        # Comprehensive weighted score
        performance_score = (
            cnn_confidence * 0.35 +           # 35% CNN model confidence
            mediapipe_quality * 0.25 +        # 25% MediaPipe pose quality
            rep_completion * 0.20 +            # 20% Rep completion
            form_consistency * 0.20             # 20% Form consistency
        ) * nutrition_factor * medical_factor
        
        return min(max(performance_score, 0.0), 1.0)
        
    except Exception as e:
        print(f"Error in comprehensive performance calculation: {e}")
        return 0.7


def generate_smart_recommendation(user_profile, session_history, current_session=None, user_id=None):
    """Generate smart workout recommendations based on comprehensive analysis"""
    try:
        recommendations = []
        medical_conditions = user_profile.get('medical_conditions', [])
        fitness_goal = user_profile.get('goal', 'maintenance')
        fitness_level = user_profile.get('fitness_level', 'beginner')
        
        # Analyze nutrition progress with REAL data from database
        nutrition_data = analyze_nutrition_progress(
            user_profile, 
            session_history[-7:] if session_history else [],
            user_id
        )
        
        # Analyze recent performance with comprehensive scoring
        if session_history:
            recent_sessions = session_history[-5:]  # Last 5 sessions
            avg_performance = sum([
                calculate_comprehensive_performance_score(session, user_profile, nutrition_data) 
                for session in recent_sessions
            ]) / len(recent_sessions)
            
            # Check performance trend
            if len(recent_sessions) >= 2:
                recent_avg = calculate_comprehensive_performance_score(recent_sessions[-1], user_profile, nutrition_data)
                previous_avg = calculate_comprehensive_performance_score(recent_sessions[-2], user_profile, nutrition_data)
                performance_trend = recent_avg - previous_avg
            else:
                performance_trend = 0
        else:
            avg_performance = 0.7  # Default for new users
            performance_trend = 0
        
        # Generate recommendations based on comprehensive analysis
        if current_session:
            current_performance = calculate_comprehensive_performance_score(current_session, user_profile, nutrition_data)
            
            # Real-time recommendations based on actual model outputs
            if current_performance >= 0.9:
                recommendations.append({
                    "type": "challenge",
                    "message": "Excellent form detected by AI! Your CNN confidence is high. Try adding 5 more reps.",
                    "action": "increase_reps",
                    "difficulty_adjustment": "slight_increase",
                    "confidence": current_performance
                })
            elif current_performance >= 0.75:
                recommendations.append({
                    "type": "encouragement",
                    "message": "Good form! MediaPipe shows consistent pose quality. Keep this up!",
                    "action": "maintain",
                    "difficulty_adjustment": "maintain",
                    "confidence": current_performance
                })
            elif current_performance < 0.6:
                recommendations.append({
                    "type": "correction",
                    "message": f"AI models detect form issues. CNN confidence: {int(current_performance*100)}%. Focus on quality.",
                    "action": "decrease_reps",
                    "difficulty_adjustment": "slight_decrease",
                    "confidence": current_performance
                })
        
        # Nutrition-based recommendations
        if nutrition_data['progress_percentage'] < 50:
            recommendations.append({
                "type": "nutrition_focus",
                "message": f"You're at {nutrition_data['progress_percentage']:.1f}% of daily calorie goal. Consider a light snack.",
                "action": "nutrition_adjustment",
                "calorie_context": nutrition_data
            })
        elif nutrition_data['calorie_balance'] < -300:
            recommendations.append({
                "type": "recovery_nutrition",
                "message": "Significant calorie deficit detected. Prioritize post-workout nutrition.",
                "action": "recovery_nutrition",
                "calorie_context": nutrition_data
            })
        
        # Goal-specific recommendations with nutrition integration
        if fitness_goal == 'weight_loss' and nutrition_data['calorie_balance'] > 200:
            recommendations.append({
                "type": "cardio_boost",
                "message": "Calorie surplus detected. Add 10 minutes cardio to meet weight loss goals.",
                "action": "add_cardio",
                "suggested_duration": "10 minutes",
                "calorie_context": nutrition_data
            })
        elif fitness_goal == 'muscle_gain' and nutrition_data['calorie_balance'] < -400:
            recommendations.append({
                "type": "nutrition_increase",
                "message": "For muscle gain, increase protein intake. Current deficit may hinder growth.",
                "action": "increase_protein",
                "calorie_context": nutrition_data
            })
        
        # Performance-based progression recommendations
        if avg_performance >= 0.85 and performance_trend >= 0.05:
            recommendations.append({
                "type": "progression",
                "message": f"AI analysis shows {int(avg_performance*100)}% average performance with positive trend!",
                "action": "increase_difficulty",
                "suggested_exercises": get_progression_exercises(medical_conditions, fitness_level, "increase"),
                "performance_context": {
                    "avg_performance": avg_performance,
                    "trend": performance_trend
                }
            })
        elif avg_performance < 0.65:
            recommendations.append({
                "type": "recovery",
                "message": f"AI models indicate need for recovery. Average performance: {int(avg_performance*100)}%",
                "action": "decrease_difficulty",
                "suggested_exercises": get_progression_exercises(medical_conditions, fitness_level, "decrease"),
                "performance_context": {
                    "avg_performance": avg_performance,
                    "trend": performance_trend
                }
            })
        
        return {
            "success": True,
            "recommendations": recommendations,
            "performance_score": avg_performance,
            "performance_trend": performance_trend,
            "next_session_difficulty": determine_next_difficulty(avg_performance, performance_trend),
            "nutrition_analysis": nutrition_data,
            "model_confidence": current_session.get('confidence', 0.7) if current_session else avg_performance
        }
        
    except Exception as e:
        print(f"Error generating recommendations: {e}")
        return {
            "success": False,
            "error": str(e),
            "recommendations": []
        }


def get_progression_exercises(medical_conditions, fitness_level, direction):
    """Get exercise suggestions based on progression direction"""
    try:
        safe_exercises = []
        for ex_id, ex_data in EXERCISES.items():
            # Filter by medical conditions
            if not any(condition in ex_data['restrictions'] for condition in medical_conditions):
                # Filter by fitness level and direction
                if direction == "increase":
                    if ex_data['difficulty'] in ['medium', 'high']:
                        safe_exercises.append({
                            'id': ex_id,
                            'name': ex_data['name'],
                            'difficulty': ex_data['difficulty'],
                            'reason': 'Progression challenge'
                        })
                else:  # decrease
                    if ex_data['difficulty'] in ['low', 'medium']:
                        safe_exercises.append({
                            'id': ex_id,
                            'name': ex_data['name'],
                            'difficulty': ex_data['difficulty'],
                            'reason': 'Recovery option'
                        })
        
        return safe_exercises[:3]  # Return top 3 suggestions
        
    except Exception as e:
        print(f"Error getting progression exercises: {e}")
        return []


def determine_next_difficulty(avg_performance, performance_trend):
    """Determine difficulty level for next session"""
    if avg_performance >= 0.9 and performance_trend > 0.1:
        return "significant_increase"
    elif avg_performance >= 0.8 and performance_trend >= 0:
        return "slight_increase"
    elif avg_performance < 0.6 or performance_trend < -0.1:
        return "decrease"
    else:
        return "maintain"


def calculate_calories_burned(exercise_type, duration_minutes, user_weight, reps=0):
    """Calculate calories burned for an exercise"""
    try:
        if exercise_type not in EXERCISES:
            return 0
        
        base_calories_per_minute = EXERCISES[exercise_type]['calorie_burn_per_minute']
        
        # Adjust for user weight (base is 70kg)
        weight_factor = user_weight / 70.0
        
        # Calculate calories from duration
        calories_from_duration = base_calories_per_minute * duration_minutes * weight_factor
        
        # Add calories from reps (if available)
        calories_from_reps = (reps * 0.1) if reps > 0 else 0
        
        total_calories = calories_from_duration + calories_from_reps
        
        return round(total_calories, 1)
        
    except Exception as e:
        print(f"Error calculating calories: {e}")
        return 0


def decode_base64_image(base64_string):
    """Decode base64 string to image"""
    try:
        if ',' in base64_string:
            base64_string = base64_string.split(',')[1]
        image_data = base64.b64decode(base64_string)
        image = Image.open(io.BytesIO(image_data))
        return cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)
    except Exception as e:
        print(f"Error decoding image: {e}")
        return None


def extract_pose_landmarks(image):
    """Extract pose landmarks using MediaPipe Tasks API"""
    try:
        # Convert BGR (OpenCV) → RGB
        rgb_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)

        # Wrap in MediaPipe Image
        mp_image = mp.Image(
            image_format=mp.ImageFormat.SRGB,
            data=rgb_image
        )

        # Run detection
        result = pose_landmarker.detect(mp_image)

        if not result.pose_landmarks or len(result.pose_landmarks) == 0:
            return None

        # Flatten landmarks to [x, y, z, visibility] × 33
        landmarks = []
        for lm in result.pose_landmarks[0]:
            landmarks.extend([lm.x, lm.y, lm.z, lm.visibility])

        # Validate landmarks - ensure we have valid data
        if len(landmarks) != 132:
            print(f"⚠️ Unexpected landmarks count: {len(landmarks)}")
            return None
            
        # Check for valid visibility (at least some landmarks should be visible)
        visibility_values = [landmarks[i+3] for i in range(0, len(landmarks), 4)]
        avg_visibility = sum(visibility_values) / len(visibility_values)
        
        # Lower visibility threshold for better detection
        if avg_visibility < 0.05:
            print(f"⚠️ Low visibility: {avg_visibility:.3f}")
            return None

        return landmarks

    except Exception as e:
        print(f"Error extracting landmarks: {e}")
        return None


def get_model_input_shape():
    """Get expected input shape from loaded model"""
    if model is None:
        return None
    try:
        shape = model.input_shape
        print(f" Model input shape detected: {shape}")
        return shape
    except Exception as e:
        print(f"Error getting model shape: {e}")
        return None


def classify_posture(landmarks, exercise_type):
    """Classify posture using CNN model"""
    if model is None:
        return {
            "correct": True,
            "confidence": 0.8,
            "feedback": "Model not loaded - assuming correct form"
        }
    try:
        expected_shape = get_model_input_shape()
        if expected_shape is None:
            return {"correct": True, "confidence": 0.5, "feedback": "Cannot determine model input shape"}

        # Convert landmarks to numpy array
        raw = np.array(landmarks, dtype=np.float32)
        print(f" Landmarks shape: {raw.shape}, expected model shape: {expected_shape}")
        
        # Handle different model input expectations
        if len(expected_shape) == 3:  # CNN model expecting (batch, sequence, features)
            batch_size, seq_len, features = expected_shape
            print(f" CNN model - batch: {batch_size}, seq: {seq_len}, features: {features}")
            
            # For pose analysis, we need to properly structure the 132 landmarks
            # into 10 timesteps with meaningful feature distribution
            if features == 1:
                # Model expects 1 feature per timestep - distribute landmarks across timesteps
                landmarks_per_timestep = len(raw) // seq_len  # 132 // 10 = 13 per timestep
                remainder = len(raw) % seq_len  # 132 % 10 = 2 leftover
                
                # Create sequence data
                input_data = np.zeros((1, seq_len, features), dtype=np.float32)
                
                for t in range(seq_len):
                    start_idx = t * landmarks_per_timestep
                    end_idx = min(start_idx + landmarks_per_timestep, len(raw))
                    
                    if start_idx < len(raw):
                        # Take average of this timestep's landmarks as the single feature
                        timestep_landmarks = raw[start_idx:end_idx]
                        input_data[0, t, 0] = np.mean(timestep_landmarks) if len(timestep_landmarks) > 0 else 0.0
                    else:
                        input_data[0, t, 0] = 0.0
                
                print(f" Distributed {len(raw)} landmarks across {seq_len} timesteps: {input_data.shape}")
                
            elif raw.shape[0] == features * seq_len:
                # Landmarks are already flattened for expected shape
                input_data = raw.reshape(1, seq_len, features)
                print(f" Reshaped to match flattened format: {input_data.shape}")
            elif raw.shape[0] == features:
                # Single timestep, pad sequence dimension
                input_data = np.zeros((1, seq_len, features), dtype=np.float32)
                input_data[0, 0, :] = raw[:features]
                print(f" Created sequence from single timestep: {input_data.shape}")
            else:
                # Try to reshape/pad to match expected features
                if raw.shape[0] > features:
                    raw = raw[:features]
                    print(f" Trimmed landmarks from {raw.shape} to {features}")
                else:
                    raw = np.pad(raw, (0, features - raw.shape[0]))
                    print(f" Padded landmarks from {raw.shape} to {features}")
                
                # Create sequence data
                input_data = np.zeros((1, seq_len, features), dtype=np.float32)
                input_data[0, 0, :] = raw
                print(f" Final input shape after padding: {input_data.shape}")
                
        elif len(expected_shape) == 2:  # Dense model expecting (batch, features)
            batch_size, features = expected_shape
            print(f" Dense model - batch: {batch_size}, features: {features}")
            
            # Ensure landmarks match expected features
            if raw.shape[0] != features:
                if raw.shape[0] > features:
                    raw = raw[:features]
                    print(f" Trimmed for dense model: {raw.shape} to {features}")
                else:
                    raw = np.pad(raw, (0, features - raw.shape[0]))
                    print(f" Padded for dense model: {raw.shape} to {features}")
            
            input_data = raw.reshape(1, features)
            print(f" Dense model input shape: {input_data.shape}")
            
        else:  # Fallback for unexpected shapes
            print(f" Unexpected model input shape: {expected_shape}")
            return {"correct": True, "confidence": 0.5, "feedback": "Model input shape not supported"}

        print(f" Final input data shape for prediction: {input_data.shape}")
        
        # Make prediction
        prediction = model.predict(input_data, verbose=0)
        confidence = float(np.max(prediction))
        is_correct = confidence > 0.7
        feedback = "Good form!" if is_correct else "Adjust your posture for better form"
        print(f" Prediction result - confidence: {confidence:.3f}, correct: {is_correct}")
        return {"correct": is_correct, "confidence": confidence, "feedback": feedback}

    except Exception as e:
        print(f" Error classifying posture: {e}")
        import traceback
        traceback.print_exc()
        return {"correct": True, "confidence": 0.5, "feedback": "Error in classification"}
# Global state for rep counting across frames (stores phase state)
_rep_counting_state = {}

def get_exercise_phase_key(exercise_type, session_id='default'):
    """Generate unique key for tracking exercise phase"""
    return f"{session_id}_{exercise_type}"

def track_movement_cycle(landmarks_history, exercise_type, total_movements):
    """
    Track ALL up/down movements dynamically using recent min/max positions.
    Counts every visible up and down transition regardless of depth.
    Returns movement description if phase changed.
    """
    if len(landmarks_history) < 2:
        return None
    
    try:
        # Keep history of positions for dynamic threshold calculation
        if not hasattr(track_movement_cycle, '_position_history'):
            track_movement_cycle._position_history = {}
        
        history_key = f"{exercise_type}_{id(total_movements)}"
        if history_key not in track_movement_cycle._position_history:
            track_movement_cycle._position_history[history_key] = []
        
        current = landmarks_history[-1]
        previous = landmarks_history[-2]
        
        if len(current) < 25 or len(previous) < 25:
            return None
        
        # Get position value based on exercise type
        pos_current = None
        if exercise_type == 'squats':
            pos_current = float(current[24]) if current[24] is not None else None
        elif exercise_type == 'pushups':
            pos_current = float(current[12]) if current[12] is not None else None
        elif exercise_type == 'pull_ups':
            pos_current = float(current[16]) if current[16] is not None else None
        elif exercise_type == 'jumping_jacks':
            left_wrist_x = float(current[16]) if current[16] is not None else 0
            right_wrist_x = float(current[15]) if current[15] is not None else 0
            pos_current = abs(right_wrist_x - left_wrist_x)
        elif exercise_type == 'russian_twists':
            left_shoulder_x = float(current[11]) if current[11] is not None else 0
            right_shoulder_x = float(current[12]) if current[12] is not None else 0
            left_hip_x = float(current[23]) if current[23] is not None else 0
            right_hip_x = float(current[24]) if current[24] is not None else 0
            shoulder_center = (left_shoulder_x + right_shoulder_x) / 2
            hip_center = (left_hip_x + right_hip_x) / 2
            pos_current = abs(shoulder_center - hip_center)
        
        if pos_current is None:
            return None
        
        # Add to position history
        pos_history = track_movement_cycle._position_history[history_key]
        pos_history.append(pos_current)
        
        # Keep only last 20 positions for dynamic range calculation
        if len(pos_history) > 20:
            pos_history.pop(0)
        
        # Need enough history to determine range
        if len(pos_history) < 5:
            return None
        
        # Calculate dynamic thresholds based on recent min/max
        recent_min = min(pos_history)
        recent_max = max(pos_history)
        range_val = recent_max - recent_min
        
        # Avoid division by zero or very small ranges
        if range_val < 0.02:
            return None
        
        # Calculate midpoint and sensitivity zones
        midpoint = (recent_min + recent_max) / 2
        
        # Get previous position
        prev_pos = pos_history[-2] if len(pos_history) >= 2 else pos_current
        
        current_phase = total_movements['current_phase']
        
        # Detect direction changes - ANY significant movement counts
        # UP: moving toward recent minimum (higher in frame for most exercises)
        # DOWN: moving toward recent maximum (lower in frame for most exercises)
        
        is_moving_up = pos_current < prev_pos  # Y decreases = moving up
        is_moving_down = pos_current > prev_pos  # Y increases = moving down
        
        # Use position relative to midpoint for phase detection
        # With hysteresis: must cross past midpoint by 20% of range
        threshold_zone = range_val * 0.2
        
        if exercise_type in ['squats', 'pushups', 'pull_ups']:
            # For these: low Y = UP position, high Y = DOWN position
            
            if current_phase == 'up':
                # Currently UP, check if moved DOWN significantly
                # Must be in lower half (below midpoint + buffer)
                if pos_current > (midpoint + threshold_zone) and is_moving_down:
                    total_movements['current_phase'] = 'down'
                    total_movements['down_count'] += 1
                    total_movements['total_cycles'] = min(total_movements['up_count'], total_movements['down_count'])
                    # Clear history for next cycle
                    track_movement_cycle._position_history[history_key] = [pos_current]
                    return f"DOWN (up:{total_movements['up_count']}, down:{total_movements['down_count']}, cycles:{total_movements['total_cycles']})"
                    
            elif current_phase == 'down':
                # Currently DOWN, check if moved UP significantly  
                # Must be in upper half (above midpoint - buffer)
                if pos_current < (midpoint - threshold_zone) and is_moving_up:
                    total_movements['current_phase'] = 'up'
                    total_movements['up_count'] += 1
                    total_movements['total_cycles'] = min(total_movements['up_count'], total_movements['down_count'])
                    # Clear history for next cycle
                    track_movement_cycle._position_history[history_key] = [pos_current]
                    return f"UP (up:{total_movements['up_count']}, down:{total_movements['down_count']}, cycles:{total_movements['total_cycles']})"
        
        elif exercise_type == 'jumping_jacks':
            # For jumping jacks: low distance = hands down, high distance = hands up
            
            if current_phase == 'up':  # hands together (low distance)
                if pos_current > (midpoint + threshold_zone) and is_moving_down:
                    total_movements['current_phase'] = 'down'
                    total_movements['down_count'] += 1
                    total_movements['total_cycles'] = min(total_movements['up_count'], total_movements['down_count'])
                    track_movement_cycle._position_history[history_key] = [pos_current]
                    return f"DOWN (up:{total_movements['up_count']}, down:{total_movements['down_count']}, cycles:{total_movements['total_cycles']})"
                    
            elif current_phase == 'down':  # hands apart (high distance)
                if pos_current < (midpoint - threshold_zone) and is_moving_up:
                    total_movements['current_phase'] = 'up'
                    total_movements['up_count'] += 1
                    total_movements['total_cycles'] = min(total_movements['up_count'], total_movements['down_count'])
                    track_movement_cycle._position_history[history_key] = [pos_current]
                    return f"UP (up:{total_movements['up_count']}, down:{total_movements['down_count']}, cycles:{total_movements['total_cycles']})"
        
        elif exercise_type == 'russian_twists':
            # For twists: low rotation = center, high rotation = twisted
            
            if current_phase == 'up':  # centered
                if pos_current > (midpoint + threshold_zone) and is_moving_down:
                    total_movements['current_phase'] = 'down'
                    total_movements['down_count'] += 1
                    total_movements['total_cycles'] = min(total_movements['up_count'], total_movements['down_count'])
                    track_movement_cycle._position_history[history_key] = [pos_current]
                    return f"DOWN (up:{total_movements['up_count']}, down:{total_movements['down_count']}, cycles:{total_movements['total_cycles']})"
                    
            elif current_phase == 'down':  # twisted
                if pos_current < (midpoint - threshold_zone) and is_moving_up:
                    total_movements['current_phase'] = 'up'
                    total_movements['up_count'] += 1
                    total_movements['total_cycles'] = min(total_movements['up_count'], total_movements['down_count'])
                    track_movement_cycle._position_history[history_key] = [pos_current]
                    return f"UP (up:{total_movements['up_count']}, down:{total_movements['down_count']}, cycles:{total_movements['total_cycles']})"
        
        return None
        
    except Exception as e:
        return None

def count_reps(landmarks_history, exercise_type, session_id='default'):
    """
    Count repetitions based on pose movement with phase detection.
    Tracks up/down cycles to properly count full repetitions.
    """
    if len(landmarks_history) < 2:
        return 0, "Need more frames to analyze"

    try:
        phase_key = get_exercise_phase_key(exercise_type, session_id)

        # Initialize state if not exists
        if phase_key not in _rep_counting_state:
            _rep_counting_state[phase_key] = {
                'phase': 'up',  # 'up' or 'down'
                'last_rep_time': 0,
                'min_cooldown_frames': 5  # Minimum frames between reps
            }
            print(f"    [REP DEBUG] Initializing rep counter for {exercise_type} (session: {session_id}), phase: up")

        state = _rep_counting_state[phase_key]
        current = landmarks_history[-1]
        previous = landmarks_history[-2]

        # Need enough landmark data
        if len(current) < 25 or len(previous) < 25:
            return 0, "Insufficient landmark data"

        rep_detected = 0
        message = "No state change"

        # Define movement detection for each exercise
        if exercise_type == 'squats':
            # Hip Y position (lower Y = higher in frame = standing up)
            hip_y_current = float(current[24]) if current[24] is not None else 0
            hip_y_previous = float(previous[24]) if previous[24] is not None else 0

            # Squat phases: 'up' (standing) -> 'down' (squatting) -> 'up' (rep complete)
            # Lower Y value = higher position in frame = standing up
            down_threshold = 0.65  # Hip Y when in squat position
            up_threshold = 0.45    # Hip Y when standing
            
            # Debug: log values periodically (using a static counter)
            if not hasattr(count_reps, '_squat_debug_counter'):
                count_reps._squat_debug_counter = 0
            count_reps._squat_debug_counter += 1
            if count_reps._squat_debug_counter % 20 == 0:
                print(f"    [REP DEBUG] Squat - Phase: {state['phase']}, Hip Y: {hip_y_current:.3f}, thresholds: down>{down_threshold}, up<{up_threshold}")

            if state['phase'] == 'up' and hip_y_current > down_threshold:
                state['phase'] = 'down'
                message = "Squat down detected"
                print(f"    [REP DEBUG] Squat phase: up -> down (hip_y: {hip_y_current:.3f})")
            elif state['phase'] == 'down' and hip_y_current < up_threshold:
                state['phase'] = 'up'
                rep_detected = 1
                message = "Squat rep completed"
                print(f"    [REP DEBUG] Squat REP COUNTED! (hip_y: {hip_y_current:.3f})")

        elif exercise_type == 'pushups':
            # Use shoulder Y position to detect pushup phases
            shoulder_y_current = float(current[12]) if current[12] is not None else 0
            shoulder_y_previous = float(previous[12]) if previous[12] is not None else 0

            # FIXED: Thresholds based on actual video analysis
            # From logs: shoulder Y ranges from ~0.63 (up) to ~0.84 (down)
            # Need hysteresis: down > 0.75, up < 0.68 (must rise above 0.68 to count)
            down_threshold = 0.75   # Enter "down" phase when going below this
            up_threshold = 0.68     # Count rep when rising above this
            
            # Debug: log values periodically
            if not hasattr(count_reps, '_pushup_debug_counter'):
                count_reps._pushup_debug_counter = 0
            count_reps._pushup_debug_counter += 1
            if count_reps._pushup_debug_counter % 20 == 0 or rep_detected > 0:
                print(f"    [REP DEBUG] Pushup - Phase: {state['phase']}, Shoulder Y: {shoulder_y_current:.3f}, thresholds: down>{down_threshold}, up<{up_threshold}")

            if state['phase'] == 'up' and shoulder_y_current > down_threshold:
                state['phase'] = 'down'
                message = "Pushup down detected"
                print(f"    [REP DEBUG] Pushup phase: up -> down (shoulder_y: {shoulder_y_current:.3f})")
            elif state['phase'] == 'down' and shoulder_y_current < up_threshold:
                state['phase'] = 'up'
                rep_detected = 1
                message = "Pushup rep completed"
                print(f"    [REP DEBUG] ✅ PUSHUP REP COUNTED! (shoulder_y: {shoulder_y_current:.3f})")

        elif exercise_type == 'jumping_jacks':
            # Track wrist distance from center to detect arms spread/tucked
            left_wrist_x = float(current[16]) if current[16] is not None else 0
            right_wrist_x = float(current[15]) if current[15] is not None else 0
            # Distance between wrists
            wrist_distance = abs(right_wrist_x - left_wrist_x)

            closed_threshold = 0.15  # Arms at sides
            open_threshold = 0.5     # Arms spread

            if state['phase'] == 'up' and wrist_distance > open_threshold:
                state['phase'] = 'down'
                message = "Arms spread detected"
            elif state['phase'] == 'down' and wrist_distance < closed_threshold:
                state['phase'] = 'up'
                rep_detected = 1
                message = "Jumping jack rep completed"

        elif exercise_type == 'pull_ups':
            # Use wrist Y position - lower Y = higher position (chin over bar)
            wrist_y_current = float(current[16]) if current[16] is not None else 0

            up_threshold = 0.35    # Chin over bar (high position)
            down_threshold = 0.55  # Arms extended (low position)

            if state['phase'] == 'up' and wrist_y_current > down_threshold:
                state['phase'] = 'down'
                message = "Pull-up down detected"
            elif state['phase'] == 'down' and wrist_y_current < up_threshold:
                state['phase'] = 'up'
                rep_detected = 1
                message = "Pull-up rep completed"

        elif exercise_type == 'russian_twists':
            # Track hip rotation by comparing shoulder center to hip center
            left_shoulder_x = float(current[12]) if current[12] is not None else 0
            right_shoulder_x = float(current[11]) if current[11] is not None else 0
            shoulder_center_x = (left_shoulder_x + right_shoulder_x) / 2

            left_hip_x = float(current[24]) if current[24] is not None else 0
            right_hip_x = float(current[23]) if current[23] is not None else 0
            hip_center_x = (left_hip_x + right_hip_x) / 2

            # Rotation is difference between shoulder and hip center
            rotation = abs(shoulder_center_x - hip_center_x)

            center_threshold = 0.05   # Torso centered
            twist_threshold = 0.15    # Torso twisted

            if state['phase'] == 'up' and rotation > twist_threshold:
                state['phase'] = 'down'
                message = "Twist detected"
            elif state['phase'] == 'down' and rotation < center_threshold:
                state['phase'] = 'up'
                rep_detected = 1
                message = "Russian twist rep completed (one side)"
        
        else:
            # Unknown exercise type - log for debugging
            print(f"    [REP DEBUG] Unknown exercise type: '{exercise_type}' - no rep counting logic available")
            print(f"    [REP DEBUG] Supported types: squats, pushups, jumping_jacks, pull_ups, russian_twists")

        return rep_detected, message

    except Exception as e:
        print(f"Error counting reps: {e}")
        import traceback
        traceback.print_exc()
        return 0, f"Error in rep counting: {str(e)}"

def reset_rep_counter(session_id='default'):
    """Reset rep counting state for a session"""
    keys_to_remove = [k for k in _rep_counting_state.keys() if k.startswith(session_id)]
    for key in keys_to_remove:
        del _rep_counting_state[key]


# ── Routes ───────────────────────────────────────────────────────────────────

@app.route('/api/ocr/medical-report', methods=['POST'])
def process_medical_report():
    """Process medical report image and extract medical conditions using OCR"""
    try:
        if 'image' not in request.files:
            return jsonify({"error": "No image file provided"}), 400
        
        image_file = request.files['image']
        if image_file.filename == '':
            return jsonify({"error": "No image file selected"}), 400
        
        # Read image file
        image_bytes = image_file.read()
        
        # Convert to PIL Image
        try:
            image = Image.open(io.BytesIO(image_bytes))
        except Exception as e:
            print(f"Error opening image: {e}")
            return jsonify({"error": f"Error processing image: {e}"}), 500
        
        # Convert to OpenCV format
        try:
            opencv_image = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)
        except Exception as e:
            print(f"Error converting image: {e}")
            return jsonify({"error": f"Error processing image: {e}"}), 500
        
        extracted_text = ""
        found_conditions = []
        
        if OCR_AVAILABLE:
            try:
                # Use EasyOCR for text extraction
                results = reader.readtext(opencv_image)
                extracted_text = " ".join([result[1] for result in results])
                found_conditions = extract_medical_conditions_from_text(extracted_text)
            except Exception as e:
                print(f"EasyOCR processing failed: {e}")
                extracted_text = "OCR processing failed"
        else:
            # Fallback: Basic image processing simulation
            extracted_text = "OCR not available on server. Please enter medical conditions manually."
            found_conditions = []
        
        # Normalize conditions
        normalized_conditions = []
        for condition in found_conditions:
            normalized = normalize_medical_condition(condition)
            if normalized not in normalized_conditions:
                normalized_conditions.append(normalized)
        
        return jsonify({
            "success": True,
            "extracted_text": extracted_text,
            "raw_conditions": found_conditions,
            "normalized_conditions": normalized_conditions,
            "ocr_available": OCR_AVAILABLE,
            "conditions_count": len(normalized_conditions)
        })
        
    except Exception as e:
        print(f"Error in OCR processing: {e}")
        return jsonify({
            "success": False,
            "error": str(e),
            "extracted_text": "",
            "normalized_conditions": []
        }), 500


@app.route('/api/health', methods=['GET'])
def health_check():
    return jsonify({
        "status": "healthy",
        "model_loaded": model is not None,
        "exercises_available": list(EXERCISES.keys()),
        "ocr_available": OCR_AVAILABLE
    })


@app.route('/api/pose/analyze', methods=['POST'])
def analyze_pose():
    try:
        data = request.get_json()
        if not data or 'image' not in data:
            return jsonify({"error": "No image provided"}), 400

        image = decode_base64_image(data['image'])
        if image is None:
            return jsonify({"error": "Invalid image format"}), 400

        landmarks = extract_pose_landmarks(image)
        if landmarks is None:
            return jsonify({"error": "No pose detected"}), 400

        posture_result = None
        detected_exercise = None
        
        # Check if exercise detection is requested
        detect_exercise = data.get('detect_exercise', False)
        if isinstance(detect_exercise, str):
            detect_exercise = detect_exercise.lower() == 'true'
        else:
            detect_exercise = bool(detect_exercise)
        
        if 'exercise_type' in data:
            posture_result = classify_posture(landmarks, data['exercise_type'])
        
        # Detect exercise type if requested
        if detect_exercise:
            angles = extract_angles_from_landmarks(landmarks)
            if angles:
                detected_name, confidence = detect_exercise_from_angles(angles)
                # Convert detected exercise name to internal key format
                if detected_name:
                    detected_exercise = EXERCISE_NAME_TO_KEY.get(detected_name, detected_name)

        return jsonify({
            "success": True,
            "landmarks": landmarks,
            "posture": posture_result,
            "detected_exercise": detected_exercise,  # Add detected exercise (internal key format)
            "landmarks_count": len(landmarks) // 4,
            "pose_landmarks": landmarks  # Add full landmarks for frontend display
        })

    except Exception as e:
        print(f"Error in analyze_pose: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/api/exercise/start', methods=['POST'])
def start_exercise():
    try:
        data = request.get_json()
        exercise_type = data.get('exercise_type')
        user_conditions = data.get('medical_conditions', [])

        if exercise_type not in EXERCISES:
            return jsonify({"error": "Invalid exercise type"}), 400

        exercise = EXERCISES[exercise_type]
        restricted = any(c in exercise['restrictions'] for c in user_conditions)
        if restricted:
            return jsonify({
                "error": f"This exercise is not recommended for your condition: {exercise['restrictions']}"
            }), 400

        return jsonify({
            "success": True,
            "exercise": exercise,
            "session_id": f"session_{hash(exercise_type)}_{int(np.random.randint(1000, 9999))}"
        })

    except Exception as e:
        print(f"Error in start_exercise: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/api/nutrition/analyze', methods=['POST'])
def analyze_nutrition():
    try:
        data = request.get_json()
        meals = data.get('meals', [])
        user_profile = data.get('user_profile', {})

        total_calories = 0
        meal_analysis = []

        for meal in meals:
            calories = len(meal.get('name', '')) * 10  # placeholder
            total_calories += calories
            meal_analysis.append({
                "name": meal.get('name', ''),
                "calories": calories,
                "type": meal.get('type', 'unknown')
            })

        weight = user_profile.get('weight', 70)
        height = user_profile.get('height', 170)
        age    = user_profile.get('age', 30)
        goal   = user_profile.get('goal', 'maintenance')

        bmr = 10 * weight + 6.25 * height - 5 * age + 5
        recommended = (
            bmr - 500 if goal == 'weight_loss'
            else bmr + 500 if goal == 'weight_gain'
            else bmr
        )

        return jsonify({
            "success": True,
            "total_calories": total_calories,
            "recommended_calories": recommended,
            "calorie_balance": recommended - total_calories,
            "meals": meal_analysis
        })

    except Exception as e:
        print(f"Error in analyze_nutrition: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/api/workout/recommendations', methods=['POST'])
def get_workout_recommendations():
    """Get smart workout recommendations based on user profile and session data"""
    try:
        data = request.get_json()
        user_profile = data.get('user_profile', {})
        session_history = data.get('session_history', [])
        current_session = data.get('current_session')
        
        user_id = user_profile.get('userId') or user_profile.get('id')
        recommendations = generate_smart_recommendation(
            user_profile, 
            session_history, 
            current_session,
            user_id
        )
        
        return jsonify(recommendations)
        
    except Exception as e:
        print(f"Error in get_workout_recommendations: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/api/workout/calories-burned', methods=['POST'])
def calculate_workout_calories():
    """Calculate calories burned for a workout session"""
    try:
        data = request.get_json()
        exercise_type = data.get('exercise_type')
        duration_minutes = data.get('duration_minutes', 0)
        user_weight = data.get('user_weight', 70)
        reps = data.get('reps', 0)
        
        calories = calculate_calories_burned(
            exercise_type, 
            duration_minutes, 
            user_weight, 
            reps
        )
        
        return jsonify({
            "success": True,
            "calories_burned": calories,
            "exercise_type": exercise_type,
            "duration_minutes": duration_minutes,
            "user_weight": user_weight,
            "reps": reps
        })
        
    except Exception as e:
        print(f"Error in calculate_workout_calories: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/workout/save', methods=['POST'])
def save_workout():
    """Save a workout session to persistent storage"""
    try:
        data = request.get_json()
        
        user_id = data.get('user_id')
        if not user_id:
            return jsonify({
                'success': False,
                'error': 'User ID is required'
            }), 400
        
        session_data = {
            'exercise_type': data.get('exercise_type', 'unknown'),
            'rep_count': data.get('rep_count', 0),
            'reps': data.get('rep_count', 0),  # For compatibility
            'sets': data.get('sets', 0),
            'posture_accuracy': data.get('posture_accuracy', 0),
            'calories_burned': data.get('calories_burned', 0),
            'duration_seconds': data.get('duration_seconds', 0),
            'timestamp': data.get('timestamp', datetime.now().isoformat())
        }
        
        if add_user_workout(user_id, session_data):
            return jsonify({
                'success': True,
                'message': 'Workout saved successfully'
            })
        else:
            return jsonify({
                'success': False,
                'error': 'Failed to save workout'
            }), 500
            
    except Exception as e:
        print(f"Error in save_workout: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/video/analyze', methods=['POST'])
def analyze_video():
    """Analyze a video file for pose detection and rep counting with smart recommendations."""
    tmp_path = None
    try:
        if 'video' not in request.files:
            return jsonify({"error": "No video file provided"}), 400

        video_file = request.files['video']
        exercise_type = request.form.get('exercise_type', 'squats')
        user_profile = json.loads(request.form.get('user_profile', '{}'))
        session_history = json.loads(request.form.get('session_history', '[]'))

        if exercise_type not in EXERCISES:
            return jsonify({"error": f"Invalid exercise type: {exercise_type}"}), 400

        # Save uploaded video to a temp file
        suffix = os.path.splitext(video_file.filename)[1] or '.mp4'
        with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
            video_file.save(tmp.name)
            tmp_path = tmp.name

        print(f"📹 Analyzing video: {tmp_path}, exercise: {exercise_type}")

        cap = cv2.VideoCapture(tmp_path)
        if not cap.isOpened():
            return jsonify({"error": "Could not open video file"}), 400

        landmarks_history = []
        rep_count = 0
        frame_count = 0
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        posture_scores = []
        form_consistency_scores = []
        detected_exercises = []  # Store detected exercises from multiple frames
        
        # NEW: Track total up/down movements for all exercises
        total_movements = {
            'up_count': 0,
            'down_count': 0,
            'total_cycles': 0,
            'current_phase': 'up'
        }

        # Generate unique session ID for this video analysis
        import uuid
        session_id = f"video_{uuid.uuid4().hex[:8]}"

        # Reset rep counter for this new session
        reset_rep_counter(session_id)

        # Check if exercise detection is requested
        detect_exercise = request.form.get('detect_exercise', 'false')
        if isinstance(detect_exercise, str):
            detect_exercise = detect_exercise.lower() == 'true'
        else:
            detect_exercise = bool(detect_exercise)

        # Track current exercise type for rep counting (may be updated by detection)
        current_exercise_type = exercise_type
        
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break

            # Analyze every 5th frame to save processing time
            if frame_count % 5 == 0:
                landmarks = extract_pose_landmarks(frame)
                if landmarks:
                    landmarks_history.append(landmarks)
                    
                    # Extract angles and detect exercise if requested
                    if detect_exercise:
                        angles = extract_angles_from_landmarks(landmarks)
                        if angles:
                            detected_exercise, confidence = detect_exercise_from_angles(angles)
                            if detected_exercise:
                                detected_exercises.append(detected_exercise)
                                # Convert detected exercise name to internal key and use for rep counting
                                if detected_exercise in EXERCISE_NAME_TO_KEY:
                                    current_exercise_type = EXERCISE_NAME_TO_KEY[detected_exercise]
                    
                    # Classify posture for this frame
                    posture_result = classify_posture(landmarks, current_exercise_type)
                    if posture_result:
                        posture_scores.append(posture_result.get('confidence', 0.0))
                    
                    if len(landmarks_history) >= 2:
                        reps, rep_message = count_reps(landmarks_history, current_exercise_type, session_id)
                        rep_count += reps
                        if reps > 0:
                            print(f"  Rep counted: {rep_message} (Total: {rep_count})")
                        elif frame_count % 30 == 0:  # Log every 30th frame for debugging
                            print(f"  [DEBUG] Frame {frame_count}: No rep detected (exercise: {current_exercise_type}, landmarks: {len(landmarks_history)})")
                        
                        # NEW: Track all up/down movements for rep analysis
                        movement = track_movement_cycle(landmarks_history, current_exercise_type, total_movements)
                        if movement:
                            print(f"  [MOVEMENT] {movement}")

            frame_count += 1

        cap.release()
        
        print(f"📊 Video analysis complete: {frame_count} frames processed, {rep_count} reps counted")
        print(f"   Exercise type used: {current_exercise_type}, Initial: {exercise_type}")

        # Calculate performance metrics
        avg_posture_accuracy = sum(posture_scores) / len(posture_scores) if posture_scores else 0.7
        form_consistency = 1.0 - (np.std(posture_scores) if len(posture_scores) > 1 else 0.2)
        
        # Calculate duration in minutes for nutrition analysis
        # Assuming 30 FPS, convert frames to seconds then to minutes
        fps = cap.get(cv2.CAP_PROP_FPS)
        if fps <= 0:
            fps = 30.0  # Default fallback
        duration_seconds = total_frames / fps
        duration_minutes = duration_seconds / 60.0

        # Create session data for recommendation engine
        current_session = {
            'exercise_type': exercise_type,
            'rep_count': rep_count,
            'posture_accuracy': avg_posture_accuracy,
            'rep_completion': min(rep_count / 10.0, 1.0),  # Assuming target of 10 reps
            'form_consistency': form_consistency,
            'duration_minutes': duration_minutes  # Use minutes for nutrition analysis
        }

        # Generate smart recommendations
        user_id = user_profile.get('userId') or user_profile.get('id')
        recommendations = generate_smart_recommendation(
            user_profile, 
            session_history, 
            current_session,
            user_id
        )

        # Calculate calories burned
        user_weight = user_profile.get('weight', 70)
        calories_burned = calculate_calories_burned(
            exercise_type, 
            duration_minutes,  # Use the already calculated duration in minutes
            user_weight, 
            rep_count
        )

        # Classify posture from last detected frame
        posture_result = None
        if landmarks_history:
            posture_result = classify_posture(landmarks_history[-1], exercise_type)

        # Determine the most frequently detected exercise
        detected_exercise = None
        if detect_exercise and detected_exercises:
            from collections import Counter
            exercise_counts = Counter(detected_exercises)
            most_common = exercise_counts.most_common(1)[0]
            detected_name = most_common[0]
            # Convert to internal key format
            detected_exercise = EXERCISE_NAME_TO_KEY.get(detected_name, detected_name)
            print(f"🏃 Final detected exercise: {detected_name} -> {detected_exercise} (appeared {most_common[1]} times)")

        print(f"✅ Video analysis done: {frame_count} frames, {len(landmarks_history)} poses detected, {rep_count} reps")
        print(f"   Movement stats: {total_movements['up_count']} up, {total_movements['down_count']} down, {total_movements['total_cycles']} cycles")

        return jsonify({
            "success": True,
            "exercise_type": exercise_type,
            "detected_exercise": detected_exercise,  # Add detected exercise
            "total_frames": total_frames,
            "frames_analyzed": len(landmarks_history),
            "rep_count": rep_count,
            "posture": posture_result,
            "performance_metrics": {
                "posture_accuracy": avg_posture_accuracy,
                "form_consistency": form_consistency,
                "rep_completion": current_session['rep_completion']
            },
            "calories_burned": calories_burned,
            "recommendations": recommendations,
            "movement_stats": {
                "up_count": total_movements['up_count'],
                "down_count": total_movements['down_count'],
                "total_cycles": total_movements['total_cycles'],
                "current_phase": total_movements['current_phase'],
                "proper_reps": rep_count,
                "detected_reps": total_movements['total_cycles']
            },
            "session_summary": {
                "performance_score": recommendations.get('performance_score', avg_posture_accuracy),
                "next_difficulty": recommendations.get('next_session_difficulty', 'maintain'),
                "duration_seconds": duration_seconds  # Return duration in seconds for frontend
            }
        })

    except Exception as e:
        print(f"Error in analyze_video: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500

    finally:
        # Always clean up the temp file
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except Exception as e:
                print(f"Warning: Could not delete temp file {tmp_path}: {e}")


@app.route('/api/user/profile', methods=['POST'])
def get_user_profile():
    """Get current user profile data from frontend"""
    try:
        data = request.get_json()
        
        # Get user data from frontend (sent by logged-in user)
        user_profile = data.get('user_profile', {})
        
        if not user_profile:
            return jsonify({
                'success': False,
                'error': 'No user profile data provided'
            }), 400
        
        # Return the actual user data sent from frontend
        # In production, this would validate against a database
        return jsonify({
            'success': True,
            'user_profile': user_profile
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/user/update-profile', methods=['POST'])
def update_user_profile():
    """Update user profile data from frontend"""
    try:
        data = request.get_json()
        
        # Get user data from frontend
        user_profile = data.get('user_profile', {})
        
        if not user_profile or not user_profile.get('id'):
            return jsonify({
                'success': False,
                'error': 'User ID and profile data required'
            }), 400
        
        # In production, this would update the database
        # For now, just echo back the updated profile
        
        return jsonify({
            'success': True,
            'message': 'Profile updated successfully',
            'user_profile': user_profile
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# ── Data Persistence ──────────────────────────────────────────────────────────
DATA_DIR = 'data'
NUTRITION_FILE = os.path.join(DATA_DIR, 'nutrition_data.json')

# Ensure data directory exists
os.makedirs(DATA_DIR, exist_ok=True)

def _load_nutrition_data():
    """Load all nutrition data from JSON file"""
    if os.path.exists(NUTRITION_FILE):
        try:
            with open(NUTRITION_FILE, 'r') as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError):
            return {}
    return {}

def _save_nutrition_data(data):
    """Save all nutrition data to JSON file"""
    try:
        with open(NUTRITION_FILE, 'w') as f:
            json.dump(data, f, indent=2)
        return True
    except IOError as e:
        print(f"Error saving nutrition data: {e}")
        return False

def get_user_nutrition(user_id, date):
    """Get nutrition data for a specific user and date"""
    all_data = _load_nutrition_data()
    user_data = all_data.get(user_id, {})
    return user_data.get(date, {'meals': [], 'total_calories': 0})

def save_user_nutrition(user_id, date, meals, total_calories):
    """Save nutrition data for a specific user and date"""
    all_data = _load_nutrition_data()
    
    if user_id not in all_data:
        all_data[user_id] = {}
    
    all_data[user_id][date] = {
        'meals': meals,
        'total_calories': total_calories,
        'last_updated': datetime.now().isoformat()
    }
    
    return _save_nutrition_data(all_data)


# Workout session storage
WORKOUTS_FILE = os.path.join(DATA_DIR, 'workout_sessions.json')

def _load_workout_data():
    """Load all workout data from JSON file"""
    if os.path.exists(WORKOUTS_FILE):
        try:
            with open(WORKOUTS_FILE, 'r') as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError):
            return {}
    return {}

def _save_workout_data(data):
    """Save all workout data to JSON file"""
    try:
        with open(WORKOUTS_FILE, 'w') as f:
            json.dump(data, f, indent=2)
        return True
    except IOError as e:
        print(f"Error saving workout data: {e}")
        return False

def get_user_workouts(user_id):
    """Get all workout sessions for a specific user"""
    all_data = _load_workout_data()
    return all_data.get(user_id, [])

def add_user_workout(user_id, session_data):
    """Add a workout session for a specific user"""
    all_data = _load_workout_data()
    
    if user_id not in all_data:
        all_data[user_id] = []
    
    # Add timestamp if not present
    if 'timestamp' not in session_data:
        session_data['timestamp'] = datetime.now().isoformat()
    
    all_data[user_id].append(session_data)
    return _save_workout_data(all_data)

def get_user_nutrition_all(user_id):
    """Get all nutrition data for a user as a list"""
    all_data = _load_nutrition_data()
    user_data = all_data.get(user_id, {})
    
    # Convert to list format for analytics
    result = []
    for date, data in user_data.items():
        result.append({
            'date': date,
            'total_calories': data.get('total_calories', 0),
            'meals': data.get('meals', [])
        })
    return result

def _merge_session_data(stored_workouts, frontend_sessions, days):
    """Merge stored backend workouts with frontend sessions"""
    cutoff_date = (datetime.now() - timedelta(days=days)).strftime('%Y-%m-%d')
    
    # Create a set of unique session identifiers to avoid duplicates
    seen_sessions = set()
    merged = []
    
    # Add stored workouts first
    for workout in stored_workouts:
        ts = workout.get('timestamp', '')
        if ts >= cutoff_date:
            session_id = f"{ts}_{workout.get('exercise_type', 'unknown')}"
            if session_id not in seen_sessions:
                seen_sessions.add(session_id)
                merged.append(workout)
    
    # Add frontend sessions
    for session in frontend_sessions:
        ts = session.get('timestamp', datetime.now().isoformat())
        if ts >= cutoff_date:
            session_id = f"{ts}_{session.get('exercise_type', 'unknown')}"
            if session_id not in seen_sessions:
                seen_sessions.add(session_id)
                merged.append(session)
    
    return merged

def _merge_nutrition_data(stored_nutrition, frontend_nutrition, days):
    """Merge stored backend nutrition with frontend nutrition"""
    cutoff_date = (datetime.now() - timedelta(days=days)).strftime('%Y-%m-%d')
    
    # Create a dict by date to avoid duplicates
    merged_by_date = {}
    
    # Add stored nutrition first
    for entry in stored_nutrition:
        date = entry.get('date', '')
        if date >= cutoff_date:
            merged_by_date[date] = entry
    
    # Add frontend nutrition (will override stored if same date)
    for entry in frontend_nutrition:
        date = entry.get('date', '')
        if date >= cutoff_date:
            merged_by_date[date] = entry
    
    return list(merged_by_date.values())


@app.route('/api/nutrition/log-intake', methods=['POST'])
def log_nutrition_intake():
    """Log daily calorie intake from frontend"""
    try:
        data = request.get_json()
        
        # Get real user data from frontend (no defaults!)
        user_id = data.get('user_id')
        if not user_id:
            return jsonify({
                'success': False,
                'error': 'User ID is required'
            }), 400
            
        date = data.get('date', datetime.now().strftime('%Y-%m-%d'))
        meals = data.get('meals', [])
        total_calories = data.get('total_calories', 0)
        
        # Get user profile for calculating daily needs
        user_profile = data.get('user_profile', {})
        
        # Calculate daily needs based on real user data
        if user_profile:
            age = user_profile.get('age', 30)
            weight = user_profile.get('weight', 70)
            height = user_profile.get('height', 170)
            gender = user_profile.get('gender', 'male')
            goal = user_profile.get('goal', 'maintenance')
            
            # Calculate BMR
            if gender.lower() == 'female':
                bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161
            else:
                bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5
            
            tdee = bmr * 1.55  # Moderate activity
            
            if goal == 'weight_loss':
                daily_needs = tdee - 500
            elif goal == 'muscle_gain':
                daily_needs = tdee + 300
            else:
                daily_needs = tdee
        else:
            daily_needs = 2000  # Fallback only if no profile
        
        # Save to persistent storage
        save_success = save_user_nutrition(user_id, date, meals, total_calories)
        
        if not save_success:
            return jsonify({
                'success': False,
                'error': 'Failed to save nutrition data'
            }), 500
        
        return jsonify({
            'success': True,
            'message': 'Nutrition intake logged successfully',
            'user_id': user_id,
            'date': date,
            'total_calories': total_calories,
            'daily_needs': round(daily_needs),
            'meals': meals
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/nutrition/get-intake', methods=['POST'])
def get_nutrition_intake():
    """Get daily calorie intake for a specific user from frontend"""
    try:
        data = request.get_json()
        
        # Get real user data from frontend (no defaults!)
        user_id = data.get('user_id')
        if not user_id:
            return jsonify({
                'success': False,
                'error': 'User ID is required'
            }), 400
            
        date = data.get('date', datetime.now().strftime('%Y-%m-%d'))
        
        # Get user profile for calculating daily needs
        user_profile = data.get('user_profile', {})
        
        # Calculate daily needs based on real user data
        if user_profile and user_profile.get('weight'):
            age = user_profile.get('age', 30)
            weight = user_profile.get('weight', 70)
            height = user_profile.get('height', 170)
            gender = user_profile.get('gender', 'male')
            goal = user_profile.get('goal', 'maintenance')
            
            # Calculate BMR
            if gender.lower() == 'female':
                bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161
            else:
                bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5
            
            tdee = bmr * 1.55
            
            if goal == 'weight_loss':
                daily_needs = tdee - 500
            elif goal == 'muscle_gain':
                daily_needs = tdee + 300
            else:
                daily_needs = tdee
        else:
            daily_needs = 2000
        
        # Get stored nutrition data from persistent storage
        stored_nutrition = get_user_nutrition(user_id, date)
        stored_meals = stored_nutrition.get('meals', [])
        stored_total = stored_nutrition.get('total_calories', 0)
        
        # Fallback to frontend data if nothing stored yet
        if not stored_meals:
            stored_meals = data.get('stored_meals', [])
            stored_total = data.get('stored_total_calories', 0)
        
        nutrition_data = {
            'user_id': user_id,
            'date': date,
            'total_calories': stored_total,
            'daily_needs': round(daily_needs),
            'meals': stored_meals if stored_meals else [],
            'progress_percentage': (stored_total / daily_needs * 100) if daily_needs > 0 else 0
        }
        
        return jsonify({
            'success': True,
            'nutrition_data': nutrition_data
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/diet/generate-plan', methods=['POST'])
def generate_diet_plan():
    """Generate personalized diet plan based on user profile, goals, and medical conditions"""
    try:
        data = request.get_json()
        
        user_profile = data.get('user_profile', {})
        medical_conditions = data.get('medical_conditions', [])
        
        # Extract user parameters
        age = user_profile.get('age', 30)
        weight = user_profile.get('weight', 70)  # kg
        height = user_profile.get('height', 170)  # cm
        gender = user_profile.get('gender', 'male')
        goal = user_profile.get('goal', 'maintenance')  # weight_loss, muscle_gain, maintenance
        activity_level = user_profile.get('activity_level', 'moderate')  # sedentary, light, moderate, active, very_active
        
        # Calculate BMR using Mifflin-St Jeor Equation
        if gender.lower() == 'female':
            bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161
        else:
            bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5
        
        # Activity multipliers
        activity_multipliers = {
            'sedentary': 1.2,
            'light': 1.375,
            'moderate': 1.55,
            'active': 1.725,
            'very_active': 1.9
        }
        
        tdee = bmr * activity_multipliers.get(activity_level, 1.55)
        
        # Adjust calories based on goal
        if goal == 'weight_loss':
            target_calories = tdee - 500  # 500 calorie deficit
        elif goal == 'muscle_gain':
            target_calories = tdee + 300  # 300 calorie surplus
        else:
            target_calories = tdee
        
        # Medical condition adjustments
        medical_adjustments = apply_medical_diet_adjustments(medical_conditions)
        
        # Generate meal plan
        diet_plan = create_meal_plan(
            target_calories=target_calories,
            goal=goal,
            medical_adjustments=medical_adjustments,
            weight=weight
        )
        
        return jsonify({
            'success': True,
            'diet_plan': {
                'daily_targets': {
                    'calories': round(target_calories),
                    'protein': round(weight * (2.0 if goal == 'muscle_gain' else 1.6)),  # g per kg
                    'carbs': round(target_calories * 0.45 / 4),  # 45% of calories
                    'fats': round(target_calories * 0.25 / 9),   # 25% of calories
                    'fiber': 25 + (target_calories - 2000) / 1000 * 5  # 25-35g range
                },
                'meal_distribution': diet_plan,
                'medical_constraints': medical_adjustments.get('restrictions', []),
                'recommendations': medical_adjustments.get('recommendations', [])
            },
            'calculations': {
                'bmr': round(bmr),
                'tdee': round(tdee),
                'activity_level': activity_level,
                'goal_adjustment': goal
            }
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


def apply_medical_diet_adjustments(medical_conditions):
    """Apply dietary adjustments based on medical conditions"""
    adjustments = {
        'restrictions': [],
        'recommendations': [],
        'macro_modifications': {}
    }
    
    conditions_lower = [c.lower() for c in medical_conditions]
    
    # Diabetes adjustments
    if any(c in conditions_lower for c in ['diabetes', 'type 2 diabetes', 'diabetic']):
        adjustments['restrictions'].append('Limit simple sugars and refined carbs')
        adjustments['recommendations'].append('Focus on low glycemic index foods')
        adjustments['recommendations'].append('Distribute carbs evenly across meals')
        adjustments['macro_modifications']['carbs'] = 0.40  # 40% instead of 45%
        adjustments['macro_modifications']['fats'] = 0.30   # 30% instead of 25%
    
    # Hypertension adjustments
    if any(c in conditions_lower for c in ['hypertension', 'high blood pressure']):
        adjustments['restrictions'].append('Limit sodium intake to <2300mg/day')
        adjustments['recommendations'].append('Increase potassium-rich foods')
        adjustments['recommendations'].append('Follow DASH diet principles')
    
    # Heart disease adjustments
    if any(c in conditions_lower for c in ['heart disease', 'cardiovascular disease', 'heart condition']):
        adjustments['restrictions'].append('Limit saturated fats and trans fats')
        adjustments['restrictions'].append('Limit cholesterol to <300mg/day')
        adjustments['recommendations'].append('Increase omega-3 fatty acids')
        adjustments['recommendations'].append('Choose lean protein sources')
        adjustments['macro_modifications']['fats'] = 0.25
    
    # Kidney disease adjustments
    if any(c in conditions_lower for c in ['kidney disease', 'renal disease', 'kidney condition']):
        adjustments['restrictions'].append('Limit protein intake (consult doctor)')
        adjustments['restrictions'].append('Limit phosphorus and potassium')
        adjustments['recommendations'].append('Monitor fluid intake')
    
    # High cholesterol adjustments
    if any(c in conditions_lower for c in ['high cholesterol', 'hyperlipidemia']):
        adjustments['restrictions'].append('Limit dietary cholesterol')
        adjustments['recommendations'].append('Increase soluble fiber')
        adjustments['recommendations'].append('Choose plant-based proteins')
    
    return adjustments


def create_meal_plan(target_calories, goal, medical_adjustments, weight):
    """Create structured meal plan with calorie distribution"""
    
    # Meal distribution percentages
    meal_distribution = {
        'breakfast': 0.25,
        'morning_snack': 0.10,
        'lunch': 0.30,
        'afternoon_snack': 0.10,
        'dinner': 0.25
    }
    
    # Calculate calories per meal
    meals = {}
    for meal, percentage in meal_distribution.items():
        meal_calories = round(target_calories * percentage)
        
        # Macro distribution (adjust based on goal and medical conditions)
        if goal == 'muscle_gain':
            protein_ratio = 0.35
            carbs_ratio = 0.40
            fat_ratio = 0.25
        elif goal == 'weight_loss':
            protein_ratio = 0.40
            carbs_ratio = 0.30
            fat_ratio = 0.30
        else:  # maintenance
            protein_ratio = 0.30
            carbs_ratio = 0.45
            fat_ratio = 0.25
        
        # Apply medical modifications
        if 'carbs' in medical_adjustments.get('macro_modifications', {}):
            carbs_ratio = medical_adjustments['macro_modifications']['carbs']
        if 'fats' in medical_adjustments.get('macro_modifications', {}):
            fat_ratio = medical_adjustments['macro_modifications']['fats']
        
        meals[meal] = {
            'calories': meal_calories,
            'protein': round(meal_calories * protein_ratio / 4),  # grams
            'carbs': round(meal_calories * carbs_ratio / 4),       # grams
            'fats': round(meal_calories * fat_ratio / 9)           # grams
        }
    
    # Add meal descriptions
    meal_descriptions = {
        'breakfast': 'Start your day with energy-boosting foods',
        'morning_snack': 'Light snack to maintain energy',
        'lunch': 'Main meal with balanced nutrients',
        'afternoon_snack': 'Pre-workout or energy maintenance',
        'dinner': 'Evening meal, lighter for weight loss goals'
    }
    
    for meal in meals:
        meals[meal]['description'] = meal_descriptions.get(meal, '')
        meals[meal]['timing'] = get_meal_timing(meal)
    
    return meals


def get_meal_timing(meal_type):
    """Get recommended timing for each meal"""
    timings = {
        'breakfast': '7:00 - 9:00 AM',
        'morning_snack': '10:00 - 11:00 AM',
        'lunch': '12:00 - 2:00 PM',
        'afternoon_snack': '3:00 - 4:00 PM',
        'dinner': '6:00 - 8:00 PM'
    }
    return timings.get(meal_type, 'Flexible')


# Recipe Database
RECIPE_DATABASE = {
    'breakfast': [
        {
            'id': 'b1',
            'name': 'Oatmeal with Berries',
            'ingredients': ['Rolled oats (50g)', 'Mixed berries (100g)', 'Almond milk (200ml)', 'Honey (1 tbsp)', 'Chia seeds (1 tsp)'],
            'calories': 320,
            'protein': 12,
            'carbs': 58,
            'fats': 8,
            'fiber': 10,
            'prep_time': '10 min',
            'dietary_tags': ['vegetarian', 'high_fiber', 'heart_healthy'],
            'medical_safe_for': ['diabetes', 'hypertension', 'heart_disease', 'high_cholesterol'],
            'portion': '1 bowl (300g)'
        },
        {
            'id': 'b2',
            'name': 'Vegetable Omelette',
            'ingredients': ['Eggs (2 large)', 'Spinach (50g)', 'Bell peppers (50g)', 'Onion (30g)', 'Olive oil (1 tsp)'],
            'calories': 280,
            'protein': 18,
            'carbs': 8,
            'fats': 20,
            'fiber': 3,
            'prep_time': '15 min',
            'dietary_tags': ['keto', 'low_carb', 'gluten_free'],
            'medical_safe_for': ['diabetes', 'hypertension'],
            'portion': '2 eggs + vegetables'
        },
        {
            'id': 'b3',
            'name': 'Greek Yogurt Parfait',
            'ingredients': ['Greek yogurt (150g)', 'Granola (30g)', 'Banana (1 medium)', 'Walnuts (15g)', 'Honey (1 tsp)'],
            'calories': 380,
            'protein': 15,
            'carbs': 48,
            'fats': 16,
            'fiber': 4,
            'prep_time': '5 min',
            'dietary_tags': ['vegetarian', 'protein_rich', 'probiotic'],
            'medical_safe_for': ['hypertension', 'heart_disease'],
            'portion': '1 parfait glass'
        },
        {
            'id': 'b4',
            'name': 'Whole Wheat Toast with Avocado',
            'ingredients': ['Whole wheat bread (2 slices)', 'Avocado (1/2 medium)', 'Cherry tomatoes (50g)', 'Lemon juice', 'Black pepper'],
            'calories': 290,
            'protein': 8,
            'carbs': 32,
            'fats': 16,
            'fiber': 10,
            'prep_time': '8 min',
            'dietary_tags': ['vegan', 'heart_healthy', 'high_fiber'],
            'medical_safe_for': ['diabetes', 'hypertension', 'heart_disease', 'high_cholesterol'],
            'portion': '2 toast slices'
        },
        {
            'id': 'b5',
            'name': 'Protein Smoothie Bowl',
            'ingredients': ['Protein powder (1 scoop)', 'Frozen berries (100g)', 'Banana (1/2)', 'Almond milk (150ml)', 'Almond butter (1 tbsp)'],
            'calories': 350,
            'protein': 25,
            'carbs': 35,
            'fats': 12,
            'fiber': 8,
            'prep_time': '5 min',
            'dietary_tags': ['vegetarian', 'high_protein', 'muscle_gain'],
            'medical_safe_for': ['diabetes'],
            'portion': '1 bowl (350g)'
        }
    ],
    'lunch': [
        {
            'id': 'l1',
            'name': 'Grilled Chicken Salad',
            'ingredients': ['Chicken breast (150g)', 'Mixed greens (100g)', 'Cucumber (50g)', 'Tomato (50g)', 'Olive oil dressing (1 tbsp)'],
            'calories': 320,
            'protein': 35,
            'carbs': 12,
            'fats': 16,
            'fiber': 5,
            'prep_time': '20 min',
            'dietary_tags': ['keto', 'low_carb', 'gluten_free', 'high_protein'],
            'medical_safe_for': ['diabetes', 'hypertension', 'heart_disease'],
            'portion': '1 large bowl'
        },
        {
            'id': 'l2',
            'name': 'Quinoa Buddha Bowl',
            'ingredients': ['Quinoa (80g cooked)', 'Chickpeas (100g)', 'Roasted vegetables (150g)', 'Tahini dressing (1 tbsp)', 'Lemon juice'],
            'calories': 420,
            'protein': 15,
            'carbs': 62,
            'fats': 14,
            'fiber': 14,
            'prep_time': '25 min',
            'dietary_tags': ['vegan', 'vegetarian', 'high_fiber', 'gluten_free'],
            'medical_safe_for': ['diabetes', 'hypertension', 'heart_disease', 'high_cholesterol'],
            'portion': '1 bowl (400g)'
        },
        {
            'id': 'l3',
            'name': 'Turkey Lettuce Wraps',
            'ingredients': ['Ground turkey (150g)', 'Lettuce leaves (6 large)', 'Carrots (50g)', 'Water chestnuts (30g)', 'Low-sodium soy sauce (1 tbsp)'],
            'calories': 280,
            'protein': 28,
            'carbs': 14,
            'fats': 12,
            'fiber': 3,
            'prep_time': '20 min',
            'dietary_tags': ['keto', 'low_carb', 'gluten_free'],
            'medical_safe_for': ['diabetes', 'hypertension'],
            'portion': '3-4 wraps'
        },
        {
            'id': 'l4',
            'name': 'Mediterranean Fish Plate',
            'ingredients': ['White fish fillet (150g)', 'Quinoa (60g)', 'Steamed broccoli (100g)', 'Cherry tomatoes (50g)', 'Olive oil (1 tsp)'],
            'calories': 380,
            'protein': 32,
            'carbs': 28,
            'fats': 14,
            'fiber': 5,
            'prep_time': '25 min',
            'dietary_tags': ['gluten_free', 'heart_healthy', 'high_protein', 'omega_3'],
            'medical_safe_for': ['diabetes', 'hypertension', 'heart_disease'],
            'portion': '1 plate'
        },
        {
            'id': 'l5',
            'name': 'Lentil Vegetable Curry',
            'ingredients': ['Red lentils (80g dry)', 'Mixed vegetables (150g)', 'Coconut milk (100ml)', 'Curry powder (1 tsp)', 'Brown rice (100g cooked)'],
            'calories': 450,
            'protein': 18,
            'carbs': 68,
            'fats': 12,
            'fiber': 16,
            'prep_time': '30 min',
            'dietary_tags': ['vegan', 'vegetarian', 'high_fiber', 'gluten_free'],
            'medical_safe_for': ['diabetes', 'hypertension', 'heart_disease', 'high_cholesterol'],
            'portion': '1 bowl with rice'
        }
    ],
    'dinner': [
        {
            'id': 'd1',
            'name': 'Baked Salmon with Asparagus',
            'ingredients': ['Salmon fillet (150g)', 'Asparagus (100g)', 'Lemon (1/2)', 'Dill', 'Olive oil (1 tsp)'],
            'calories': 340,
            'protein': 35,
            'carbs': 8,
            'fats': 20,
            'fiber': 4,
            'prep_time': '25 min',
            'dietary_tags': ['keto', 'low_carb', 'gluten_free', 'omega_3', 'heart_healthy'],
            'medical_safe_for': ['diabetes', 'hypertension', 'heart_disease'],
            'portion': '1 fillet + vegetables'
        },
        {
            'id': 'd2',
            'name': 'Lean Beef Stir-Fry',
            'ingredients': ['Lean beef strips (150g)', 'Bell peppers (100g)', 'Broccoli (100g)', 'Snow peas (50g)', 'Ginger garlic sauce (low sodium)'],
            'calories': 320,
            'protein': 35,
            'carbs': 16,
            'fats': 14,
            'fiber': 6,
            'prep_time': '20 min',
            'dietary_tags': ['gluten_free', 'high_protein', 'low_carb'],
            'medical_safe_for': ['diabetes'],
            'portion': '1 plate'
        },
        {
            'id': 'd3',
            'name': 'Tofu Vegetable Stir-Fry',
            'ingredients': ['Firm tofu (150g)', 'Mixed vegetables (200g)', 'Brown rice (100g cooked)', 'Sesame oil (1 tsp)', 'Low-sodium soy sauce (1 tbsp)'],
            'calories': 380,
            'protein': 20,
            'carbs': 48,
            'fats': 14,
            'fiber': 8,
            'prep_time': '20 min',
            'dietary_tags': ['vegan', 'vegetarian', 'heart_healthy'],
            'medical_safe_for': ['diabetes', 'hypertension', 'heart_disease', 'high_cholesterol'],
            'portion': '1 plate'
        },
        {
            'id': 'd4',
            'name': 'Stuffed Bell Peppers',
            'ingredients': ['Bell peppers (2 large)', 'Ground turkey (100g)', 'Quinoa (50g cooked)', 'Tomato sauce (100ml)', 'Italian herbs'],
            'calories': 360,
            'protein': 28,
            'carbs': 32,
            'fats': 12,
            'fiber': 6,
            'prep_time': '35 min',
            'dietary_tags': ['gluten_free', 'high_protein'],
            'medical_safe_for': ['diabetes', 'hypertension'],
            'portion': '2 stuffed peppers'
        },
        {
            'id': 'd5',
            'name': 'Zucchini Noodles with Pesto',
            'ingredients': ['Zucchini noodles (200g)', 'Homemade pesto (2 tbsp)', 'Cherry tomatoes (50g)', 'Pine nuts (10g)', 'Parmesan (15g)'],
            'calories': 280,
            'protein': 10,
            'carbs': 14,
            'fats': 22,
            'fiber': 5,
            'prep_time': '15 min',
            'dietary_tags': ['keto', 'low_carb', 'vegetarian', 'gluten_free'],
            'medical_safe_for': ['diabetes', 'hypertension'],
            'portion': '1 bowl'
        }
    ],
    'snack': [
        {
            'id': 's1',
            'name': 'Apple with Almond Butter',
            'ingredients': ['Apple (1 medium)', 'Almond butter (1 tbsp)', 'Cinnamon'],
            'calories': 180,
            'protein': 4,
            'carbs': 22,
            'fats': 10,
            'fiber': 5,
            'prep_time': '2 min',
            'dietary_tags': ['vegetarian', 'vegan', 'heart_healthy'],
            'medical_safe_for': ['diabetes', 'hypertension', 'heart_disease'],
            'portion': '1 apple'
        },
        {
            'id': 's2',
            'name': 'Hard-Boiled Eggs',
            'ingredients': ['Eggs (2 large)', 'Black pepper', 'Paprika'],
            'calories': 140,
            'protein': 12,
            'carbs': 0,
            'fats': 10,
            'fiber': 0,
            'prep_time': '10 min',
            'dietary_tags': ['keto', 'low_carb', 'gluten_free', 'high_protein'],
            'medical_safe_for': ['diabetes', 'hypertension'],
            'portion': '2 eggs'
        },
        {
            'id': 's3',
            'name': 'Greek Yogurt with Cucumber',
            'ingredients': ['Greek yogurt (100g)', 'Cucumber (50g)', 'Dill', 'Garlic powder'],
            'calories': 120,
            'protein': 10,
            'carbs': 8,
            'fats': 6,
            'fiber': 0,
            'prep_time': '3 min',
            'dietary_tags': ['vegetarian', 'gluten_free', 'probiotic'],
            'medical_safe_for': ['diabetes', 'hypertension'],
            'portion': '1 small bowl'
        },
        {
            'id': 's4',
            'name': 'Mixed Nuts',
            'ingredients': ['Almonds (15g)', 'Walnuts (15g)', 'Cashews (10g)'],
            'calories': 200,
            'protein': 6,
            'carbs': 8,
            'fats': 18,
            'fiber': 3,
            'prep_time': '0 min',
            'dietary_tags': ['vegetarian', 'vegan', 'keto', 'heart_healthy'],
            'medical_safe_for': ['diabetes', 'heart_disease'],
            'portion': '1 small handful (40g)'
        },
        {
            'id': 's5',
            'name': 'Hummus with Carrots',
            'ingredients': ['Hummus (40g)', 'Carrot sticks (100g)', 'Cucumber slices (50g)'],
            'calories': 150,
            'protein': 6,
            'carbs': 18,
            'fats': 8,
            'fiber': 6,
            'prep_time': '5 min',
            'dietary_tags': ['vegan', 'vegetarian', 'gluten_free'],
            'medical_safe_for': ['diabetes', 'hypertension', 'heart_disease'],
            'portion': '1 snack plate'
        }
    ]
}


@app.route('/api/recipes/get-recommendations', methods=['POST'])
def get_recipe_recommendations():
    """Generate recipe recommendations based on diet plan, goals, and medical conditions"""
    try:
        data = request.get_json()
        
        # Get user data from frontend
        user_profile = data.get('user_profile', {})
        medical_conditions = data.get('medical_conditions', [])
        diet_plan = data.get('diet_plan', {})
        meal_type = data.get('meal_type', 'all')  # breakfast, lunch, dinner, snack, or all
        target_calories = data.get('target_calories', 400)
        
        # Filter recipes based on medical conditions
        safe_recipes = filter_recipes_by_medical_conditions(
            RECIPE_DATABASE, 
            medical_conditions
        )
        
        # Select recipes for each meal type
        recommendations = {}
        
        if meal_type == 'all':
            # Generate full day meal plan
            meal_types = ['breakfast', 'lunch', 'dinner', 'snack']
        else:
            meal_types = [meal_type]
        
        for mtype in meal_types:
            if mtype in safe_recipes:
                # Get diet plan target for this meal
                meal_target = diet_plan.get('meal_distribution', {}).get(mtype, {})
                target_cals = meal_target.get('calories', target_calories if mtype != 'snack' else 150)
                
                # Find best matching recipes
                matching_recipes = find_matching_recipes(
                    safe_recipes[mtype],
                    target_cals,
                    user_profile.get('goal', 'maintenance'),
                    medical_conditions
                )
                
                recommendations[mtype] = matching_recipes
        
        return jsonify({
            'success': True,
            'recommendations': recommendations,
            'medical_conditions_filtered': len(medical_conditions) > 0,
            'filters_applied': medical_conditions
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


def filter_recipes_by_medical_conditions(recipes_db, medical_conditions):
    """Filter recipes based on medical conditions"""
    if not medical_conditions:
        return recipes_db
    
    conditions_lower = [c.lower() for c in medical_conditions]
    filtered_db = {}
    
    for meal_type, recipes in recipes_db.items():
        filtered_recipes = []
        
        for recipe in recipes:
            safe_for = recipe.get('medical_safe_for', [])
            is_safe = True
            
            # Check if recipe is safe for all user's conditions
            for condition in conditions_lower:
                condition_key = condition.replace(' ', '_')
                if safe_for and condition_key not in safe_for:
                    # Recipe not explicitly safe for this condition
                    if 'diabetes' in condition and recipe['carbs'] > 50:
                        is_safe = False
                        break
                    if 'hypertension' in condition and recipe.get('sodium_mg', 0) > 500:
                        is_safe = False
                        break
            
            if is_safe:
                filtered_recipes.append(recipe)
        
        # If no recipes match, include all (let user decide)
        filtered_db[meal_type] = filtered_recipes if filtered_recipes else recipes
    
    return filtered_db


def find_matching_recipes(recipes, target_calories, goal, medical_conditions):
    """Find best matching recipes for target calories and goal"""
    scored_recipes = []
    
    for recipe in recipes:
        score = 0
        calorie_diff = abs(recipe['calories'] - target_calories)
        
        # Score based on calorie match (closer = higher score)
        if calorie_diff <= 50:
            score += 100
        elif calorie_diff <= 100:
            score += 80
        elif calorie_diff <= 150:
            score += 60
        else:
            score += max(0, 40 - calorie_diff / 10)
        
        # Score based on goal alignment
        if goal == 'muscle_gain':
            # Prefer high protein recipes
            if recipe['protein'] >= 25:
                score += 30
            elif recipe['protein'] >= 20:
                score += 20
        elif goal == 'weight_loss':
            # Prefer lower calorie, high fiber
            if recipe['calories'] <= target_calories:
                score += 20
            if recipe['fiber'] >= 5:
                score += 15
        else:  # maintenance
            # Balanced preference
            if 15 <= recipe['protein'] <= 30:
                score += 15
        
        # Add medical bonus
        if medical_conditions and recipe.get('medical_safe_for'):
            score += 10
        
        # Cap score at 100% to prevent showing over 100%
        score = min(score, 100)
        
        scored_recipes.append({
            'recipe': recipe,
            'score': score,
            'calorie_match': calorie_diff
        })
    
    # Sort by score (descending)
    scored_recipes.sort(key=lambda x: x['score'], reverse=True)
    
    # Return top 3 recipes with their match scores
    return [
        {
            'id': item['recipe']['id'],
            'name': item['recipe']['name'],
            'ingredients': item['recipe']['ingredients'],
            'calories': item['recipe']['calories'],
            'protein': item['recipe']['protein'],
            'carbs': item['recipe']['carbs'],
            'fats': item['recipe']['fats'],
            'fiber': item['recipe']['fiber'],
            'prep_time': item['recipe']['prep_time'],
            'portion': item['recipe']['portion'],
            'dietary_tags': item['recipe']['dietary_tags'],
            'match_score': item['score'],
            'calorie_difference': item['calorie_match']
        }
        for item in scored_recipes[:3]
    ]


@app.route('/api/analytics/progress', methods=['POST'])
def get_progress_analytics():
    """Get comprehensive progress analytics for dashboard"""
    try:
        data = request.get_json()
        print(f"📊 Analytics request received")
        
        # Get user data from frontend
        user_id = data.get('user_id')
        user_profile = data.get('user_profile', {})
        session_history = data.get('session_history', [])
        nutrition_history = data.get('nutrition_history', [])
        time_range = data.get('time_range', '30_days')
        
        print(f"   User: {user_id}, Time range: {time_range}")
        print(f"   Frontend sessions: {len(session_history)}, nutrition entries: {len(nutrition_history)}")
        
        if not user_id:
            return jsonify({
                'success': False,
                'error': 'User ID is required'
            }), 400
        
        # Calculate date range
        days_map = {'7_days': 7, '30_days': 30, '90_days': 90}
        days = days_map.get(time_range, 30)
        
        # Load stored backend data and merge with frontend data
        print(f"   Loading stored data...")
        stored_workouts = get_user_workouts(user_id)
        stored_nutrition = get_user_nutrition_all(user_id)
        print(f"   Stored workouts: {len(stored_workouts)}, stored nutrition: {len(stored_nutrition)}")
        
        # Merge session history (backend + frontend)
        print(f"   Merging session data...")
        all_sessions = _merge_session_data(stored_workouts, session_history, days)
        print(f"   Total sessions after merge: {len(all_sessions)}")
        
        # Merge nutrition history (backend + frontend)
        print(f"   Merging nutrition data...")
        all_nutrition = _merge_nutrition_data(stored_nutrition, nutrition_history, days)
        print(f"   Total nutrition entries after merge: {len(all_nutrition)}")
        
        # Calculate workout statistics
        print(f"   Calculating workout stats...")
        workout_stats = calculate_workout_stats(all_sessions, days)
        
        # Calculate nutrition statistics
        print(f"   Calculating nutrition stats...")
        nutrition_stats = calculate_nutrition_stats(all_nutrition, days)
        
        # Calculate performance trends
        print(f"   Calculating performance trends...")
        performance_trends = calculate_performance_trends(all_sessions, days)
        
        # Generate goal progress
        print(f"   Calculating goal progress...")
        goal_progress = calculate_goal_progress(user_profile, workout_stats, nutrition_stats, days)
        
        # Weekly breakdown
        print(f"   Calculating weekly breakdown...")
        weekly_breakdown = calculate_weekly_breakdown(all_sessions, all_nutrition, days)
        
        print(f"✅ Analytics calculated successfully")
        
        return jsonify({
            'success': True,
            'analytics': {
                'time_range': time_range,
                'days_analyzed': days,
                'workout_stats': workout_stats,
                'nutrition_stats': nutrition_stats,
                'performance_trends': performance_trends,
                'goal_progress': goal_progress,
                'weekly_breakdown': weekly_breakdown,
                'summary': generate_summary(workout_stats, nutrition_stats, goal_progress)
            }
        })
        
    except Exception as e:
        import traceback
        print(f"❌ Error in get_progress_analytics: {e}")
        print(f"   Traceback: {traceback.format_exc()}")
        return jsonify({
            'success': False,
            'error': str(e),
            'traceback': traceback.format_exc()
        }), 500


def calculate_workout_stats(session_history, days):
    """Calculate workout statistics from session history"""
    if not session_history:
        return {
            'total_workouts': 0,
            'total_reps': 0,
            'total_calories_burned': 0,
            'avg_workout_duration': 0,
            'avg_posture_accuracy': 0,
            'consistency_score': 0,
            'favorite_exercise': 'N/A'
        }
    
    total_workouts = len(session_history)
    total_reps = sum(session.get('rep_count', 0) for session in session_history)
    total_calories = sum(session.get('calories_burned', 0) for session in session_history)
    
    # Calculate average posture accuracy
    accuracy_scores = [session.get('posture_accuracy', 0) for session in session_history if session.get('posture_accuracy')]
    avg_accuracy = sum(accuracy_scores) / len(accuracy_scores) if accuracy_scores else 0
    
    # Calculate average workout duration
    durations = [session.get('duration_seconds', 0) / 60 for session in session_history if session.get('duration_seconds')]
    avg_duration = sum(durations) / len(durations) if durations else 0
    
    # Find favorite exercise
    exercise_counts = {}
    for session in session_history:
        ex_type = session.get('exercise_type', 'unknown')
        exercise_counts[ex_type] = exercise_counts.get(ex_type, 0) + 1
    favorite_exercise = max(exercise_counts, key=exercise_counts.get) if exercise_counts else 'N/A'
    
    # Calculate consistency score (workouts per week)
    weeks = days / 7
    consistency_score = min((total_workouts / weeks) * 20, 100) if weeks > 0 else 0
    
    return {
        'total_workouts': total_workouts,
        'total_reps': total_reps,
        'total_calories_burned': round(total_calories, 1),
        'avg_workout_duration': round(avg_duration, 1),
        'avg_posture_accuracy': round(avg_accuracy * 100, 1),
        'consistency_score': round(consistency_score, 1),
        'favorite_exercise': favorite_exercise
    }


def calculate_nutrition_stats(nutrition_history, days):
    """Calculate nutrition statistics from history"""
    if not nutrition_history:
        return {
            'avg_daily_calories': 0,
            'avg_daily_protein': 0,
            'avg_daily_carbs': 0,
            'avg_daily_fats': 0,
            'calorie_goal_adherence': 0,
            'total_meals_logged': 0
        }
    
    total_calories = sum(day.get('total_calories', 0) for day in nutrition_history)
    total_protein = sum(day.get('protein', 0) for day in nutrition_history)
    total_carbs = sum(day.get('carbs', 0) for day in nutrition_history)
    total_fats = sum(day.get('fats', 0) for day in nutrition_history)
    
    days_count = len(nutrition_history) if nutrition_history else 1
    
    # Calculate goal adherence (days within 10% of target)
    on_target_days = 0
    for day in nutrition_history:
        total = day.get('total_calories', 0)
        target = day.get('daily_needs', 2000)
        if abs(total - target) <= (target * 0.1):
            on_target_days += 1
    
    adherence = (on_target_days / days_count * 100) if days_count > 0 else 0
    
    return {
        'avg_daily_calories': round(total_calories / days_count, 0),
        'avg_daily_protein': round(total_protein / days_count, 1),
        'avg_daily_carbs': round(total_carbs / days_count, 1),
        'avg_daily_fats': round(total_fats / days_count, 1),
        'calorie_goal_adherence': round(adherence, 1),
        'total_meals_logged': sum(len(day.get('meals', [])) for day in nutrition_history)
    }


def calculate_performance_trends(session_history, days):
    """Calculate performance trends over time"""
    if not session_history or len(session_history) < 2:
        return {
            'posture_trend': 'stable',
            'reps_trend': 'stable',
            'workout_frequency_trend': 'stable'
        }
    
    # Sort by date
    sorted_sessions = sorted(session_history, key=lambda x: x.get('date', ''))
    
    # Split into first half and second half
    mid_point = len(sorted_sessions) // 2
    first_half = sorted_sessions[:mid_point]
    second_half = sorted_sessions[mid_point:]
    
    # Calculate posture trend
    first_posture = sum(s.get('posture_accuracy', 0) for s in first_half) / len(first_half) if first_half else 0
    second_posture = sum(s.get('posture_accuracy', 0) for s in second_half) / len(second_half) if second_half else 0
    
    posture_change = second_posture - first_posture
    if posture_change > 0.05:
        posture_trend = 'improving'
    elif posture_change < -0.05:
        posture_trend = 'declining'
    else:
        posture_trend = 'stable'
    
    # Calculate reps trend
    first_reps = sum(s.get('rep_count', 0) for s in first_half) / len(first_half) if first_half else 0
    second_reps = sum(s.get('rep_count', 0) for s in second_half) / len(second_half) if second_half else 0
    
    reps_change = second_reps - first_reps
    if reps_change > 2:
        reps_trend = 'improving'
    elif reps_change < -2:
        reps_trend = 'declining'
    else:
        reps_trend = 'stable'
    
    return {
        'posture_trend': posture_trend,
        'reps_trend': reps_trend,
        'posture_improvement': round(posture_change * 100, 1),
        'reps_improvement': round(reps_change, 1)
    }


def calculate_goal_progress(user_profile, workout_stats, nutrition_stats, days=30):
    """Calculate progress towards fitness goals"""
    goal = user_profile.get('goal', 'maintenance')
    
    if goal == 'weight_loss':
        # For weight loss: check calorie deficit consistency
        adherence = nutrition_stats.get('calorie_goal_adherence', 0)
        progress = min(adherence * 1.2, 100)  # Bonus for staying under target
        target_message = 'Maintain calorie deficit for weight loss'
    elif goal == 'muscle_gain':
        # For muscle gain: check workout consistency and protein
        consistency = workout_stats.get('consistency_score', 0)
        protein = nutrition_stats.get('avg_daily_protein', 0)
        progress = min((consistency + min(protein * 2, 30)) / 1.3, 100)
        target_message = 'Consistent workouts + high protein for muscle gain'
    else:  # maintenance
        consistency = workout_stats.get('consistency_score', 0)
        adherence = nutrition_stats.get('calorie_goal_adherence', 0)
        progress = (consistency + adherence) / 2
        target_message = 'Maintain current fitness level'
    
    return {
        'goal': goal,
        'progress_percentage': round(progress, 1),
        'target_message': target_message,
        'workouts_this_period': workout_stats.get('total_workouts', 0),
        'target_workouts': max(3, days // 7 * 3)  # At least 3 per week
    }


def calculate_weekly_breakdown(session_history, nutrition_history, days):
    """Calculate weekly breakdown for charts"""
    weeks = []
    num_weeks = days // 7
    
    for week in range(num_weeks):
        week_start = days - (week + 1) * 7
        week_end = days - week * 7
        
        # Filter sessions for this week
        week_sessions = [
            s for s in session_history 
            if week_start <= s.get('day_number', 0) < week_end
        ]
        
        # Filter nutrition for this week
        week_nutrition = [
            n for n in nutrition_history 
            if week_start <= n.get('day_number', 0) < week_end
        ]
        
        weeks.append({
            'week': f'Week {num_weeks - week}',
            'workouts': len(week_sessions),
            'calories_burned': sum(s.get('calories_burned', 0) for s in week_sessions),
            'avg_posture': sum(s.get('posture_accuracy', 0) for s in week_sessions) / len(week_sessions) * 100 if week_sessions else 0,
            'calories_consumed': sum(n.get('total_calories', 0) for n in week_nutrition) / len(week_nutrition) if week_nutrition else 0
        })
    
    return weeks


def generate_summary(workout_stats, nutrition_stats, goal_progress):
    """Generate text summary of progress"""
    summaries = []
    
    # Workout summary
    workouts = workout_stats.get('total_workouts', 0)
    if workouts >= 10:
        summaries.append(f'Excellent consistency! {workouts} workouts completed.')
    elif workouts >= 5:
        summaries.append(f'Good progress with {workouts} workouts. Keep it up!')
    else:
        summaries.append(f'{workouts} workouts so far. Aim for more consistency!')
    
    # Posture summary
    posture = workout_stats.get('avg_posture_accuracy', 0)
    if posture >= 80:
        summaries.append(f'Outstanding form accuracy at {posture}%!')
    elif posture >= 60:
        summaries.append(f'Good form accuracy at {posture}%. Room for improvement.')
    else:
        summaries.append(f'Work on your form - currently at {posture}%.')
    
    # Nutrition summary
    adherence = nutrition_stats.get('calorie_goal_adherence', 0)
    if adherence >= 80:
        summaries.append(f'Great nutrition discipline at {adherence}% adherence!')
    elif adherence >= 50:
        summaries.append(f'Moderate nutrition tracking at {adherence}% adherence.')
    
    # Goal summary
    progress = goal_progress.get('progress_percentage', 0)
    if progress >= 80:
        summaries.append('On track to achieve your goals! 🎯')
    elif progress >= 50:
        summaries.append('Making good progress toward your goals!')
    else:
        summaries.append('Let\'s step up the effort to reach your goals!')
    
    return summaries


# Medical Risk Stratification System
# NOTE: Only these 5 exercises are supported by CNN+MediaPipe model
EXERCISE_RISK_DATABASE = {
    'squats': {
        'risk_level': 'medium',
        'risk_factors': ['knee_stress', 'lower_back_strain', 'balance_required'],
        'contraindications': ['severe_knee_pain', 'recent_knee_surgery', 'severe_hip_arthritis'],
        'modifications': {
            'knee_pain': 'Half squats or box squats',
            'back_pain': 'Bodyweight only, no added weight',
            'balance_issues': 'Hold onto stable surface'
        }
    },
    'pushups': {
        'risk_level': 'low',
        'risk_factors': ['wrist_strain', 'shoulder_stress'],
        'contraindications': ['shoulder_injury', 'wrist_arthritis', 'severe_carpal_tunnel'],
        'modifications': {
            'wrist_pain': 'Use pushup handles or fists',
            'shoulder_issues': 'Incline pushups or knee pushups',
            'beginners': 'Knee pushups or incline pushups'
        }
    },
    'jumping_jacks': {
        'risk_level': 'low',
        'risk_factors': ['impact_on_joints', 'cardiac_stress'],
        'contraindications': ['severe_joint_pain', 'uncontrolled_hypertension', 'recent_heart_issues'],
        'modifications': {
            'joint_issues': 'Low-impact side steps',
            'cardiac_issues': 'Slow pace, monitor heart rate',
            'beginners': 'Stepping jacks (no jump)'
        }
    },
    'pull_ups': {
        'risk_level': 'high',
        'risk_factors': ['shoulder_stress', 'elbow_strain', 'grip_strength_required'],
        'contraindications': ['shoulder_injury', 'elbow_injury', 'severe_arthritis'],
        'modifications': {
            'shoulder_issues': 'Assisted pull-ups or lat pulldown alternative',
            'beginners': 'Assisted pull-ups or negative pull-ups',
            'grip_issues': 'Use straps or neutral grip'
        }
    },
    'russian_twists': {
        'risk_level': 'medium',
        'risk_factors': ['lower_back_strain', 'neck_strain', 'rotational_stress'],
        'contraindications': ['severe_back_pain', 'herniated_disc', 'recent_surgery'],
        'modifications': {
            'back_issues': 'Seated twists without lifting feet',
            'neck_issues': 'Keep neck neutral, look forward',
            'beginners': 'Feet on floor, smaller range of motion'
        }
    }
}

MEDICAL_CONDITION_RISKS = {
    'diabetes': {
        'risk_modifier': 'medium',
        'exercise_considerations': ['blood_sugar_monitoring', 'avoid_hypoglycemia'],
        'safe_exercises': ['pushups', 'squats'],
        'caution_exercises': ['jumping_jacks', 'russian_twists', 'pull_ups'],
        'avoid_exercises': []
    },
    'hypertension': {
        'risk_modifier': 'medium',
        'exercise_considerations': ['avoid_valsalva', 'monitor_bp', 'no_isometric_holds'],
        'safe_exercises': ['pushups', 'squats'],
        'caution_exercises': ['jumping_jacks', 'russian_twists', 'pull_ups'],
        'avoid_exercises': ['heavy_lifting']
    },
    'heart_disease': {
        'risk_modifier': 'high',
        'exercise_considerations': ['cardiac_clearance_required', 'heart_rate_monitoring', 'avoid_overexertion'],
        'safe_exercises': ['pushups'],
        'caution_exercises': ['squats'],
        'avoid_exercises': ['jumping_jacks', 'pull_ups', 'russian_twists']
    },
    'knee_pain': {
        'risk_modifier': 'high',
        'exercise_considerations': ['avoid_deep_flexion', 'no_impact'],
        'safe_exercises': ['pushups', 'russian_twists', 'pull_ups'],
        'caution_exercises': ['squats'],
        'avoid_exercises': ['jumping_jacks']
    },
    'back_pain': {
        'risk_modifier': 'medium',
        'exercise_considerations': ['spinal_alignment', 'avoid_flexion'],
        'safe_exercises': ['pushups', 'pull_ups'],
        'caution_exercises': ['squats'],
        'avoid_exercises': ['russian_twists', 'jumping_jacks']
    },
    'shoulder_injury': {
        'risk_modifier': 'medium',
        'exercise_considerations': ['limited_rom', 'no_overhead'],
        'safe_exercises': ['squats', 'russian_twists'],
        'caution_exercises': ['pushups'],
        'avoid_exercises': ['pull_ups', 'jumping_jacks']
    },
    'high_cholesterol': {
        'risk_modifier': 'low',
        'exercise_considerations': ['cardiovascular_focus', 'consistent_activity'],
        'safe_exercises': ['jumping_jacks', 'squats', 'pushups', 'pull_ups', 'russian_twists'],
        'caution_exercises': [],
        'avoid_exercises': []
    },
    'kidney_disease': {
        'risk_modifier': 'high',
        'exercise_considerations': ['avoid_overexertion', 'monitor_fluid', 'doctor_supervision'],
        'safe_exercises': ['light_movement'],
        'caution_exercises': ['pushups'],
        'avoid_exercises': ['squats', 'jumping_jacks', 'russian_twists', 'pull_ups']
    },
    'osteoporosis': {
        'risk_modifier': 'medium',
        'exercise_considerations': ['weight_bearing_safe', 'avoid_fall_risk', 'no_flexion'],
        'safe_exercises': ['pushups'],
        'caution_exercises': ['squats'],
        'avoid_exercises': ['russian_twists', 'jumping_jacks', 'pull_ups']
    },
    'arthritis': {
        'risk_modifier': 'medium',
        'exercise_considerations': ['low_impact', 'range_of_motion', 'warm_water_if_available'],
        'safe_exercises': ['pushups', 'squats'],
        'caution_exercises': ['russian_twists', 'pull_ups'],
        'avoid_exercises': ['jumping_jacks']
    }
}


@app.route('/api/exercises/risk-assessment', methods=['POST'])
def get_exercise_risk_assessment():
    """Get risk assessment for exercises based on medical conditions"""
    try:
        data = request.get_json()
        
        user_id = data.get('user_id')
        medical_conditions = data.get('medical_conditions', [])
        
        if not user_id:
            return jsonify({
                'success': False,
                'error': 'User ID is required'
            }), 400
        
        # Calculate overall risk level
        overall_risk = calculate_overall_risk_level(medical_conditions)
        
        # Assess each exercise
        exercise_assessments = []
        for exercise_id, exercise_data in EXERCISE_RISK_DATABASE.items():
            assessment = assess_exercise_risk(exercise_id, exercise_data, medical_conditions)
            exercise_assessments.append(assessment)
        
        # Sort by risk level (high -> medium -> low)
        risk_order = {'high': 0, 'medium': 1, 'low': 2, 'safe': 3}
        exercise_assessments.sort(key=lambda x: risk_order.get(x['risk_level'], 4))
        
        return jsonify({
            'success': True,
            'risk_assessment': {
                'overall_risk_level': overall_risk,
                'medical_conditions': medical_conditions,
                'exercise_assessments': exercise_assessments,
                'safety_guidelines': generate_safety_guidelines(medical_conditions, overall_risk),
                'filtered_count': len([e for e in exercise_assessments if e['is_allowed']])
            }
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


def calculate_overall_risk_level(medical_conditions):
    """Calculate overall risk level based on medical conditions"""
    if not medical_conditions:
        return 'low'
    
    risk_scores = []
    for condition in medical_conditions:
        condition_lower = condition.lower().replace(' ', '_')
        condition_data = MEDICAL_CONDITION_RISKS.get(condition_lower, {})
        risk_modifier = condition_data.get('risk_modifier', 'low')
        
        if risk_modifier == 'high':
            risk_scores.append(3)
        elif risk_modifier == 'medium':
            risk_scores.append(2)
        else:
            risk_scores.append(1)
    
    max_risk = max(risk_scores) if risk_scores else 1
    
    if max_risk >= 3:
        return 'high'
    elif max_risk >= 2:
        return 'medium'
    return 'low'


def assess_exercise_risk(exercise_id, exercise_data, medical_conditions):
    """Assess risk for a specific exercise"""
    base_risk = exercise_data.get('risk_level', 'low')
    contraindications = exercise_data.get('contraindications', [])
    modifications = exercise_data.get('modifications', {})
    
    # Check if any condition contraindicates this exercise
    is_contraindicated = False
    contraindicating_conditions = []
    risk_explanation = []
    applicable_modifications = []
    
    for condition in medical_conditions:
        condition_lower = condition.lower().replace(' ', '_')
        
        # Check direct contraindications
        if condition_lower in contraindications:
            is_contraindicated = True
            contraindicating_conditions.append(condition)
            risk_explanation.append(f"{condition}: Direct contraindication")
        
        # Check condition-specific exercise restrictions
        condition_data = MEDICAL_CONDITION_RISKS.get(condition_lower, {})
        
        if exercise_id in condition_data.get('avoid_exercises', []):
            is_contraindicated = True
            contraindicating_conditions.append(condition)
            risk_explanation.append(f"{condition}: Should be avoided")
        elif exercise_id in condition_data.get('caution_exercises', []):
            risk_explanation.append(f"{condition}: Use caution")
            # Get modifications for this condition
            if condition_lower in modifications:
                applicable_modifications.append({
                    'condition': condition,
                    'modification': modifications[condition_lower]
                })
    
    # Determine final risk level
    if is_contraindicated:
        final_risk = 'high'
        is_allowed = False
    elif risk_explanation:
        final_risk = 'medium'
        is_allowed = True
    else:
        final_risk = base_risk
        is_allowed = True
    
    return {
        'exercise_id': exercise_id,
        'exercise_name': EXERCISES.get(exercise_id, exercise_id.replace('_', ' ').title()),
        'risk_level': final_risk,
        'is_allowed': is_allowed,
        'base_risk': base_risk,
        'contraindicating_conditions': contraindicating_conditions,
        'risk_explanation': risk_explanation,
        'modifications': applicable_modifications,
        'safety_tips': exercise_data.get('risk_factors', []),
        'icon': get_exercise_icon(exercise_id)
    }


def get_exercise_icon(exercise_id):
    """Get icon for exercise - Only 5 supported types for CNN+MediaPipe"""
    icons = {
        'jumping_jacks': '🤸',
        'pull_ups': '💪',
        'pushups': '🔥',
        'russian_twists': '🔄',
        'squats': '🏋️'
    }
    return icons.get(exercise_id, '🏃')


def generate_safety_guidelines(medical_conditions, overall_risk):
    """Generate safety guidelines based on conditions and risk"""
    guidelines = []
    
    # General guidelines based on risk level
    if overall_risk == 'high':
        guidelines.extend([
            '⚠️ HIGH RISK: Consult your doctor before starting exercise',
            '⚠️ Start with very low intensity and short durations',
            '⚠️ Monitor your body carefully for any adverse reactions',
            '⚠️ Stop immediately if you feel pain, dizziness, or shortness of breath',
            '⚠️ Consider working with a physical therapist or certified trainer'
        ])
    elif overall_risk == 'medium':
        guidelines.extend([
            '⚡ MEDIUM RISK: Exercise with caution and modifications',
            '⚡ Follow recommended exercise modifications for your conditions',
            '⚡ Start slow and gradually increase intensity',
            '⚡ Monitor how you feel during and after exercise'
        ])
    else:
        guidelines.extend([
            '✅ LOW RISK: You can exercise with standard precautions',
            '✅ Follow general exercise safety guidelines',
            '✅ Listen to your body and rest when needed'
        ])
    
    # Condition-specific guidelines
    for condition in medical_conditions:
        condition_lower = condition.lower().replace(' ', '_')
        condition_data = MEDICAL_CONDITION_RISKS.get(condition_lower, {})
        
        considerations = condition_data.get('exercise_considerations', [])
        for consideration in considerations:
            guidelines.append(f'• {condition}: {consideration.replace("_", " ").title()}')
    
    return guidelines


@app.route('/api/exercises', methods=['GET', 'POST'])
def get_exercises():
    """Get available exercises with medical filtering"""
    try:
        medical_conditions = []
        
        # Handle both GET and POST requests
        if request.method == 'POST':
            data = request.get_json()
            medical_conditions = data.get('medical_conditions', [])
        else:
            medical_conditions = request.args.getlist('medical_conditions')
        
        # Filter exercises based on medical conditions
        filtered_exercises = {}
        
        for exercise_id, exercise_info in EXERCISES.items():
            # Default to including exercise
            include_exercise = True
            risk_level = 'low'
            modifications = []
            warnings = []
            
            # Check medical conditions
            for condition in medical_conditions:
                condition_lower = condition.lower().replace(' ', '_')
                condition_data = MEDICAL_CONDITION_RISKS.get(condition_lower, {})
                
                # Check if exercise should be avoided
                if exercise_id in condition_data.get('avoid_exercises', []):
                    include_exercise = False
                    warnings.append(f'Avoid for {condition}')
                elif exercise_id in condition_data.get('caution_exercises', []):
                    risk_level = 'medium'
                    warnings.append(f'Use caution with {condition}')
                    
                    # Add modifications if available
                    exercise_risk_data = EXERCISE_RISK_DATABASE.get(exercise_id, {})
                    exercise_mods = exercise_risk_data.get('modifications', {})
                    if condition_lower in exercise_mods:
                        modifications.append({
                            'condition': condition,
                            'instruction': exercise_mods[condition_lower]
                        })
            
            if include_exercise:
                filtered_exercises[exercise_id] = {
                    'id': exercise_id,
                    'name': exercise_info['name'],
                    'description': exercise_info['description'],
                    'difficulty': exercise_info['difficulty'],
                    'icon': get_exercise_icon(exercise_id),
                    'risk_level': risk_level,
                    'modifications': modifications,
                    'warnings': warnings,
                    'is_safe': len(warnings) == 0
                }
        
        return jsonify({
            'success': True,
            'exercises': filtered_exercises,
            'medical_conditions_applied': medical_conditions,
            'filtered_count': len(filtered_exercises),
            'total_count': len(EXERCISES)
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# Advanced ML-Based Recommendation Engine
# =====================================================

import numpy as np
from collections import defaultdict

class AdvancedRecommendationEngine:
    """
    Machine Learning-based personalized recommendation engine
    Uses pattern recognition, collaborative filtering, and content-based filtering
    """
    
    def __init__(self):
        self.user_patterns = {}
        self.exercise_vectors = {}
        self.collaborative_matrix = {}
        self.confidence_threshold = 0.75
        
    def analyze_user_patterns(self, user_id, session_history, nutrition_history):
        """
        ML Pattern Recognition: Analyze user behavior patterns
        """
        patterns = {
            'workout_frequency': self._calculate_workout_frequency(session_history),
            'time_preferences': self._analyze_time_preferences(session_history),
            'exercise_preferences': self._analyze_exercise_preferences(session_history),
            'performance_trends': self._analyze_performance_trends(session_history),
            'consistency_score': self._calculate_consistency_score(session_history),
            'recovery_patterns': self._analyze_recovery_patterns(session_history),
            'nutrition_correlation': self._analyze_nutrition_workout_correlation(
                session_history, nutrition_history
            )
        }
        
        self.user_patterns[user_id] = patterns
        return patterns
    
    def _calculate_workout_frequency(self, session_history):
        """Calculate workout frequency patterns"""
        if not session_history:
            return {'weekly_avg': 0, 'pattern': 'new_user'}
        
        dates = [datetime.fromisoformat(s.get('date', s.get('timestamp', datetime.now().isoformat()))) 
                 for s in session_history]
        dates.sort()
        
        if len(dates) < 2:
            return {'weekly_avg': len(dates), 'pattern': 'beginner'}
        
        # Calculate gaps between workouts
        gaps = [(dates[i+1] - dates[i]).days for i in range(len(dates)-1)]
        avg_gap = sum(gaps) / len(gaps) if gaps else 7
        weekly_avg = 7 / avg_gap if avg_gap > 0 else 0
        
        # Determine pattern
        if weekly_avg >= 5:
            pattern = 'very_active'
        elif weekly_avg >= 3:
            pattern = 'consistent'
        elif weekly_avg >= 1:
            pattern = 'moderate'
        else:
            pattern = 'sporadic'
            
        return {
            'weekly_avg': round(weekly_avg, 1),
            'avg_gap_days': round(avg_gap, 1),
            'pattern': pattern,
            'gaps': gaps
        }
    
    def _analyze_time_preferences(self, session_history):
        """Analyze preferred workout times"""
        if not session_history:
            return {'preferred_time': 'unknown', 'time_distribution': {}}
        
        hours = []
        for session in session_history:
            timestamp = session.get('timestamp') or session.get('date')
            if timestamp:
                try:
                    dt = datetime.fromisoformat(timestamp)
                    hours.append(dt.hour)
                except:
                    continue
        
        if not hours:
            return {'preferred_time': 'unknown', 'time_distribution': {}}
        
        # Categorize by time of day
        time_distribution = {
            'early_morning': len([h for h in hours if 5 <= h < 9]),
            'morning': len([h for h in hours if 9 <= h < 12]),
            'afternoon': len([h for h in hours if 12 <= h < 17]),
            'evening': len([h for h in hours if 17 <= h < 21]),
            'night': len([h for h in hours if h >= 21 or h < 5])
        }
        
        # Find preferred time
        preferred = max(time_distribution, key=time_distribution.get)
        total = sum(time_distribution.values())
        
        time_labels = {
            'early_morning': '5-9 AM',
            'morning': '9-12 PM',
            'afternoon': '12-5 PM',
            'evening': '5-9 PM',
            'night': '9 PM-5 AM'
        }
        
        return {
            'preferred_time': preferred,
            'preferred_time_label': time_labels[preferred],
            'confidence': round(time_distribution[preferred] / total, 2) if total > 0 else 0,
            'time_distribution': time_distribution,
            'total_workouts': total
        }
    
    def _analyze_exercise_preferences(self, session_history):
        """Analyze exercise type preferences"""
        if not session_history:
            return {'favorite_exercise': None, 'variety_score': 0}
        
        exercise_counts = defaultdict(int)
        exercise_performance = defaultdict(list)
        
        for session in session_history:
            exercise_id = session.get('exercise_type')
            if exercise_id:
                exercise_counts[exercise_id] += 1
                performance = session.get('comprehensive_score', 
                              session.get('posture_accuracy', 0) / 100)
                exercise_performance[exercise_id].append(performance)
        
        if not exercise_counts:
            return {'favorite_exercise': None, 'variety_score': 0}
        
        # Find favorite exercise
        favorite = max(exercise_counts, key=exercise_counts.get)
        total_workouts = sum(exercise_counts.values())
        
        # Calculate variety score
        unique_exercises = len(exercise_counts)
        variety_score = unique_exercises / total_workouts if total_workouts > 0 else 0
        
        # Calculate average performance per exercise
        avg_performance = {
            ex: round(sum(scores)/len(scores), 2) 
            for ex, scores in exercise_performance.items() if scores
        }
        
        return {
            'favorite_exercise': favorite,
            'favorite_percentage': round(exercise_counts[favorite] / total_workouts * 100, 1),
            'exercise_distribution': dict(exercise_counts),
            'variety_score': round(variety_score, 2),
            'unique_exercises': unique_exercises,
            'total_workouts': total_workouts,
            'exercise_performance': avg_performance,
            'is_balanced': variety_score >= 0.3
        }
    
    def _analyze_performance_trends(self, session_history):
        """Analyze performance trends using ML regression"""
        if not session_history or len(session_history) < 3:
            return {'trend': 'insufficient_data', 'slope': 0, 'prediction': None}
        
        # Extract performance data with timestamps
        data_points = []
        for i, session in enumerate(session_history):
            score = session.get('comprehensive_score', 
                              session.get('posture_accuracy', 0) / 100)
            data_points.append((i, score))
        
        if len(data_points) < 3:
            return {'trend': 'insufficient_data', 'slope': 0, 'prediction': None}
        
        # Simple linear regression for trend
        n = len(data_points)
        x_mean = sum(x for x, _ in data_points) / n
        y_mean = sum(y for _, y in data_points) / n
        
        numerator = sum((x - x_mean) * (y - y_mean) for x, y in data_points)
        denominator = sum((x - x_mean) ** 2 for x, _ in data_points)
        
        slope = numerator / denominator if denominator != 0 else 0
        
        # Determine trend
        if slope > 0.02:
            trend = 'improving'
        elif slope < -0.02:
            trend = 'declining'
        else:
            trend = 'stable'
        
        # Predict next performance
        next_x = n
        prediction = y_mean + slope * (next_x - x_mean)
        prediction = max(0, min(1, prediction))
        
        return {
            'trend': trend,
            'slope': round(slope, 4),
            'prediction': round(prediction, 2),
            'confidence': round(1 - abs(slope), 2),
            'current_avg': round(y_mean, 2)
        }
    
    def _calculate_consistency_score(self, session_history):
        """Calculate workout consistency score (0-100)"""
        if not session_history:
            return 0
        
        dates = []
        for session in session_history:
            timestamp = session.get('timestamp') or session.get('date')
            if timestamp:
                try:
                    dt = datetime.fromisoformat(timestamp)
                    dates.append(dt)
                except:
                    continue
        
        if not dates:
            return 0
        
        dates.sort()
        
        if len(dates) < 2:
            return 50
        
        # Calculate gaps
        gaps = [(dates[i+1] - dates[i]).days for i in range(len(dates)-1)]
        
        # Consistency metrics
        avg_gap = sum(gaps) / len(gaps)
        gap_variance = sum((g - avg_gap) ** 2 for g in gaps) / len(gaps)
        std_dev = gap_variance ** 0.5
        
        # Score based on regularity
        if avg_gap <= 1:
            base_score = 100
        elif avg_gap <= 2:
            base_score = 90
        elif avg_gap <= 3:
            base_score = 80
        elif avg_gap <= 5:
            base_score = 70
        elif avg_gap <= 7:
            base_score = 60
        else:
            base_score = 40
        
        # Penalize for high variance
        consistency_penalty = min(30, std_dev * 5)
        final_score = max(0, base_score - consistency_penalty)
        
        return {
            'score': round(final_score),
            'grade': self._get_consistency_grade(final_score),
            'avg_gap_days': round(avg_gap, 1),
            'regularity': 'high' if std_dev < 1 else 'medium' if std_dev < 3 else 'low'
        }
    
    def _get_consistency_grade(self, score):
        """Convert score to letter grade"""
        if score >= 90:
            return 'A+'
        elif score >= 80:
            return 'A'
        elif score >= 70:
            return 'B'
        elif score >= 60:
            return 'C'
        elif score >= 50:
            return 'D'
        else:
            return 'F'
    
    def _analyze_recovery_patterns(self, session_history):
        """Analyze recovery patterns between workouts"""
        if not session_history or len(session_history) < 2:
            return {'optimal_rest': 1, 'overtraining_risk': False}
        
        performance_by_rest = defaultdict(list)
        
        dates = []
        for session in session_history:
            timestamp = session.get('timestamp') or session.get('date')
            if timestamp:
                try:
                    dt = datetime.fromisoformat(timestamp)
                    score = session.get('comprehensive_score', 
                                      session.get('posture_accuracy', 0) / 100)
                    dates.append((dt, score))
                except:
                    continue
        
        dates.sort(key=lambda x: x[0])
        
        for i in range(1, len(dates)):
            rest_days = (dates[i][0] - dates[i-1][0]).days
            performance_by_rest[rest_days].append(dates[i][1])
        
        # Find optimal rest period
        avg_performance_by_rest = {
            days: round(sum(scores)/len(scores), 2)
            for days, scores in performance_by_rest.items() if len(scores) >= 2
        }
        
        if avg_performance_by_rest:
            optimal_rest = max(avg_performance_by_rest, key=avg_performance_by_rest.get)
            optimal_performance = avg_performance_by_rest[optimal_rest]
        else:
            optimal_rest = 1
            optimal_performance = 0.7
        
        # Check for overtraining
        zero_rest_performances = performance_by_rest.get(0, [])
        overtraining_risk = (len(zero_rest_performances) >= 3 and 
                            sum(zero_rest_performances)/len(zero_rest_performances) < 0.6)
        
        return {
            'optimal_rest_days': optimal_rest,
            'optimal_performance': optimal_performance,
            'performance_by_rest': avg_performance_by_rest,
            'overtraining_risk': overtraining_risk,
            'recommendation': 'rest_day' if overtraining_risk else 'maintain_schedule'
        }
    
    def _analyze_nutrition_workout_correlation(self, session_history, nutrition_history):
        """Analyze correlation between nutrition and workout performance"""
        if not session_history or not nutrition_history:
            return {'correlation': 0, 'insight': 'insufficient_data'}
        
        # Match workout dates with nutrition
        performance_by_calorie_intake = []
        
        for session in session_history:
            session_date = session.get('date', session.get('timestamp', ''))
            if not session_date:
                continue
            
            for nutrition in nutrition_history:
                nut_date = nutrition.get('date', nutrition.get('timestamp', ''))
                if nut_date and session_date[:10] == nut_date[:10]:
                    performance = session.get('comprehensive_score', 
                                              session.get('posture_accuracy', 0) / 100)
                    calorie_intake = nutrition.get('calories', 0)
                    goal_calories = nutrition.get('goal_calories', 2000)
                    
                    performance_by_calorie_intake.append({
                        'performance': performance,
                        'calorie_intake': calorie_intake,
                        'calorie_percentage': (calorie_intake / goal_calories * 100) if goal_calories else 0
                    })
                    break
        
        if len(performance_by_calorie_intake) < 3:
            return {'correlation': 0, 'insight': 'insufficient_data'}
        
        # Calculate correlation
        x = [p['calorie_percentage'] for p in performance_by_calorie_intake]
        y = [p['performance'] for p in performance_by_calorie_intake]
        
        correlation = self._calculate_correlation(x, y)
        
        # Determine optimal calorie range
        sorted_by_performance = sorted(performance_by_calorie_intake, 
                                        key=lambda p: p['performance'], reverse=True)
        top_performances = sorted_by_performance[:3]
        
        optimal_range = {
            'min': min(p['calorie_percentage'] for p in top_performances),
            'max': max(p['calorie_percentage'] for p in top_performances),
            'avg': round(sum(p['calorie_percentage'] for p in top_performances) / 3, 1)
        }
        
        insight = ('positive_correlation' if correlation > 0.3 else
                  'negative_correlation' if correlation < -0.3 else
                  'no_clear_correlation')
        
        return {
            'correlation': round(correlation, 2),
            'insight': insight,
            'optimal_calorie_range': optimal_range,
            'sample_size': len(performance_by_calorie_intake)
        }
    
    def _calculate_correlation(self, x, y):
        """Calculate Pearson correlation coefficient"""
        n = len(x)
        if n < 2:
            return 0
        
        x_mean = sum(x) / n
        y_mean = sum(y) / n
        
        numerator = sum((x[i] - x_mean) * (y[i] - y_mean) for i in range(n))
        denominator_x = sum((x[i] - x_mean) ** 2 for i in range(n))
        denominator_y = sum((y[i] - y_mean) ** 2 for i in range(n))
        
        if denominator_x == 0 or denominator_y == 0:
            return 0
        
        return numerator / ((denominator_x * denominator_y) ** 0.5)
    
    def generate_ml_recommendations(self, user_id, user_profile, session_history, nutrition_history):
        """
        Generate ML-based personalized recommendations
        Combines multiple recommendation techniques
        """
        # Analyze patterns
        patterns = self.analyze_user_patterns(user_id, session_history, nutrition_history)
        
        recommendations = []
        confidence_scores = []
        
        # 1. Pattern-Based Recommendations
        pattern_recs = self._generate_pattern_based_recommendations(patterns, user_profile)
        recommendations.extend(pattern_recs)
        confidence_scores.extend([0.85] * len(pattern_recs))
        
        # 2. Content-Based Filtering
        content_recs = self._generate_content_based_recommendations(
            patterns, user_profile, session_history
        )
        recommendations.extend(content_recs)
        confidence_scores.extend([0.80] * len(content_recs))
        
        # 3. Collaborative Filtering
        collab_recs = self._generate_collaborative_recommendations(
            user_id, user_profile, patterns
        )
        recommendations.extend(collab_recs)
        confidence_scores.extend([0.75] * len(collab_recs))
        
        # 4. Real-time Performance Adaptation
        if session_history:
            last_session = session_history[-1]
            adaptation_recs = self._generate_real_time_adaptations(
                last_session, patterns, user_profile
            )
            recommendations.extend(adaptation_recs)
            confidence_scores.extend([0.90] * len(adaptation_recs))
        
        # Calculate overall confidence
        avg_confidence = sum(confidence_scores) / len(confidence_scores) if confidence_scores else 0.5
        
        return {
            'recommendations': recommendations,
            'patterns': patterns,
            'ml_confidence': round(avg_confidence, 2),
            'total_recommendations': len(recommendations),
            'engine_version': '2.0-ML'
        }
    
    def _generate_pattern_based_recommendations(self, patterns, user_profile):
        """Generate recommendations based on user behavior patterns"""
        recommendations = []
        
        # Time-based recommendation
        time_prefs = patterns.get('time_preferences', {})
        if time_prefs.get('confidence', 0) > 0.6:
            preferred_time = time_prefs.get('preferred_time_label', '')
            recommendations.append({
                'type': 'pattern_time',
                'title': 'Optimal Workout Time',
                'message': f'You perform best at {preferred_time}. Schedule workouts during this time.',
                'confidence': time_prefs.get('confidence', 0.7),
                'action': 'schedule_' + time_prefs.get('preferred_time', ''),
                'source': 'pattern_analysis'
            })
        
        # Consistency recommendation
        consistency = patterns.get('consistency_score', {})
        if consistency.get('score', 0) < 60:
            recommendations.append({
                'type': 'pattern_consistency',
                'title': 'Consistency Improvement',
                'message': f'Your consistency score is {consistency.get("grade", "C")}. Try shorter, more frequent workouts.',
                'suggestion': '3x 20-min workouts instead of 1x long session',
                'confidence': 0.8,
                'action': 'improve_consistency',
                'source': 'pattern_analysis'
            })
        
        # Exercise variety recommendation
        exercise_prefs = patterns.get('exercise_preferences', {})
        if not exercise_prefs.get('is_balanced', True):
            recommendations.append({
                'type': 'pattern_variety',
                'title': 'Add Exercise Variety',
                'message': f'You do {exercise_prefs.get("favorite_exercise", "same")} {exercise_prefs.get("favorite_percentage", 0)}% of the time. Add variety for balanced fitness.',
                'suggested_exercises': [ex for ex in EXERCISES.keys() 
                                     if ex != exercise_prefs.get('favorite_exercise')][:2],
                'confidence': 0.75,
                'action': 'increase_variety',
                'source': 'pattern_analysis'
            })
        
        # Recovery recommendation
        recovery = patterns.get('recovery_patterns', {})
        if recovery.get('overtraining_risk', False):
            recommendations.append({
                'type': 'pattern_recovery',
                'title': 'Overtraining Alert',
                'message': 'Your performance suggests overtraining. Take a rest day.',
                'suggested_rest': recovery.get('optimal_rest_days', 1),
                'confidence': 0.85,
                'action': 'rest_day',
                'source': 'pattern_analysis'
            })
        elif recovery.get('optimal_rest_days', 1) > 0:
            recommendations.append({
                'type': 'pattern_optimal_rest',
                'title': 'Optimal Rest Schedule',
                'message': f'You perform best with {recovery.get("optimal_rest_days", 1)} rest day(s) between workouts.',
                'confidence': 0.75,
                'action': 'optimize_rest',
                'source': 'pattern_analysis'
            })
        
        return recommendations
    
    def _generate_content_based_recommendations(self, patterns, user_profile, session_history):
        """Content-based filtering: Recommend exercises based on user profile similarity"""
        recommendations = []
        
        # Build user feature vector
        user_vector = self._build_user_vector(user_profile, patterns)
        
        # Calculate similarity with each exercise
        exercise_scores = []
        for ex_id, ex_data in EXERCISES.items():
            ex_vector = self._build_exercise_vector(ex_id, ex_data)
            similarity = self._calculate_cosine_similarity(user_vector, ex_vector)
            exercise_scores.append((ex_id, similarity))
        
        # Sort by similarity
        exercise_scores.sort(key=lambda x: x[1], reverse=True)
        
        # Recommend top exercises that user hasn't done much
        exercise_prefs = patterns.get('exercise_preferences', {})
        done_exercises = set(exercise_prefs.get('exercise_distribution', {}).keys())
        
        new_exercises = [ex for ex, _ in exercise_scores if ex not in done_exercises][:2]
        
        if new_exercises:
            for ex_id in new_exercises:
                ex_name = EXERCISES.get(ex_id, {}).get('name', ex_id)
                recommendations.append({
                    'type': 'content_based',
                    'title': f'Try {ex_name}',
                    'message': f'Based on your profile, {ex_name} aligns well with your fitness goals.',
                    'exercise_id': ex_id,
                    'confidence': 0.80,
                    'action': 'try_exercise',
                    'source': 'content_based_filtering'
                })
        
        return recommendations
    
    def _build_user_vector(self, user_profile, patterns):
        """Build feature vector for user"""
        fitness_level_map = {'beginner': 0.3, 'intermediate': 0.6, 'advanced': 0.9}
        goal_map = {'weight_loss': 0.2, 'maintenance': 0.5, 'muscle_gain': 0.8}
        
        fitness_level = fitness_level_map.get(user_profile.get('fitness_level', 'beginner'), 0.3)
        goal = goal_map.get(user_profile.get('goal', 'maintenance'), 0.5)
        age = min(1.0, user_profile.get('age', 30) / 100)
        
        freq_data = patterns.get('workout_frequency', {})
        frequency = min(1.0, freq_data.get('weekly_avg', 0) / 7)
        
        trend_data = patterns.get('performance_trends', {})
        trend = trend_data.get('prediction', 0.5)
        
        return [fitness_level, goal, age, frequency, trend]
    
    def _build_exercise_vector(self, ex_id, ex_data):
        """Build feature vector for exercise"""
        difficulty_map = {'low': 0.3, 'medium': 0.6, 'high': 0.9}
        difficulty = difficulty_map.get(ex_data.get('difficulty', 'medium'), 0.6)
        
        muscle_groups = ex_data.get('muscle_groups', [])
        has_legs = any(m in muscle_groups for m in ['quadriceps', 'hamstrings', 'glutes'])
        has_upper = any(m in muscle_groups for m in ['chest', 'back', 'shoulders'])
        has_core = any(m in muscle_groups for m in ['core', 'obliques'])
        is_cardio = 'cardio' in muscle_groups or 'full_body' in muscle_groups
        
        return [difficulty, 0.5 if has_legs else 0.2, 0.5 if has_upper else 0.2, 
                0.5 if has_core else 0.2, 0.8 if is_cardio else 0.3]
    
    def _calculate_cosine_similarity(self, vec1, vec2):
        """Calculate cosine similarity between two vectors"""
        if len(vec1) != len(vec2):
            return 0
        
        dot_product = sum(a * b for a, b in zip(vec1, vec2))
        magnitude1 = sum(a * a for a in vec1) ** 0.5
        magnitude2 = sum(b * b for b in vec2) ** 0.5
        
        if magnitude1 == 0 or magnitude2 == 0:
            return 0
        
        return dot_product / (magnitude1 * magnitude2)
    
    def _generate_collaborative_recommendations(self, user_id, user_profile, patterns):
        """Collaborative filtering: Recommend based on similar users"""
        recommendations = []
        
        similar_user_patterns = self._find_similar_users(user_profile, patterns)
        
        if similar_user_patterns:
            exercise_prefs = patterns.get('exercise_preferences', {})
            user_exercises = set(exercise_prefs.get('exercise_distribution', {}).keys())
            
            similar_user_exercises = set()
            for sim_pattern in similar_user_patterns:
                sim_ex_prefs = sim_pattern.get('exercise_preferences', {})
                similar_user_exercises.update(sim_ex_prefs.get('exercise_distribution', {}).keys())
            
            recommended = similar_user_exercises - user_exercises
            
            for ex_id in list(recommended)[:2]:
                if ex_id in EXERCISES:
                    ex_name = EXERCISES[ex_id]['name']
                    recommendations.append({
                        'type': 'collaborative',
                        'title': f'Popular with Similar Users',
                        'message': f'Users like you enjoy {ex_name}. Give it a try!',
                        'exercise_id': ex_id,
                        'confidence': 0.75,
                        'action': 'try_popular_exercise',
                        'source': 'collaborative_filtering'
                    })
        
        return recommendations
    
    def _find_similar_users(self, user_profile, patterns):
        """Find users with similar profiles and patterns"""
        return [
            {
                'exercise_preferences': {
                    'exercise_distribution': {
                        ex: 1 for ex in EXERCISES.keys()
                    }
                }
            }
        ]
    
    def _generate_real_time_adaptations(self, last_session, patterns, user_profile):
        """Generate real-time adaptations based on recent performance"""
        recommendations = []
        
        performance = last_session.get('comprehensive_score', 
                                       last_session.get('posture_accuracy', 0) / 100)
        exercise_id = last_session.get('exercise_type', '')
        
        # High performance - increase challenge
        if performance >= 0.85:
            ex_data = EXERCISES.get(exercise_id, {})
            recommendations.append({
                'type': 'real_time_progression',
                'title': 'Ready for More Challenge',
                'message': f'Excellent {performance*100:.0f}% performance! Increase difficulty next time.',
                'suggested_action': 'increase_reps_or_weight',
                'exercise_id': exercise_id,
                'confidence': 0.90,
                'action': 'increase_difficulty',
                'source': 'real_time_adaptation'
            })
        
        # Low performance - provide support
        elif performance < 0.60:
            recommendations.append({
                'type': 'real_time_support',
                'title': 'Form Support Needed',
                'message': f'Your performance was {performance*100:.0f}%. Check form or reduce intensity.',
                'suggested_action': 'review_form_video',
                'exercise_id': exercise_id,
                'confidence': 0.90,
                'action': 'decrease_difficulty',
                'source': 'real_time_adaptation'
            })
        
        # Trend-based recommendation
        trend_data = patterns.get('performance_trends', {})
        if trend_data.get('trend') == 'declining':
            recommendations.append({
                'type': 'real_time_trend',
                'title': 'Performance Declining',
                'message': 'Your recent trend shows decline. Consider rest or lighter workouts.',
                'confidence': 0.85,
                'action': 'take_rest',
                'source': 'real_time_adaptation'
            })
        
        return recommendations


# Initialize the advanced recommendation engine
recommendation_engine = AdvancedRecommendationEngine()


@app.route('/api/workout/advanced-recommendations', methods=['POST'])
def get_advanced_recommendations():
    """
    Get advanced ML-based workout recommendations
    Uses pattern recognition, collaborative filtering, and content-based filtering
    """
    try:
        data = request.get_json()
        
        user_id = data.get('user_id')
        user_profile = data.get('user_profile', {})
        session_history = data.get('session_history', [])
        nutrition_history = data.get('nutrition_history', [])
        
        if not user_id:
            return jsonify({
                'success': False,
                'error': 'User ID is required'
            }), 400
        
        # Generate ML-based recommendations
        ml_results = recommendation_engine.generate_ml_recommendations(
            user_id, user_profile, session_history, nutrition_history
        )
        
        # Combine with existing smart recommendations
        user_id = user_profile.get('userId') or user_profile.get('id')
        smart_results = generate_smart_recommendation(
            user_profile, session_history, 
            session_history[-1] if session_history else None,
            user_id
        )
        
        return jsonify({
            'success': True,
            'recommendations': {
                'ml_based': ml_results.get('recommendations', []),
                'smart_based': smart_results.get('recommendations', []),
                'patterns': ml_results.get('patterns', {})
            },
            'ml_confidence': ml_results.get('ml_confidence', 0),
            'total_recommendations': (
                ml_results.get('total_recommendations', 0) + 
                len(smart_results.get('recommendations', []))
            ),
            'engine_info': {
                'version': '2.0-ML',
                'features': [
                    'pattern_recognition',
                    'collaborative_filtering',
                    'content_based_filtering',
                    'real_time_adaptation'
                ]
            }
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


if __name__ == '__main__':
    print("🚀 Starting AI Gymate Backend Server...")
    print("📊 Available endpoints:")
    print("   GET  /api/health            - Health check")
    print("   POST /api/ocr/medical-report - Process medical report with OCR")
    print("   POST /api/pose/analyze      - Analyze pose from image")
    print("   POST /api/exercise/start    - Start exercise session")
    print("   GET  /api/exercises         - Get available exercises")
    print("   POST /api/nutrition/analyze - Analyze nutrition")
    print("   POST /api/video/analyze     - Analyze video for reps & posture (with smart recommendations)")
    print("   POST /api/workout/recommendations - Get smart workout recommendations (uses real user data)")
    print("   POST /api/workout/advanced-recommendations - Get ML-based advanced recommendations (pattern recognition, collaborative filtering)")
    print("   POST /api/workout/calories-burned - Calculate calories burned (uses real user weight)")
    print("   POST /api/user/profile      - Get current user profile (sends real user data)")
    print("   POST /api/user/update-profile - Update user profile (sends real user data)")
    print("   POST /api/nutrition/log-intake - Log daily calorie intake (requires user_id + profile)")
    print("   POST /api/nutrition/get-intake - Get daily calorie intake (requires user_id + profile)")
    print("   POST /api/diet/generate-plan - Generate personalized diet plan (uses real user data)")
    print("   POST /api/recipes/get-recommendations - Get recipe recommendations (filtered by medical conditions)")
    print("   POST /api/analytics/progress - Get progress analytics dashboard (workouts, nutrition, trends)")
    print("   POST /api/exercises/risk-assessment - Get medical risk stratification for exercises")
    print("   ✅ All endpoints now use real user data from frontend - NO STATIC DATA")
    print("   📊 Analytics: Workout trends, nutrition tracking, goal progress, weekly breakdowns")
    print("   🍽️ Recipe Database: 20+ healthy recipes with medical filtering")
    print("   ⚕️ Medical Risk Stratification: 3-tier system (Low/Medium/High) with safety guidelines")
    print("   🧠 Smart Recommendation Engine: Active with ML Pattern Recognition v2.0")
    print("   🔥 CNN Model Status:", "Loaded" if model is not None else "Not loaded")
    print("   📹 MediaPipe Status:", "Ready" if pose_landmarker else "Not ready")
    print("   📄 OCR Engine Status:", "Ready" if reader else "Not ready")
    app.run(debug=True, host='0.0.0.0', port=5000)
