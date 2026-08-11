import os
import hashlib
from flask import Flask, request, jsonify

app = Flask(__name__)

# เปลี่ยนพาทตามไดรฟ์ RAID 1 หรือโฟลเดอร์ที่คุณต้องการ
SAVE_DIR = r"M:\Photos\iPhone_Backup"
os.makedirs(SAVE_DIR, exist_ok=True)

def get_file_md5(file_bytes):
    md5_hash = hashlib.md5()
    md5_hash.update(file_bytes)
    return md5_hash.hexdigest()

@app.route('/upload', methods=['POST'])
def upload_file():
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
            print(f"⏭️  ข้ามรูปซ้ำ: {filename}")
            return jsonify({"status": "skipped", "message": "File already exists"}), 200

    with open(file_path, 'wb') as f:
        f.write(file_bytes)
        
    print(f"✅ บันทึกไฟล์สำเร็จ: {filename}")
    return jsonify({"status": "success", "filename": filename}), 200

if __name__ == '__main__':
    print("==========================================")
    print("🚀 Photo Receiver Server is Running...")
    print(f"📁 Save Directory: {SAVE_DIR}")
    print("==========================================")
    app.run(host='0.0.0.0', port=5002)