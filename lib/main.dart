import 'package:flutter/material.dart';
import 'mqtt_service.dart';
import 'esp32_monitor_service.dart';
import 'esp32_status_widget.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final MQTTService _mqttService = MQTTService();
  final ESP32MonitorService _monitorService = ESP32MonitorService();
  
  bool _isConnected = false;
  String _connectionStatus = "Desconectado";
  String _relayState = "unknown";

  @override
  void initState() {
    super.initState();
    
    // Callback para cambios de estado del relé desde MQTT
    _mqttService.onRelayStateChanged = (String newState) {
      setState(() {
        _relayState = newState;
      });
    };

    // CRÍTICO: Callback del monitor para estado del relé
    _monitorService.onRelayStateChanged = (String newState) {
      setState(() {
        _relayState = newState;
      });
      print('🔄 Estado del relé actualizado por monitor: $newState');
    };



    
    // NUEVO: Callback para monitorear el estado del ESP32
    _monitorService.onStatusChanged = (ESP32Status newStatus) {
      // Si el ESP32 se desconecta, poner el relé en unknown
      if (!newStatus.wifiConnected ) {
        setState(() {
          _relayState = "unknown";
        });
        print('🔄 ESP32 desconectado - Estado del relé cambiado a: unknown');
      }
      // Si el ESP32 se reconecta, solicitar el estado actual del relé
      else if (newStatus.isOnline && newStatus.wifiConnected && newStatus.internetConnected && newStatus.mqttConnected) {
        // Solo solicitar estado si acabamos de reconectar (evitar solicitudes repetidas)
        if (_relayState == "unknown") {
          print('🔄 ESP32 reconectado - Solicitando estado actual del relé');
          _mqttService.requestRelayState();
        }
      }
    };
    
    _connectToBroker();
  }

  Future<void> _connectToBroker() async {
    setState(() {
      _connectionStatus = "Conectando...";
    });
    
    await _mqttService.connect();
    
    setState(() {
      _isConnected = _mqttService.isConnected();
      _connectionStatus = _isConnected ? "Conectado a broker.emqx.io" : "Error de conexión";
    });
    
    // Si no se puede conectar la app, también poner relé en unknown
    if (!_isConnected) {
      setState(() {
        _relayState = "unknown";
      });
    }
  }

  Future<void> _reconnect() async {
    // Al reconectar, primero poner en unknown
    setState(() {
      _relayState = "unknown";
    });
    
    _mqttService.disconnect();
    await Future.delayed(const Duration(seconds: 1));
    await _connectToBroker();
  }

  Color _getRelayStateColor() {
    switch (_relayState) {
      case 'on':
        return Colors.green;
      case 'off':
        return Colors.red;
      case 'unknown':
        return Colors.orange; // Color naranja para estado desconocido
      default:
        return Colors.grey;
    }
  }

  String _getRelayStateText() {
    switch (_relayState) {
      case 'on':
        return 'ENCENDIDO';
      case 'off':
        return 'APAGADO';
      case 'unknown':
        return 'DESCONOCIDO';
      default:
        return 'DESCONOCIDO';
    }
  }

  IconData _getRelayStateIcon() {
    switch (_relayState) {
      case 'on':
        return Icons.power;
      case 'off':
        return Icons.power_off;
      case 'unknown':
        return Icons.help_outline;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Control Relé ESP32',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Control Relé ESP32'),
          backgroundColor: Colors.blue,
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                
                // Widget de estado del ESP32
                ESP32StatusWidget(monitorService: _monitorService),
                
                const SizedBox(height: 30),
                
                // Estado actual del relé
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _getRelayStateColor().withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _getRelayStateColor(),
                      width: 3,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _getRelayStateIcon(),
                        size: 64,
                        color: _getRelayStateColor(),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Estado del Relé',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _getRelayStateText(),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: _getRelayStateColor(),
                        ),
                      ),
                      // NUEVO: Mostrar información adicional cuando está en unknown
                      if (_relayState == 'unknown') ...[
                        const SizedBox(height: 8),
                        Text(
                          'ESP32 no disponible',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.orange.shade700,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Botón para encender el relé
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    // MODIFICADO: Solo habilitar si la app está conectada Y el ESP32 está online
                    onPressed: (_isConnected && _relayState != 'unknown') 
                        ? () => _mqttService.publish("rele/control", "on")  //AQUI SE CAMBIA EL TOPIC PARA CADA CLIENTE
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      disabledForegroundColor: Colors.grey.shade600,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: (_isConnected && _relayState != 'unknown') ? 3 : 0,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.power_settings_new, size: 28),
                        SizedBox(width: 12),
                        Text("ENCENDER RELÉ", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Botón para apagar el relé
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    // MODIFICADO: Solo habilitar si la app está conectada Y el ESP32 está online
                    onPressed: (_isConnected && _relayState != 'unknown') 
                        ? () => _mqttService.publish("rele/control", "off") //AQUI SE CAMBIA EL TOPIC PARA CADA CLIENTE
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      disabledForegroundColor: Colors.grey.shade600,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: (_isConnected && _relayState != 'unknown') ? 3 : 0,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.power_off, size: 28),
                        SizedBox(width: 12),
                        Text("APAGAR RELÉ", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // Botones de utilidad
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        // MODIFICADO: Solo habilitar actualizar estado si ESP32 está disponible
                        onPressed: (_isConnected && _relayState != 'unknown') 
                            ? () => _mqttService.requestRelayState() 
                            : null,
                        icon: const Icon(Icons.refresh),
                        label: const Text("Actualizar Estado"),
                        style: TextButton.styleFrom(
                          foregroundColor: (_isConnected && _relayState != 'unknown') ? Colors.blue : Colors.grey,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _reconnect,
                        icon: const Icon(Icons.wifi),
                        label: const Text("Reconectar"),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mqttService.disconnect();
    _monitorService.disconnect();
    super.dispose();
  }
}
