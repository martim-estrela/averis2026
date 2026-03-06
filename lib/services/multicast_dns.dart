import 'package:multicast_dns/multicast_dns.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../shelly_discovery.dart';

class MdnsShellyDiscovery implements ShellyDiscovery {
  @override
  Future<List<DiscoveredShelly>> discover({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final client = MDnsClient();
    final result = <DiscoveredShelly>[];

    await client.start();

    // 1) procurar serviços Shelly
    await for (final PtrResourceRecord ptr
        in client
            .lookup<PtrResourceRecord>(
              ResourceRecordQuery.serverPointer('_shelly._tcp.local.'),
            )
            .timeout(timeout, onTimeout: (sink) => sink.close())) {
      // 2) resolver para SRV -> hostname + port
      await for (final SrvResourceRecord srv
          in client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
          )) {
        final host = srv.target; // ex: shellyplug-s-abcdef.local.

        // 3) resolver hostname para IP
        await for (final IPAddressResourceRecord addr
            in client.lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(host),
            )) {
          final ip = addr.address.address; // string tipo 192.168.1.64

          // 4) confirmar se é mesmo Shelly (opcional mas recomendado)
          try {
            final uri = Uri.parse('http://$ip/rpc/Shelly.GetDeviceInfo');
            final res = await http.get(uri).timeout(const Duration(seconds: 2));
            if (res.statusCode == 200) {
              final data = jsonDecode(res.body) as Map<String, dynamic>;
              final model = data['model']?.toString() ?? 'Shelly';
              final id = data['id']?.toString() ?? host;
              result.add(DiscoveredShelly(name: '$model $id', ip: ip));
            }
          } catch (_) {
            // ignora equipamentos que não respondem
          }
        }
      }
    }

    client.stop();
    return result;
  }
}
