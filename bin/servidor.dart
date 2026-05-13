import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

final List<Map<String, dynamic>> _solicitudes = [];
final List<Map<String, dynamic>> _devoluciones = [];

void main() async {
  final puerto = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;

  final router = Router()
    ..get('/', _estado)
    ..get('/estado', _estado)
    ..get('/prestar', _formulario)
    ..post('/prestar', _registrarPrestamo)
    ..post('/devolver', _registrarDevolucion)
    ..get('/solicitudes', _obtenerSolicitudes)
    ..post('/solicitudes/confirmar', _confirmarSolicitud)
    ..get('/devoluciones', _obtenerDevoluciones)
    ..post('/devoluciones/confirmar', _confirmarDevolucion);

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_cors())
      .addHandler(router.call);

  final server = await io.serve(handler, InternetAddress.anyIPv4, puerto);
  print('Biblioteca AUNAR — puerto ${server.port}');
}

Middleware _cors() => (handler) => (req) async {
      if (req.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders());
      }
      return (await handler(req)).change(headers: _corsHeaders());
    };

Map<String, String> _corsHeaders() => {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    };

String _b64decode(String b64) {
  try {
    final normalized = b64.replaceAll('-', '+').replaceAll('_', '/');
    final padded = normalized.padRight((normalized.length + 3) ~/ 4 * 4, '=');
    return utf8.decode(base64.decode(padded));
  } catch (_) {
    return b64;
  }
}

Response _estado(Request req) => Response.ok(
      jsonEncode({
        'estado': 'activo',
        'hora': DateTime.now().toIso8601String(),
        'solicitudesPendientes': _solicitudes.where((s) => s['procesado'] == false).length,
        'devolucionesPendientes': _devoluciones.where((d) => d['procesado'] == false).length,
      }),
      headers: {'content-type': 'application/json'},
    );

Response _formulario(Request req) {
  final libroId = req.url.queryParameters['id'] ?? '';
  final tituloB64 = req.url.queryParameters['t'] ?? '';
  final tituloLegible = tituloB64.isNotEmpty ? _b64decode(tituloB64) : 'Libro de biblioteca';

  final html = '''<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Biblioteca AUNAR</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: Georgia, serif; background: #0F0F1A; color: #E8E8FF;
      min-height: 100vh; display: flex; align-items: center;
      justify-content: center; padding: 20px; }
    .card { background: #1A1A2E; border-radius: 16px; padding: 32px 28px;
      width: 100%; max-width: 420px; border: 1px solid #2A2A3E;
      box-shadow: 0 8px 32px rgba(124,111,205,0.15); }
    .logo { text-align: center; font-size: 13px; color: #D4A853;
      letter-spacing: 3px; margin-bottom: 4px; }
    .icono { text-align: center; font-size: 48px; margin: 10px 0; }
    .libro { color: #D4A853; font-style: italic; text-align: center;
      font-size: 15px; margin: 12px 0; padding: 8px 12px;
      background: rgba(212,168,83,0.08); border-radius: 8px;
      border-left: 3px solid #D4A853; }
    .opciones { display: flex; gap: 12px; margin: 20px 0; }
    .btn-opcion { flex: 1; padding: 16px 8px; border: 2px solid;
      border-radius: 12px; cursor: pointer; font-size: 13px; font-weight: bold;
      font-family: Georgia, serif; letter-spacing: 1px; transition: all 0.2s;
      background: transparent; }
    .btn-prestamo { border-color: #7C6FCD; color: #7C6FCD; }
    .btn-prestamo:hover, .btn-prestamo.activo { background: #7C6FCD; color: #fff; }
    .btn-devolucion { border-color: #5DBF85; color: #5DBF85; }
    .btn-devolucion:hover, .btn-devolucion.activo { background: #5DBF85; color: #0D0D0D; }
    .form-seccion { display: none; }
    .form-seccion.visible { display: block; }
    label { display: block; color: #9E8FD8; font-size: 11px;
      letter-spacing: 1.5px; margin-bottom: 6px; margin-top: 18px; }
    input[type=text], input[type=number] { width: 100%; padding: 13px 14px;
      background: #0F0F1A; border: 1px solid #3A3A5A; border-radius: 10px;
      color: #E8E8FF; font-size: 16px; outline: none; transition: border-color 0.2s; }
    input:focus { border-color: #7C6FCD; }
    .btn-enviar { width: 100%; padding: 15px; margin-top: 26px;
      border: none; border-radius: 12px; font-size: 15px; font-weight: bold;
      font-family: Georgia, serif; letter-spacing: 2px; cursor: pointer;
      transition: opacity 0.2s; color: #fff; }
    .btn-enviar-prestamo { background: linear-gradient(135deg, #7C6FCD, #5A4FAA); }
    .btn-enviar-devolucion { background: linear-gradient(135deg, #5DBF85, #3A9E66); color: #0D0D0D; }
    .btn-enviar:active { opacity: 0.8; }
    .aviso { color: #6A6A9A; font-size: 11px; text-align: center; margin-top: 10px; }
    .footer { text-align: center; margin-top: 20px; color: #3A3A5A;
      font-size: 10px; letter-spacing: 1px; }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">UNIVERSIDAD AUNAR</div>
    <div class="icono">&#128218;</div>
    <div class="libro">$tituloLegible</div>

    <div class="opciones">
      <button class="btn-opcion btn-prestamo activo" onclick="mostrar('prestamo')" id="tab-prestamo">
        &#128222; PRESTAR
      </button>
      <button class="btn-opcion btn-devolucion" onclick="mostrar('devolucion')" id="tab-devolucion">
        &#10003; DEVOLVER
      </button>
    </div>

    <div id="form-prestamo" class="form-seccion visible">
      <form method="POST" action="/prestar">
        <input type="hidden" name="id" value="$libroId">
        <input type="hidden" name="t" value="$tituloB64">
        <label>NOMBRE COMPLETO</label>
        <input type="text" name="nombre" placeholder="Tu nombre completo"
          required autocomplete="name">
        <label>NUMERO DE CEDULA</label>
        <input type="number" name="cedula" placeholder="Tu numero de cedula"
          required inputmode="numeric">
        <p class="aviso">El bibliotecario recibira tu solicitud en segundos</p>
        <button type="submit" class="btn-enviar btn-enviar-prestamo">SOLICITAR PRESTAMO</button>
      </form>
    </div>

    <div id="form-devolucion" class="form-seccion">
      <form method="POST" action="/devolver">
        <input type="hidden" name="id" value="$libroId">
        <input type="hidden" name="t" value="$tituloB64">
        <label>NUMERO DE CEDULA</label>
        <input type="number" name="cedula" placeholder="Tu numero de cedula"
          required inputmode="numeric" autofocus>
        <p class="aviso">La devolucion se registrara automaticamente</p>
        <button type="submit" class="btn-enviar btn-enviar-devolucion">CONFIRMAR DEVOLUCION</button>
      </form>
    </div>

    <div class="footer">BIBLIOTECA AUNAR - SISTEMA DE PRESTAMOS</div>
  </div>
  <script>
    function mostrar(tipo) {
      document.getElementById('form-prestamo').classList.toggle('visible', tipo === 'prestamo');
      document.getElementById('form-devolucion').classList.toggle('visible', tipo === 'devolucion');
      document.getElementById('tab-prestamo').classList.toggle('activo', tipo === 'prestamo');
      document.getElementById('tab-devolucion').classList.toggle('activo', tipo === 'devolucion');
    }
  </script>
</body>
</html>''';

  return Response.ok(html, headers: {'content-type': 'text/html; charset=utf-8'});
}

Future<Response> _registrarPrestamo(Request req) async {
  try {
    final body = await req.readAsString();
    final params = Uri.splitQueryString(body);
    final nombre = params['nombre']?.trim() ?? '';
    final cedula = params['cedula']?.trim() ?? '';
    final libroId = params['id']?.trim() ?? '';
    final tituloB64 = params['t']?.trim() ?? '';
    final titulo = tituloB64.isNotEmpty ? _b64decode(tituloB64) : 'Libro de biblioteca';

    if (nombre.isEmpty || cedula.isEmpty || libroId.isEmpty) {
      return Response(400, body: 'Datos incompletos');
    }

    _solicitudes.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'libroId': libroId,
      'titulo': titulo,
      'nombre': nombre,
      'cedula': cedula,
      'fecha': DateTime.now().toIso8601String(),
      'procesado': false,
    });

    print('Solicitud prestamo: $nombre (CC $cedula) -> $titulo');
    return Response.ok(_paginaExito('SOLICITUD ENVIADA',
        'Hola, <span class="nombre">$nombre</span>.',
        titulo,
        'El bibliotecario recibira tu solicitud en segundos y procesara el prestamo.',
        '#5DBF85'),
      headers: {'content-type': 'text/html; charset=utf-8'});
  } catch (e) {
    print('Error prestamo: $e');
    return Response.internalServerError(body: 'Error: $e');
  }
}

Future<Response> _registrarDevolucion(Request req) async {
  try {
    final body = await req.readAsString();
    final params = Uri.splitQueryString(body);
    final cedula = params['cedula']?.trim() ?? '';
    final libroId = params['id']?.trim() ?? '';
    final tituloB64 = params['t']?.trim() ?? '';
    final titulo = tituloB64.isNotEmpty ? _b64decode(tituloB64) : 'Libro de biblioteca';

    if (cedula.isEmpty || libroId.isEmpty) {
      return Response(400, body: 'Datos incompletos');
    }

    _devoluciones.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'libroId': libroId,
      'titulo': titulo,
      'cedula': cedula,
      'fecha': DateTime.now().toIso8601String(),
      'procesado': false,
    });

    print('Solicitud devolucion: CC $cedula -> $titulo');
    return Response.ok(_paginaExito('DEVOLUCION REGISTRADA',
        'Cedula: <span class="nombre">$cedula</span>',
        titulo,
        'La devolucion sera procesada automaticamente. Gracias.',
        '#4FC3F7'),
      headers: {'content-type': 'text/html; charset=utf-8'});
  } catch (e) {
    print('Error devolucion: $e');
    return Response.internalServerError(body: 'Error: $e');
  }
}

String _paginaExito(String titulo, String saludo, String libro, String mensaje, String color) =>
    '''<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$titulo</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: Georgia, serif; background: #0F0F1A; color: #E8E8FF;
      min-height: 100vh; display: flex; align-items: center;
      justify-content: center; padding: 20px; }
    .card { background: #1A1A2E; border-radius: 16px; padding: 40px 28px;
      width: 100%; max-width: 400px; text-align: center; }
    .check { font-size: 64px; margin-bottom: 16px; }
    h1 { color: $color; font-size: 18px; letter-spacing: 2px; margin-bottom: 16px; }
    .nombre { color: #E8E8FF; font-weight: bold; }
    .libro { color: #D4A853; font-style: italic; margin: 12px 0; }
    p { color: #9E8FD8; font-size: 13px; line-height: 1.7; }
    .aviso { margin-top: 20px; padding: 12px; border-radius: 8px;
      background: rgba(79,195,247,0.08); border: 1px solid rgba(79,195,247,0.2);
      color: $color; font-size: 12px; }
  </style>
</head>
<body>
  <div class="card">
    <div class="check">&#10003;</div>
    <h1>$titulo</h1>
    <p>$saludo</p>
    <p class="libro">$libro</p>
    <div class="aviso">$mensaje</div>
  </div>
</body>
</html>''';

Response _obtenerSolicitudes(Request req) {
  final pendientes = _solicitudes.where((s) => s['procesado'] == false).toList();
  return Response.ok(jsonEncode({'solicitudes': pendientes}),
      headers: {'content-type': 'application/json'});
}

Future<Response> _confirmarSolicitud(Request req) async {
  try {
    final params = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final id = params['id']?.toString() ?? '';
    for (final s in _solicitudes) {
      if (s['id'] == id) { s['procesado'] = true; break; }
    }
    return Response.ok(jsonEncode({'ok': true}),
        headers: {'content-type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(body: 'Error: $e');
  }
}

Response _obtenerDevoluciones(Request req) {
  final pendientes = _devoluciones.where((d) => d['procesado'] == false).toList();
  return Response.ok(jsonEncode({'devoluciones': pendientes}),
      headers: {'content-type': 'application/json'});
}

Future<Response> _confirmarDevolucion(Request req) async {
  try {
    final params = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final id = params['id']?.toString() ?? '';
    for (final d in _devoluciones) {
      if (d['id'] == id) { d['procesado'] = true; break; }
    }
    return Response.ok(jsonEncode({'ok': true}),
        headers: {'content-type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(body: 'Error: $e');
  }
}
