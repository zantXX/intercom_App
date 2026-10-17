import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// シグナリングで送受信するメッセージ（architecture.md §5.2）。
class SignalingMessage {
  SignalingMessage({required this.type, Map<String, dynamic>? data, this.connId = 0})
      : data = data ?? <String, dynamic>{};

  final String type;
  final Map<String, dynamic> data;

  /// 受信元の接続ID。ホスト側でのみ意味を持つ（クライアント側では常に 0 ＝ホスト）。
  final int connId;

  String toJson() => jsonEncode({'type': type, 'data': data});

  static SignalingMessage? tryParse(Object? raw, int connId) {
    if (raw is! String) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map<String, dynamic>) return null;
      final type = m['type'];
      if (type is! String) return null;
      final data = m['data'];
      return SignalingMessage(
        type: type,
        data: data is Map<String, dynamic> ? data : null,
        connId: connId,
      );
    } catch (_) {
      return null;
    }
  }
}

/// ホスト端末内のWebSocketサーバー、または参加者側のクライアント。
class SignalingService {
  static const int defaultPort = 47800;
  static const Duration _pingInterval = Duration(seconds: 3);

  HttpServer? _server;
  WebSocket? _hostSocket; // 参加者側：ホストへの接続
  final Map<int, WebSocket> _clients = {}; // ホスト側：接続ID → 参加者
  int _nextConnId = 1;

  final _messages = StreamController<SignalingMessage>.broadcast();
  final _clientClosed = StreamController<int>.broadcast();
  final _hostClosed = StreamController<void>.broadcast();

  Stream<SignalingMessage> get onMessage => _messages.stream;

  /// ホスト側：参加者の接続が切れた（接続ID）。
  Stream<int> get onClientDisconnected => _clientClosed.stream;

  /// 参加者側：ホストとの接続が切れた。
  Stream<void> get onHostDisconnected => _hostClosed.stream;

  int? get port => _server?.port;

  /// ホストとして待受開始。既定ポートが使用中なら空きポートを使う。実際のポートを返す。
  Future<int> startHost({int port = defaultPort}) async {
    await close();
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    } on SocketException {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    _server!.listen(_handleRequest, onError: (_) {});
    return _server!.port;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    socket.pingInterval = _pingInterval;
    final id = _nextConnId++;
    _clients[id] = socket;
    socket.listen(
      (raw) {
        final m = SignalingMessage.tryParse(raw, id);
        if (m != null && !_messages.isClosed) _messages.add(m);
      },
      onDone: () => _removeClient(id),
      onError: (_) => _removeClient(id),
      cancelOnError: true,
    );
  }

  void _removeClient(int id) {
    if (_clients.remove(id) != null && !_clientClosed.isClosed) {
      _clientClosed.add(id);
    }
  }

  /// 参加者としてホストに接続。
  Future<void> connectToHost(String host, {int port = defaultPort}) async {
    await close();
    final socket =
        await WebSocket.connect('ws://$host:$port/ws').timeout(const Duration(seconds: 5));
    socket.pingInterval = _pingInterval;
    _hostSocket = socket;
    socket.listen(
      (raw) {
        final m = SignalingMessage.tryParse(raw, 0);
        if (m != null && !_messages.isClosed) _messages.add(m);
      },
      onDone: _onHostClosed,
      onError: (_) => _onHostClosed(),
      cancelOnError: true,
    );
  }

  void _onHostClosed() {
    if (_hostSocket == null) return; // 自分で閉じた場合は通知しない
    _hostSocket = null;
    if (!_hostClosed.isClosed) _hostClosed.add(null);
  }

  /// 送信。参加者側は常にホストへ。ホスト側は [to] 指定でその接続へ、未指定なら全員へ。
  void send(SignalingMessage msg, {int? to}) {
    final raw = msg.toJson();
    final host = _hostSocket;
    if (host != null) {
      _safeAdd(host, raw);
      return;
    }
    if (to != null) {
      final c = _clients[to];
      if (c != null) _safeAdd(c, raw);
      return;
    }
    for (final c in _clients.values) {
      _safeAdd(c, raw);
    }
  }

  void _safeAdd(WebSocket s, String raw) {
    try {
      if (s.readyState == WebSocket.open) s.add(raw);
    } catch (_) {}
  }

  Future<void> disconnectClient(int id) async {
    final s = _clients.remove(id);
    await s?.close();
  }

  Future<void> close() async {
    final host = _hostSocket;
    _hostSocket = null;
    await host?.close();

    final clients = _clients.values.toList();
    _clients.clear();
    for (final c in clients) {
      await c.close();
    }

    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> dispose() async {
    await close();
    await _messages.close();
    await _clientClosed.close();
    await _hostClosed.close();
  }
}
