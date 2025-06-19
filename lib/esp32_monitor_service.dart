import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class ESP32MonitorService {
  late MqttServerClient _client;
  bool _isConnected = false;
  
  ESP32Status _esp32Status = ESP32Status();
  
  Function(ESP32Status)? onStatusChanged;
  Function(bool)? onConnectionChanged;
  Function(String)? onRelayStateChanged;
  
  Timer? _heartbeatTimer;
  DateTime? _lastESP32Heartbeat; // SOLO heartbeats del ESP32
  final int _esp32TimeoutSeconds = 10;
  
  Future<void> connect() async {
    try {
      final clientId = 'flutter_monitor_${DateTime.now().millisecondsSinceEpoch}';
      
      _client = MqttServerClient('broker.emqx.io', clientId);
      _client.port = 1883;
      _client.keepAlivePeriod = 0; // CRÍTICO: Desactivar keep alive de Flutter
      _client.autoReconnect = false;
      _client.logging(on: false);

      final connMess = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .withProtocolName('MQTT')
          .withProtocolVersion(4)
          .startClean()
          .withWillQos(MqttQos.atMostOnce);
      _client.connectionMessage = connMess;

      _client.onConnected = () {
        print('✅ Monitor MQTT conectado (SIN keep alive)');
        _isConnected = true;
        _setupSubscriptions();
        
        // NUEVO: Verificar estado inicial después de conectar
        Timer(Duration(milliseconds: 1000), () {
          _checkInitialConnectionStatus();
        });
        
        _startESP32HeartbeatMonitoring(); // Solo monitorear ESP32
        
        if (onConnectionChanged != null) {
          onConnectionChanged!(true);
        }
      };
      
      _client.onDisconnected = () {
        print('❌ Monitor MQTT desconectado');
        _isConnected = false;
        _stopESP32HeartbeatMonitoring();
        _setESP32Offline();
        
        if (onConnectionChanged != null) {
          onConnectionChanged!(false);
        }
      };

      await _client.connect();
      
    } catch (e) {
      print('❌ Error conectando monitor: $e');
      _isConnected = false;
      _setESP32Offline();
    }
  }

  // NUEVO MÉTODO: Verificar estado real al inicializar
  void _checkInitialConnectionStatus() {
    print('🔍 Verificando estado inicial del ESP32...');
    
    // Solicitar estado inmediatamente
    requestStatus();
    
    // Si después de 3 segundos no hay respuesta, marcar como offline
    Timer(Duration(seconds: 3), () {
      if (_lastESP32Heartbeat == null && _esp32Status.isOnline) {
        print('⚠️ No se recibió respuesta inicial del ESP32 - marcando offline');
        _setESP32Offline();
      }
    });
  }

  // NUEVO MÉTODO: Para el botón de refrescar
  Future<void> refreshConnection() async {
    print('🔄 Refrescando conexión ESP32...');
    
    // Resetear estado
    _lastESP32Heartbeat = null;
    
    // Solicitar estado fresco
    requestStatus();
    
    // Esperar respuesta
    await Future.delayed(Duration(seconds: 2));
    
    // Si aún no hay respuesta, intentar reconectar MQTT
    if (_lastESP32Heartbeat == null) {
      print('🔄 Sin respuesta - reintentando conexión MQTT...');
      await disconnect();
      await Future.delayed(Duration(milliseconds: 500));
      await connect();
    }
  }

  // FUNCIÓN MODIFICADA: Solo monitorear heartbeats del ESP32
  void _startESP32HeartbeatMonitoring() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkESP32Heartbeat();
    });
    print('🔍 Monitoreando SOLO heartbeats del ESP32 (timeout: $_esp32TimeoutSeconds s)');
  }

  void _stopESP32HeartbeatMonitoring() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    print('⏹️ Detenido monitoreo de ESP32');
  }

  // FUNCIÓN CRÍTICA: Solo verificar heartbeats del ESP32
  void _checkESP32Heartbeat() {
    final now = DateTime.now();
    
    if (_lastESP32Heartbeat == null) {
      // Nunca se recibió heartbeat del ESP32
      if (_esp32Status.isOnline) {
        print('⚠️ Nunca se recibió heartbeat del ESP32 - marcando como offline');
        _setESP32Offline();
      }
    } else {
      // Verificar si el último heartbeat del ESP32 es muy antiguo
      final timeSinceESP32Heartbeat = now.difference(_lastESP32Heartbeat!);
      if (timeSinceESP32Heartbeat.inSeconds > _esp32TimeoutSeconds) {
        print('⚠️ ESP32 TIMEOUT: ${timeSinceESP32Heartbeat.inSeconds}s sin heartbeat del ESP32');
        _setESP32Offline();
      } else {
        print('✅ ESP32 OK: último heartbeat hace ${timeSinceESP32Heartbeat.inSeconds}s');
      }
    }
  }

  void _setESP32Offline() {
    bool wasOnline = _esp32Status.isOnline;
    
    _esp32Status.isOnline = false;
    _esp32Status.wifiConnected = false;
    _esp32Status.internetConnected = false;
    _esp32Status.mqttConnected = false;
    _esp32Status.wifiIp = '';
    _esp32Status.wifiRssi = 0;
    
    print('🔴 ESP32 marcado como OFFLINE');
    
    if (onStatusChanged != null) {
      onStatusChanged!(_esp32Status);
    }
    
    if (onRelayStateChanged != null && wasOnline) {
      onRelayStateChanged!("unknown");
      print('🔄 Relé puesto en UNKNOWN - ESP32 sin heartbeat');
    }
  }

  void _setupSubscriptions() {
    try {
      // Solo suscribirse a topics del ESP32
      _client.subscribe('esp32/status', MqttQos.atMostOnce);//AQUI SE CAMBIA EL TOPIC PARA CADA CLIENTE
      _client.subscribe('esp32/heartbeat', MqttQos.atMostOnce);//AQUI SE CAMBIA EL TOPIC PARA CADA CLIENTE
      
      print('📡 Suscrito SOLO a topics del ESP32');

      _client.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? messageList) {
        _handleIncomingMessages(messageList);
      });
      
    } catch (e) {
      print('❌ Error configurando suscripciones: $e');
    }
  }

  void _handleIncomingMessages(List<MqttReceivedMessage<MqttMessage?>>? messageList) {
    try {
      if (messageList == null || messageList.isEmpty) return;
      
      for (var receivedMessage in messageList) {
        final mqttMessage = receivedMessage.payload;
        if (mqttMessage is MqttPublishMessage) {
          final topic = receivedMessage.topic;
          final payload = mqttMessage.payload;
          
          if (payload != null) {
            final message = String.fromCharCodes(payload.message).trim();
            
            // IMPORTANTE: Solo procesar mensajes del ESP32
            if (topic.startsWith('esp32/')) {
              _processESP32Message(topic, message);
            }
          }
        }
      }
    } catch (e) {
      print('❌ Error procesando mensajes: $e');
    }
  }

  // FUNCIÓN RENOMBRADA: Solo procesar mensajes del ESP32
  void _processESP32Message(String topic, String message) {
    try {
      final data = json.decode(message);
      
      if (topic == 'esp32/status') {//AQUI SE CAMBIA EL TOPIC PARA CADA CLIENTE
        _onESP32StatusReceived(data);
      } else if (topic == 'esp32/heartbeat') {//AQUI SE CAMBIA EL TOPIC PARA CADA CLIENTE
        _onESP32HeartbeatReceived(data);
      }
      
    } catch (e) {
      print('❌ Error procesando mensaje del ESP32: $e');
    }
  }

  void _onESP32StatusReceived(Map<String, dynamic> data) {
    _esp32Status = ESP32Status.fromJson(data);
    _lastESP32Heartbeat = DateTime.now();
    
    print('🔄 Estado ESP32 recibido: ${_esp32Status.toString()}');
    
    if (onStatusChanged != null) {
      onStatusChanged!(_esp32Status);
    }
  }

  // FUNCIÓN CRÍTICA: Solo heartbeats reales del ESP32
  void _onESP32HeartbeatReceived(Map<String, dynamic> data) {
    final now = DateTime.now();
    
    // Verificar que el mensaje viene del ESP32 real
    if (data.containsKey('device_id') && data['device_id'].toString().contains('ESP32')) {
      _lastESP32Heartbeat = now;
      _esp32Status.lastSeen = now;
      _esp32Status.isOnline = true;
      
      if (data.containsKey('wifi_rssi')) {
        _esp32Status.wifiRssi = data['wifi_rssi'];
      }
      if (data.containsKey('internet_ok')) {
        _esp32Status.internetConnected = data['internet_ok'];
      }
      
      print('💓 Heartbeat REAL del ESP32 recibido - ONLINE');
      
      if (onStatusChanged != null) {
        onStatusChanged!(_esp32Status);
      }
    } else {
      print('⚠️ Heartbeat ignorado - no viene del ESP32');
    }
  }

  void requestStatus() {
    if (_isConnected) {
      try {
        print('📤 Solicitando estado del ESP32...');
        _client.publishMessage('esp32/request_status', MqttQos.atLeastOnce, //AQUI SE CAMBIA EL TOPIC PARA CADA CLIENTE
            MqttClientPayloadBuilder().addString('{"request": "full_status"}').payload!);
      } catch (e) {
        print('❌ Error solicitando estado: $e');
      }
    } else {
      print('⚠️ No se puede solicitar estado - MQTT desconectado');
    }
  }

  bool get isConnected => _isConnected;
  ESP32Status get esp32Status => _esp32Status;

  Future<void> disconnect() async {
    print('🔌 Desconectando ESP32MonitorService...');
    _stopESP32HeartbeatMonitoring();
    _setESP32Offline();
    
    if (_client != null) {
      try {
        _client.disconnect();
      } catch (e) {
        print('⚠️ Error desconectando: $e');
      }
    }
    
    // Limpiar estado
    _lastESP32Heartbeat = null;
    _isConnected = false;
  }
}

class ESP32Status {
  String deviceId;
  bool isOnline;
  bool wifiConnected;
  String wifiIp;
  int wifiRssi;
  bool mqttConnected;
  bool internetConnected;
  int uptime;
  int freeHeap;
  DateTime lastSeen;

  ESP32Status({
    this.deviceId = 'Unknown',
    this.isOnline = false,
    this.wifiConnected = false,
    this.wifiIp = '',
    this.wifiRssi = 0,
    this.mqttConnected = false,
    this.internetConnected = false,
    this.uptime = 0,
    this.freeHeap = 0,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  factory ESP32Status.fromJson(Map<String, dynamic> json) {
    return ESP32Status(
      deviceId: json['device_id'] ?? 'Unknown',
      isOnline: true,
      wifiConnected: json['wifi_connected'] ?? false,
      wifiIp: json['wifi_ip'] ?? '',
      wifiRssi: json['wifi_rssi'] ?? 0,
      mqttConnected: json['mqtt_connected'] ?? false,
      internetConnected: json['internet_status'] ?? false,
      uptime: json['uptime'] ?? 0,
      freeHeap: json['free_heap'] ?? 0,
      lastSeen: DateTime.now(),
    );
  }

  String getConnectionStatusText() {
    if (!isOnline) return 'ESP32 Desconectado';
    if (!wifiConnected) return 'Sin WiFi';
    if (!internetConnected) return 'Sin Internet';
    if (!mqttConnected) return 'Sin MQTT';
    return 'Conectado (Todo OK)';
  }

  Color getConnectionStatusColor() {
    if (!isOnline || !wifiConnected || !internetConnected) {
      return Colors.red;
    }
    if (!mqttConnected) {
      return Colors.orange;
    }
    return Colors.green;
  }

  @override
  String toString() {
    return 'ESP32Status{deviceId: $deviceId, online: $isOnline, wifi: $wifiConnected, internet: $internetConnected, mqtt: $mqttConnected}';
  }
}
