const {
  withDangerousMod,
  withAndroidColors,
  withAndroidManifest,
  withEntitlementsPlist,
  withInfoPlist,
  AndroidConfig,
  createRunOncePlugin,
} = require("@expo/config-plugins");
const fs = require("fs/promises");
const path = require("path");
const pkg = require("../package.json");

const TOOLS_NAMESPACE = "http://schemas.android.com/tools";
const ANDROID_AUTO_PERMISSION = "androidx.car.app.MAP_TEMPLATES";
const ANDROID_AUTO_SERVICE = "expo.modules.mapboxnavigation.MainCarAppService";
const ANDROID_AUTO_NAVIGATE_ACTION = "androidx.car.app.action.NAVIGATE";
const ANDROID_AUTO_METADATA = [
  "com.google.android.gms.car.application",
  "androidx.car.app.minCarApiLevel",
];
const CARPLAY_APP_DELEGATE_PROTOCOL = "CPApplicationDelegate";
const CARPLAY_CONNECT_METHOD = "didConnectCarInterfaceController";

const CARPLAY_IMPORTS = [
  "CarPlay",
  "MapboxNavigationCore",
  "MapboxNavigationUIKit",
  "ExpoMapboxNavigation",
];

const CARPLAY_APP_DELEGATE_CODE = `
  // expo-mapbox-navigation: CarPlay lifecycle
  private var carPlayManager: CarPlayManager?

  public func application(
    _ application: UIApplication,
    didConnectCarInterfaceController interfaceController: CPInterfaceController,
    to window: CPWindow
  ) {
    print("[ExpoMapboxNavigation] CarPlay connecting...")

    if carPlayManager == nil {
      let provider = NavigationProviderManager.shared.getProvider(forSimulation: false)
      carPlayManager = CarPlayManager(navigationProvider: provider)
    }

    carPlayManager?.application(
      application,
      didConnectCarInterfaceController: interfaceController,
      to: window
    )

    CarPlayStateManager.shared.interfaceController = interfaceController
    CarPlayStateManager.shared.carPlayWindow = window
    CarPlayStateManager.shared.carPlayManager = carPlayManager

    NotificationCenter.default.post(
      name: Notification.Name("CarPlayDidConnect"),
      object: nil,
      userInfo: ["interfaceController": interfaceController, "window": window]
    )

    CarPlayStateManager.shared.checkForActiveNavigation()
    print("[ExpoMapboxNavigation] CarPlay connected successfully")
  }

  public func application(
    _ application: UIApplication,
    didDisconnectCarInterfaceController interfaceController: CPInterfaceController,
    from window: CPWindow
  ) {
    print("[ExpoMapboxNavigation] CarPlay disconnecting...")

    carPlayManager?.application(
      application,
      didDisconnectCarInterfaceController: interfaceController,
      from: window
    )

    CarPlayStateManager.shared.interfaceController = nil
    CarPlayStateManager.shared.carPlayWindow = nil
    CarPlayStateManager.shared.carPlayManager = nil

    NotificationCenter.default.post(
      name: Notification.Name("CarPlayDidDisconnect"),
      object: nil
    )

    print("[ExpoMapboxNavigation] CarPlay disconnected")
  }
  // expo-mapbox-navigation: end CarPlay lifecycle
`;

/**
 * Adds the legacy CarPlay application lifecycle used by Mapbox Navigation 3.8.
 *
 * Expo SDK 55 generates `class AppDelegate: ExpoAppDelegate`, while older Expo
 * templates generated `public class AppDelegate: ExpoAppDelegate`. The previous
 * exact string replacement only inserted the methods and never added protocol
 * conformance on SDK 55, so UIKit could not discover the Objective-C CarPlay
 * selectors when the icon was opened.
 */
const applyCarPlayAppDelegateModifications = (source) => {
  let contents = source;

  const missingImports = CARPLAY_IMPORTS.filter(
    (moduleName) =>
      !new RegExp(
        `^\\s*(?:internal\\s+)?import\\s+${moduleName}\\s*$`,
        "m",
      ).test(contents),
  );

  if (missingImports.length > 0) {
    const expoImportPattern = /^(\s*(?:internal\s+)?import\s+Expo\s*)$/m;
    if (!expoImportPattern.test(contents)) {
      throw new Error(
        "expo-mapbox-navigation: Could not find the Expo import in AppDelegate.swift",
      );
    }

    contents = contents.replace(
      expoImportPattern,
      `$1\n${missingImports.map((moduleName) => `import ${moduleName}`).join("\n")}`,
    );
  }

  const appDelegatePattern =
    /(\bclass\s+AppDelegate\s*:\s*ExpoAppDelegate)([^\{]*)(\{)/;
  const appDelegateMatch = contents.match(appDelegatePattern);

  if (!appDelegateMatch) {
    throw new Error(
      "expo-mapbox-navigation: Could not find the AppDelegate class declaration",
    );
  }

  if (!appDelegateMatch[2].includes(CARPLAY_APP_DELEGATE_PROTOCOL)) {
    contents = contents.replace(
      appDelegatePattern,
      (_match, declaration, conformances, openingBrace) =>
        `${declaration}${conformances.trimEnd()}, ${CARPLAY_APP_DELEGATE_PROTOCOL} ${openingBrace}`,
    );
  }

  if (!contents.includes(CARPLAY_CONNECT_METHOD)) {
    const reactNativeDelegatePattern = /}\s*\n\s*\nclass ReactNativeDelegate:/;
    if (!reactNativeDelegatePattern.test(contents)) {
      throw new Error(
        "expo-mapbox-navigation: Could not find the end of AppDelegate.swift",
      );
    }

    contents = contents.replace(
      reactNativeDelegatePattern,
      `${CARPLAY_APP_DELEGATE_CODE}}\n\nclass ReactNativeDelegate:`,
    );
  }

  return contents;
};

/**
 * This plugin adds a post-install step to the Podfile that addresses linking issues between pods and xcframeworks.
 * In this case, the navigation library is added as an xcframework, and the maps library is added as a pod
 *
 * See https://github.com/CocoaPods/CocoaPods/issues/11079#issuecomment-984670700
 */

const applyPodfilePostInstallModifications = (src, mapboxMapsVersion) => {
  return (
    `ENV['ExpoNavigationMapboxMapsVersion'] = '${mapboxMapsVersion}'\n` +
    src.replace(
      "post_install do |installer|",
      `post_install do |installer|
      installer.pods_project.targets.each do |target|
          if (target.name.include? 'MapboxMaps' or target.name.include? 'Turf')
            target.build_configurations.each do |config|
              config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
            end
          end
        end`,
    )
  );
};

const withIosPostInstallStep = (config, mapboxMapsVersion) =>
  withDangerousMod(config, [
    "ios",
    async (exportedConfig) => {
      const file = path.join(
        exportedConfig.modRequest.platformProjectRoot,
        "Podfile",
      );

      const contents = await fs.readFile(file, "utf8");
      await fs.writeFile(
        file,
        applyPodfilePostInstallModifications(contents, mapboxMapsVersion),
        "utf-8",
      );

      return exportedConfig;
    },
  ]);

const withIosTokenInfoPlist = (config, accessToken) => {
  if (!config.ios) {
    config.ios = {};
  }
  if (!config.ios.infoPlist) {
    config.ios.infoPlist = {};
  }

  config.ios.infoPlist["MBXAccessToken"] = accessToken;

  return config;
};

const withCarPlayInfoPlist = (config, enableCarPlay) => {
  if (!enableCarPlay) {
    return config;
  }

  return withInfoPlist(config, (config) => {
    if (!config.modResults.UIBackgroundModes) {
      config.modResults.UIBackgroundModes = [];
    }

    const requiredModes = ["location", "audio", "fetch"];
    requiredModes.forEach((mode) => {
      if (!config.modResults.UIBackgroundModes.includes(mode)) {
        config.modResults.UIBackgroundModes.push(mode);
      }
    });

    return config;
  });
};

const withCarPlayEntitlements = (config, enableCarPlay) => {
  if (!enableCarPlay) {
    return config;
  }

  return withEntitlementsPlist(config, (config) => {
    config.modResults["com.apple.developer.carplay-driving-task"] = true;
    config.modResults["com.apple.developer.carplay-maps"] = true;

    return config;
  });
};

const withIosConfig = (
  config,
  { accessToken, mapboxMapsVersion, enableCarPlay = false },
) => {
  let modifiedConfig = withIosPostInstallStep(config, mapboxMapsVersion);
  modifiedConfig = withIosTokenInfoPlist(modifiedConfig, accessToken);
  modifiedConfig = withCarPlayInfoPlist(modifiedConfig, enableCarPlay);
  modifiedConfig = withCarPlayEntitlements(modifiedConfig, enableCarPlay);
  modifiedConfig = withCarPlayAppDelegate(modifiedConfig, enableCarPlay);
  return modifiedConfig;
};

const replaceManifestEntry = (items = [], name, replacement) => [
  ...items.filter((item) => item?.$?.["android:name"] !== name),
  replacement,
];

const removalMarker = (name) => ({
  $: {
    "android:name": name,
    "tools:node": "remove",
  },
});

const androidAutoService = {
  $: {
    "android:name": ANDROID_AUTO_SERVICE,
    "android:exported": "true",
    "android:label": "@string/app_name",
    "android:icon": "@mipmap/ic_launcher",
    "android:roundIcon": "@mipmap/ic_launcher_round",
    "android:foregroundServiceType": "location",
  },
  "intent-filter": [
    {
      action: [
        {
          $: {
            "android:name": "androidx.car.app.CarAppService",
          },
        },
      ],
      category: [
        {
          $: {
            "android:name": "androidx.car.app.category.NAVIGATION",
          },
        },
      ],
    },
  ],
};

const androidAutoMetadata = {
  "com.google.android.gms.car.application": {
    $: {
      "android:name": "com.google.android.gms.car.application",
      "android:resource": "@xml/automotive_app_desc",
    },
  },
  "androidx.car.app.minCarApiLevel": {
    $: {
      "android:name": "androidx.car.app.minCarApiLevel",
      "android:value": "3",
      "tools:replace": "android:value",
    },
  },
};

const androidAutoNavigationIntentFilter = {
  action: [
    {
      $: {
        "android:name": ANDROID_AUTO_NAVIGATE_ACTION,
      },
    },
  ],
  category: [
    {
      $: {
        "android:name": "android.intent.category.DEFAULT",
      },
    },
  ],
  data: [
    {
      $: {
        "android:scheme": "geo",
      },
    },
  ],
};

const isAndroidAutoNavigationIntentFilter = (intentFilter) =>
  intentFilter?.action?.some(
    (action) => action?.$?.["android:name"] === ANDROID_AUTO_NAVIGATE_ACTION,
  );

const withAndroidAuto = (config, enableAndroidAuto) =>
  withAndroidManifest(config, (manifestConfig) => {
    const androidManifest = manifestConfig.modResults.manifest;
    androidManifest.$ = androidManifest.$ || {};
    androidManifest.$["xmlns:tools"] = TOOLS_NAMESPACE;

    androidManifest["uses-permission"] = replaceManifestEntry(
      androidManifest["uses-permission"],
      ANDROID_AUTO_PERMISSION,
      enableAndroidAuto
        ? {
            $: {
              "android:name": ANDROID_AUTO_PERMISSION,
            },
          }
        : removalMarker(ANDROID_AUTO_PERMISSION),
    );

    const mainApplication = AndroidConfig.Manifest.getMainApplicationOrThrow(
      manifestConfig.modResults,
    );
    const mainActivity = AndroidConfig.Manifest.getMainActivityOrThrow(
      manifestConfig.modResults,
    );

    mainActivity["intent-filter"] = [
      ...(mainActivity["intent-filter"] || []).filter(
        (intentFilter) => !isAndroidAutoNavigationIntentFilter(intentFilter),
      ),
      ...(enableAndroidAuto ? [androidAutoNavigationIntentFilter] : []),
    ];

    mainApplication.service = replaceManifestEntry(
      mainApplication.service,
      ANDROID_AUTO_SERVICE,
      enableAndroidAuto
        ? androidAutoService
        : removalMarker(ANDROID_AUTO_SERVICE),
    );

    for (const metadataName of ANDROID_AUTO_METADATA) {
      mainApplication["meta-data"] = replaceManifestEntry(
        mainApplication["meta-data"],
        metadataName,
        enableAndroidAuto
          ? androidAutoMetadata[metadataName]
          : removalMarker(metadataName),
      );
    }

    return manifestConfig;
  });

const withAndroidTokenMetaData = (config, accessToken) => {
  return withAndroidManifest(config, async (config) => {
    const androidManifest = config.modResults;
    const mainApplication = androidManifest.manifest.application[0];

    if (!mainApplication["meta-data"]) {
      mainApplication["meta-data"] = [];
    }

    mainApplication["meta-data"] = mainApplication["meta-data"].filter(
      (item) => item.$["android:name"] !== "MBXAccessToken",
    );

    mainApplication["meta-data"].push({
      $: {
        "android:name": "MBXAccessToken",
        "android:value": accessToken,
      },
    });

    return config;
  });
};

const withAndroidConfig = (
  config,
  { accessToken, androidColorOverrides = {}, enableAndroidAuto = false },
) => {
  const configWithColors = withAndroidColors(config, (config) => {
    let currentModResults = config.modResults;

    for (const [name, value] of Object.entries(androidColorOverrides)) {
      AndroidConfig.Colors.assignColorValue(currentModResults, { name, value });
    }

    config.modResults = currentModResults;

    return config;
  });

  const configWithToken = withAndroidTokenMetaData(
    configWithColors,
    accessToken,
  );

  return withAndroidAuto(configWithToken, enableAndroidAuto);
};

const withCarPlayAppDelegate = (config, enableCarPlay) => {
  if (!enableCarPlay) {
    return config;
  }

  return withDangerousMod(config, [
    "ios",
    async (exportedConfig) => {
      const appDelegatePath = path.join(
        exportedConfig.modRequest.platformProjectRoot,
        exportedConfig.modRequest.projectName,
        "AppDelegate.swift",
      );

      let contents = await fs.readFile(appDelegatePath, "utf8");
      contents = applyCarPlayAppDelegateModifications(contents);

      await fs.writeFile(appDelegatePath, contents, "utf-8");

      return exportedConfig;
    },
  ]);
};

const withConfig = (
  config,
  {
    accessToken,
    mapboxMapsVersion,
    androidColorOverrides,
    enableCarPlay = false,
    enableAndroidAuto = false,
  },
) => {
  const configWithIos = withIosConfig(config, {
    accessToken,
    mapboxMapsVersion,
    enableCarPlay,
  });
  const configWithAndroid = withAndroidConfig(configWithIos, {
    accessToken,
    androidColorOverrides,
    enableAndroidAuto,
  });
  return configWithAndroid;
};

module.exports = createRunOncePlugin(withConfig, pkg.name, pkg.version);

// Exposed for deterministic config-plugin tests without running an iOS prebuild.
module.exports._internal = {
  applyCarPlayAppDelegateModifications,
};
