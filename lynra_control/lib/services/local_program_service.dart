import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import '../models/control_program.dart';

class LocalProgramService {
  static Future<Directory> _directory() async {
    final root = await getApplicationDocumentsDirectory();

    final dir = Directory(
      '${root.path}${Platform.pathSeparator}programs',
    );

    await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _file(String id) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw ArgumentError('Invalid program ID');
    }

    final dir = await _directory();

    return File(
      '${dir.path}${Platform.pathSeparator}$id.lynra',
    );
  }

  static Future<String> save(
    ControlProgram program, {
    String? id,
  }) async {
    final programId =
        id ?? DateTime.now().microsecondsSinceEpoch.toString();

    final file = await _file(programId);

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(program.toJson()),
      flush: true,
    );

    return programId;
  }

  static Future<ControlProgram> load(String id) async {
    final file = await _file(id);

    final data = jsonDecode(await file.readAsString());

    return ControlProgram.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
  }
	
	static Future<List<({String id, String name})>> listPrograms() async {
  final dir = await _directory();

  final programs = <({String id, String name})>[];

  await for (final entity in dir.list()) {
    if (entity is! File || !entity.path.endsWith('.lynra')) {
      continue;
    }

    try {
      final filename = entity.path.split(Platform.pathSeparator).last;
      final id = filename.substring(0, filename.length - 6);

      final program = await load(id);

      programs.add((
        id: id,
        name: program.name,
      ));
    } catch (e) {
      // Bozuk veya uyumsuz program dosyasını atla.
      continue;
    }
  }

  programs.sort(
    (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  );

  return programs;
}
static Future<void> delete(String id) async {
  final file = await _file(id);

  if (await file.exists()) {
    await file.delete();
  }
}
static Future<void> rename(String id, String newName) async {
  final name = newName.trim();

  if (name.isEmpty) {
    throw ArgumentError('Program adı boş olamaz.');
  }

  final file = await _file(id);

  final data = Map<String, dynamic>.from(
    jsonDecode(await file.readAsString()) as Map,
  );

  data['name'] = name;

  await file.writeAsString(
    const JsonEncoder.withIndent(' ').convert(data),
    flush: true,
  );
}
}