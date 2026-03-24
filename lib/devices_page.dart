import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_device_page.dart';
import 'services/smart_plug_service.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispositivos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddDevicePage()),
            ),
          ),
        ],
      ),

      // ✅ users/{uid}/devices
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('devices')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.electrical_services_outlined,
                      size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('Sem dispositivos',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('Adiciona o teu primeiro Smart Plug',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.grey[600])),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AddDevicePage()),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar Dispositivo'),
                  ),
                ],
              ),
            );
          }

          final devices = snapshot.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: devices.length,
            separatorBuilder: (BuildContext ctx, int idx) =>
                const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final deviceDoc = devices[index];
              final deviceData = deviceDoc.data() as Map<String, dynamic>;

              return DeviceCard(
                deviceDoc: deviceDoc,
                deviceData: deviceData,
                userId: userId,
                onNameChanged: (newName) async {
                  await deviceDoc.reference.update({'name': newName});
                },
                onToggle: (isOn) async {
                  final ip = (deviceData['ip'] as String?) ?? '';
                  final type =
                      (deviceData['type'] as String?) ?? 'shelly-plug';
                  // ✅ Passa uid ao SmartPlugService
                  await SmartPlugService.toggle(
                      userId, deviceDoc.id, ip, type, isOn);
                },
                onDelete: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Eliminar dispositivo'),
                      content: Text(
                          'Tem a certeza que quer eliminar "${deviceData['name']}"?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Eliminar',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) await deviceDoc.reference.delete();
                },
              );
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DeviceCard
// ─────────────────────────────────────────────────────────────────────────────

class DeviceCard extends StatefulWidget {
  final QueryDocumentSnapshot deviceDoc;
  final Map<String, dynamic> deviceData;
  final String userId;
  final Function(String) onNameChanged;
  final Function(bool) onToggle;
  final VoidCallback onDelete;

  const DeviceCard({
    super.key,
    required this.deviceDoc,
    required this.deviceData,
    required this.userId,
    required this.onNameChanged,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  State<DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<DeviceCard> {
  bool _isEditingName = false;
  late TextEditingController _nameController;
  bool _deviceOn = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
        text: widget.deviceData['name'] as String? ?? '');
    _deviceOn = widget.deviceData['status'] == 'on';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ip = (widget.deviceData['ip'] as String?) ?? 'Sem IP';
    final isOnline = widget.deviceData['online'] == true;
    final lastMetrics =
        (widget.deviceData['lastMetrics'] as Map?)?.cast<String, dynamic>();
    final powerW = (lastMetrics?['powerW'] as num?)?.toDouble() ?? 0.0;
    final totalKwh = (lastMetrics?['totalKwh'] as num?)?.toDouble() ?? 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nome + online badge
            Row(
              children: [
                Expanded(
                  child: _isEditingName
                      ? TextFormField(
                          controller: _nameController,
                          autofocus: true,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                          onFieldSubmitted: (value) {
                            if (value.trim().isNotEmpty)
                              widget.onNameChanged(value.trim());
                            setState(() => _isEditingName = false);
                          },
                        )
                      : GestureDetector(
                          onTap: () => setState(() => _isEditingName = true),
                          child: Text(
                            (widget.deviceData['name'] as String?) ?? 'Sem nome',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isOnline
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isOnline
                            ? Colors.green.shade200
                            : Colors.red.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isOnline ? Colors.green : Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isOnline ? 'Online' : 'Offline',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isOnline
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => setState(() => _isEditingName = true),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // IP e tipo
            Row(
              children: [
                Icon(Icons.router, color: Colors.blue[600], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('IP: $ip', style: theme.textTheme.bodyMedium),
                      Text(
                        'Tipo: ${widget.deviceData['type'] ?? 'Desconhecido'}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Métricas
            if (lastMetrics != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  _MetricChip(
                    icon: Icons.bolt,
                    label: '${powerW.toStringAsFixed(1)} W',
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  _MetricChip(
                    icon: Icons.electric_meter,
                    label: '${totalKwh.toStringAsFixed(3)} kWh',
                    color: Colors.blue,
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),

            // Toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _deviceOn ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _deviceOn ? 'Ligado' : 'Desligado',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                Switch(
                  value: _deviceOn,
                  onChanged: isOnline
                      ? (value) {
                          setState(() => _deviceOn = value);
                          widget.onToggle(value);
                        }
                      : null,
                ),
              ],
            ),

            const SizedBox(height: 4),

            TextButton.icon(
              onPressed: widget.onDelete,
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text('Eliminar',
                  style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetricChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 13, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
