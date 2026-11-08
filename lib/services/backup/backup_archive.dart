import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

import '../../core/errors/app_errors.dart';
import 'backup_format.dart';

// Synchronous archive work. The archive package does blocking file I/O, so
// callers run these functions on a background isolate.

/// A file to store in the archive under [archivePath].
final class ArchiveSource {
  const ArchiveSource({required this.archivePath, required this.sourcePath});

  final String archivePath;
  final String sourcePath;
}

final class FileDigest {
  const FileDigest({required this.sizeBytes, required this.sha256});

  final int sizeBytes;
  final String sha256;
}

/// Streams [path] through SHA-256 without holding the file in memory.
FileDigest digestFile(String path) {
  final digest = _DigestSink();
  final input = sha256.startChunkedConversion(digest);
  final file = File(path).openSync();
  final buffer = Uint8List(_chunkBytes);
  var size = 0;
  try {
    while (true) {
      final read = file.readIntoSync(buffer);
      if (read == 0) break;
      size += read;
      input.add(Uint8List.sublistView(buffer, 0, read));
    }
  } finally {
    file.closeSync();
  }
  input.close();
  return FileDigest(sizeBytes: size, sha256: digest.value.toString());
}

/// Writes [sources] to a new ZIP at [outputPath] in the given order, without
/// compression: publications and covers are already compressed, and stored
/// entries are copied straight from disk instead of being buffered.
void writeBackupArchive(String outputPath, List<ArchiveSource> sources) {
  final encoder = ZipFileEncoder()
    ..create(outputPath, level: ZipFileEncoder.store);
  try {
    for (final source in sources) {
      encoder.addFileSync(File(source.sourcePath), source.archivePath);
    }
  } finally {
    encoder.closeSync();
  }
}

/// Checks a backup archive without extracting it (BACKUP_FORMAT.md §5.3,
/// §8.1 steps 2–4, §9): resource limits, entry types and paths, duplicates,
/// that `manifest.json` comes first and declares exactly the other entries,
/// and every entry's size and SHA-256. Returns the parsed manifest. Throws
/// [BackupError]; I/O failures surface as [FileSystemException].
///
/// Dataset contents are not parsed here.
BackupManifest verifyBackupArchive(
  String archivePath, {
  BackupLimits limits = const BackupLimits(),
}) {
  if (File(archivePath).lengthSync() > limits.maxArchiveBytes) {
    throw const BackupError(BackupErrorKind.limitExceeded, 'archive too big');
  }
  final input = InputFileStream(archivePath);
  try {
    final decoder = ZipDecoder();
    try {
      decoder.decodeStream(input, throwOnError: true);
    } on FormatException {
      throw const BackupError(BackupErrorKind.invalidArchive, 'not a zip');
    }
    final headers = decoder.directory.fileHeaders;
    if (headers.length > limits.maxEntries) {
      throw const BackupError(
        BackupErrorKind.limitExceeded,
        'too many entries',
      );
    }
    if (headers.isEmpty ||
        headers.first.filename != BackupFormat.manifestPath) {
      throw const BackupError(
        BackupErrorKind.invalidArchive,
        'manifest.json is not the first entry',
      );
    }

    final byName = <String, ZipFileHeader>{};
    var total = 0;
    for (final header in headers) {
      _checkHeader(header, limits);
      if (byName.putIfAbsent(header.filename, () => header) != header) {
        throw const BackupError(
          BackupErrorKind.invalidArchive,
          'duplicate entry',
        );
      }
      total += header.uncompressedSize;
    }
    if (total > limits.maxTotalBytes) {
      throw const BackupError(BackupErrorKind.limitExceeded, 'too much data');
    }

    final manifestHeader = headers.first;
    if (manifestHeader.uncompressedSize > limits.maxManifestBytes) {
      throw const BackupError(
        BackupErrorKind.limitExceeded,
        'manifest too big',
      );
    }
    final manifest = BackupManifest.parse(_readJson(manifestHeader));

    final declared = {for (final entry in manifest.entries) entry.path};
    if (declared.length != headers.length - 1 ||
        !headers.skip(1).every((h) => declared.contains(h.filename))) {
      throw const BackupError(
        BackupErrorKind.invalidArchive,
        'entries do not match the manifest',
      );
    }
    for (final entry in manifest.entries) {
      final header = byName[entry.path]!;
      if (entry.sizeBytes > limits.maxBytesFor(entry.role)) {
        throw const BackupError(BackupErrorKind.limitExceeded, 'entry too big');
      }
      if (header.uncompressedSize != entry.sizeBytes) {
        throw const BackupError(
          BackupErrorKind.checksumMismatch,
          'entry size does not match the manifest',
        );
      }
      final actual = _digestEntry(header);
      if (actual.sizeBytes != entry.sizeBytes ||
          actual.sha256 != entry.sha256) {
        throw const BackupError(
          BackupErrorKind.checksumMismatch,
          'entry digest does not match the manifest',
        );
      }
    }
    return manifest;
  } finally {
    input.closeSync();
  }
}

/// Verifies [archivePath] and returns its manifest with the bytes of every
/// dataset entry (each already checked against the manifest and bounded by
/// [BackupLimits.maxDataEntryBytes]).
({BackupManifest manifest, Map<String, List<int>> datasets}) loadBackupData(
  String archivePath, {
  BackupLimits limits = const BackupLimits(),
}) {
  final manifest = verifyBackupArchive(archivePath, limits: limits);
  final wanted = {
    for (final entry in manifest.entries)
      if (entry.role == BackupEntryRole.data) entry.path,
  };
  final datasets = <String, List<int>>{};
  _withHeaders(archivePath, (headers) {
    for (final header in headers) {
      if (wanted.contains(header.filename)) {
        datasets[header.filename] = _readBytes(header);
      }
    }
  });
  return (manifest: manifest, datasets: datasets);
}

/// One entry to extract to [destinationPath], which must not exist yet.
final class ExtractRequest {
  const ExtractRequest({required this.entry, required this.destinationPath});

  final BackupEntry entry;
  final String destinationPath;
}

/// Extracts the requested entries, hashing the bytes as they are written,
/// and fails with [BackupErrorKind.checksumMismatch] if any differs from
/// the manifest. Destination paths are chosen by the caller, never taken
/// from the archive. A failed entry's partial file is deleted; earlier
/// entries are left for the caller's staging cleanup.
void extractBackupEntries(String archivePath, List<ExtractRequest> requests) {
  _withHeaders(archivePath, (headers) {
    final byName = {for (final header in headers) header.filename: header};
    for (final request in requests) {
      final header = byName[request.entry.path];
      if (header == null) {
        throw const BackupError(
          BackupErrorKind.invalidArchive,
          'entry to extract is missing',
        );
      }
      final file = File(request.destinationPath);
      file.parent.createSync(recursive: true);
      final handle = file.openSync(mode: FileMode.writeOnly);
      final digest = _DigestSink();
      final hasher = sha256.startChunkedConversion(digest);
      final output = SinkOutputStream(_FileSink(handle))..watch = hasher.add;
      var complete = false;
      try {
        try {
          header.file!
            ..verify = true
            ..throwOnError = true
            ..decompress(output);
          output.flush();
        } on FormatException {
          throw const BackupError(
            BackupErrorKind.checksumMismatch,
            'entry data is corrupt',
          );
        }
        hasher.close();
        if (output.length != request.entry.sizeBytes ||
            digest.value.toString() != request.entry.sha256) {
          throw const BackupError(
            BackupErrorKind.checksumMismatch,
            'extracted entry does not match the manifest',
          );
        }
        complete = true;
      } finally {
        handle.closeSync();
        if (!complete && file.existsSync()) file.deleteSync();
      }
    }
  });
}

void _withHeaders(
  String archivePath,
  void Function(List<ZipFileHeader> headers) body,
) {
  final input = InputFileStream(archivePath);
  try {
    final decoder = ZipDecoder();
    try {
      decoder.decodeStream(input, throwOnError: true);
    } on FormatException {
      throw const BackupError(BackupErrorKind.invalidArchive, 'not a zip');
    }
    body(decoder.directory.fileHeaders);
  } finally {
    input.closeSync();
  }
}

const int _chunkBytes = 1 << 20;
const int _ratioCheckMinBytes = 1 << 20;
const int _unixFileTypeMask = 0xF000;
const int _unixRegularFile = 0x8000;
const int _hostUnix = 3;

void _checkHeader(ZipFileHeader header, BackupLimits limits) {
  final name = header.filename;
  if (!isSafeArchivePath(name)) {
    throw const BackupError(BackupErrorKind.invalidArchive, 'unsafe path');
  }
  // Only regular files: directories, symlinks and special entries are
  // rejected (§9.1). Archives from non-Unix hosts carry no file type.
  final unixType = (header.externalFileAttributes >> 16) & _unixFileTypeMask;
  if (header.versionMadeBy >> 8 == _hostUnix &&
      unixType != 0 &&
      unixType != _unixRegularFile) {
    throw const BackupError(
      BackupErrorKind.invalidArchive,
      'entry is not a regular file',
    );
  }
  if (header.generalPurposeBitFlag & 1 != 0) {
    throw const BackupError(BackupErrorKind.invalidArchive, 'encrypted entry');
  }
  final method = header.compressionMethod;
  if (method != ZipFile.zipCompressionStore &&
      method != ZipFile.zipCompressionDeflate) {
    throw const BackupError(
      BackupErrorKind.invalidArchive,
      'unsupported compression method',
    );
  }
  final size = header.uncompressedSize;
  final compressed = header.compressedSize;
  if (size < 0 || compressed < 0) {
    throw const BackupError(BackupErrorKind.invalidArchive, 'negative size');
  }
  if (method == ZipFile.zipCompressionDeflate &&
      size > _ratioCheckMinBytes &&
      size > compressed * limits.maxCompressionRatio) {
    throw const BackupError(
      BackupErrorKind.limitExceeded,
      'compression ratio too high',
    );
  }
}

/// Decompresses one entry through SHA-256. The archive package stops at the
/// entry's declared size, so a lying header cannot make this run unbounded.
FileDigest _digestEntry(ZipFileHeader header) {
  final digest = _DigestSink();
  final input = sha256.startChunkedConversion(digest);
  final output = SinkOutputStream(input);
  try {
    final file = header.file;
    if (file == null) {
      throw const BackupError(BackupErrorKind.invalidArchive, 'no entry data');
    }
    file
      ..verify = true
      ..throwOnError = true
      ..decompress(output);
    output.flush();
  } on FormatException {
    // ArchiveException (corrupt data, CRC or size mismatch) is a
    // FormatException.
    throw const BackupError(
      BackupErrorKind.checksumMismatch,
      'entry data is corrupt',
    );
  }
  input.close();
  return FileDigest(sizeBytes: output.length, sha256: digest.value.toString());
}

List<int> _readBytes(ZipFileHeader header) {
  final collected = BytesBuilder(copy: false);
  final output = SinkOutputStream(_BytesSink(collected));
  try {
    header.file!
      ..verify = true
      ..throwOnError = true
      ..decompress(output);
    output.flush();
  } on FormatException {
    throw const BackupError(
      BackupErrorKind.checksumMismatch,
      'entry data is corrupt',
    );
  }
  return collected.takeBytes();
}

Object? _readJson(ZipFileHeader header) {
  try {
    return jsonDecode(utf8.decode(_readBytes(header)));
  } on FormatException {
    throw const BackupError(
      BackupErrorKind.invalidArchive,
      'manifest is not valid UTF-8 JSON',
    );
  }
}

final class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value => _value!;

  @override
  void add(Digest data) => _value = data;

  @override
  void close() {}
}

final class _BytesSink implements Sink<List<int>> {
  _BytesSink(this._builder);

  final BytesBuilder _builder;

  @override
  void add(List<int> data) => _builder.add(data);

  @override
  void close() {}
}

final class _FileSink implements Sink<List<int>> {
  _FileSink(this._file);

  final RandomAccessFile _file;

  @override
  void add(List<int> data) => _file.writeFromSync(data);

  @override
  void close() {}
}
