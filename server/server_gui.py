import os
import sys
import socket
import hashlib
import sqlite3
import threading
from datetime import datetime
from flask import Flask, request, jsonify
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

# --- Helper Function: Get Local IP Address ---
def get_local_ip():
    """ดึง IP Address ของเครื่องในวง LAN อัตโนมัติ"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

# --- Configuration & Flask Setup ---
app = Flask(__name__)
UPLOAD_FOLDER = os.path.join(os.path.expanduser('~'), 'Pictures', 'PhotoSync')
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

DB_NAME = os.path.join(UPLOAD_FOLDER, 'photo_sync.db')

# --- SQLite Database Helper ---
def init_db():
    """สร้างตาราง photo_hashes ใน SQLite ถ้ายังไม่มี"""
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS photo_hashes (
            hash TEXT PRIMARY KEY,
            filename TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    conn.commit()
    conn.close()

# เรียกสร้าง DB ตั้งแต่เริ่ม
init_db()

def save_uploaded_file_with_db(file, save_dir):
    """ฟังก์ชันเช็ก Hash ผ่าน SQLite และบันทึกรูป"""
    file_bytes = file.read()
    file_hash = hashlib.md5(file_bytes).hexdigest()
    
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    
    # 🔍 1. ค้นหาใน DB (เร็วปรี๊ดแม้มีเป็นล้านรูป)
    cursor.execute('SELECT filename FROM photo_hashes WHERE hash = ?', (file_hash,))
    record = cursor.fetchone()
    
    if record:
        conn.close()
        return "skipped", record[0]
        
    # 💾 2. ถ้าเป็นรูปใหม่ -> บันทึกลงเครื่อง
    ext = os.path.splitext(file.filename)[1].lower() or '.jpg'
    new_filename = f"{file_hash}{ext}"
    target_path = os.path.join(save_dir, new_filename)
    
    with open(target_path, "wb") as f:
        f.write(file_bytes)
        
    # 📝 3. บันทึก Hash ลง SQLite
    cursor.execute('INSERT INTO photo_hashes (hash, filename) VALUES (?, ?)', (file_hash, new_filename))
    conn.commit()
    conn.close()
    
    return "success", new_filename

# --- Flask Routes ---
@app.route('/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return jsonify({'status': 'error', 'message': 'No file part'}), 400
        
    file = request.files['file']
    if file.filename == '':
        return jsonify({'status': 'error', 'message': 'No selected file'}), 400

    status, filename = save_uploaded_file_with_db(file, UPLOAD_FOLDER)

    # อัปเดต Log บนหน้าจอ GUI
    if status == "skipped":
        gui_app.log_message(f"⏭️ ข้ามรูปซ้ำ: {filename}")
        return jsonify({'status': 'skipped', 'message': 'File already exists'}), 200
    else:
        gui_app.log_message(f"✅ บันทึกรูปใหม่: {filename}")
        return jsonify({'status': 'success', 'message': 'File uploaded successfully'}), 200

# --- GUI Application ---
class ServerGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("📸 Photo Sync Server (SQLite Enabled)")
        self.root.geometry("580x420")

        # ดึง IP เครื่องปัจจุบัน
        self.local_ip = get_local_ip()

        # Label แสดงโฟลเดอร์ปลายทาง
        tk.Label(root, text="📁 โฟลเดอร์เก็บรูปภาพ:", font=("Arial", 10, "bold")).pack(anchor="w", padx=10, pady=(10, 0))
        
        frame_dir = tk.Frame(root)
        frame_dir.pack(fill="x", padx=10, pady=5)
        
        self.lbl_dir = tk.Label(frame_dir, text=UPLOAD_FOLDER, bg="#e0e0e0", anchor="w", relief="sunken")
        self.lbl_dir.pack(side="left", fill="x", expand=True, ipady=4, ipadx=4)
        
        btn_change = tk.Button(frame_dir, text="เปลี่ยน...", command=self.change_folder)
        btn_change.pack(side="right", padx=(5, 0))

        # Log Window
        tk.Label(root, text="📊 สถานะการทำงาน / ล็อก:", font=("Arial", 10, "bold")).pack(anchor="w", padx=10, pady=(10, 0))
        
        self.log_text = tk.Text(root, state="disabled", height=12)
        self.log_text.pack(fill="both", expand=True, padx=10, pady=5)

        # Status Bar ด้านล่าง (แสดง IP Address และ Port)
        status_text = f"🟢 Server Online | IP: {self.local_ip}:5001 (SQLite Active)"
        self.lbl_status = tk.Label(root, text=status_text, bg="#d4edda", fg="#155724", font=("Arial", 10, "bold"))
        self.lbl_status.pack(fill="x", side="bottom", ipady=6)

        self.log_message(f"🚀 เริ่มต้น Server เรียบร้อยแล้ว")
        self.log_message(f"🌐 IP สำหรับกรอกในแอป: {self.local_ip}:5001")
        self.log_message(f"🗄️ SQLite DB: {DB_NAME}")

    def change_folder(self):
        global UPLOAD_FOLDER, DB_NAME
        selected = filedialog.askdirectory(initialdir=UPLOAD_FOLDER)
        if selected:
            UPLOAD_FOLDER = selected
            DB_NAME = os.path.join(UPLOAD_FOLDER, 'photo_sync.db')
            init_db()
            self.lbl_dir.config(text=UPLOAD_FOLDER)
            self.log_message(f"🔄 เปลี่ยนโฟลเดอร์เป็น: {UPLOAD_FOLDER}")

    def log_message(self, message):
        time_str = datetime.now().strftime("%H:%M:%S")
        self.log_text.config(state="normal")
        self.log_text.insert(tk.END, f"[{time_str}] {message}\n")
        self.log_text.see(tk.END)
        self.log_text.config(state="disabled")

# --- Run Server & GUI ---
def run_flask():
    app.run(host='0.0.0.0', port=5001, debug=False, use_reloader=False)

if __name__ == '__main__':
    # รัน Flask ใน Background Thread
    threading.Thread(target=run_flask, daemon=True).start()
    
    # รัน GUI
    root = tk.Tk()
    gui_app = ServerGUI(root)
    root.mainloop()