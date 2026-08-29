import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

class ProcessPerformanceSnapshot {
  const ProcessPerformanceSnapshot({
    required this.timestamp,
    this.rssBytes,
    this.maxRssBytes,
    this.cpuTime,
  });

  final DateTime timestamp;
  final int? rssBytes;
  final int? maxRssBytes;
  final Duration? cpuTime;
}

class ProcessPerformanceSampler {
  ProcessPerformanceSnapshot sample() => ProcessPerformanceSnapshot(
        timestamp: DateTime.now(),
        rssBytes: ProcessInfo.currentRss,
        maxRssBytes: ProcessInfo.maxRss,
        cpuTime: _readProcessCpuTime(),
      );

  Duration? _readProcessCpuTime() {
    try {
      return Platform.isWindows ? _readWindowsCpuTime() : _readPosixCpuTime();
    } catch (_) {
      return null;
    }
  }

  Duration? _readPosixCpuTime() {
    final clockGetTime = DynamicLibrary.process().lookupFunction<
        Int32 Function(Int32, Pointer<_Timespec>),
        int Function(int, Pointer<_Timespec>)>('clock_gettime');
    final value = calloc<_Timespec>();
    try {
      final clockId = Platform.isMacOS || Platform.isIOS ? 12 : 2;
      if (clockGetTime(clockId, value) != 0) return null;
      return Duration(
        seconds: value.ref.seconds,
        microseconds: value.ref.nanoseconds ~/ 1000,
      );
    } finally {
      calloc.free(value);
    }
  }

  Duration? _readWindowsCpuTime() {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final getCurrentProcess = kernel32.lookupFunction<Pointer<Void> Function(),
        Pointer<Void> Function()>('GetCurrentProcess');
    final getProcessTimes = kernel32.lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<_FileTime>,
          Pointer<_FileTime>,
          Pointer<_FileTime>,
          Pointer<_FileTime>,
        ),
        int Function(
          Pointer<Void>,
          Pointer<_FileTime>,
          Pointer<_FileTime>,
          Pointer<_FileTime>,
          Pointer<_FileTime>,
        )>('GetProcessTimes');
    final creation = calloc<_FileTime>();
    final exit = calloc<_FileTime>();
    final kernel = calloc<_FileTime>();
    final user = calloc<_FileTime>();
    try {
      if (getProcessTimes(
            getCurrentProcess(),
            creation,
            exit,
            kernel,
            user,
          ) ==
          0) {
        return null;
      }
      final ticks = _fileTimeTicks(kernel.ref) + _fileTimeTicks(user.ref);
      return Duration(microseconds: ticks ~/ 10);
    } finally {
      calloc
        ..free(creation)
        ..free(exit)
        ..free(kernel)
        ..free(user);
    }
  }

  int _fileTimeTicks(_FileTime value) =>
      (value.highDateTime << 32) | value.lowDateTime;
}

final class _Timespec extends Struct {
  @IntPtr()
  external int seconds;

  @IntPtr()
  external int nanoseconds;
}

final class _FileTime extends Struct {
  @Uint32()
  external int lowDateTime;

  @Uint32()
  external int highDateTime;
}
