import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiService {
  ApiService._internal();

  static final ApiService instance = ApiService._internal();

  String baseUrl = '';
  String? _bearerToken;

  void init({required String url, String? bearerToken}) {
    baseUrl = url;
    _bearerToken = bearerToken;
  }

  void setBaseUrl(String url) => baseUrl = url;

  void setBearerToken(String token) => _bearerToken = token;

  Map<String, String> _defaultHeaders({Map<String, String>? extra}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_bearerToken != null && _bearerToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_bearerToken';
    }
    if (extra != null) {
      headers.addAll(extra);
    }
    return headers;
  }

  Uri _buildUri(String endpoint, [Map<String, dynamic>? query]) {
    final uri = baseUrl.isEmpty ? Uri.parse(endpoint) : Uri.parse(baseUrl + endpoint);
    if (query != null && query.isNotEmpty) {
      return uri.replace(queryParameters: query.map((k, v) => MapEntry(k, v.toString())));
    }
    return uri;
  }

  Future<http.Response> get(String endpoint, {Map<String, dynamic>? query, Map<String, String>? headers}) {
    final uri = _buildUri(endpoint, query);
    return http.get(uri, headers: _defaultHeaders(extra: headers));
  }

  Future<http.Response> post(String endpoint, {dynamic body, Map<String, String>? headers}) {
    final uri = _buildUri(endpoint);
    return http.post(uri, headers: _defaultHeaders(extra: headers), body: body == null ? null : jsonEncode(body));
  }

  Future<http.Response> put(String endpoint, {dynamic body, Map<String, String>? headers}) {
    final uri = _buildUri(endpoint);
    return http.put(uri, headers: _defaultHeaders(extra: headers), body: body == null ? null : jsonEncode(body));
  }

  Future<http.Response> patch(String endpoint, {dynamic body, Map<String, String>? headers}) {
    final uri = _buildUri(endpoint);
    return http.patch(uri, headers: _defaultHeaders(extra: headers), body: body == null ? null : jsonEncode(body));
  }

  Future<http.Response> delete(String endpoint, {dynamic body, Map<String, String>? headers}) {
    final uri = _buildUri(endpoint);
    return http.delete(uri, headers: _defaultHeaders(extra: headers), body: body == null ? null : jsonEncode(body));
  }

  T decodeJson<T>(http.Response response) {
    final dynamic data = jsonDecode(response.body);
    return data as T;
  }
}
