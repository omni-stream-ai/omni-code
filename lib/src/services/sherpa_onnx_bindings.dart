import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

final DynamicLibrary _lib = _loadLibrary();

DynamicLibrary _loadLibrary() {
  if (Platform.isLinux) {
    return _openBundledLinuxLibrary('libsherpa-onnx-c-api.so');
  } else if (Platform.isAndroid) {
    return DynamicLibrary.open('libsherpa-onnx-c-api.so');
  } else if (Platform.isWindows) {
    return DynamicLibrary.open('sherpa-onnx-c-api.dll');
  } else if (Platform.isMacOS) {
    return DynamicLibrary.open('libsherpa-onnx-c-api.dylib');
  } else if (Platform.isIOS) {
    return DynamicLibrary.process();
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

DynamicLibrary _openBundledLinuxLibrary(String libraryName) {
  final executableDir = File(Platform.resolvedExecutable).parent.path;
  final bundledLibDirs = [
    '$executableDir/lib',
    '${Directory.current.path}/build/linux/x64/debug/bundle/lib',
  ];
  for (final dependencyName in [
    'libonnxruntime.so',
    'libsherpa-onnx-cxx-api.so',
  ]) {
    for (final bundledLibDir in bundledLibDirs) {
      final dependencyPath = '$bundledLibDir/$dependencyName';
      if (File(dependencyPath).existsSync()) {
        DynamicLibrary.open(dependencyPath);
        break;
      }
    }
  }
  for (final bundledLibDir in bundledLibDirs) {
    final bundledPath = '$bundledLibDir/$libraryName';
    if (File(bundledPath).existsSync()) {
      return DynamicLibrary.open(bundledPath);
    }
  }
  return DynamicLibrary.open(libraryName);
}

// Feature config
final class SherpaOnnxFeatureConfig extends Struct {
  @Int32()
  external int sampleRate;

  @Int32()
  external int featureDim;
}

// Online transducer model config
final class SherpaOnnxOnlineTransducerModelConfig extends Struct {
  external Pointer<Utf8> encoder;
  external Pointer<Utf8> decoder;
  external Pointer<Utf8> joiner;
}

// Online paraformer model config
final class SherpaOnnxOnlineParaformerModelConfig extends Struct {
  external Pointer<Utf8> encoder;
  external Pointer<Utf8> decoder;
}

// Online Zipformer2 CTC model config
final class SherpaOnnxOnlineZipformer2CtcModelConfig extends Struct {
  external Pointer<Utf8> model;
}

// Online NeMo CTC model config
final class SherpaOnnxOnlineNemoCtcModelConfig extends Struct {
  external Pointer<Utf8> model;
}

// Online T-One CTC model config
final class SherpaOnnxOnlineToneCtcModelConfig extends Struct {
  external Pointer<Utf8> model;
}

// Online model config
final class SherpaOnnxOnlineModelConfig extends Struct {
  external SherpaOnnxOnlineTransducerModelConfig transducer;
  external SherpaOnnxOnlineParaformerModelConfig paraformer;
  external SherpaOnnxOnlineZipformer2CtcModelConfig zipformer2Ctc;
  external Pointer<Utf8> tokens;
  @Int32()
  external int numThreads;
  external Pointer<Utf8> provider;
  @Int32()
  external int debug;
  external Pointer<Utf8> modelType;
  external Pointer<Utf8> modelingUnit;
  external Pointer<Utf8> bpeVocab;
  external Pointer<Utf8> tokensBuf;
  @Int32()
  external int tokensBufSize;
  external SherpaOnnxOnlineNemoCtcModelConfig nemoCtc;
  external SherpaOnnxOnlineToneCtcModelConfig tOneCtc;
}

// Keyword spotter config
final class SherpaOnnxKeywordSpotterConfig extends Struct {
  external SherpaOnnxFeatureConfig featConfig;
  external SherpaOnnxOnlineModelConfig modelConfig;
  @Int32()
  external int maxActivePaths;
  @Int32()
  external int numTrailingBlanks;
  @Float()
  external double keywordsScore;
  @Float()
  external double keywordsThreshold;
  external Pointer<Utf8> keywordsFile;
  external Pointer<Utf8> keywordsBuf;
  @Int32()
  external int keywordsBufSize;
}

// Keyword result
final class SherpaOnnxKeywordResult extends Struct {
  external Pointer<Utf8> keyword;
  external Pointer<Utf8> tokens;
  external Pointer<Pointer<Utf8>> tokensArr;
  @Int32()
  external int count;
  external Pointer<Float> timestamps;
  @Float()
  external double startTime;
  external Pointer<Utf8> json;
}

// Function bindings
typedef CreateKeywordSpotterNative = Pointer<Void> Function(
    Pointer<SherpaOnnxKeywordSpotterConfig> config);
typedef CreateKeywordSpotterDart = Pointer<Void> Function(
    Pointer<SherpaOnnxKeywordSpotterConfig> config);

typedef DestroyKeywordSpotterNative = Void Function(Pointer<Void> spotter);
typedef DestroyKeywordSpotterDart = void Function(Pointer<Void> spotter);

typedef CreateKeywordStreamNative = Pointer<Void> Function(
    Pointer<Void> spotter);
typedef CreateKeywordStreamDart = Pointer<Void> Function(Pointer<Void> spotter);

typedef DestroyOnlineStreamNative = Void Function(Pointer<Void> stream);
typedef DestroyOnlineStreamDart = void Function(Pointer<Void> stream);

typedef AcceptWaveformNative = Void Function(
    Pointer<Void> stream, Int32 sampleRate, Pointer<Float> samples, Int32 n);
typedef AcceptWaveformDart = void Function(
    Pointer<Void> stream, int sampleRate, Pointer<Float> samples, int n);

typedef DecodeKeywordStreamNative = Void Function(
    Pointer<Void> spotter, Pointer<Void> stream);
typedef DecodeKeywordStreamDart = void Function(
    Pointer<Void> spotter, Pointer<Void> stream);

typedef IsStreamReadyNative = Int32 Function(
    Pointer<Void> spotter, Pointer<Void> stream);
typedef IsStreamReadyDart = int Function(
    Pointer<Void> spotter, Pointer<Void> stream);

typedef GetKeywordResultNative = Pointer<SherpaOnnxKeywordResult> Function(
    Pointer<Void> spotter, Pointer<Void> stream);
typedef GetKeywordResultDart = Pointer<SherpaOnnxKeywordResult> Function(
    Pointer<Void> spotter, Pointer<Void> stream);

typedef DestroyKeywordResultNative = Void Function(
    Pointer<SherpaOnnxKeywordResult> result);
typedef DestroyKeywordResultDart = void Function(
    Pointer<SherpaOnnxKeywordResult> result);

typedef GetKeywordResultJsonNative = Pointer<Utf8> Function(
    Pointer<Void> spotter, Pointer<Void> stream);
typedef GetKeywordResultJsonDart = Pointer<Utf8> Function(
    Pointer<Void> spotter, Pointer<Void> stream);

typedef FreeKeywordResultJsonNative = Void Function(Pointer<Utf8> result);
typedef FreeKeywordResultJsonDart = void Function(Pointer<Utf8> result);

typedef ResetStreamNative = Void Function(
    Pointer<Void> spotter, Pointer<Void> stream);
typedef ResetStreamDart = void Function(
    Pointer<Void> spotter, Pointer<Void> stream);

// Bindings
final createKeywordSpotter =
    _lib.lookupFunction<CreateKeywordSpotterNative, CreateKeywordSpotterDart>(
        'SherpaOnnxCreateKeywordSpotter');

final destroyKeywordSpotter =
    _lib.lookupFunction<DestroyKeywordSpotterNative, DestroyKeywordSpotterDart>(
        'SherpaOnnxDestroyKeywordSpotter');

final createKeywordStream =
    _lib.lookupFunction<CreateKeywordStreamNative, CreateKeywordStreamDart>(
        'SherpaOnnxCreateKeywordStream');

final destroyOnlineStream =
    _lib.lookupFunction<DestroyOnlineStreamNative, DestroyOnlineStreamDart>(
        'SherpaOnnxDestroyOnlineStream');

final acceptWaveform =
    _lib.lookupFunction<AcceptWaveformNative, AcceptWaveformDart>(
        'SherpaOnnxOnlineStreamAcceptWaveform');

final decodeKeywordStream =
    _lib.lookupFunction<DecodeKeywordStreamNative, DecodeKeywordStreamDart>(
        'SherpaOnnxDecodeKeywordStream');

final isStreamReady =
    _lib.lookupFunction<IsStreamReadyNative, IsStreamReadyDart>(
        'SherpaOnnxIsKeywordStreamReady');

final getKeywordResult =
    _lib.lookupFunction<GetKeywordResultNative, GetKeywordResultDart>(
        'SherpaOnnxGetKeywordResult');

final destroyKeywordResult =
    _lib.lookupFunction<DestroyKeywordResultNative, DestroyKeywordResultDart>(
        'SherpaOnnxDestroyKeywordResult');

final getKeywordResultJson =
    _lib.lookupFunction<GetKeywordResultJsonNative, GetKeywordResultJsonDart>(
        'SherpaOnnxGetKeywordResultAsJson');

final freeKeywordResultJson =
    _lib.lookupFunction<FreeKeywordResultJsonNative, FreeKeywordResultJsonDart>(
        'SherpaOnnxFreeKeywordResultJson');

final resetStream = _lib.lookupFunction<ResetStreamNative, ResetStreamDart>(
    'SherpaOnnxResetKeywordStream');

// Helper to create a config
Pointer<SherpaOnnxKeywordSpotterConfig> createKeywordSpotterConfig({
  required String encoderPath,
  required String decoderPath,
  required String joinerPath,
  required String tokensPath,
  required String keywords,
  int numThreads = 1,
  double keywordsScore = 3.0,
  double keywordsThreshold = 0.1,
}) {
  final config = calloc<SherpaOnnxKeywordSpotterConfig>();

  config.ref.featConfig.sampleRate = 16000;
  config.ref.featConfig.featureDim = 80;

  config.ref.modelConfig.transducer.encoder = encoderPath.toNativeUtf8();
  config.ref.modelConfig.transducer.decoder = decoderPath.toNativeUtf8();
  config.ref.modelConfig.transducer.joiner = joinerPath.toNativeUtf8();
  config.ref.modelConfig.tokens = tokensPath.toNativeUtf8();
  config.ref.modelConfig.numThreads = numThreads;
  config.ref.modelConfig.provider = 'cpu'.toNativeUtf8();
  config.ref.modelConfig.debug = 0;

  config.ref.maxActivePaths = 4;
  config.ref.numTrailingBlanks = 1;
  config.ref.keywordsScore = keywordsScore;
  config.ref.keywordsThreshold = keywordsThreshold;
  config.ref.keywordsBuf = keywords.toNativeUtf8();
  config.ref.keywordsBufSize = keywords.length;

  return config;
}

void freeKeywordSpotterConfig(Pointer<SherpaOnnxKeywordSpotterConfig> config) {
  calloc.free(config.ref.modelConfig.transducer.encoder);
  calloc.free(config.ref.modelConfig.transducer.decoder);
  calloc.free(config.ref.modelConfig.transducer.joiner);
  calloc.free(config.ref.modelConfig.tokens);
  calloc.free(config.ref.modelConfig.provider);
  if (config.ref.keywordsBuf != nullptr) {
    calloc.free(config.ref.keywordsBuf);
  }
  calloc.free(config);
}
