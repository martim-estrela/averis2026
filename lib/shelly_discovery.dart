// lib/services/shelly_discovery.dart

class DiscoveredShelly {
  final String name; // ex: "Shelly Plug S a1b2c3"
  final String ip; // ex: "192.168.1.64"

  DiscoveredShelly({required this.name, required this.ip});
}

abstract class ShellyDiscovery {
  Future<List<DiscoveredShelly>> discover({Duration timeout});
}
