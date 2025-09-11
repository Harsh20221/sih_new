// // lib/main.dart
// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

// void main() {
//   runApp(const MaterialApp(home: RoleGate(), debugShowCheckedModeBanner: false));
// }

// /// Role gate: initializes plugin (same pattern as your working code) and
// /// routes to Teacher/Student flows while reusing the same FlutterP2pConnection instance.
// class RoleGate extends StatefulWidget {
//   const RoleGate({super.key});
//   @override
//   State<RoleGate> createState() => _RoleGateState();
// }

// class _RoleGateState extends State<RoleGate> with WidgetsBindingObserver {
//   final p2p = FlutterP2pConnection();
//   String status = 'Initializing…';
//   bool ready = false;
//   StreamSubscription<WifiP2PInfo>? _infoSub;
//   StreamSubscription<List<DiscoveredPeers>>? _peersSub;

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     _init();
//   }

//   Future<void> _init() async {
//     try {
//       setState(() => status = 'Asking permissions…');
//       await p2p.askConnectionPermissions();

//       // Ensure wifi/location are enabled (helpers from the plugin)
//       if (!(await p2p.checkWifiEnabled())) {
//         await p2p.enableWifiServices();
//       }
//       if (!(await p2p.checkLocationEnabled())) {
//         await p2p.enableLocationServices();
//       }

//       setState(() => status = 'Initializing plugin…');
//       await p2p.initialize();
//       await p2p.register();

//       // keep subscriptions so child screens can rely on plugin state (optional logs)
//       _infoSub = p2p.streamWifiP2PInfo().listen((info) {
//         debugPrint('RoleGate P2P Info: $info');
//       });
//       _peersSub = p2p.streamPeers().listen((peers) {
//         debugPrint('RoleGate Peers count: ${peers.length}');
//       });

//       setState(() {
//         ready = true;
//         status = 'Ready';
//       });
//     } catch (e) {
//       setState(() => status = 'Init error: $e');
//     }
//   }

//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     _infoSub?.cancel();
//     _peersSub?.cancel();
//     p2p.unregister();
//     super.dispose();
//   }

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     // same lifecycle handling as your working code
//     if (state == AppLifecycleState.paused) {
//       p2p.unregister();
//     } else if (state == AppLifecycleState.resumed) {
//       p2p.register();
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('P2P Verification')),
//       body: Center(
//         child: ready
//             ? Column(mainAxisSize: MainAxisSize.min, children: [
//                 ElevatedButton(
//                   onPressed: () => Navigator.push(
//                     context,
//                     MaterialPageRoute(builder: (_) => NameInputPage(isTeacher: true, p2p: p2p)),
//                   ),
//                   child: const Text("I'm a Teacher"),
//                 ),
//                 const SizedBox(height: 12),
//                 ElevatedButton(
//                   onPressed: () => Navigator.push(
//                     context,
//                     MaterialPageRoute(builder: (_) => NameInputPage(isTeacher: false, p2p: p2p)),
//                   ),
//                   child: const Text("I'm a Student"),
//                 ),
//               ])
//             : Column(mainAxisSize: MainAxisSize.min, children: [
//                 const CircularProgressIndicator(),
//                 const SizedBox(height: 12),
//                 Text(status),
//               ]),
//       ),
//     );
//   }
// }

// /// Name input screen (teacher enters their name; student enters teacher's name)
// class NameInputPage extends StatefulWidget {
//   final bool isTeacher;
//   final FlutterP2pConnection p2p;
//   const NameInputPage({required this.isTeacher, required this.p2p, super.key});

//   @override
//   State<NameInputPage> createState() => _NameInputPageState();
// }

// class _NameInputPageState extends State<NameInputPage> {
//   final TextEditingController _ctrl = TextEditingController();

//   @override
//   void dispose() {
//     _ctrl.dispose();
//     super.dispose();
//   }

//   void _continue() {
//     final name = _ctrl.text.trim();
//     if (name.isEmpty) return;
//     if (widget.isTeacher) {
//       Navigator.pushReplacement(
//         context,
//         MaterialPageRoute(
//           builder: (_) => TeacherScreen(p2p: widget.p2p, teacherName: name),
//         ),
//       );
//     } else {
//       Navigator.pushReplacement(
//         context,
//         MaterialPageRoute(
//           builder: (_) => StudentScreen(p2p: widget.p2p, teacherName: name),
//         ),
//       );
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: Text(widget.isTeacher ? 'Enter your name' : "Teacher's name")),
//       body: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(children: [
//           TextField(controller: _ctrl, decoration: InputDecoration(labelText: widget.isTeacher ? 'Your name' : 'Teacher name to find')),
//           const SizedBox(height: 16),
//           ElevatedButton(onPressed: _continue, child: const Text('Continue')),
//           const SizedBox(height: 8),
//           const Text(
//             'Note: discovery matches by the peer deviceName reported by Wi-Fi P2P.\nIf automatic matching fails, ensure the teacher device Wi-Fi P2P name contains the entered name.',
//             textAlign: TextAlign.center,
//             style: TextStyle(fontSize: 12),
//           ),
//         ]),
//       ),
//     );
//   }
// }

// /// Teacher screen: createGroup, start socket server; keep discovery running.
// /// When a student connects to socket, send "Verified". Student will disconnect itself.
// class TeacherScreen extends StatefulWidget {
//   final FlutterP2pConnection p2p;
//   final String teacherName;
//   const TeacherScreen({required this.p2p, required this.teacherName, super.key});

//   @override
//   State<TeacherScreen> createState() => _TeacherScreenState();
// }

// class _TeacherScreenState extends State<TeacherScreen> {
//   WifiP2PInfo? info;
//   WifiP2PGroupInfo? group;
//   bool groupCreated = false;
//   bool socketStarted = false;
//   bool discovering = false;
//   String log = '';
//   StreamSubscription<WifiP2PInfo>? _infoSub;
//   StreamSubscription<List<DiscoveredPeers>>? _peersSub;

//   void _append(String s) => setState(() => log = '$log$s\n');

//   @override
//   void initState() {
//     super.initState();
//     // keep listening to info updates (similar to your previous code)
//     _infoSub = widget.p2p.streamWifiP2PInfo().listen((event) {
//       setState(() => info = event);
//       _append('P2P info: isConnected=${event.isConnected}, GO=${event.groupOwnerAddress}');
//       // if we have groupOwnerAddress and socket not started -> start socket
//       if (event.groupOwnerAddress != null && groupCreated && !socketStarted) {
//         _startSocketServer(event.groupOwnerAddress!);
//       }
//     });

//     // optional peers stream (for log)
//     _peersSub = widget.p2p.streamPeers().listen((list) {
//       _append('Peers discovered: ${list.map((p) => p.deviceName).toList()}');
//     });
//   }

//   Future<void> _createGroupAndDiscover() async {
//     try {
//       await widget.p2p.createGroup();
//       group = await widget.p2p.groupInfo();
//       setState(() => groupCreated = true);
//       _append('Group created: ${group?.groupNetworkName ?? "..."}');

//       // start discovery so peer list keeps updating (teacher keeps scanning)
//       await widget.p2p.discover();
//       setState(() => discovering = true);
//       _append('Discovery started');
//       // note: startSocket will be triggered when streamWifiP2PInfo gives groupOwnerAddress (see listener)
//     } catch (e) {
//       _append('createGroup/discover error: $e');
//     }
//   }

//   Future<void> _startSocketServer(String goAddress) async {
//     try {
//       await widget.p2p.startSocket(
//         groupOwnerAddress: goAddress,
//         downloadPath: "/storage/emulated/0/Download/",
//         maxConcurrentDownloads: 2,
//         deleteOnError: true,
//         onConnect: (name, address) async {
//           _append('Client connected (socket): $name @ $address  — sending Verified');
//           // send Verified to connected clients (returns bool)
//           try {
//             await widget.p2p.sendStringToSocket('Verified');
//             _append('Sent "Verified" to client.');
//             // note: we do not close the server socket here because we want to keep listening for other clients
//             // the client will close its socket after receiving the message (one-shot)
//           } catch (e) {
//             _append('sendStringToSocket error: $e');
//           }
//         },
//         transferUpdate: (t) {
//           // keep for logs if file transfers happen
//           _append('Transfer update: ${t.filename} ${t.count}/${t.total}');
//         },
//         receiveString: (msg) async {
//           // if clients send strings to host we can log them
//           _append('Host received string: $msg');
//         },
//         onCloseSocket: () {
//           _append('Server socket closed.');
//           setState(() => socketStarted = false);
//         },
//       );
//       setState(() => socketStarted = true);
//       _append('Socket server started on $goAddress');
//     } catch (e) {
//       _append('startSocket error: $e');
//     }
//   }

//   Future<void> _stopAll() async {
//     try {
//       if (discovering) {
//         await widget.p2p.stopDiscovery();
//         setState(() => discovering = false);
//         _append('Stopped discovery');
//       }
//       if (socketStarted) {
//         await widget.p2p.closeSocket();
//         setState(() => socketStarted = false);
//         _append('Closed socket');
//       }
//       if (groupCreated) {
//         await widget.p2p.removeGroup();
//         setState(() {
//           groupCreated = false;
//           group = null;
//         });
//         _append('Removed group');
//       }
//     } catch (e) {
//       _append('stop error: $e');
//     }
//   }

//   @override
//   void dispose() {
//     _infoSub?.cancel();
//     _peersSub?.cancel();
//     // stop discovery and leave group when leaving screen
//     _stopAll();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final connected = info?.isConnected == true;
//     return Scaffold(
//       appBar: AppBar(title: Text('Teacher — ${widget.teacherName}')),
//       body: Padding(
//         padding: const EdgeInsets.all(12),
//         child: Column(children: [
//           Wrap(spacing: 8, runSpacing: 8, children: [
//             ElevatedButton(
//               onPressed: groupCreated ? null : _createGroupAndDiscover,
//               child: const Text('Create Group & Start Discovery'),
//             ),
//             ElevatedButton(
//               onPressed: groupCreated || discovering || socketStarted ? _stopAll : null,
//               child: const Text('Stop'),
//             ),
//           ]),
//           const SizedBox(height: 8),
//           ListTile(title: const Text('Connected'), trailing: Text(connected.toString())),
//           ListTile(title: const Text('GO Address'), trailing: Text(info?.groupOwnerAddress ?? '-')),
//           const SizedBox(height: 8),
//           const Text('Log (latest at bottom):', style: TextStyle(fontWeight: FontWeight.bold)),
//           const SizedBox(height: 6),
//           Expanded(
//             child: Container(
//               padding: const EdgeInsets.all(8),
//               decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(8)),
//               child: SingleChildScrollView(reverse: true, child: Text(log)),
//             ),
//           ),
//         ]),
//       ),
//     );
//   }
// }

// /// Student screen: discover peers until a peer whose deviceName contains the teacherName is found.
// /// Connect, then connectToSocket to receive the one-shot "Verified", show it in green and stop searching.
// class StudentScreen extends StatefulWidget {
//   final FlutterP2pConnection p2p;
//   final String teacherName;
//   const StudentScreen({required this.p2p, required this.teacherName, super.key});

//   @override
//   State<StudentScreen> createState() => _StudentScreenState();
// }

// class _StudentScreenState extends State<StudentScreen> {
//   List<DiscoveredPeers> peers = [];
//   WifiP2PInfo? info;
//   bool discovering = false;
//   bool connecting = false;
//   String message = '';
//   StreamSubscription<List<DiscoveredPeers>>? _peersSub;
//   StreamSubscription<WifiP2PInfo>? _infoSub;

//   @override
//   void initState() {
//     super.initState();

//     // listen peers
//     _peersSub = widget.p2p.streamPeers().listen((list) {
//       setState(() => peers = list);
//       // if scanning, try to auto-connect to matching teacher
//       if (discovering && !connecting) {
//         for (var p in list) {
//           final name = (p.deviceName ?? '').toLowerCase();
//           if (name.contains(widget.teacherName.toLowerCase())) {
//             // found a device whose deviceName contains the teacherName
//             _tryConnectToPeer(p);
//             break;
//           }
//         }
//       }
//     });

//     // listen connection info: when connected, try connectToSocket
//     _infoSub = widget.p2p.streamWifiP2PInfo().listen((i) {
//       setState(() => info = i);
//       if (i.isConnected == true && i.groupOwnerAddress != null && message.isEmpty) {
//         // connect to socket to receive host message
//         _connectToSocket(i.groupOwnerAddress!);
//       }
//     });
//   }

//   Future<void> _tryConnectToPeer(DiscoveredPeers p) async {
//     if (connecting) return;
//     setState(() => connecting = true);
//     try {
//       await widget.p2p.connect(p.deviceAddress);
//       // connect() triggers Wi-Fi p2p connection; connectToSocket will be attempted when streamWifiP2PInfo says connected
//     } catch (e) {
//       debugPrint('connect error: $e');
//       setState(() => connecting = false);
//     }
//   }

//   Future<void> _connectToSocket(String goAddress) async {
//     try {
//       await widget.p2p.connectToSocket(
//         groupOwnerAddress: goAddress,
//         downloadPath: "/storage/emulated/0/Download/",
//         maxConcurrentDownloads: 1,
//         deleteOnError: true,
//         onConnect: (address) {
//           debugPrint('Connected to socket at $address');
//         },
//         transferUpdate: (t) {
//           debugPrint('transfer update: ${t.filename} ${t.count}/${t.total}');
//         },
//         receiveString: (msg) async {
//           // received "Verified" from teacher
//           setState(() {
//             message = msg;
//             discovering = false;
//           });
//           // close our client socket
//           await widget.p2p.closeSocket();
//           // stop discovery so we don't reattempt
//           await widget.p2p.stopDiscovery();
//         },
//         onCloseSocket: () {
//           debugPrint('client socket closed');
//         },
//       );
//     } catch (e) {
//       debugPrint('connectToSocket error: $e');
//     } finally {
//       setState(() => connecting = false);
//     }
//   }

//   Future<void> _startDiscover() async {
//     try {
//       setState(() => discovering = true);
//       await widget.p2p.discover();
//     } catch (e) {
//       debugPrint('discover error: $e');
//     }
//   }

//   Future<void> _stopDiscover() async {
//     setState(() {
//       discovering = false;
//       connecting = false;
//     });
//     try {
//       await widget.p2p.stopDiscovery();
//     } catch (e) {
//       debugPrint('stop discovery error: $e');
//     }
//   }

//   @override
//   void dispose() {
//     _peersSub?.cancel();
//     _infoSub?.cancel();
//     _stopDiscover();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: Text('Student — find ${widget.teacherName}')),
//       body: Padding(
//         padding: const EdgeInsets.all(12),
//         child: Column(children: [
//           if (message.isNotEmpty)
//             Container(
//               padding: const EdgeInsets.all(12),
//               decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
//               child: Text(message, style: const TextStyle(color: Colors.green, fontSize: 22)),
//             )
//           else
//             Wrap(spacing: 8, runSpacing: 8, children: [
//               ElevatedButton(
//                 onPressed: discovering ? null : _startDiscover,
//                 child: const Text('Start Searching'),
//               ),
//               ElevatedButton(
//                 onPressed: discovering ? _stopDiscover : null,
//                 child: const Text('Stop'),
//               ),
//               Text('Discovering: $discovering   Peers: ${peers.length}'),
//             ]),
//           const SizedBox(height: 12),
//           Expanded(
//             child: ListView.separated(
//               itemCount: peers.length,
//               separatorBuilder: (_, __) => const Divider(),
//               itemBuilder: (ctx, i) {
//                 final p = peers[i];
//                 return ListTile(
//                   title: Text(p.deviceName ?? 'Unknown'),
//                   subtitle: Text(p.deviceAddress ?? ''),
//                   trailing: ElevatedButton(
//                     onPressed: () async {
//                       // manual connect option
//                       await widget.p2p.connect(p.deviceAddress);
//                     },
//                     child: const Text('Connect'),
//                   ),
//                 );
//               },
//             ),
//           ),
//         ]),
//       ),
//     );
//   }
// }
