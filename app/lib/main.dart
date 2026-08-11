import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const PhotoSyncApp());
}

class PhotoSyncApp extends StatelessWidget {
  const PhotoSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Photo Sync LAN',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _ipController = TextEditingController();
  
  List<AssetEntity> _allPhotos = [];
  Set<String> _uploadedHashes = {}; // เก็บรายการ Hash รูปที่อัพโหลดแล้ว
  bool _isLoadingPhotos = false;
  bool _isUploading = false;
  String _statusMessage = 'กรุณากรอก IP คอมพิวเตอร์ แล้วกด "โหลดรูปทั้งหมด"';

  // 1. ดึงรูปภาพทั้งหมดจากเครื่องมือถือ
  Future<void> _loadDevicePhotos() async {
    setState(() {
      _isLoadingPhotos = true;
      _statusMessage = 'กำลังขอสิทธิ์เข้าถึงคลังรูปภาพ...';
    });

    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth) {
      setState(() {
        _isLoadingPhotos = false;
        _statusMessage = 'ไม่ได้รับสิทธิ์เข้าถึงรูปภาพ';
      });
      return;
    }

    setState(() => _statusMessage = 'กำลังโหลดรูปภาพจากมือถือ...');

    // ดึงอัลบั้มรูปทั้งหมด
    List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
    );

    if (albums.isNotEmpty) {
      // ดึงรูปภาพ 100 รูปแรก (หรือปรับตามต้องการ)
      List<AssetEntity> photos = await albums[0].getAssetListRange(start: 0, end: 300);
      setState(() {
        _allPhotos = photos;
        _isLoadingPhotos = false;
        _statusMessage = 'พบรูปภาพ ${_allPhotos.length} รูปในมือถือ';
      });

      // ถ้ากรอก IP ไว้แล้ว ให้เช็กสถานะการอัพโหลดทันที
      if (_ipController.text.isNotEmpty) {
        _checkUploadedStatus();
      }
    } else {
      setState(() {
        _isLoadingPhotos = false;
        _statusMessage = 'ไม่พบรูปภาพในเครื่อง';
      });
    }
  }

  // 2. ส่งรายการภาพไปถาม Server ว่ารูปไหนเคยอัพโหลดแล้วบ้าง
  Future<void> _checkUploadedStatus() async {
    String serverIp = _ipController.text.trim();
    if (serverIp.isEmpty) return;
    if (!serverIp.contains(':')) serverIp = '$serverIp:5001';

    try {
      // ดึง MD5 หรือตรวจสอบรายการกับ Server
      final response = await http.get(Uri.parse('http://$serverIp/check_status'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _uploadedHashes = Set<String>.from(data['uploaded_hashes'] ?? []);
          _statusMessage = 'เช็กสถานะรูปภาพกับ Server เรียบร้อย';
        });
      }
    } catch (e) {
      print('Check status error: $e');
    }
  }

  // 3. ฟังก์ชันอัพโหลดรูปภาพที่ยังไม่ได้อัพ
  Future<void> _uploadNewPhotos() async {
    String serverIp = _ipController.text.trim();
    if (serverIp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอก IP Address')),
      );
      return;
    }

    if (!serverIp.contains(':')) serverIp = '$serverIp:5001';

    setState(() {
      _isUploading = true;
      _statusMessage = 'กำลังเตรียมส่งรูปภาพ...';
    });

    int successCount = 0;
    final Uri uri = Uri.parse('http://$serverIp/upload');

    for (int i = 0; i < _allPhotos.length; i++) {
      final AssetEntity photo = _allPhotos[i];
      final File? file = await photo.file;

      if (file != null) {
        try {
          var request = http.MultipartRequest('POST', uri);
          request.files.add(await http.MultipartFile.fromPath('file', file.path));

          var streamedResponse = await request.send();
          var response = await http.Response.fromStream(streamedResponse);

          if (response.statusCode == 200) {
            successCount++;
          }

          setState(() {
            _statusMessage = 'กำลังส่งรูป... (${i + 1}/${_allPhotos.length})';
          });
        } catch (e) {
          print('Upload error: $e');
        }
      }
    }

    // อัปเดตสถานะติ๊กถูกใหม่หลังจากส่งเสร็จ
    await _checkUploadedStatus();

    setState(() {
      _isUploading = false;
      _statusMessage = 'ซิงค์ข้อมูลเสร็จสิ้น!';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📸 Photo Sync (Google Photos Style)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDevicePhotos,
            tooltip: 'โหลดรูปภาพใหม่',
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // ช่องกรอก IP Address
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipController,
                    decoration: const InputDecoration(
                      labelText: 'IP Address คอมพิวเตอร์',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _checkUploadedStatus,
                  child: const Text('เชื่อมต่อ'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ข้อความสถานะ
            Text(
              _statusMessage,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
            ),
            const SizedBox(height: 8),

            // แสดง Gallery พร้อมไอคอนติ๊กถูก
            Expanded(
              child: _isLoadingPhotos
                  ? const Center(child: CircularProgressIndicator())
                  : _allPhotos.isEmpty
                      ? Center(
                          child: ElevatedButton.icon(
                            onPressed: _loadDevicePhotos,
                            icon: const Icon(Icons.photo),
                            label: const Text('ดึงรูปภาพจากเครื่อง'),
                          ),
                        )
                      : GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 4,
                          ),
                          itemCount: _allPhotos.length,
                          itemBuilder: (context, index) {
                            final photo = _allPhotos[index];
                            return FutureBuilder<File?>(
                              future: photo.file,
                              builder: (context, snapshot) {
                                if (snapshot.hasData && snapshot.data != null) {
                                  // เช็กดูว่ารูปนี้อัพแล้วหรือยัง (เช็กผ่านชื่อไฟล์/ID)
                                  bool isUploaded = _uploadedHashes.contains(photo.id);

                                  return Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.file(
                                        snapshot.data!,
                                        fit: BoxFit.cover,
                                      ),
                                      // 🟢 สัญลักษณ์ติ๊กถูกเขียว ถ้าอัพแล้ว
                                      if (isUploaded)
                                        Container(
                                          color: Colors.black26,
                                          child: const Align(
                                            alignment: Alignment.topRight,
                                            padding: EdgeInsets.all(4),
                                            child: Icon(
                                              Icons.check_circle,
                                              color: Colors.greenAccent,
                                              size: 28,
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                }
                                return Container(color: Colors.grey.shade300);
                              },
                            );
                          },
                        ),
            ),
            const SizedBox(height: 8),

            // ปุ่มกด Sync รูปภาพ
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isUploading ? null : _uploadNewPhotos,
                icon: _isUploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.cloud_upload),
                label: Text(_isUploading ? 'กำลังส่งรูปภาพ...' : 'เริ่มอัพโหลดซิงค์ทั้งหมด'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}