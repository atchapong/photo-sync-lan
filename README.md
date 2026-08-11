# 📸 Photo Sync LAN

> **Local-first, Lossless Photo & Video Backup for iOS & Android to Windows**

**Photo Sync LAN** คือระบบสำรองข้อมูลรูปภาพและวิดีโอต้นฉบับ (Original 100% ไม่บีบอัด ไม่ลดคุณภาพ) จากมือถือ iOS และ Android ส่งตรงเข้าคอมพิวเตอร์ Windows (RAID 1 / HDD) ผ่านเครือข่าย Wi-Fi ภายในบ้านโดยไม่ต้องพึ่ง Cloud

---

## ✨ Features (จุดเด่น)

- 🔒 **Privacy & Local-first:** ข้อมูลวิ่งตรงผ่านวง LAN (Wi-Fi บ้าน) เท่านั้น ปลอดภัย ไม่ผ่าน Server นอก
- 💎 **100% Original Quality:** เก็บไฟล์ต้นฉบับเป๊ะๆ (RAW, HEIC, JPG, 4K MP4)
- 🚀 **Cross-Platform App:** แอปมือถือพัฒนาด้วย Flutter สวยงาม ใช้ง่าย รองรับทั้ง iOS และ Android
- ⚡ **Lightweight Windows Service:** ฝั่งคอมพิวเตอร์เป็นไฟล์ `.exe` เบาหวิว ไม่กิน CPU/RAM
- 🛡️ **Duplicate Detection:** มีระบบเช็ก Hash (MD5) กันรูปส่งซ้ำโดยอัตโนมัติ

---

## 📁 Project Structure (โครงสร้างโปรเจกต์)

```text
photo-sync-lan/
├── README.md
├── server/                 # ฝั่งคอมพิวเตอร์ (Windows Service)
│   ├── server.py           # Python Flask Core API
│   ├── requirements.txt    # Python Dependencies
│   └── PhotoReceiver.exe   # Standalone Executable
└── app/                    # ฝั่งแอปมือถือ (Flutter Client)
    ├── lib/                # Flutter Source Code (UI/Logic)
    └── pubspec.yaml        # Flutter Packages