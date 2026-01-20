const {
  withDangerousMod,
  withAndroidColors,
  withAndroidManifest,
  withEntitlementsPlist,
  withInfoPlist,
  AndroidConfig,
} = require("@expo/config-plugins");
const fs = require("fs/promises");
const path = require("path");

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

/**
 * Add CarPlay scene configuration to Info.plist
 * Note: For Expo/React Native apps, we only add CarPlay-specific keys
 * without modifying UIApplicationSceneManifest to avoid breaking the main app
 */
const withCarPlayInfoPlist = (config, enableCarPlay) => {
  if (!enableCarPlay) {
    return config;
  }

  return withInfoPlist(config, (config) => {
    // Add CarPlay Dashboard support flag
    config.modResults.CPSupportsDashboardNavigationScene = true;

    // Add required background modes for navigation
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

/**
 * Add CarPlay entitlements
 */
const withCarPlayEntitlements = (config, enableCarPlay) => {
  if (!enableCarPlay) {
    return config;
  }

  return withEntitlementsPlist(config, (config) => {
    // Add CarPlay navigation entitlement
    config.modResults["com.apple.developer.carplay-driving-task"] = true;

    // Also add maps entitlement for navigation apps
    config.modResults["com.apple.developer.carplay-maps"] = true;

    return config;
  });
};

const withIosConfig = (
  config,
  { accessToken, mapboxMapsVersion, enableCarPlay = true },
) => {
  let modifiedConfig = withIosPostInstallStep(config, mapboxMapsVersion);
  modifiedConfig = withIosTokenInfoPlist(modifiedConfig, accessToken);
  modifiedConfig = withCarPlayInfoPlist(modifiedConfig, enableCarPlay);
  modifiedConfig = withCarPlayEntitlements(modifiedConfig, enableCarPlay);
  return modifiedConfig;
};

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
  { accessToken, androidColorOverrides = {} },
) => {
  const configWithColors = withAndroidColors(config, (config) => {
    let currentModResults = config.modResults;

    for (const [name, value] of Object.entries(androidColorOverrides)) {
      AndroidConfig.Colors.assignColorValue(currentModResults, { name, value });
    }

    config.modResults = currentModResults;

    return config;
  });

  return withAndroidTokenMetaData(configWithColors, accessToken);
};

const withConfig = (
  config,
  {
    accessToken,
    mapboxMapsVersion,
    androidColorOverrides,
    enableCarPlay = true,
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
  });
  return configWithAndroid;
};

module.exports = withConfig;
