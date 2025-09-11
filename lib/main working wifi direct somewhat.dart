// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

// void main() => runApp(const P2PApp());

// const String kClassCode = 'CLASS25';
// const String msgRequestClass = 'REQUEST_CLASS';
// const String msgPromote = 'PROMOTE';

// class P2PApp extends StatelessWidget {
//   const P2PApp({super.key});
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'P2P Chain',
//       theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
//       home: const RoleGate(),
//     );
//   }
// }

// class RoleGate extends StatefulWidget {
//   const RoleGate({super.key});
//   @override
//   State<RoleGate> createState() => _RoleGateState();
// }

// class _RoleGateState extends State<RoleGate> {
//   final p2p = FlutterP2pConnection();
//   bool ready = false;
//   String status = 'Initializing...';
//   StreamSubscription? _infoSub;
//   StreamSubscription? _peerSub;

//   @override
//   void initState() {
//     super.initState();
//     _init();
//   }

//   Future<void> _init() async {
//     try {
//       status = 'Permissions...'; setState(() {});
//       await p2p.askConnectionPermissions();
//       if (!(await p2p.checkWifiEnabled())) await p2p.enableWifiServices();
//       if (!(await p2p.checkLocationEnabled())) await p2p.enableLocationServices();
//       status = 'Plugin init...'; setState(() {});
//       await p2p.initialize();
//       await p2p.register();
//       // Keep receivers warm
//       _infoSub = p2p.streamWifiP2PInfo().listen((_) {});
//       _peerSub = p2p.streamPeers().listen((_) {});
//       status = 'Ready'; ready = true; setState(() {});
//     } catch (e) {
//       status = 'Init error: $e'; setState(() {});
//     }
//   }

//   @override
//   void dispose() {
//     _infoSub?.cancel();
//     _peerSub?.cancel();
//     p2p.unregister();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Role Selection')),
//       body: Center(
//         child: ready
//             ? Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   const Icon(Icons.wifi, size: 72),
//                   const SizedBox(height: 16),
//                   FilledButton.icon(
//                     icon: const Icon(Icons.school),
//                     label: const Text('Teacher (Scanner)'),
//                     onPressed: () {
//                       Navigator.push(
//                         context,
//                         MaterialPageRoute(
//                           builder: (_) => ChainScreen(
//                             p2p: p2p,
//                             initialRole: ChainRole.teacher,
//                           ),
//                         ),
//                       );
//                     },
//                   ),
//                   const SizedBox(height: 12),
//                   FilledButton.tonalIcon(
//                     icon: const Icon(Icons.person),
//                     label: const Text('Student (Broadcast)'),
//                     onPressed: () {
//                       Navigator.push(
//                         context,
//                         MaterialPageRoute(
//                           builder: (_) => ChainScreen(
//                             p2p: p2p,
//                             initialRole: ChainRole.student,
//                           ),
//                         ),
//                       );
//                     },
//                   ),
//                 ],
//               )
//             : Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   const CircularProgressIndicator(),
//                   const SizedBox(height: 12),
//                   Text(status),
//                 ],
//               ),
//       ),
//     );
//   }
// }

// enum ChainRole { teacher, student }

// class ChainScreen extends StatefulWidget {
//   final FlutterP2pConnection p2p;
//   final ChainRole initialRole;
//   const ChainScreen({super.key, required this.p2p, required this.initialRole});
//   @override
//   State<ChainScreen> createState() => _ChainScreenState();
// }

// class _ChainScreenState extends State<ChainScreen> {
//   late ChainRole role;

//   // Peer tracking
//   List<DiscoveredPeers> peers = [];
//   final Set<String> blacklist = {}; // includes verified & failed
//   final Set<String> connecting = {};
//   final Set<String> verified = {}; // MACs verified (also in blacklist)

//   // State
//   bool discovering = false;
//   bool socketUp = false;
//   bool running = false;

//   WifiP2PInfo? info;
//   WifiP2PGroupInfo? group;

//   // Subs
//   StreamSubscription<List<DiscoveredPeers>>? _peerSub;
//   StreamSubscription<WifiP2PInfo>? _infoSub;

//   // Log
//   String log = '';
//   void _log(String s) {
//     setState(() => log = '$log$s\n');
//   }

//   @override
//   void initState() {
//     super.initState();
//     role = widget.initialRole;

//     _peerSub = widget.p2p.streamPeers().listen((list) {
//       peers = list;
//       setState(() {});
//       if (running && role == ChainRole.teacher) {
//         _teacherAutoConnect();
//       }
//     });

//     _infoSub = widget.p2p.streamWifiP2PInfo().listen((i) async {
//       info = i;
//       setState(() {});
//       if (i.isConnected == true) {
//         await _afterLinkEstablished();
//       }
//     });

//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       if (role == ChainRole.teacher) {
//         _startTeacher();
//       } else {
//         _startStudent();
//       }
//     });
//   }

//   @override
//   void dispose() {
//     _peerSub?.cancel();
//     _infoSub?.cancel();
//     _teardownAll();
//     _teacherSocketRetryTimer?.cancel();
//     super.dispose();
//   }

//   // --- Mode start/stop ---

//   Future<void> _startTeacher() async {
//     _log('Teacher mode start (scanning).');
//     running = true; setState(() {});
//     await _ensureRadios();
//     await _startDiscovery();
//     // Teacher does NOT create group (only scans and initiates outgoing connects)
//   }

//   Future<void> _startStudent() async {
//     _log('Student mode start (broadcasting).');
//     running = true; setState(() {});
//     await _ensureRadios();
//     await _becomeGroupOwnerAndServe();
//   }

//   Future<void> _teardownAll() async {
//     running = false;
//     try { if (discovering) await widget.p2p.stopDiscovery(); } catch (_) {}
//     discovering = false;
//     try { await widget.p2p.closeSocket(); } catch (_) {}
//     socketUp = false;
//     try { await widget.p2p.removeGroup(); } catch (_) {}
//     connecting.clear();
//     setState(() {});
//   }

//   // --- Common helpers ---

//   Future<void> _ensureRadios() async {
//     if (!(await widget.p2p.checkWifiEnabled())) await widget.p2p.enableWifiServices();
//     if (!(await widget.p2p.checkLocationEnabled())) await widget.p2p.enableLocationServices();
//   }

//   Future<void> _startDiscovery() async {
//     try {
//       await widget.p2p.discover();
//       discovering = true;
//       _log('Discovering peers...');
//       setState(() {});
//     } catch (e) {
//       _log('Discover start error: $e');
//     }
//   }

//   Future<void> _stopDiscovery() async {
//     try {
//       await widget.p2p.stopDiscovery();
//       discovering = false;
//       _log('Stopped discovery.');
//       setState(() {});
//     } catch (e) {
//       _log('Stop discovery error: $e');
//     }
//   }

//   // --- Student broadcasting (become GO) ---

//   Future<void> _becomeGroupOwnerAndServe() async {
//     // Ensure fresh state
//     await _teardownTeacherArtifacts();
//     try {
//       await widget.p2p.createGroup();
//       _log('Student created group (GO pending). Waiting GO address...');
//     } catch (e) {
//       _log('createGroup error: $e');
//       return;
//     }
//     // Wait until groupOwnerAddress available then launch socket server
//     _waitForGoThenStartServer();
//   }

//   void _waitForGoThenStartServer() {
//     Timer.periodic(const Duration(milliseconds: 400), (t) async {
//       if (!mounted) { t.cancel(); return; }
//       final goAddr = info?.groupOwnerAddress;
//       final isGo = (await _readGroupIsGo());
//       if (goAddr != null && goAddr.isNotEmpty && isGo) {
//         t.cancel();
//         _log('GO address: $goAddr (student broadcast). Starting server socket.');
//         await _startServerSocket(goAddr);
//       }
//     });
//   }

//   Future<bool> _readGroupIsGo() async {
//     try {
//       group = await widget.p2p.groupInfo();
//       return group?.isGroupOwner ?? false;
//     } catch (_) {
//       return false;
//     }
//   }

//   // --- Teacher scanning & connecting ---

//   Future<void> _teacherAutoConnect() async {
//     if (!discovering) return;
//     // Pick first eligible peer not already connecting/blacklisted
//     for (final p in peers) {
//       final mac = p.deviceAddress ?? '';
//       if (mac.isEmpty) continue;
//       if (blacklist.contains(mac)) continue;
//       if (connecting.contains(mac)) continue;
//       connecting.add(mac);
//       _log('Connecting to ${p.deviceName ?? "Unknown"} ($mac)...');
//       try {
//         await widget.p2p.connect(mac);
//         // After connected, socket handshake in _afterLinkEstablished()
//       } catch (e) {
//         _log('Connect failed: $e');
//         connecting.remove(mac);
//       }
//       break; // One at a time
//     }
//   }

//   // --- After Wi-Fi Direct link established ---

// Timer? _teacherSocketRetryTimer;
// int _teacherSocketRetries = 0;
// final int _teacherSocketMaxRetries = 8;

// Future<void> _afterLinkEstablished() async {
//   try { group = await widget.p2p.groupInfo(); } catch (_) {}
//   final goAddr = info?.groupOwnerAddress;
//   final isGo = group?.isGroupOwner ?? false;

//   if (role == ChainRole.teacher) {
//     if (isGo) {
//       _log('Teacher became GO (unexpected) – will not host socket.');
//     } else {
//       if (goAddr != null && goAddr.isNotEmpty && !socketUp) {
//         _scheduleTeacherSocketConnect(goAddr);
//       }
//     }
//   } else {
//     if (isGo && !socketUp && goAddr != null && goAddr.isNotEmpty) {
//       _log('Student (GO) ensure server on $goAddr.');
//       await _startServerSocket(goAddr);
//     }
//   }
// }

// void _scheduleTeacherSocketConnect(String goAddr) {
//   // If already trying or connected, skip
//   if (socketUp) return;
//   _teacherSocketRetryTimer?.cancel();
//   _teacherSocketRetries = 0;
//   _log('Teacher scheduling socket connect to $goAddr.');
//   _teacherSocketRetryTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
//     if (!mounted || !running || role != ChainRole.teacher) {
//       t.cancel(); return;
//     }
//     if (socketUp) {
//       t.cancel(); return;
//     }
//     _teacherSocketRetries++;
//     _log('Teacher socket attempt #$_teacherSocketRetries to $goAddr');
//     final ok = await _tryTeacherSocket(goAddr);
//     if (ok) {
//       _log('Teacher socket connected on attempt #$_teacherSocketRetries.');
//       t.cancel();
//     } else if (_teacherSocketRetries >= _teacherSocketMaxRetries) {
//       _log('Teacher giving up after $_teacherSocketRetries attempts. Disconnecting P2P link.');
//       t.cancel();
//       try { await widget.p2p.closeSocket(); } catch (_) {}
//       try { await widget.p2p.removeGroup(); } catch (_) {}
//       // Force re-discovery cycle
//       if (running) {
//         await Future.delayed(const Duration(milliseconds: 300));
//         if (!discovering) await _startDiscovery();
//       }
//     }
//   });
// }

// Future<bool> _tryTeacherSocket(String goAddr) async {
//   try {
//     await _connectClientSocket(goAddr, asTeacher: true);
//     return socketUp;
//   } catch (_) {
//     return false;
//   }
// }

//   // --- Socket management ---

//   Future<void> _startServerSocket(String goAddr) async {
//     try {
//       await widget.p2p.startSocket(
//         groupOwnerAddress: goAddr,
//         downloadPath: "/storage/emulated/0/Download/",
//         maxConcurrentDownloads: 1,
//         deleteOnError: true,
//         onConnect: (name, address) {
//           _log('Socket client connected: $name @$address');
//         },
//         receiveString: (msg) async {
//           await _onServerReceive(msg);
//         },
//         transferUpdate: (_) {},
//         onCloseSocket: () {
//           socketUp = false; setState(() {});
//           _log('Server socket closed.');
//           // Keep broadcasting (student) unless promoted
//           if (running && role == ChainRole.student) {
//             // Server might auto-close after promotion tear-down
//           }
//         },
//       );
//       socketUp = true; setState(() {});
//       _log('Server socket up.');
//     } catch (e) {
//       _log('Server socket error: $e');
//     }
//   }

//   Future<void> _connectClientSocket(String goAddr, {required bool asTeacher}) async {
//     await widget.p2p.connectToSocket(
//       groupOwnerAddress: goAddr,
//       downloadPath: "/storage/emulated/0/Download/",
//       maxConcurrentDownloads: 1,
//       deleteOnError: true,
//       onConnect: (addr) async {
//         socketUp = true; setState(() {});
//         _log('Client socket connected to $addr');
//         if (asTeacher) {
//           final ok = await widget.p2p.sendStringToSocket(msgRequestClass);
//           _log('Sent $msgRequestClass ($ok)');
//         }
//       },
//       receiveString: (msg) async {
//         await _onClientReceive(msg, asTeacher: asTeacher);
//       },
//       transferUpdate: (_) {},
//       onCloseSocket: () {
//         socketUp = false; setState(() {});
//         _log('Client socket closed.');
//       },
//     );
//   }

//   // --- Protocol handlers ---

//   Future<void> _onServerReceive(String msg) async {
//     _log('Server recv: $msg');
//     if (role == ChainRole.student) {
//       // Expecting REQUEST_CLASS from teacher
//       if (msg == msgRequestClass) {
//         final sent = await widget.p2p.sendStringToSocket('CLASS:$kClassCode');
//         _log('Sent CLASS:$kClassCode ($sent)');
//       } else if (msg == msgPromote) {
//         _log('Received PROMOTE → switching to TEACHER.');
//         // Verified -> add teacher MAC? (unknown here; skip)
//         await _promoteStudentToTeacher();
//       }
//     } else {
//       // Teacher should not be running server (ignoring)
//     }
//   }

//   Future<void> _onClientReceive(String msg, {required bool asTeacher}) async {
//     _log('Client recv: $msg');
//     if (asTeacher) {
//       // Teacher expects CLASS:<code>
//       if (msg.startsWith('CLASS:')) {
//         final code = msg.substring(6);
//         // Identify MAC (best-effort)
//         String? mac;
//         // pick connecting not yet blacklisted
//         for (final addr in connecting) {
//             mac = addr; break;
//         }
//         if (code == kClassCode) {
//           _log('Class code OK.');
//           if (mac != null) {
//             verified.add(mac);
//             blacklist.add(mac);
//           }
//           // Send PROMOTE
//             final ok = await widget.p2p.sendStringToSocket(msgPromote);
//             _log('Sent PROMOTE ($ok)');
//           // Close link & move on (remain teacher)
//           await _finishExchange(mac);
//         } else {
//           _log('Class code mismatch. Blacklisting.');
//           if (mac != null) blacklist.add(mac);
//           await _finishExchange(mac);
//         }
//       }
//     } else {
//       // Student side in client role (unused)
//     }
//   }

//   Future<void> _finishExchange(String? mac) async {
//     try { await widget.p2p.closeSocket(); } catch (_) {}
//     socketUp = false;
//     try { await widget.p2p.removeGroup(); } catch (_) {}
//     if (mac != null) connecting.remove(mac);
//     setState(() {});
//     // Resume scanning if teacher
//     if (role == ChainRole.teacher && running) {
//       if (!discovering) await _startDiscovery();
//     }
//   }

//   Future<void> _promoteStudentToTeacher() async {
//     // Stop broadcasting (tear down server + group)
//     try { await widget.p2p.closeSocket(); } catch (_) {}
//     try { await widget.p2p.removeGroup(); } catch (_) {}
//     socketUp = false;
//     // Switch role
//     role = ChainRole.teacher;
//     setState(() {});
//     _log('Promoted → Teacher. Starting scan.');
//     // Start scanning
//     await _startTeacher();
//   }

//   Future<void> _teardownTeacherArtifacts() async {
//     // Ensure no lingering discovery interfering with group creation
//     if (discovering) await _stopDiscovery();
//     // Ensure no socket leftover
//     try { await widget.p2p.closeSocket(); } catch (_) {}
//     try { await widget.p2p.removeGroup(); } catch (_) {}
//     socketUp = false;
//   }

//   // --- Manual controls ---

//   Future<void> _toggleRun() async {
//     if (running) {
//       _log('Stopping mode.');
//       await _teardownAll();
//     } else {
//       if (role == ChainRole.teacher) {
//         await _startTeacher();
//       } else {
//         await _startStudent();
//       }
//     }
//   }

//   Future<void> _manualDiscover() async {
//     if (role == ChainRole.teacher) {
//       if (!discovering) {
//         await _startDiscovery();
//       }
//     } else {
//       _log('Student manual discover not needed (broadcast mode).');
//     }
//   }

//   // --- UI ---

//   @override
//   Widget build(BuildContext context) {
//     final isConnected = info?.isConnected == true;
//     final goAddr = info?.groupOwnerAddress ?? '-';
//     final isGo = group?.isGroupOwner ?? false;
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('${role.name.toUpperCase()}'),
//         actions: [
//           TextButton(
//             onPressed: _toggleRun,
//             child: Text(running ? 'Stop' : 'Start'),
//           ),
//           if (role == ChainRole.teacher)
//             IconButton(
//               onPressed: _manualDiscover,
//               icon: const Icon(Icons.refresh),
//               tooltip: 'Discover',
//             ),
//         ],
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(12),
//         child: Column(
//           children: [
//             Wrap(
//               spacing: 8,
//               runSpacing: 4,
//               children: [
//                 _chip('Role', role.name),
//                 _chip('Running', running.toString()),
//                 _chip('Discovering', discovering.toString()),
//                 _chip('Connected', isConnected.toString()),
//                 _chip('IsGO', isGo.toString()),
//                 _chip('GO Addr', goAddr),
//                 _chip('Socket', socketUp.toString()),
//                 _chip('Peers', peers.length.toString()),
//               ],
//             ),
//             const SizedBox(height: 8),
//             Expanded(
//               child: Row(
//                 children: [
//                   Expanded(child: _peersList()),
//                   const SizedBox(width: 8),
//                   Expanded(
//                     child: Container(
//                       padding: const EdgeInsets.all(8),
//                       decoration: BoxDecoration(
//                         border: Border.all(color: Colors.black12),
//                         borderRadius: BorderRadius.circular(8),
//                       ),
//                       child: SingleChildScrollView(
//                         child: Text(
//                           log,
//                           style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
//                         ),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _peersList() {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           role == ChainRole.teacher ? 'Scanned Students' : 'Nearby Teachers / Devices',
//           style: const TextStyle(fontWeight: FontWeight.bold),
//         ),
//         const SizedBox(height: 6),
//         Expanded(
//           child: ListView.separated(
//             itemCount: peers.length,
//             separatorBuilder: (_, __) => const Divider(height: 1),
//             itemBuilder: (c, i) {
//               final p = peers[i];
//               final mac = p.deviceAddress ?? '';
//               final name = p.deviceName ?? 'Unknown';
//               final isBlack = blacklist.contains(mac);
//               final isVer = verified.contains(mac);
//               return ListTile(
//                 dense: true,
//                 title: Text(name),
//                 subtitle: Text(mac),
//                 trailing: isVer
//                     ? const Icon(Icons.verified, color: Colors.green)
//                     : isBlack
//                         ? const Icon(Icons.block, color: Colors.red)
//                         : const Icon(Icons.wifi),
//               );
//             },
//           ),
//         ),
//         const SizedBox(height: 8),
//         const Text('Blacklist (incl. verified):', style: TextStyle(fontWeight: FontWeight.bold)),
//         SizedBox(
//           height: 70,
//           child: SingleChildScrollView(
//             child: Text(
//               blacklist.isEmpty ? '(empty)' : blacklist.join('\n'),
//               style: const TextStyle(fontSize: 12),
//             ),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _chip(String k, String v) {
//     return Chip(label: Text('$k: $v', style: const TextStyle(fontSize: 12)));
//   }
// }