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
import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';

Future<bool> requestBlePermissions() async {
  try {
    if (Platform.isIOS) {
      // On iOS foreground advertising/scanning usually only needs Bluetooth.
      final btStatus = await Permission.bluetooth.status;
      if (!btStatus.isGranted) {
        final req = await Permission.bluetooth.request();
        if (!req.isGranted) return false;
      }
      // Location optional for classic foreground BLE scanning; ignore if denied.
      return true;
    }

    // ANDROID
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdk = androidInfo.version.sdkInt;

    // Build required permissions based on SDK
    List<Permission> required = [];
    List<Permission> optional = [];

    if (sdk >= 31) {
      // Android 12+ granular Bluetooth permissions
      required = [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise, // needed because you advertise
      ];
      // Location is optional if you declared SCAN with neverForLocation and do not need location features
      optional = [Permission.location];
    } else if (sdk >= 29) {
      // Android 10–11: Location required for BLE scans
      required = [Permission.location];
      // Legacy Bluetooth permissions are normal (granted at install), no runtime request
    } else {
      // Android 9 and below: coarse/fine location (permission_handler maps both to location)
      required = [Permission.location];
    }

    // Request only missing required permissions
    final toRequest = <Permission>[
      for (final p in required)
        if (!(await p.status).isGranted) p,
    ];
    if (toRequest.isNotEmpty) {
      await toRequest.request();
    }

    final allRequiredGranted = await _allGranted(required);

    if (!allRequiredGranted) {
      // If something critical (required) denied -> fail
      return false;
    }

    // Optionally try requesting optional (ignored in result)
    for (final p in optional) {
      final st = await p.status;
      if (!st.isGranted && !st.isPermanentlyDenied) {
        await p.request();
      }
    }

    return true;
  } catch (e) {
    debugPrint('Permission check error: $e');
    // Fail open only if you already have at least scan/connect granted (best effort)
    return true;
  }
}

Future<bool> _allGranted(List<Permission> perms) async {
  for (final p in perms) {
    final st = await p.status;
    if (!st.isGranted) return false;
  }
  return true;
}

final _ble = FlutterReactiveBle();
final _peripheral = FlutterBlePeripheral();
final _uuidGen = uuid_gen.Uuid();

final Uuid serviceUuid = Uuid.parse("12345678-1234-5678-1234-56789abcdef0");
const String TARGET_CLASS_ID = "CLS25";

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
    setState(() {
      _devices.clear();
      _advInfo.clear();
      _verifiedIds.clear();
      _scanning = true;
    });

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
  final String _studentId = _uuidGen.v4().substring(0, 6);
  final TextEditingController _nameController = TextEditingController(
    text: 'Student-${_shortId()}',
  );
  final TextEditingController _classController = TextEditingController(
    text: TARGET_CLASS_ID,
  );

  bool _advertising = false;
  String _currentStrategy = '';

  static String _shortId() {
    return _uuidGen.v4().substring(0, 6);
  }


   @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      bool granted = await requestBlePermissions();
      if (granted) {
        await _checkDeviceCapability();
      }
    });
  }
Future<void> _checkDeviceCapability() async {
    try {
      final isSupported = await _peripheral.isSupported;
      debugPrint('📱 Device BLE advertising support: $isSupported');
      
      if (!isSupported) {
        setState(() => _advertising = false);
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('BLE Advertising Not Supported'),
              content: const Text(
                'This device does not support BLE advertising. '
                'Other students with compatible devices will not be able to detect you.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }
      
      // Device supports BLE, try advertising
      await _startAdvertising();
    } catch (e) {
      debugPrint('❌ Error checking BLE capability: $e');
      await _startAdvertising(); // Try anyway
    }
  }
  Future<void> _startAdvertising() async {
    final classId = _classController.text.trim();
    final displayName = _nameController.text.trim();
    
    // Try multiple advertising strategies
    await _tryAdvertisingStrategies(classId, displayName);
  }

  Future<void> _tryAdvertisingStrategies(String classId, String displayName) async {
    
    // Strategy : Simple manufacturer data only
    if (await _trySimpleManufacturerData(classId)) return;
    
    // All strategies failed
    debugPrint('❌ All advertising strategies failed');
    setState(() {
      _advertising = false;
      _currentStrategy = 'Failed';
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('BLE advertising not supported on this device'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }


  Future<bool> _trySimpleManufacturerData(String classId) async {
    try {
      debugPrint('🔄 Trying simple manufacturer data...');
      //bytes should be less than 20bytes i.e. bytes.length < 20
      final payload = 'ATS:$classId';
      final bytes = Uint8List.fromList(utf8.encode(payload));
      
      final advertiseData = AdvertiseData(
        serviceUuid: "0000180a-0000-1000-8000-00805f9b34fb",
        serviceDataUuid: "0000180a-0000-1000-8000-00805f9b34fd",
        serviceData: bytes,
        // localName: payload,
        includeDeviceName: false,
      );

      final advertiseSetParameters = AdvertiseSetParameters(
        connectable: false,
        legacyMode: true,
        scannable: false,
        includeTxPowerLevel: false,
      );

      await _peripheral.stop(); // Stop any previous advertising
      await Future.delayed(Duration(milliseconds: 500));
      
      await _peripheral.start(
        advertiseData: advertiseData,
        advertiseSetParameters: advertiseSetParameters,
      );
      
      debugPrint('✅ Simple manufacturer data advertising started');
      setState(() {
        _advertising = true;
        _currentStrategy = 'Simple Data';
      });
      return true;
    } catch (e) {
      debugPrint('❌ Simple manufacturer data failed: $e');
      return false;
    }
  }

  Future<void> _stopAdvertising() async {
    try {
      await _peripheral.stop();
    } catch (e) {
      debugPrint('Stop advertise error: $e');
    } finally {
      setState(() {
        _advertising = false;
        _currentStrategy = '';
      });
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
const String kPrimaryServiceUuidStr   = "0000180a-0000-1000-8000-00805f9b34fb";
const String kServiceDataUuidStr      = "0000180a-0000-1000-8000-00805f9b34fd";

final Uuid kPrimaryServiceUuid  = Uuid.parse(kPrimaryServiceUuidStr);
final Uuid kServiceDataUuid     = Uuid.parse(kServiceDataUuidStr);
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
  
  String? raw;
  String? classId;
  String? name;
  String? sid;

  // 1. Prefer the explicit serviceDataUuid you used in advertising
    if (d.serviceData.isNotEmpty) {
      Uint8List? dataBytes;

      if (d.serviceData.containsKey(kServiceDataUuid)) {
        dataBytes = d.serviceData[kServiceDataUuid];
      } else if (d.serviceData.containsKey(kPrimaryServiceUuid)) {
        dataBytes = d.serviceData[kPrimaryServiceUuid];
      } else {
        // fallback: first entry that decodes to ATS:
        for (final entry in d.serviceData.entries) {
          try {
            final test = utf8.decode(entry.value, allowMalformed: true).trim();
            if (test.startsWith('ATS:')) {
              dataBytes = entry.value;
              break;
            }
          } catch (_) {}
        }
      }

      if (dataBytes != null) {
        try {
          final decoded = utf8.decode(dataBytes, allowMalformed: true).trim();
          debugPrint('🔍 serviceData decoded: $decoded');
          if (decoded.startsWith('ATS:')) {
            raw = decoded;
            // Current format: ATS:<CLASS_ID>
            // (If later you add |Name|ID:XYZ, this still works: first token after ATS:)
            final body = decoded.substring(4);
            final parts = body.split('|');
            if (parts.isNotEmpty && parts.first.isNotEmpty) {
              classId = parts.first;
            }
            // Optional future extensions:
            if (parts.length > 1) name = parts[1];
            if (parts.length > 2 && parts[2].startsWith('ID:')) {
              sid = parts[2].substring(3);
            }
          }
        } catch (e) {
          debugPrint('⚠️ Error decoding serviceData: $e');
        }
      }
    }

    // (No manufacturer parsing since you said you only use service data)
    return ParsedAdvertisement(
      rawManufacturerString: raw,
      classId: classId,
      displayName: name ?? d.name,
      studentId: sid,
    );
  }


}
