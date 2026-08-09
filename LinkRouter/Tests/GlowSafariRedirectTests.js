"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const script = fs.readFileSync(
  path.join(__dirname, "..", "SafariExtensionResources", "redirect.js"),
  "utf8"
);

function redirectFor(href, options = {}) {
  const url = new URL(href);
  let redirected;
  const storage = new Map();
  const window = {
    location: {
      href,
      hostname: url.hostname,
      protocol: url.protocol,
      replace(target) {
        redirected = target;
      }
    },
    sessionStorage: {
      getItem(key) {
        return storage.get(key) ?? null;
      },
      setItem(key, value) {
        storage.set(key, value);
      }
    }
  };
  const document = {
    querySelectorAll(selector) {
      let values = [];
      if (selector === 'meta[property="al:ios:url"]') {
        values = options.nativeRoutes ?? [];
      } else if (selector === 'link[rel="canonical"]' && options.canonical) {
        values = [options.canonical];
      } else if (selector === 'meta[property="og:url"]' && options.openGraph) {
        values = [options.openGraph];
      }
      return values.map((content) => ({
        getAttribute(name) {
          return name === "content" || name === "href" ? content : null;
        }
      }));
    }
  };

  vm.runInNewContext(script, {URL, document, window});
  return redirected;
}

assert.equal(
  redirectFor("https://www.facebook.com/reel/123?ref=share#clip", {
    nativeRoutes: ["fb://reel/123?ref=share"]
  }),
  "fb://reel/123?ref=share"
);
assert.equal(
  redirectFor("https://www.facebook.com/share/r/abc/?mibextid=xyz", {
    nativeRoutes: ["https://evil.example/payload"]
  }),
  "fb-www-link://www_link/?url=https%3A%2F%2Fwww.facebook.com%2Fshare%2Fr%2Fabc%2F%3Fmibextid%3Dxyz"
);
assert.equal(redirectFor("https://facebook.com.example/reel/123"), undefined);
assert.equal(redirectFor("https://notfacebook.com/reel/123"), undefined);
assert.equal(
  redirectFor(
    "https://www.facebook.com/reel/1071097325498008/?referral_source=external_link&surface_type=tab&in_reels_tab_context=TRUE"
  ),
  "fb-www-link://www_link/?url=https%3A%2F%2Fwww.facebook.com%2Freel%2F1071097325498008%2F%3Freferral_source%3Dexternal_link%26surface_type%3Dtab%26in_reels_tab_context%3DTRUE"
);

console.log("PASS GlowSafariRedirectTests");
