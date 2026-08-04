const assert = require("node:assert/strict");
const test = require("node:test");

const {
  applyCarPlayAppDelegateModifications,
} = require("./config.js")._internal;

const expo55AppDelegate = `import Expo
import React

@main
class AppDelegate: ExpoAppDelegate {
  var window: UIWindow?
}

class ReactNativeDelegate: ExpoReactNativeFactoryDelegate {
}
`;

test("adds CarPlay protocol conformance to the Expo SDK 55 AppDelegate", () => {
  const result = applyCarPlayAppDelegateModifications(expo55AppDelegate);

  assert.match(
    result,
    /class AppDelegate: ExpoAppDelegate, CPApplicationDelegate \{/,
  );
  assert.match(result, /^import CarPlay$/m);
  assert.match(result, /^import ExpoMapboxNavigation$/m);
  assert.match(result, /didConnectCarInterfaceController/);
  assert.match(result, /didDisconnectCarInterfaceController/);
});

test("is idempotent", () => {
  const once = applyCarPlayAppDelegateModifications(expo55AppDelegate);
  const twice = applyCarPlayAppDelegateModifications(once);

  assert.equal(twice, once);
  assert.equal((twice.match(/private var carPlayManager/g) || []).length, 1);
  assert.equal((twice.match(/^import CarPlay$/gm) || []).length, 1);
});

test("supports older Expo templates with a public AppDelegate", () => {
  const oldExpoAppDelegate = expo55AppDelegate.replace(
    "class AppDelegate:",
    "public class AppDelegate:",
  );

  const result = applyCarPlayAppDelegateModifications(oldExpoAppDelegate);

  assert.match(
    result,
    /public class AppDelegate: ExpoAppDelegate, CPApplicationDelegate \{/,
  );
});

test("repairs conformance without duplicating callbacks already generated", () => {
  const partiallyGeneratedAppDelegate = expo55AppDelegate.replace(
    "  var window: UIWindow?",
    `  var window: UIWindow?

  private var carPlayManager: CarPlayManager?

  public func application(
    _ application: UIApplication,
    didConnectCarInterfaceController interfaceController: CPInterfaceController,
    to window: CPWindow
  ) {}`,
  );

  const result = applyCarPlayAppDelegateModifications(
    partiallyGeneratedAppDelegate,
  );

  assert.match(
    result,
    /class AppDelegate: ExpoAppDelegate, CPApplicationDelegate \{/,
  );
  assert.equal((result.match(/private var carPlayManager/g) || []).length, 1);
});
