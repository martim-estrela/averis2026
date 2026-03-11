import 'package:flutter/material.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/shelly_provisioning_service.dart';

enum ProvisioningStep {
  selectNetwork, // Utilizador seleciona o AP do Shelly
  enterWifi, // Utilizador insere credenciais do Wi-Fi de casa
  configuring, // A configurar...
  waitingReboot, // À espera que o Shelly reinicie
  discovering, // A descobrir o novo IP
  done, // ✅ Concluído
  error,
}

class ShellyProvisioningPage extends StatefulWidget {
  const ShellyProvisioningPage({super.key});

  @override
  State<ShellyProvisioningPage> createState() => _ShellyProvisioningPageState();
}

class _ShellyProvisioningPageState extends State<ShellyProvisioningPage> {
  ProvisioningStep _step = ProvisioningStep.selectNetwork;
  String _statusMessage = 'À procura de redes Shelly...';
  String? _error;

  List<WifiNetwork> _shellyNetworks = [];
  WifiNetwork? _selectedNetwork;

  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  String? _discoveredIp;
  String? _deviceMac;
  String? _deviceModel;

  @override
  void initState() {
    super.initState();
    _scanForShellyNetworks();
  }

  Future<void> _scanForShellyNetworks() async {
    // Pedir permissão de localização (obrigatório no Android para Wi-Fi scan)
    final status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) {
      setState(() {
        _step = ProvisioningStep.error;
        _error =
            'Permissão de localização necessária para detetar redes Wi-Fi.';
      });
      return;
    }

    setState(() => _statusMessage = 'A procurar redes Shelly...');

    final networks = await WiFiForIoTPlugin.loadWifiList();
    final shellyNets =
        networks
            ?.where((n) => n.ssid?.startsWith('Shelly') ?? false)
            .toList() ??
        [];

    setState(() {
      _shellyNetworks = shellyNets;
      _statusMessage = shellyNets.isEmpty
          ? 'Nenhuma rede Shelly encontrada. O dispositivo está em modo AP?'
          : '${shellyNets.length} rede(s) Shelly encontrada(s)';
    });
  }

  Future<void> _connectToShellyAp(WifiNetwork network) async {
    setState(() {
      _step = ProvisioningStep.configuring;
      _statusMessage = 'A ligar ao ${network.ssid}...';
    });

    try {
      // Ligar ao AP do Shelly (sem password por defeito no Gen 3)
      await WiFiForIoTPlugin.connect(
        network.ssid!,
        security: NetworkSecurity.NONE,
        joinOnce: true,
        withInternet: false,
      );

      await Future.delayed(const Duration(seconds: 2));

      // Obter info do dispositivo
      setState(() => _statusMessage = 'A identificar dispositivo...');
      final info = await ShellyProvisioningService.getDeviceInfo();
      _deviceMac = info['mac'];
      _deviceModel = info['model'];

      setState(() {
        _selectedNetwork = network;
        _step = ProvisioningStep.enterWifi;
        _statusMessage = 'Dispositivo: ${info['model']} (${info['mac']})';
      });
    } catch (e) {
      setState(() {
        _step = ProvisioningStep.error;
        _error = 'Erro ao ligar ao Shelly: $e';
      });
    }
  }

  Future<void> _doProvisioning() async {
    if (_ssidController.text.trim().isEmpty) return;

    setState(() {
      _step = ProvisioningStep.configuring;
      _statusMessage = 'A configurar Wi-Fi no Shelly...';
    });

    try {
      await ShellyProvisioningService.setWifiConfig(
        ssid: _ssidController.text.trim(),
        password: _passwordController.text,
      );

      setState(() {
        _step = ProvisioningStep.waitingReboot;
        _statusMessage = 'A reiniciar o Shelly... (aguarda ~15 segundos)';
      });

      await ShellyProvisioningService.reboot();
      await Future.delayed(const Duration(seconds: 15));

      // Reconectar à rede de casa
      setState(() {
        _step = ProvisioningStep.discovering;
        _statusMessage =
            'A reconectar à tua rede e a descobrir o IP do Shelly...';
      });

      await WiFiForIoTPlugin.disconnect();
      await Future.delayed(const Duration(seconds: 3));

      // Descobrir o IP na subnet
      final info = NetworkInfo();
      final wifiIp = await info.getWifiIP(); // ex: 192.168.1.100
      final subnet = wifiIp?.split('.').take(3).join('.'); // ex: 192.168.1

      if (subnet == null) throw Exception('Não foi possível obter a subnet');

      final ip = await ShellyProvisioningService.discoverShellyIp(
        subnet: subnet,
        expectedMac: _deviceMac,
      );

      if (ip == null)
        throw Exception('Shelly não encontrado na rede após reboot');

      setState(() {
        _discoveredIp = ip;
        _step = ProvisioningStep.done;
        _statusMessage = '✅ Shelly configurado com sucesso!';
      });
    } catch (e) {
      setState(() {
        _step = ProvisioningStep.error;
        _error = 'Erro durante provisioning: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurar Shelly')),
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(24), child: _buildStep()),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case ProvisioningStep.selectNetwork:
        return _buildSelectNetwork();
      case ProvisioningStep.enterWifi:
        return _buildEnterWifi();
      case ProvisioningStep.configuring:
      case ProvisioningStep.waitingReboot:
      case ProvisioningStep.discovering:
        return _buildLoading();
      case ProvisioningStep.done:
        return _buildDone();
      case ProvisioningStep.error:
        return _buildError();
    }
  }

  Widget _buildSelectNetwork() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.wifi, size: 64, color: Colors.blue),
        const SizedBox(height: 16),
        const Text(
          'Redes Shelly Detetadas',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _statusMessage,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 24),
        if (_shellyNetworks.isEmpty) ...[
          ElevatedButton.icon(
            onPressed: _scanForShellyNetworks,
            icon: const Icon(Icons.refresh),
            label: const Text('Voltar a procurar'),
          ),
          const SizedBox(height: 16),
          const Text(
            'Certifica-te que o Shelly está em modo AP (LED a piscar).\n'
            'Se necessário, mantém o botão pressionado 10s para fazer reset.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ] else
          ..._shellyNetworks.map(
            (network) => Card(
              child: ListTile(
                leading: const Icon(Icons.router, color: Colors.blue),
                title: Text(network.ssid ?? 'Rede desconhecida'),
                subtitle: const Text('Toca para configurar'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _connectToShellyAp(network),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEnterWifi() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.home, size: 64, color: Colors.green),
        const SizedBox(height: 16),
        Text(
          'Dispositivo: $_deviceModel',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Insere as credenciais do teu Wi-Fi de casa',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _ssidController,
          decoration: const InputDecoration(
            labelText: 'Nome do Wi-Fi (SSID) *',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.wifi),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: 'Password do Wi-Fi',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility : Icons.visibility_off,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _doProvisioning,
          icon: const Icon(Icons.check),
          label: const Text('Configurar Shelly'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text(
          _statusMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildDone() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle, size: 80, color: Colors.green),
        const SizedBox(height: 16),
        const Text(
          'Shelly configurado!',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'IP: $_discoveredIp',
          style: const TextStyle(fontSize: 16),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(context).pop({
            'ip': _discoveredIp,
            'mac': _deviceMac,
            'model': _deviceModel,
          }),
          icon: const Icon(Icons.add),
          label: const Text('Adicionar à app'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 80, color: Colors.red),
        const SizedBox(height: 16),
        Text(
          _error ?? 'Erro desconhecido',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => setState(() {
            _step = ProvisioningStep.selectNetwork;
            _error = null;
            _scanForShellyNetworks();
          }),
          child: const Text('Tentar novamente'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
