from flask import Flask, request, jsonify
from flask_cors import CORS
import sqlite3
from werkzeug.security import generate_password_hash, check_password_hash
from datetime import datetime

app = Flask(__name__)
CORS(app)

DB_NAME = "database.db"

# ---------- NUTRITION DATA (RULE-BASED) ----------
# Simple hardcoded dictionary for academic demo
NUTRITION_DATA = {
    "egg": {"calories": 70, "protein": 6, "carbs": 0.6, "fats": 5},
    "rice": {"calories": 130, "protein": 2.7, "carbs": 28, "fats": 0.3},
    "chicken": {"calories": 165, "protein": 31, "carbs": 0, "fats": 3.6},
    "bread": {"calories": 80, "protein": 2.5, "carbs": 15, "fats": 1},
    "milk": {"calories": 103, "protein": 8, "carbs": 12, "fats": 2.4},
    "banana": {"calories": 105, "protein": 1.3, "carbs": 27, "fats": 0.3},
    "apple": {"calories": 95, "protein": 0.5, "carbs": 25, "fats": 0.3},
}

DEFAULT_NUTRITION = {"calories": 50, "protein": 1, "carbs": 5, "fats": 1}

def estimate_nutrition(meal_text):
    """
    Splits the meal string and estimates nutrition based on keywords.
    Returns: dict with total calories, protein, carbs, fats
    """
    total = {"calories": 0, "protein": 0, "carbs": 0, "fats": 0}
    words = meal_text.lower().split()
    
    for word in words:
        # Check if word matches a known food item
        # We do simple substring matching or direct lookup
        found = False
        nutrition = DEFAULT_NUTRITION # Default for unknown words that might be food
        
        # Check explicit match first
        if word in NUTRITION_DATA:
            nutrition = NUTRITION_DATA[word]
            found = True
        else:
            # Check singular/plural or contains
            for food_key, values in NUTRITION_DATA.items():
                if food_key in word:
                    nutrition = values
                    found = True
                    break
        
        # If we want to only count "food-like" words, this is hard without NLP.
        # For this demo, we assume the user types mostly food words.
        # To be cleaner, we might only add if we found a match? 
        # But requirements say "Unknown foods should return a default estimate".
        # So we add default for every word that isn't a known stop word? 
        # Let's keep it simple: Add values for matched words, 
        # plus a default for words that don't match but aren't common fillers (like "and", "with").
        
        IGNORE_WORDS = {"and", "with", "a", "an", "the", "bowl", "of", "cup", "plate"}
        if word not in IGNORE_WORDS:
             total["calories"] += nutrition["calories"]
             total["protein"] += nutrition["protein"]
             total["carbs"] += nutrition["carbs"]
             total["fats"] += nutrition["fats"]

    return total


# ---------- DATABASE CONNECTION ----------
def get_db():
    conn = sqlite3.connect(DB_NAME)
    conn.row_factory = sqlite3.Row
    return conn


# ---------- INIT TABLE ----------
def init_db():
    conn = get_db()
    conn.execute("""
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        password TEXT NOT NULL
    )
    """)
    # 🔥 WORKOUT TABLE (ADD THIS)
    conn.execute("""
    CREATE TABLE IF NOT EXISTS workouts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_email TEXT,
        exercise TEXT,
        reps INTEGER,
        calories REAL,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
    )
    """)

    # 🔥 MEALS TABLE (ADD THIS)
    conn.execute("""
    CREATE TABLE IF NOT EXISTS meals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_email TEXT,
        meal_name TEXT,
        calories REAL,
        protein REAL,
        carbs REAL,
        fats REAL,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
    )
    """)
  

    conn.commit()
    conn.close()


# ---------- SIGN UP ----------
@app.route("/signup", methods=["POST"])
def signup():
    data = request.json
    name = data.get("name")
    email = data.get("email")
    password = data.get("password")

    if not name or not email or not password:
        return jsonify({"error": "Missing fields"}), 400

    hashed_password = generate_password_hash(password)

    try:
        conn = get_db()
        conn.execute(
            "INSERT INTO users (name, email, password) VALUES (?, ?, ?)",
            (name, email, hashed_password)
        )
        conn.commit()
        conn.close()
        return jsonify({"message": "User created successfully"})
    except sqlite3.IntegrityError:
        return jsonify({"error": "Email already exists"}), 409


# ---------- LOGIN ----------
@app.route("/login", methods=["POST"])
def login():
    data = request.json
    email = data.get("email")
    password = data.get("password")

    conn = get_db()
    user = conn.execute(
        "SELECT * FROM users WHERE email = ?",
        (email,)
    ).fetchone()
    conn.close()

    if user and check_password_hash(user["password"], password):
        return jsonify({
            "message": "Login successful",
            "user": {
                "id": user["id"],
                "name": user["name"],
                "email": user["email"]
            }
        })
    else:
        return jsonify({"error": "Invalid credentials"}), 401

# ---------- SAVE WORKOUT ----------
@app.route("/save_workout", methods=["POST"])
def save_workout():
    data = request.json

    email = data.get("email")
    exercise = data.get("exercise")
    reps = data.get("reps")
    calories = data.get("calories")

    if not email or not exercise or reps is None or calories is None:
        return jsonify({"error": "Missing workout data"}), 400

    conn = get_db()
    conn.execute(
        """
        INSERT INTO workouts (user_email, exercise, reps, calories)
        VALUES (?, ?, ?, ?)
        """,
        (email, exercise, reps, calories)
    )
    conn.commit()
    conn.close()

    return jsonify({"message": "Workout saved successfully"})


# ---------- MEAL TRACKING ENDPOINTS ----------

@app.route("/add_meal", methods=["POST"])
def add_meal():
    data = request.json
    email = data.get("email")
    meal = data.get("meal")

    if not email or not meal:
        return jsonify({"error": "Missing email or meal"}), 400

    # 1. Estimate Nutrition
    nutrition = estimate_nutrition(meal)
    
    # 2. Save to Database
    conn = get_db()
    conn.execute(
        """
        INSERT INTO meals (user_email, meal_name, calories, protein, carbs, fats)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (email, meal, nutrition["calories"], nutrition["protein"], nutrition["carbs"], nutrition["fats"])
    )
    conn.commit()
    conn.close()

    return jsonify({
        "status": "success",
        "total_calories": nutrition["calories"],
        "nutrition": nutrition
    })


@app.route("/nutrition_summary", methods=["GET"])
def nutrition_summary():
    email = request.args.get("email")
    if not email:
        return jsonify({"error": "Missing email"}), 400

    conn = get_db()
    
    # Get today's start and end logic is handled by SQL 'date' or typically we check date(timestamp)
    # SQLite 'date(timestamp)' returns YYYY-MM-DD
    
    cursor = conn.execute(
        """
        SELECT 
            SUM(calories) as total_calories, 
            SUM(protein) as total_protein, 
            SUM(carbs) as total_carbs, 
            SUM(fats) as total_fats
        FROM meals 
        WHERE user_email = ? AND date(timestamp) = date('now', 'localtime')
        """,
        (email,)
    )
    row = cursor.fetchone()
    conn.close()

    summary = {
        "calories": row["total_calories"] or 0,
        "protein": row["total_protein"] or 0,
        "carbs": row["total_carbs"] or 0,
        "fats": row["total_fats"] or 0
    }

    return jsonify(summary)


if __name__ == "__main__":
    init_db()
    app.run(debug=True, host='0.0.0.0')
