import { useState, useEffect } from "react";
import axios from "axios";

export default function App() {
  const [tasks, setTasks] = useState([]);
  const [title, setTitle] = useState("");

  // API base URL: use Docker env or fallback to local
  const API_URL = import.meta.env.VITE_API_URL;

  useEffect(() => {
    axios.get(`${API_URL}/tasks`)
      .then(res => setTasks(res.data))
      .catch(err => console.error("Error fetching tasks:", err));
  }, []);

  const addTask = async () => {
    if (!title.trim()) return;
    try {
      await axios.post(`${API_URL}/tasks`, { title });
      setTitle("");
      const res = await axios.get(`${API_URL}/tasks`);
      setTasks(res.data);
    } catch (err) {
      console.error("Error adding task:", err);
    }
  };

  return (
    <div style={{
      fontFamily: "sans-serif",
      padding: "2rem",
      maxWidth: "600px",
      margin: "auto"
    }}>
      <h1 style={{ textAlign: "center" }}>Task List</h1>
      <div style={{ display: "flex", gap: "8px", marginBottom: "1rem" }}>
        <input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="New task"
          style={{ flex: 1, padding: "0.5rem" }}
        />
        <button onClick={addTask}>Add</button>
      </div>

      {tasks.length === 0 ? (
        <p>No tasks yet — add one above!</p>
      ) : (
        <ul>
          {tasks.map((t) => (
            <li key={t.id}>{t.title}</li>
          ))}
        </ul>
      )}
    </div>
  );
}
