import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

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
  final ImagePicker _picker = ImagePicker();
  
  List<XFile> _selectedImages = [];
  bool _isUploading = false;
  String _statusMessage = 'กรุณากรอก IP คอมพิวเตอร์ และเลือกรูปภาพ';

  // ฟังก์ชันเลือกรูปหลายรูป
  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      if (images.isNotEmpty) {
        setState(() {
          _selectedImages = images;
          _statusMessage = 'เลือกรูปแล้ว ${_selectedImages.length} รูป';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'เกิดข้อผิดพลาดในการเลือกรูป: $e';
      });
    }
  }

 // ฟังก์ชันยิงรูปส่งเข้า Python Server ใน LAN
  Future<void> _uploadImages() async {
    String serverIp = _ipController.text.trim();
    if (serverIp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอก IP Address ของคอมพิวเตอร์')),
      );
      return;
    }

    if (_selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกรูปภาพอย่างน้อย 1 รูป')),
      );
      return;
    }

    // ถ้าผู้ใช้ไม่ได้พิมพ์ :port มา ให้ใส่ :5001 เป็นค่าเริ่มต้นให้อัตโนมัติ
    if (!serverIp.contains(':')) {
      serverIp = '$serverIp:5001';
    }

    setState(() {
      _isUploading = true;
      _statusMessage = 'กำลังส่งรูปภาพ... (0/${_selectedImages.length})';
    });

    int successCount = 0;
    int skippedCount = 0;
    final Uri uri = Uri.parse('http://$serverIp/upload');

    for (int i = 0; i < _selectedImages.length; i++) {
      final XFile image = _selectedImages[i];
      try {
        var request = http.MultipartRequest('POST', uri);
        request.files.add(
          await http.MultipartFile.fromPath('file', image.path),
        );

        var streamedResponse = await request.send();
        var response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          if (response.body.contains('skipped')) {
            skippedCount++;
          } else {
            successCount++;
          }
        }

        setState(() {
          _statusMessage = 'กำลังส่งรูปภาพ... (${i + 1}/${_selectedImages.length})';
        });
      } catch (e) {
        print('Error uploading ${image.name}: $e');
      }
    }

    setState(() {
      _isUploading = false;
      _statusMessage = 'ส่งสำเร็จ $successCount รูป | ข้ามรูปซ้ำ $skippedCount รูป';
      _selectedImages.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📸 Photo Sync LAN'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ช่องกรอก IP Address
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'IP Address คอมพิวเตอร์ (เช่น 192.168.1.50)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.computer),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),

            // ข้อความแจ้งสถานะ
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),

            // แสดงพรีวิวรูปที่เลือก
            Expanded(
              child: _selectedImages.isEmpty
                  ? const Center(child: Text('ยังไม่ได้เลือกรูปภาพ'))
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                      itemCount: _selectedImages.length,
                      itemBuilder: (context, index) {
                        return Image.file(
                          File(_selectedImages[index].path),
                          fit: BoxFit.cover,
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),

            // ปุ่มกดเลือกรูป และ ปุ่มส่งรูป
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isUploading ? null : _pickImages,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('เลือกรูปภาพ'),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isUploading ? null : _uploadImages,
                    icon: _isUploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.cloud_upload),
                    label: Text(_isUploading ? 'กำลังส่ง...' : 'ส่งรูปเข้าคอม'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}