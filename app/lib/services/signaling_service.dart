import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum SignalingRole { host, client }

class SignalingMessage {
  final String type; // 'offer', 'answer', 'candidate', 'hangup'
  final dynamic data;

  SignalingMessage({required this.type, required this.data});

  Map<String, dynamic> toMap() => {'type': type, 'data': data};

  String toJson() => jsonEncode(toMap());

  factory SignalingMessage.fromJson(String str) {
    final map = jsonDecode(str) as Map<String, dynamic>;
    return SignalingMessage(type: map['type'] as String, data: map['data']);
  }
}

class SignalingService {
  HttpServer? _server;
  WebSocket? _clientSocket; // If role == client, this is the connection to host
  final List<WebSocket> _connectedClients = []; // If role == host

  final _messageController = StreamController<SignalingMessage>.broadcast();
  Stream<SignalingMessage> get onMessage => _messageController.stream;

  final _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get onConnectedStateChanged => _connectionStateController.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // ホスト（サーバー）として待受開始
  Future<void> startHost({int port = 47800}) async {
    await close();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen((HttpRequest request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        _connectedClients.add(socket);
        _isConnected = true;
        _connectionStateController.add(true);

        socket.listen(
          (message) {
            final msg = SignalingMessage.fromJson(message as String);
            _messageController.add(msg);
          },
          onDone: () {
            _connectedClients.remove(socket);
            if (_connectedClients.isEmpty) {
              _isConnected = false;
              _connectionStateController.add(false);
            }
          },
          onError: (e) {
            _connectedClients.remove(socket);
          },
        );
      } else {
        request.response.statusCode = HttpStatus.forbidden;
        request.response.close();
      }
    });
  }

  // クライアントとしてホストに接続
  Future<void> connectToHost(String hostIp, {int port = 47800}) async {
    await close();
    final url = 'ws://$hostIp:$port/ws';
    _clientSocket = await WebSocket.connect(url).timeout(const Duration(seconds: 5));
    _isConnected = true;
    _connectionStateController.add(true);

    _clientSocket!.listen(
      (message) {
        final msg = SignalingMessage.fromJson(message as String);
        _messageController.add(msg);
      },
      onDone: () {
        _isConnected = false;
        _connectionStateController.add(false);
      },
      onError: (e) {
        _isConnected = false;
        _connectionStateController.add(false);
      },
    );
  }

  // メッセージ送信
  void send(SignalingMessage msg) {
    final raw = msg.toJson();
    if (_clientSocket != null && _clientSocket!.readyState == WebSocket.open) {
      _clientSocket!.add(raw);
    }
    for (final client in _connectedClients) {
      if (client.readyState == WebSocket.open) {
        client.add(raw);
      }
    }
  }

  // 切断・停止
  Future<void> close() async {
    _isConnected = false;
    _connectionStateController.add(false);
    await _clientSocket?.close();
    _clientSocket = null;
    for (final client in _connectedClients) {
      await client.close();
    }
    _connectedClients.clear();
    await _server?.close(force: true);
    _server = null;
  }

  void dispose() {
    close();
    _messageController.close();
    _connectionStateController.close();
  }
}
