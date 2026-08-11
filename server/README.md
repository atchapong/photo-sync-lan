# 📸 Photo Sync LAN - Server (Python GUI)

โปรแกรมฝั่ง Server สำหรับรับรูปภาพจากแอปมือถือผ่าน Wi-Fi LAN รองรับการทำงานบน Windows พร้อมหน้าต่าง GUI และระบบซ่อนลง System Tray

---

## 🛠️ วิธีติดตั้งและสั่ง Build เป็นไฟล์ `.exe`

> ⚠️ **ข้อควรจำ:** การสั่ง Build เป็นไฟล์ `.exe` สำหรับใช้งานบน Windows **ต้องทำบนเครื่อง Windows เท่านั้น**

---

### Step 1: เปิด Terminal / Command Prompt
ย้ายเข้าไปที่โฟลเดอร์ `server` ในโปรเจกต์:

```bash
cd photo-sync-lan/server

# 1. สร้างโฟลเดอร์ .venv
python -m venv .venv

# 2. Activate เปิดใช้งาน (สำหรับ Windows Command Prompt / CMD)
.venv\Scripts\activate.bat

# (หรือถ้าใช้ Windows PowerShell ให้ใช้คำสั่งนี้)
# .venv\Scripts\Activate.ps1

# อัปเดต pip และติดตั้งไลบรารีจาก requirements.txt
python -m pip install --upgrade pip
pip install -r requirements.txt


# สร้างไฟล์ .exe (ห้ามลบเครื่องหมาย --noconsole ถ้าต้องการให้เป็น Service)
pyinstaller --noconsole --onefile --name "PhotoSyncServer" server_gui.py