Drop the Android AARs here:

  engine-release.aar          from vendor/nuvio-engine/platform/android/engine/build/outputs/aar/
  nuvio-libass-release.aar    optional, from vendor/nuvio-libass/build/outputs/aar/

scripts/build-android.sh copies both in for you. Without engine-release.aar the
:app module does not compile, because MainActivity imports com.nuvio.engine.*.

*.aar is gitignored. When nuvio-libass is present, also stage
app/src/main/jniLibs/<abi>/libc++_shared.so from the NDK — the libass AAR
excludes it on purpose.
