import 'plugins/ice/ice_api_server.dart';

final iceApiServer = IceApiServer();

Future<void> restartIce() async {
  await iceApiServer.restart();
}
