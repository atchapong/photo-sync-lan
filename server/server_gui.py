import os
import sys
import socket
import hashlib
import sqlite3
import threading
from datetime import datetime
from flask import Flask, request, jsonify
import tkinter as tk
from tkinter import filedialog, messagebox
from zeroconf import ServiceInfo, Zeroconf

# --- Helper Function: Get Local IP Address ---
def get_local_ip():
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

def init_db():
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

init_db()

def save_uploaded_file_with_db(file, save_dir):
    file_bytes = file.read()
    file_hash = hashlib.md5(file_bytes).hexdigest()
    
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    cursor.execute('SELECT filename FROM photo_hashes WHERE hash = ?', (file_hash,))
    record = cursor.fetchone()
    
    if record:
        conn.close()
        return "skipped", record[0]
        
    ext = os.path.splitext(file.filename)[1].lower() or '.jpg'
    new_filename = f"{file_hash}{ext}"
    target_path = os.path.join(save_dir, new_filename)
    
    with open(target_path, "wb") as f:
        f.write(file_bytes)
        
    cursor.execute('INSERT INTO photo_hashes (hash, filename) VALUES (?, ?)', (file_hash, new_filename))
    conn.commit()
    conn.close()
    
    return "success", new_filename

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return jsonify({'status': 'error', 'message': 'No file part'}), 400
    file = request.files['file']
    if file.filename == '':
        return jsonify({'status': 'error', 'message': 'No selected file'}), 400

    status, filename = save_uploaded_file_with_db(file, UPLOAD_FOLDER)

    if status == "skipped":
        gui_app.log_message(f"⏭️ ข้ามรูปซ้ำ: {filename}")
        return jsonify({'status': 'skipped', 'message': 'File already exists'}), 200
    else:
        gui_app.log_message(f"✅ บันทึกรูปใหม่: {filename}")
        return jsonify({'status': 'success', 'message': 'File uploaded successfully'}), 200

@app.route('/check_status', methods=['GET'])
def check_status():
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    cursor.execute('SELECT hash FROM photo_hashes')
    rows = cursor.fetchall()
    conn.close()
    return jsonify({'uploaded_hashes': [row[0] for row in rows]}), 200

# --- Smart Connect (mDNS Broadcast) ---
def register_mdns_service(ip_address, port=5001):
    desc = {'version': '1.0.0'}
    info = ServiceInfo(
        "_photosync._tcp.local.",
        "PhotoSyncServer._photosync._tcp.local.",
        addresses=[socket.inet_aton(ip_address)],
        port=port,
        properties=desc,
        server="photosync.local.",
    )
    zeroconf = Zeroconf()
    zeroconf.register_service(info)
    return zeroconf, info

# --- GUI Application ---
class ServerGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("📸 Photo Sync Server (Smart Connect)")
        self.root.geometry("580x420")

        self.local_ip = get_local_ip()

        tk.Label(root, text="📁 โฟลเดอร์เก็บรูปภาพ:", font=("Arial", 10, "bold")).pack(anchor="w", padx=10, pady=(10, 0))
        frame_dir = tk.Frame(root)
        frame_dir.pack(fill="x", padx=10, pady=5)
        self.lbl_dir = tk.Label(frame_dir, text=UPLOAD_FOLDER, bg="#e0e0e0", anchor="w", relief="sunken")
        self.lbl_dir.pack(side="left", fill="x", expand=True, ipady=4, ipadx=4)
        
        tk.Label(root, text="📊 สถานะการทำงาน / ล็อก:", font=("Arial", 10, "bold")).pack(anchor="w", padx=10, pady=(10, 0))
        self.log_text = tk.Text(root, state="disabled", height=12)
        self.log_text.pack(fill="both", expand=True, padx=10, pady=5)

        status_text = f"🟢 Smart Connect Active | IP: {self.local_ip}:5001"
        self.lbl_status = tk.Label(root, text=status_text, bg="#d4edda", fg="#155724", font=("Arial", 10, "bold"))
        self.lbl_status.pack(fill="x", side="bottom", ipady=6)

        self.log_message(f"🚀 เริ่มต้น Server เรียบร้อยแล้ว")
        self.log_message(f"📡 กระจายสัญญาณ Smart Connect แล้ว (ไม่ต้องกรอก IP บนมือถือ)")

    def log_message(self, message):
        time_str = datetime.now().strftime("%H:%M:%S")
        self.log_text.config(state="normal")
        self.log_text.insert(tk.END, f"[{time_str}] {message}\n")
        self.log_text.see(tk.END)
        self.log_text.config(state="disabled")

def run_flask():
    app.run(host='0.0.0.0', port=5001, debug=False, use_reloader=False)

if __name__ == '__main__':
    local_ip = get_local_ip()
    zeroconf_obj, service_info = register_mdns_service(local_ip, 5001)
    
    threading.Thread(target=run_flask, daemon=True).start()
    
    root = tk.Tk()
    gui_app = ServerGUI(root)
    root.mainloop()