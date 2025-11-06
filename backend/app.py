from flask import Flask, jsonify, request
from flask_cors import CORS
import psycopg2
import os

app = Flask(__name__)
CORS(app)  # ✅ allow all origins (frontend, etc.)

DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "password")
DB_NAME = os.getenv("DB_NAME", "tasks_db")
DB_HOST = os.getenv("DB_HOST", "db")  # docker-compose service name

@app.route("/tasks", methods=["GET"])
def get_tasks():
    conn = psycopg2.connect(
        host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASSWORD
    )
    cur = conn.cursor()
    cur.execute("SELECT id, title FROM tasks;")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return jsonify([{"id": r[0], "title": r[1]} for r in rows])

@app.route("/tasks", methods=["POST"])
def create_task():
    data = request.json
    conn = psycopg2.connect(
        host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASSWORD
    )
    cur = conn.cursor()
    cur.execute("INSERT INTO tasks (title) VALUES (%s) RETURNING id;", (data["title"],))
    task_id = cur.fetchone()[0]
    conn.commit()
    cur.close()
    conn.close()
    return jsonify({"id": task_id, "title": data["title"]}), 201

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
