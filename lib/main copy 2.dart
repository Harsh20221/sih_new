// main.dart
//
// Packages: flutter_reactive_ble, flutter_ble_peripheral, uuid
// Permissions: BLE as in previous example.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:uuid/uuid.dart' as uuid_gen;
import 'package:permission_handler/permission_handler.dart';

Future<bool> requestBlePermissions() async {
  final statuses = await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.location,
  ].request();

  return statuses.values.every((status) => status.isGranted);
}

final _ble = FlutterReactiveBle();
final _peripheral = FlutterBlePeripheral();
final _uuidGen = uuid_gen.Uuid();

final Uuid serviceUuid = Uuid.parse("12345678-1234-5678-1234-56789abcdef0");
const String TARGET_CLASS_ID = "CLASS25";

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Attendance',
      home: const RoleSelectionScreen(),
    );
  }
}

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BLE Attendance — Choose Role')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TeacherScreen()),
              ),
              child: const Text("I'm a Teacher (Scanner)"),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StudentScreen()),
              ),
              child: const Text("I'm a Student (Advertiser)"),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================= TEACHER =======================
class TeacherScreen extends StatefulWidget {
  const TeacherScreen({super.key});
  @override
  State<TeacherScreen> createState() => _TeacherScreenState();
}

class _TeacherScreenState extends State<TeacherScreen> {
  StreamSubscription<DiscoveredDevice>? _scanSub;
  final Map<String, DiscoveredDevice> _devices = {};
  final Map<String, ParsedAdvertisement> _advInfo = {};
  final Set<String> _verifiedIds = {};
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      bool granted = await requestBlePermissions();
      if (granted) {
        _startScanning();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('BLE permissions are required to scan devices.'),
          ),
        );
      }
    });
  }

  void _startScanning() {
    _scanSub?.cancel();
    _devices.clear();
    _advInfo.clear();
    _verifiedIds.clear();
    _scanning = true;

    _scanSub = _ble
        .scanForDevices(withServices: [], scanMode: ScanMode.lowLatency)
        .listen(
          (device) {
            debugPrint(
              '🔹 Found device: ${device.name}, id: ${device.id}, manufacturerData: ${device.manufacturerData}',
            );
            final adv = ParsedAdvertisement.fromDiscoveredDevice(device);
            if (adv.rawManufacturerString == null) {
              // Not our frame → ignore
              return;
            }
            _devices[device.id] = device;
            _advInfo[device.id] = adv;

            // Automatically verify if class ID matches
            if (adv.classId == TARGET_CLASS_ID) {
              _verifiedIds.add(device.id);
            }

            setState(() {});
          },
          onError: (e) {
            debugPrint('Scan error: $e');
            setState(() => _scanning = false);
          },
        );
  }

  void _stopScanning() async {
    await _scanSub?.cancel();
    _scanSub = null;
    setState(() => _scanning = false);
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  Widget _deviceTile(DiscoveredDevice d) {
    final id = d.id;
    final parsed = _advInfo[id];
    final displayName =
        parsed?.displayName ?? (d.name.isNotEmpty ? d.name : '(unnamed)');
    final classId = parsed?.classId ?? '-';
    final manufStr = parsed?.rawManufacturerString ?? '';

    return ListTile(
      title: Text(displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('id: $id'),
          Text('class: $classId'),
          if (manufStr.isNotEmpty)
            Text('adv: $manufStr', overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deviceList = _devices.values.toList()
      ..sort((a, b) => (b.rssi ?? 0).compareTo(a.rssi ?? 0));

    final verifiedList = deviceList
        .where((d) => _verifiedIds.contains(d.id))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Teacher — Scanning')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _scanning ? null : _startScanning,
                  child: const Text('Start Scan'),
                ),
                ElevatedButton(
                  onPressed: _scanning ? _stopScanning : null,
                  child: const Text('Stop Scan'),
                ),
                Text('Discovered: ${deviceList.length}'),
                Text('Verified: ${_verifiedIds.length}'),
              ],
            ),
          ),
          const Divider(),
          // Verified Students List
          if (verifiedList.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '✅ Verified Students',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ...verifiedList.map((d) {
                    final adv = _advInfo[d.id]!;
                    return ListTile(
                      title: Text(adv.displayName ?? d.name),
                      subtitle: Text('id:${d.id}, class:${adv.classId}'),
                      leading: const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                      ),
                    );
                  }).toList(),
                  const Divider(),
                ],
              ),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: deviceList.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final d = deviceList[i];
                final adv = _advInfo[d.id]!;
                // Skip showing verified devices in main list (already in top list)
                if (_verifiedIds.contains(d.id)) return const SizedBox.shrink();
                return _deviceTile(d);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ======================= STUDENT =======================
class StudentScreen extends StatefulWidget {
  const StudentScreen({super.key});
  @override
  State<StudentScreen> createState() => _StudentScreenState();
}

class _StudentScreenState extends State<StudentScreen> {
  final String _studentId = _uuidGen.v4().substring(0, 6); // stable for this run
  final TextEditingController _nameController = TextEditingController(
    text: 'Student-${_shortId()}',
  );
  final TextEditingController _classController = TextEditingController(
    text: TARGET_CLASS_ID,
  );

  bool _advertising = false;

  static String _shortId() {
    return _uuidGen.v4().substring(0, 6);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startAdvertising());
  }

  Future<void> _startAdvertising() async {
    final classId = _classController.text.trim();
    final displayName = _nameController.text.trim();
    final payload = 'ATS:$classId|$displayName|ID:$_studentId';
    final bytes = Uint8List.fromList(utf8.encode(payload));
    final advertiseData = AdvertiseData(
      manufacturerId: 0x1234,
      manufacturerData: bytes,
      localName: '',
    );
    try {
      await _peripheral.requestPermission();
      await _peripheral.start(advertiseData: advertiseData);
      debugPrint('✅ Advertising started. studentId=$_studentId payload="$payload"');
      setState(() => _advertising = true);
    } catch (e) {
      debugPrint('❌ Advertise error (studentId=$_studentId): $e');
      setState(() => _advertising = false);
    }
  }

  Future<void> _stopAdvertising() async {
    try {
      await _peripheral.stop();
    } catch (e) {
      debugPrint('Stop advertise error: $e');
    } finally {
      setState(() => _advertising = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Student — Advertising')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Your name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _classController,
              decoration: const InputDecoration(labelText: 'Class ID'),
            ),
            const SizedBox(height: 12),
            
            Row(
              children: [
                ElevatedButton(
                  onPressed: _advertising ? null : _startAdvertising,
                  child: Text(
                    _advertising ? 'Advertising...' : 'Start Advertising',
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _advertising ? _stopAdvertising : null,
                  child: const Text('Stop Advertising / Verified'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Advertising payload: ${_classController.text}|${_nameController.text}',
            ),
            Text('Student ID: $_studentId'),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// Helper class to parse BLE advertisement
class ParsedAdvertisement {
  final String? rawManufacturerString;
  final String? classId;
  final String? displayName;
  final String? studentId; // <— new

  ParsedAdvertisement({
    this.rawManufacturerString,
    this.classId,
    this.displayName,
    this.studentId,
  });

  static ParsedAdvertisement fromDiscoveredDevice(DiscoveredDevice d) {
  final data = d.manufacturerData;
  String? raw;
  String? classId;
  String? name;
  String? sid;

  if (data != null && data.isNotEmpty) {
    try {
      // manufacturerData in Android includes 2-byte companyId at start
      final bytesWithoutId = data.length > 2 ? data.sublist(2) : data;
      raw = utf8.decode(bytesWithoutId, allowMalformed: true);

      if (raw.startsWith('ATS:')) {
        final body = raw.substring(4);
        final parts = body.split('|');
        if (parts.isNotEmpty) classId = parts[0];
        if (parts.length > 1) name = parts[1];
        if (parts.length > 2 && parts[2].startsWith('ID:')) {
          sid = parts[2].substring(3);
        }
      } else {
        raw = null;
      }
    } catch (e) {
      raw = null;
    }
  }

  return ParsedAdvertisement(
    rawManufacturerString: raw,
    classId: classId,
    displayName: name ?? d.name,
    studentId: sid,
  );
}

}
