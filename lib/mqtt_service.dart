import 'dart:async';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MQTTService {
  late MqttServerClient _client;
  bool _isConnected = false;
  String _relayState = "unknown";
  
  // NUEVO: Sistema de timeout
  Timer? _timeoutTimer;
  final int _timeoutSeconds = 5; // Tiempo para esperar respuesta del estado
  
  Function(String)? onRelayStateChanged;

  Future<void> connect() async {
    try {
      final clientId = 'flutter_android_${DateTime.now().millisecondsSinceEpoch}';
      
      _client = MqttServerClient('broker.emqx.io', clientId);
      _client.port = 1883;
      _client.keepAlivePeriod = 60;
      _client.autoReconnect = false;
      _client.logging(on: true);

      final connMess = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .withProtocolName('MQTT')
          .withProtocolVersion(4)
          .startClean()
          .withWillQos(MqttQos.atMostOnce);
      _client.connectionMessage = connMess;

      _client.onConnected = () {
        print('✅ MQTT conectado exitosamente');
        _isConnected = true;
        _setupSubscriptions();
      };
      
      _client.onDisconnected = () {
        print('❌ MQTT desconectado');
        _isConnected = false;
        _cancelTimeout(); // Cancelar timeout al desconectar
        _setRelayStateToUnknown(); // Poner en unknown al desconectar
      };

      await _client.connect();
      
      if (_client.connectionStatus!.state == MqttConnectionState.connected) {
        _isConnected = true;
        print('✅ Estado final: Conectado');
      } else {
        print('❌ Estado final: ${_client.connectionStatus}');
        _isConnected = false;
      }
      
    } catch (e) {
      print('❌ Error de conexión MQTT: $e');
      _isConnected = false;
      _setRelayStateToUnknown(); // Poner en unknown en caso de error
      if (_client != null) {
        _client.disconnect();
      }
    }
  }

  void _setupSubscriptions() {
    try {
      _client.updates!.listen(
        (List<MqttReceivedMessage<MqttMessage?>>? messageList) {
          _handleIncomingMessages(messageList);
        },
        onError: (error) {
          print('❌ Error en listener: $error');
        },
      );
    //AQUI SE CAMBIA EL TOPIC PARA CADA CLIENTE
      _client.subscribe('rele/estado', MqttQos.atLeastOnce);
      print('📡 Suscrito al topic: rele/estado');
      
      Future.delayed(const Duration(seconds: 2), () {
        requestRelayState();
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
            print('📥 Mensaje recibido: "$message" en topic: $topic');
            _processMessage(topic, message);
          }
        }
      }
    } catch (e) {
      print('❌ Error procesando mensajes: $e');
    }
  }
//AQUI SE CAMBIA EL TOPIC PARA CADA CLIENTE
  void _processMessage(String topic, String message) {
    if (topic == 'rele/estado') {
      final newState = message.toLowerCase();
      if (newState == 'on' || newState == 'off') {
        _relayState = newState;
        print('🔄 Estado del relé actualizado: $_relayState');
        
        // IMPORTANTE: Cancelar timeout al recibir respuesta válida
        _cancelTimeout();
        
        if (onRelayStateChanged != null) {
          onRelayStateChanged!(_relayState);
        }
      }
    }
  }

  // NUEVA FUNCIÓN: Iniciar timeout cuando se solicita estado
  void _startTimeout() {
    _cancelTimeout(); // Cancelar timeout anterior si existe
    
    _timeoutTimer = Timer(Duration(seconds: _timeoutSeconds), () {
      print('⏰ Timeout: No se recibió respuesta del ESP32 en $_timeoutSeconds segundos');
      _setRelayStateToUnknown();
    });
    
    print('⏰ Timeout iniciado: $_timeoutSeconds segundos para recibir respuesta');
  }

  // NUEVA FUNCIÓN: Cancelar timeout
  void _cancelTimeout() {
    if (_timeoutTimer != null) {
      _timeoutTimer!.cancel();
      _timeoutTimer = null;
    }
  }

  // NUEVA FUNCIÓN: Poner estado en unknown y notificar UI
  void _setRelayStateToUnknown() {
    if (_relayState != "unknown") {
      _relayState = "unknown";
      print('🔄 Estado del relé cambiado a: unknown (sin respuesta del ESP32)');
      
      if (onRelayStateChanged != null) {
        onRelayStateChanged!(_relayState);
      }
    }
  }
//AQUI SE CAMBIA EL TOPIC PARA CADA CLIENTE
  // FUNCIÓN MODIFICADA: Iniciar timeout al solicitar estado
  void requestRelayState() {
    if (isConnected()) {
      publish('rele/solicitar_estado', 'status');
      print('❓ Solicitando estado actual del relé');
      
      // NUEVO: Iniciar timeout para detectar falta de respuesta
      _startTimeout();
    } else {
      _setRelayStateToUnknown();
    }
  }

  bool isConnected() {
    return _isConnected && 
           _client.connectionStatus!.state == MqttConnectionState.connected;
  }

  void publish(String topic, String message) {
    if (isConnected()) {
      try {
        final builder = MqttClientPayloadBuilder();
        builder.addString(message);
        _client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
        print('📤 Mensaje enviado: $message al topic: $topic');
        //AQUI SE CAMBIA EL TOPIC PARA CADA CLIENTE
        // NUEVO: Si es un comando de control, iniciar timeout para verificar respuesta
        if (topic == 'rele/control') {
          _startTimeout();
        }
        
      } catch (e) {
        print('❌ Error al publicar: $e');
      }
    } else {
      print('❌ No conectado al broker MQTT');
      _setRelayStateToUnknown();
    }
  }

  String get relayState => _relayState;

  void disconnect() {
    try {
      _cancelTimeout(); // Cancelar timeout al desconectar
      
      if (_client != null) {
        print('🔌 Desconectando del broker MQTT...');
        _client.disconnect();
        _isConnected = false;
        _setRelayStateToUnknown(); // Poner en unknown al desconectar
        print('✅ Desconectado exitosamente');
      }
    } catch (e) {
      print('❌ Error al desconectar: $e');
    }
  }
}
