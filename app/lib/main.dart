import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:nsd/nsd.dart';

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
  String? _serverUrl;
  bool _isSearchingServer = false;
  
  List<AssetEntity> _allPhotos = [];
  Map<String, String> _photoHashCache = {};
  Set<String> _uploadedHashes = {};
  
  bool _isLoadingPhotos = false;
  bool _isUploading = false;
  String _statusMessage = 'กำลังสแกนหา Server อัตโนมัติ (Smart Connect)...';

  @override
  void initState() {
    super.initState();
    _autoDiscoverServer(); // สแกนหา Server ทันทีที่เปิดแอป
  }

// 📡 ฟังก์ชัน Smart Connect: สแกนหา Server ใน LAN อัตโนมัติ (อัปเดต API nsd เวอร์ชันใหม่)
  Future<void> _autoDiscoverServer() async {
    setState(() {
      _isSearchingServer = true;
      _statusMessage = '🔍 กำลังค้นหา คอมพิวเตอร์ ในวง Wi-Fi...';
    });

    try {
      final discovery = await startDiscovery('_photosync._tcp');
      
      // ✅ ใช้ addListener แทน addNestedListener
      discovery.addListener(() {
        for (final service in discovery.services) {
          if (service.host != null) {
            final host = service.host;
            final port = service.port ?? 5001;
            
            setState(() {
              _serverUrl = 'http://$host:$port';
              _isSearchingServer = false;
              _statusMessage = '⚡ เชื่อมต่อคอมพิวเตอร์สำเร็จ! ($_serverUrl)';
            });
            
            stopDiscovery(discovery);
            _loadDevicePhotos();
            break;
          }
        }
      });

      // ถ้าค้นหาเกิน 5 วินาทีแล้วไม่พบ ให้หยุดการสแกน
      Future.delayed(const Duration(seconds: 5), () {
        if (_serverUrl == null) {
          stopDiscovery(discovery);
          setState(() {
            _isSearchingServer = false;
            _statusMessage = '❌ ไม่พบ Server กรุณาเปิดโปรแกรมบนคอมพิวเตอร์';
          });
        }
      });
    } catch (e) {
      setState(() {
        _isSearchingServer = false;
        _statusMessage = 'ค้นหา Server ล้มเหลว: $e';
      });
    }
  }

  // 1. ดึงรูปภาพทั้งหมดในเครื่อง
  Future<void> _loadDevicePhotos() async {
    setState(() {
      _isLoadingPhotos = true;
    });

    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth && !ps.hasAccess) {
      setState(() {
        _isLoadingPhotos = false;
        _statusMessage = 'ไม่ได้รับสิทธิ์เข้าถึงรูปภาพ';
      });
      return;
    }

    List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(type: RequestType.image);

    if (albums.isNotEmpty) {
      List<AssetEntity> photos = await albums[0].getAssetListRange(start: 0, end: 200);
      setState(() {
        _allPhotos = photos;
        _isLoadingPhotos = false;
      });

      if (_serverUrl != null) {
        _checkUploadedStatus();
      }
    } else {
      setState(() {
        _isLoadingPhotos = false;
        _statusMessage = 'ไม่พบรูปภาพในเครื่อง';
      });
    }
  }

  // 2. ดึงรายการ Hash จาก Server
  Future<void> _checkUploadedStatus() async {
    if (_serverUrl == null) return;

    try {
      final response = await http.get(Uri.parse('$_serverUrl/check_status'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _uploadedHashes = Set<String>.from(data['uploaded_hashes'] ?? []);
          _statusMessage = '🟢 พร้อมซิงค์! ตรวจพบรูปซิงค์แล้ว ${_uploadedHashes.length} รูป';
        });
      }
    } catch (e) {
      print('Check status error: $e');
    }
  }

  Future<String?> _getHashForPhoto(AssetEntity photo) async {
    if (_photoHashCache.containsKey(photo.id)) return _photoHashCache[photo.id];
    final File? file = await photo.file;
    if (file != null) {
      final bytes = await file.readAsBytes();
      final hash = md5.convert(bytes).toString();
      _photoHashCache[photo.id] = hash;
      return hash;
    }
    return null;
  }

  // 3. ฟังก์ชันอัพโหลดรูป
  Future<void> _uploadAllPhotos() async {
    if (_serverUrl == null) {
      _autoDiscoverServer();
      return;
    }

    setState(() {
      _isUploading = true;
      _statusMessage = 'กำลังเริ่มซิงค์รูปภาพ...';
    });

    final Uri uri = Uri.parse('$_serverUrl/upload');

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
            final hash = await _getHashForPhoto(photo);
            if (hash != null) {
              setState(() => _uploadedHashes.add(hash));
            }
          }

          setState(() {
            _statusMessage = 'กำลังซิงค์... (${i + 1}/${_allPhotos.length})';
          });
        } catch (e) {
          print('Upload error: $e');
        }
      }
    }

    await _checkUploadedStatus();
    setState(() {
      _isUploading = false;
      _statusMessage = '✨ ซิงค์รูปภาพเรียบร้อยแล้ว!';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📸 Photo Sync (Smart Connect)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _autoDiscoverServer,
            tooltip: 'ค้นหา Server ใหม่',
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // Status Header
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _serverUrl != null ? Colors.green.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _serverUrl != null ? Icons.wifi : Icons.wifi_off,
                    color: _serverUrl != null ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _statusMessage,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _serverUrl != null ? Colors.green.shade900 : Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Gallery Grid
            Expanded(
              child: _isLoadingPhotos || _isSearchingServer
                  ? const Center(child: CircularProgressIndicator())
                  : _allPhotos.isEmpty
                      ? const Center(child: Text('ไม่พบรูปภาพในมือถือ'))
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
                                  return FutureBuilder<String?>(
                                    future: _getHashForPhoto(photo),
                                    builder: (context, hashSnapshot) {
                                      final hash = hashSnapshot.data;
                                      final bool isUploaded = hash != null && _uploadedHashes.contains(hash);

                                      return Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Image.file(snapshot.data!, fit: BoxFit.cover),
                                          if (isUploaded)
                                            Container(
                                              color: Colors.black12,
                                              child: const Padding(
                                                padding: EdgeInsets.all(4.0),
                                                child: Align(
                                                  alignment: Alignment.topRight,
                                                  child: Icon(Icons.check_circle, color: Colors.greenAccent, size: 26),
                                                ),
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  );
                                }
                                return Container(color: Colors.grey.shade300);
                              },
                            );
                          },
                        ),
            ),
            const SizedBox(height: 12),

            // Sync Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_isUploading || _serverUrl == null) ? null : _uploadAllPhotos,
                icon: _isUploading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload),
                label: Text(_isUploading ? 'กำลังซิงค์...' : 'เริ่มซิงค์รูปภาพทั้งหมด'),
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