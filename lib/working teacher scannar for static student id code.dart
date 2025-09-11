import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BLE Teacher Scanner',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const TeacherScannerScreen(),
    );
  }
}

class TeacherScannerScreen extends StatefulWidget {
  const TeacherScannerScreen({super.key});

  @override
  State<TeacherScannerScreen> createState() => _TeacherScannerScreenState();
}

class _TeacherScannerScreenState extends State<TeacherScannerScreen> {
  final flutterReactiveBle = FlutterReactiveBle();

  final int targetManufacturerId = 0x1234; // 👈 Change to match your Student
  final List<DiscoveredDevice> _devices = [];
  final Map<String, String> _payloads = {};

  bool _isScanning = false;
  Stream<DiscoveredDevice>? _scanStream;

  void _startScan() {
    setState(() {
      _devices.clear();
      _payloads.clear();
      _isScanning = true;
    });

    _scanStream = flutterReactiveBle.scanForDevices(withServices: []);
    _scanStream!.listen((device) {
      if (!_devices.any((d) => d.id == device.id)) {
        _devices.add(device);

        final Uint8List mfgData = device.manufacturerData;
        if (mfgData.length >= 2) {
          final id = (mfgData[1] << 8) | mfgData[0]; // little-endian
          if (id == targetManufacturerId) {
            final payloadBytes = mfgData.sublist(2);
            try {
              _payloads[device.id] = utf8.decode(payloadBytes, allowMalformed: true);
            } catch (_) {
              _payloads[device.id] = payloadBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
            }
          }
        }

        setState(() {});
      }
    });
  }

  void _stopScan() {
    flutterReactiveBle.deinitialize(); // stops scan stream
    setState(() {
      _isScanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Teacher BLE Scanner")),
      body: Column(
        children: [
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _isScanning ? _stopScan : _startScan,
            child: Text(_isScanning ? "Stop Scanning" : "Start Scanning"),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _devices.isEmpty
                ? const Center(child: Text("No devices yet..."))
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final d = _devices[index];
                      final payload = _payloads[d.id];
                      return Card(
                        color: payload != null ? Colors.green[100] : null,
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: ListTile(
                          title: Text(d.name.isNotEmpty ? d.name : "Unnamed"),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("ID: ${d.id}"),
                              Text("RSSI: ${d.rssi} dBm"),
                              if (payload != null) Text("Payload: $payload"),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
