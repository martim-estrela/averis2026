import 'package:wifi_iot/wifi_iot.dart';
import 'shelly_api_service.dart';

class ShellyProvisioningService {
  Future<void> connectToShelly(String ssid) async {
    await WiFiForIoTPlugin.connect(
      ssid,
      security: NetworkSecurity.NONE,
      joinOnce: true,
    );
  }

  Future<void> provisionDevice(String wifiSSID, String wifiPass) async {
    final api = ShellyApiService();

    await api.setWifi(wifiSSID, wifiPass);
    await api.reboot();
  }
}
