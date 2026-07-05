import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await RustBuilder(
      assetName: 'generated/frb_generated.dart',
      cratePath: 'rust',
      extraCargoEnvironmentVariables: input.config.buildCodeAssets
          ? _cargoEnvironmentFor(input.config.code)
          : const {},
    ).run(input: input, output: output);
  });
}

Map<String, String> _cargoEnvironmentFor(CodeConfig codeConfig) {
  if (codeConfig.targetOS == OS.iOS) {
    final deploymentTarget = Platform.environment['IPHONEOS_DEPLOYMENT_TARGET'];
    final configuredTarget = '${codeConfig.iOS.targetVersion}.0';
    return {
      'IPHONEOS_DEPLOYMENT_TARGET':
          deploymentTarget == null || deploymentTarget.isEmpty
          ? configuredTarget
          : deploymentTarget,
    };
  }

  return const {};
}
