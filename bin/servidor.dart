import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

// Almacenamiento en memoria — sin archivos, sin permisos de filesystem
final List<Map<String, dynamic>> _solicitudes = [];

void main() async {
  final puerto = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;

  final router = Router()
    ..get('/', _estadoServidor)
    ..get('/estado', _estadoServidor)
    ..get('/prestar', _formularioPrestamo)
    ..post('/prestar', _registrarPrestamo)
    ..get('/solicitudes', _obtenerSolicitudes)
    ..post('/solicitudes/confirmar', _confirmarSolicitud);

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsMiddleware())
      .addHandler(router.call);

  final server = await io.serve(handler, InternetAddress.anyIPv4, puerto);
  print('✅ Biblioteca AUNAR — Servidor activo en puerto ${server.port}');
}

Middleware _corsMiddleware() {
  return (Handler handler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders());
      }
      final response = await handler(request);
      return response.change(headers: _corsHeaders());
    };
  };
}

Map<String, String> _corsHeaders() => {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

Response _estadoServidor(Request req) {
  return Response.ok(
    jsonEncode({
      'estado': 'activo',
      'hora': DateTime.now().toIso8601String(),
      'solicitudesPendientes': _solicitudes.where((s) => s['procesado'] == false).length,
    }),
    headers: {'content-type': 'application/json'},
  );
}

Response _formularioPrestamo(Request req) {
  try {
  final libroId = req.url.queryParameters['id'] ?? '';
  // 't' viene en base64url desde la app Flutter
  final tituloB64 = req.url.queryParameters['t'] ?? '';
  String tituloLegible = 'Libro de biblioteca';
  if (tituloB64.isNotEmpty) {
    try {
      tituloLegible = utf8.decode(base64Url.decode(base64Url.normalize(tituloB64)));
    } catch (_) {
      tituloLegible = tituloB64;
    }
  }
  final titulo = tituloLegible;

  final html = '''<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Solicitar préstamo — Biblioteca AUNAR</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: Georgia, serif;
      background: #0F0F1A;
      color: #E8E8FF;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .card {
      background: #1A1A2E;
      border-radius: 16px;
      padding: 32px 28px;
      width: 100%;
      max-width: 420px;
      border: 1px solid #2A2A3E;
      box-shadow: 0 8px 32px rgba(124,111,205,0.15);
    }
    .logo {
      text-align: center;
      font-size: 13px;
      color: #D4A853;
      letter-spacing: 3px;
      margin-bottom: 4px;
    }
    .icono { text-align: center; font-size: 52px; margin: 12px 0; }
    h1 {
      color: #7C6FCD;
      font-size: 17px;
      letter-spacing: 2px;
      text-align: center;
      margin-bottom: 6px;
    }
    .libro {
      color: #D4A853;
      font-style: italic;
      text-align: center;
      font-size: 15px;
      margin-bottom: 8px;
      padding: 8px 12px;
      background: rgba(212,168,83,0.08);
      border-radius: 8px;
      border-left: 3px solid #D4A853;
    }
    .aviso {
      color: #6A6A9A;
      font-size: 11px;
      text-align: center;
      margin-bottom: 20px;
    }
    label {
      display: block;
      color: #9E8FD8;
      font-size: 11px;
      letter-spacing: 1.5px;
      margin-bottom: 6px;
      margin-top: 18px;
    }
    input {
      width: 100%;
      padding: 13px 14px;
      background: #0F0F1A;
      border: 1px solid #3A3A5A;
      border-radius: 10px;
      color: #E8E8FF;
      font-size: 16px;
      outline: none;
      transition: border-color 0.2s;
    }
    input:focus { border-color: #7C6FCD; }
    button {
      width: 100%;
      padding: 15px;
      margin-top: 26px;
      background: linear-gradient(135deg, #7C6FCD, #5A4FAA);
      color: #fff;
      border: none;
      border-radius: 12px;
      font-size: 15px;
      font-weight: bold;
      font-family: Georgia, serif;
      letter-spacing: 2px;
      cursor: pointer;
      transition: opacity 0.2s;
    }
    button:active { opacity: 0.8; }
    .footer {
      text-align: center;
      margin-top: 20px;
      color: #3A3A5A;
      font-size: 10px;
      letter-spacing: 1px;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">UNIVERSIDAD AUNAR</div>
    <div class="icono">📚</div>
    <h1>SOLICITAR PRÉSTAMO</h1>
    <div class="libro">$tituloLegible</div>
    <div class="aviso">El bibliotecario recibirá tu solicitud en segundos</div>
    <form method="POST" action="/prestar">
      <input type="hidden" name="id" value="$libroId">
      <input type="hidden" name="titulo" value="$titulo">
      <label>NOMBRE COMPLETO</label>
      <input type="text" name="nombre" placeholder="Tu nombre completo" required autocomplete="name" autofocus>
      <label>NÚMERO DE CÉDULA</label>
      <input type="number" name="cedula" placeholder="Tu número de cédula" required inputmode="numeric">
      <button type="submit">✉ ENVIAR SOLICITUD</button>
    </form>
    <div class="footer">BIBLIOTECA AUNAR — SISTEMA DE PRÉSTAMOS</div>
  </div>
</body>
</html>''';

  return Response.ok(html, headers: {'content-type': 'text/html; charset=utf-8'});
  } catch (e) {
    print('Error en _formularioPrestamo: $e');
    return Response.internalServerError(body: 'Error: $e');
  }
}

Future<Response> _registrarPrestamo(Request req) async {
  try {
    final body = await req.readAsString();
    final params = Uri.splitQueryString(body);
    final nombre = params['nombre']?.trim() ?? '';
    final cedula = params['cedula']?.trim() ?? '';
    final libroId = params['id']?.trim() ?? '';
    final titulo = params['titulo']?.trim() ?? '';

    if (nombre.isEmpty || cedula.isEmpty || libroId.isEmpty) {
      return Response(400, body: 'Datos incompletos');
    }

    final solicitud = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'libroId': libroId,
      'titulo': Uri.decodeComponent(titulo),
      'nombre': nombre,
      'cedula': cedula,
      'fecha': DateTime.now().toIso8601String(),
      'procesado': false,
    };

    _solicitudes.add(solicitud);
    print('[${DateTime.now().toIso8601String()}] Nueva solicitud: $nombre (CC: $cedula) → ${Uri.decodeComponent(titulo)}');

    final html = '''<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Solicitud enviada — Biblioteca AUNAR</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: Georgia, serif;
      background: #0F0F1A;
      color: #E8E8FF;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .card {
      background: #1A1A2E;
      border-radius: 16px;
      padding: 40px 28px;
      width: 100%;
      max-width: 400px;
      text-align: center;
      border: 1px solid #1A3A2A;
      box-shadow: 0 8px 32px rgba(93,191,133,0.1);
    }
    .check { font-size: 72px; margin-bottom: 20px; }
    h1 { color: #5DBF85; font-size: 20px; letter-spacing: 2px; margin-bottom: 16px; }
    .nombre { color: #E8E8FF; font-weight: bold; }
    .libro { color: #D4A853; font-style: italic; margin: 12px 0; }
    p { color: #9E8FD8; font-size: 13px; line-height: 1.7; }
    .aviso {
      margin-top: 20px;
      padding: 12px;
      background: rgba(93,191,133,0.08);
      border-radius: 8px;
      border: 1px solid rgba(93,191,133,0.2);
      color: #5DBF85;
      font-size: 12px;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="check">✅</div>
    <h1>SOLICITUD ENVIADA</h1>
    <p>Hola, <span class="nombre">$nombre</span>.</p>
    <p class="libro">${Uri.decodeComponent(titulo)}</p>
    <p>Tu solicitud de préstamo fue registrada exitosamente.</p>
    <div class="aviso">📱 El bibliotecario recibirá tu solicitud en segundos y procesará el préstamo.</div>
  </div>
</body>
</html>''';

    return Response.ok(html, headers: {'content-type': 'text/html; charset=utf-8'});
  } catch (e) {
    print('Error al registrar préstamo: $e');
    return Response.internalServerError(body: 'Error interno del servidor');
  }
}

Response _obtenerSolicitudes(Request req) {
  final pendientes = _solicitudes.where((s) => s['procesado'] == false).toList();
  return Response.ok(
    jsonEncode({'solicitudes': pendientes}),
    headers: {'content-type': 'application/json'},
  );
}

Future<Response> _confirmarSolicitud(Request req) async {
  try {
    final body = await req.readAsString();
    final params = jsonDecode(body) as Map<String, dynamic>;
    final solicitudId = params['id']?.toString() ?? '';

    for (final s in _solicitudes) {
      if (s['id'] == solicitudId) {
        s['procesado'] = true;
        break;
      }
    }
    print('[${DateTime.now().toIso8601String()}] Solicitud $solicitudId confirmada');
    return Response.ok(
      jsonEncode({'ok': true}),
      headers: {'content-type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(body: 'Error: $e');
  }
}
