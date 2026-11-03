{{flutter_js}}
{{flutter_build_config}}

// Load CanvasKit and the fallback fonts from this server instead of a CDN,
// so the app makes no third-party font requests (see fonts/fallback/).
const earshotEngineConfig = {
  canvasKitBaseUrl: "canvaskit/",
  fontFallbackBaseUrl: "fonts/fallback/",
};

_flutter.loader.load({
  config: earshotEngineConfig,
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine(earshotEngineConfig);
    await appRunner.runApp();
  },
});
