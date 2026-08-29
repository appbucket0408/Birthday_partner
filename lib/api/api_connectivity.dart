import 'package:connectivity_plus/connectivity_plus.dart';

/// Pre-flight check. Cheaper and clearer than letting a request hang and
/// surfacing a socket exception the user cannot act on.
class ApiConnectivity {
  const ApiConnectivity(this._connectivity);
  final Connectivity _connectivity;

  Future<bool> get isOnline async {
    final result = await _connectivity.checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }
}
