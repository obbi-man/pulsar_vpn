/// Parsed Pulsar / CustomShield access URL.
///
/// Accepted schemes (case-insensitive):
/// - `pulsar://secret@host:port/?id=connId` (preferred in UI)
/// - `cs://secret@host:port/?id=connId` (compat)
///
/// - port defaults to `51820` when omitted
/// - `id` query param is the 4-byte Connection ID (8 hex chars)
class AccessKey {
  const AccessKey({
    required this.secretKey,
    required this.serverIp,
    required this.port,
    required this.connectionId,
    this.scheme = 'pulsar',
  });

  final String secretKey;
  final String serverIp;
  final int port;
  final String connectionId;

  /// Canonical scheme used when serializing (`pulsar` or `cs`).
  final String scheme;

  static const defaultPort = 51820;
  static const supportedSchemes = {'pulsar', 'cs'};

  /// Human-facing URL (always `pulsar://` for display/copy).
  String get displayUrl => toUri(preferPulsar: true).toString();

  /// Wire URL — same payload; prefer pulsar in new UI, cs still valid.
  Uri toUri({bool preferPulsar = true}) {
    final s = preferPulsar ? 'pulsar' : (scheme == 'cs' ? 'cs' : 'pulsar');
    return Uri(
      scheme: s,
      userInfo: Uri.encodeComponent(secretKey),
      host: serverIp,
      port: port == defaultPort ? null : port,
      queryParameters: {'id': connectionId},
    );
  }

  @override
  String toString() => displayUrl;

  static AccessKey parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Пустой ключ доступа');
    }

    // Normalize: allow missing // after scheme in paste mistakes.
    var input = trimmed;
    final lower = input.toLowerCase();
    if (lower.startsWith('pulsar:') && !lower.startsWith('pulsar://')) {
      input = 'pulsar://${input.substring(7)}';
    } else if (lower.startsWith('cs:') && !lower.startsWith('cs://')) {
      input = 'cs://${input.substring(3)}';
    }

    final uri = Uri.tryParse(input);
    if (uri == null || !uri.hasScheme) {
      throw const FormatException(
        'Ожидается pulsar://secret@host:port/?id=… или cs://…',
      );
    }

    final scheme = uri.scheme.toLowerCase();
    if (!supportedSchemes.contains(scheme)) {
      throw FormatException(
        'Неизвестная схема «${uri.scheme}». Используйте pulsar:// или cs://',
      );
    }

    final secret = uri.userInfo.isEmpty
        ? ''
        : Uri.decodeComponent(uri.userInfo);
    if (secret.isEmpty) {
      throw const FormatException('В ключе нет secret (pulsar://SECRET@host/…)');
    }

    final host = uri.host;
    if (host.isEmpty) {
      throw const FormatException('В ключе нет IP или хоста сервера');
    }

    final port = uri.hasPort ? uri.port : defaultPort;
    if (port <= 0 || port > 65535) {
      throw const FormatException('Некорректный порт');
    }

    final id = uri.queryParameters['id']?.trim() ?? '';
    if (id.isEmpty) {
      throw const FormatException('Нужен параметр id= (Connection ID)');
    }
    if (!RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(id)) {
      throw const FormatException('id должен быть 8 hex-символов');
    }

    return AccessKey(
      secretKey: secret,
      serverIp: host,
      port: port,
      connectionId: id.toLowerCase(),
      scheme: scheme,
    );
  }
}
