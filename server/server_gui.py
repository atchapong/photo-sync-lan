import os
import threading
import hashlib
from tkinter import filedialog  # เพิ่มโมดูลเลือกโฟลเดอร์
import customtkinter as ctk
from flask import Flask, request, jsonify
from PIL import Image, ImageDraw
import pystray

# --- ตั้งค่าธีม UI ---
ctk.set_appearance_mode("System")
ctk.set_default_color_theme("blue")

# ตั้งค่าโฟลเดอร์เริ่มต้น (สามารถกดเปลี่ยนทีหลังใน UI ได้)
SAVE_DIR = r"M:\Photos\iPhone_Backup" if os.path.exists("M:") else os.path.expanduser("~/Pictures/iPhone_Backup")
os.makedirs(SAVE_DIR, exist_ok=True)

app = Flask(__name__)
gui_instance = None  # Reference สำหรับส่งข้อมูลเข้า UI

def get_file_md5(file_bytes):
    md5_hash = hashlib.md5()
    md5_hash.update(file_bytes)
    return md5_hash.hexdigest()

@app.route('/upload', methods=['POST'])
def upload_file():
    global SAVE_DIR
    if 'file' not in request.files:
        return jsonify({"status": "error", "message": "No file part"}), 400
    
    file = request.files['file']
    filename = file.filename
    if not filename:
        return jsonify({"status": "error", "message": "No selected file"}), 400
    
    file_bytes = file.read()
    file_path = os.path.join(SAVE_DIR, filename)

    # เช็กรูปซ้ำ
    if os.path.exists(file_path):
        with open(file_path, 'rb') as f:
            existing_md5 = get_file_md5(f.read())
        incoming_md5 = get_file_md5(file_bytes)
        
        if existing_md5 == incoming_md5:
            if gui_instance:
                gui_instance.log(f"⏭️ ข้ามรูปซ้ำ: {filename}")
            return jsonify({"status": "skipped", "message": "File already exists"}), 200

    # สร้างโฟลเดอร์หากยังไม่มีอยู่
    os.makedirs(SAVE_DIR, exist_ok=True)

    with open(file_path, 'wb') as f:
        f.write(file_bytes)
        
    if gui_instance:
        gui_instance.log(f"✅ รับไฟล์สำเร็จ: {filename}")
        
    return jsonify({"status": "success", "filename": filename}), 200

def run_flask():
    app.run(host='0.0.0.0', port=5001, debug=False, use_reloader=False)

# --- หน้าต่างโปรแกรมหลัก ---
class PhotoServerApp(ctk.CTk):
    def __init__(self):
        super().__init__()
        global gui_instance
        gui_instance = self

        self.title("📸 Photo Sync LAN - Server")
        self.geometry("520x450")
        self.protocol('WM_DELETE_WINDOW', self.hide_to_tray)

        # Header
        self.title_label = ctk.CTkLabel(self, text="Photo Receiver Server", font=ctk.CTkFont(size=20, weight="bold"))
        self.title_label.pack(pady=10)

        self.status_label = ctk.CTkLabel(self, text="🟢 Server Status: Running on Port 5000", text_color="green", font=ctk.CTkFont(size=14))
        self.status_label.pack(pady=5)

        # Frame สำหรับเลือกโฟลเดอร์ปลายทาง
        self.dir_frame = ctk.CTkFrame(self)
        self.dir_frame.pack(pady=10, padx=20, fill="x")

        self.dir_label = ctk.CTkLabel(self.dir_frame, text=f"📁 โฟลเดอร์ปลายทาง:\n{SAVE_DIR}", font=ctk.CTkFont(size=12), wraplength=350)
        self.dir_label.pack(side="left", padx=10, pady=10)

        self.btn_change_dir = ctk.CTkButton(self.dir_frame, text="เปลี่ยน...", width=80, command=self.change_directory)
        self.btn_change_dir.pack(side="right", padx=10, pady=10)

        # Log Box
        self.log_box = ctk.CTkTextbox(self, width=470, height=180)
        self.log_box.pack(pady=10, padx=10)
        self.log("🚀 โปรแกรมพร้อมทำงาน รอรับรูปภาพ...")

        # ปุ่มซ่อนโปรแกรม
        self.hide_button = ctk.CTkButton(self, text="ซ่อนโปรแกรมลง System Tray", command=self.hide_to_tray)
        self.hide_button.pack(pady=10)

        # เริ่มทำงาน Flask ใน Background Thread
        self.server_thread = threading.Thread(target=run_flask, daemon=True)
        self.server_thread.start()

        self.tray_icon = None

    def change_directory(self):
        global SAVE_DIR
        selected_folder = filedialog.askdirectory(title="เลือกโฟลเดอร์สำหรับเซฟรูปภาพ")
        if selected_folder:
            SAVE_DIR = selected_folder
            self.dir_label.configure(text=f"📁 โฟลเดอร์ปลายทาง:\n{SAVE_DIR}")
            self.log(f"📌 เปลี่ยนโฟลเดอร์ปลายทางเป็น: {SAVE_DIR}")

    def log(self, message):
        self.log_box.insert("end", f"{message}\n")
        self.log_box.see("end")

    def create_tray_icon(self):
        image = Image.new('RGB', (64, 64), color=(30, 144, 255))
        draw = ImageDraw.Draw(image)
        draw.ellipse((16, 16, 48, 48), fill=(255, 255, 255))

        menu = pystray.Menu(
            pystray.MenuItem('เปิดหน้าต่างโปรแกรม', self.show_from_tray),
            pystray.MenuItem('ออกจากโปรแกรม', self.quit_app)
        )
        self.tray_icon = pystray.Icon("PhotoSync", image, "Photo Sync LAN", menu)
        self.tray_icon.run()

    def hide_to_tray(self):
        self.withdraw()
        threading.Thread(target=self.create_tray_icon, daemon=True).start()

    def show_from_tray(self, icon, item):
        if self.tray_icon:
            self.tray_icon.stop()
        self.deiconify()

    def quit_app(self, icon, item):
        if self.tray_icon:
            self.tray_icon.stop()
        self.destroy()

if __name__ == "__main__":
    app = PhotoServerApp()
    app.mainloop()