import 'package:flutter/material.dart';
import 'esp32_monitor_service.dart';

class ESP32StatusWidget extends StatefulWidget {
  final ESP32MonitorService monitorService;

  const ESP32StatusWidget({Key? key, required this.monitorService}) : super(key: key);

  @override
  _ESP32StatusWidgetState createState() => _ESP32StatusWidgetState();
}

class _ESP32StatusWidgetState extends State<ESP32StatusWidget> {
  ESP32Status _status = ESP32Status();
  bool _monitorConnected = false;
  bool _isExpanded = false; // Controlar el estado de expansión

  @override
  void initState() {
    super.initState();
    
    // Configurar callbacks del monitor - SIEMPRE ACTIVOS
    widget.monitorService.onStatusChanged = (ESP32Status newStatus) {
      setState(() {
        _status = newStatus;
      });
      // La actualización ocurre automáticamente sin importar si está expandido
    };
    
    widget.monitorService.onConnectionChanged = (bool connected) {
      setState(() {
        _monitorConnected = connected;
      });
      // La actualización ocurre automáticamente sin importar si está expandido
    };
    
    // Conectar al servicio de monitoreo
    widget.monitorService.connect();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: ExpansionTile(
        leading: Icon(
          Icons.developer_board,
          color: _status.getConnectionStatusColor(),
          size: 24,
        ),
        title: Text(
          'Estado del ESP32',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _status.getConnectionStatusColor(),
          ),
        ),
        
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.refresh),
              iconSize: 20,
              onPressed: () => widget.monitorService.refreshConnection(), // MÉTODO MEJORADO
            ),
          ],
        ),
        onExpansionChanged: (bool expanded) {
          setState(() {
            _isExpanded = expanded;
          });
        },
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Estado principal detallado
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _status.getConnectionStatusColor().withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _status.getConnectionStatusColor(),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _status.getConnectionStatusText(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _status.getConnectionStatusColor(),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Última actualización: ${_formatLastSeen(_status.lastSeen)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Detalles de conectividad
                _buildDetailRow('WiFi', _status.wifiConnected ? 'Conectado' : 'Desconectado', _status.wifiConnected),
                if (_status.wifiConnected) ...[
                  _buildDetailRow('IP', _status.wifiIp, true),
                  _buildDetailRow('Señal WiFi', '${_status.wifiRssi} dBm', _status.wifiRssi > -70),
                ],
                _buildDetailRow('Internet', _status.internetConnected ? 'Disponible' : 'Sin acceso', _status.internetConnected),
                _buildDetailRow('MQTT', _status.mqttConnected ? 'Conectado' : 'Desconectado', _status.mqttConnected),
                
                const SizedBox(height: 12),
                
                // Información adicional
                if (_status.isOnline) ...[
                  const Divider(),
                  _buildInfoRow('Dispositivo', _status.deviceId),
                  _buildInfoRow('Último contacto', _formatLastSeen(_status.lastSeen)),
                  _buildInfoRow('Tiempo activo', _formatUptime(_status.uptime)),
                  _buildInfoRow('Memoria libre', '${(_status.freeHeap / 1024).toStringAsFixed(1)} KB'),
                ],
                
                // Estado del monitor
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _monitorConnected ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _monitorConnected ? Colors.green.shade200 : Colors.red.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _monitorConnected ? Icons.cloud_done : Icons.cloud_off,
                        size: 16,
                        color: _monitorConnected ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _monitorConnected ? 'Monitor conectado' : 'Monitor desconectado',
                        style: TextStyle(
                          fontSize: 12,
                          color: _monitorConnected ? Colors.green.shade700 : Colors.red.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, bool isOk) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            isOk ? Icons.check_circle : Icons.error,
            size: 16,
            color: isOk ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isOk ? Colors.green.shade700 : Colors.red.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Text(
            '$label:',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  String _formatLastSeen(DateTime lastSeen) {
    final difference = DateTime.now().difference(lastSeen);
    if (difference.inSeconds < 60) {
      return 'Hace ${difference.inSeconds}s';
    } else if (difference.inMinutes < 60) {
      return 'Hace ${difference.inMinutes}m';
    } else {
      return 'Hace ${difference.inHours}h';
    }
  }

  String _formatUptime(int uptimeMs) {
    final uptime = Duration(milliseconds: uptimeMs);
    if (uptime.inHours > 0) {
      return '${uptime.inHours}h ${uptime.inMinutes % 60}m';
    } else if (uptime.inMinutes > 0) {
      return '${uptime.inMinutes}m ${uptime.inSeconds % 60}s';
    } else {
      return '${uptime.inSeconds}s';
    }
  }
}
