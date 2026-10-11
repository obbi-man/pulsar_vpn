/// Visual / UX state of the main round connect button.
enum ConnectUiState {
  /// Ready to connect.
  disconnected,

  /// Handshake + local proxy / system VPN in progress (or disconnecting).
  connecting,

  /// Tunnel active.
  connected,
}
