class ConnectionState {
  bool isConnected;
  DateTime lastActivity;
  bool isSwipping;

  ConnectionState({
    this.isConnected = false,
    DateTime? lastActivity,
    this.isSwipping = false,
  }) : lastActivity = lastActivity ?? DateTime.now();
}
