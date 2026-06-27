import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/club_error.dart';

/// Downloads raw artwork bytes from a vault URL (public; no auth) so the editor
/// can open a Club artwork for remix/replace.
class EditApi {
  final Dio _dio;
  EditApi([Dio? dio]) : _dio = dio ?? Dio();

  Future<Uint8List> downloadArtwork(String url) async {
    try {
      final resp = await _dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
      return Uint8List.fromList(resp.data ?? const []);
    } on DioException catch (e) {
      throw ClubError.fromDio(e);
    }
  }
}
