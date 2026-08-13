"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const script = fs.readFileSync(
  path.join(__dirname, "..", "SafariExtensionResources", "redirect.js"),
  "utf8"
);
const manifest = JSON.parse(
  fs.readFileSync(
    path.join(__dirname, "..", "SafariExtensionResources", "manifest.json"),
    "utf8"
  )
);

assert.equal(manifest.version, "1.0.2");
assert.equal(manifest.content_scripts[0].run_at, "document_start");

async function redirectFor(href, options = {}) {
  const url = new URL(href);
  let redirected;
  const storage = new Map();
  function makeDocument(source = options) {
    return {
      querySelectorAll(selector) {
        let values = [];
        if (selector === 'meta[property="al:ios:url"]') {
          values = source.nativeRoutes ?? [];
        } else if (selector === 'link[rel="canonical"]' && source.canonical) {
          values = [source.canonical];
        } else if (selector === 'meta[property="og:url"]' && source.openGraph) {
          values = [source.openGraph];
        }
        return values.map((content) => ({
          getAttribute(name) {
            return name === "content" || name === "href" ? content : null;
          }
        }));
      }
    };
  }
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
    },
    stop() {},
    async fetch() {
      return {
        ok: options.fetchOK !== false,
        status: options.fetchOK === false ? 500 : 200,
        async text() {
          return "<html></html>";
        }
      };
    }
  };
  class DOMParser {
    parseFromString() {
      return makeDocument(options.fetched ?? options);
    }
  }
  const document = makeDocument();

  vm.runInNewContext(script, {DOMParser, Error, URL, document, window});
  await new Promise(setImmediate);
  return redirected;
}

async function main() {
assert.equal(
  await redirectFor("https://www.facebook.com/reel/123?ref=share#clip", {
    nativeRoutes: ["fb://reel/123?ref=share"]
  }),
  "fb://reel/123?ref=share"
);
assert.equal(
  await redirectFor("https://www.facebook.com/share/r/abc/?mibextid=xyz", {
    nativeRoutes: ["https://evil.example/payload"],
    canonical: "https://www.facebook.com/reel/123"
  }),
  "fb-www-link://www_link/?url=https%3A%2F%2Fwww.facebook.com%2Freel%2F123"
);
assert.equal(
  await redirectFor("https://www.facebook.com/share/v/19RsNqHveR/?mibextid=wwXIfr", {
    fetched: {
      canonical: "https://www.facebook.com/MEMES.of.the.NFL/posts/1467604858743867/",
      openGraph: "https://www.facebook.com/MEMES.of.the.NFL/posts/1467604858743867/"
    }
  }),
  "fb-www-link://www_link/?url=https%3A%2F%2Fwww.facebook.com%2FMEMES.of.the.NFL%2Fposts%2F1467604858743867%2F"
);
assert.equal(
  await redirectFor("https://www.facebook.com/share/v/abc", {
    canonical: "https://www.facebook.com/",
    openGraph: "https://www.facebook.com/share/v/abc"
  }),
  "fb-www-link://www_link/?url=https%3A%2F%2Fwww.facebook.com%2Fshare%2Fv%2Fabc"
);
assert.equal(await redirectFor("https://facebook.com.example/reel/123"), undefined);
assert.equal(await redirectFor("https://notfacebook.com/reel/123"), undefined);
assert.equal(
  await redirectFor(
    "https://www.facebook.com/reel/1071097325498008/?referral_source=external_link&surface_type=tab&in_reels_tab_context=TRUE"
  ),
  "fb-www-link://www_link/?url=https%3A%2F%2Fwww.facebook.com%2Freel%2F1071097325498008%2F%3Freferral_source%3Dexternal_link%26surface_type%3Dtab%26in_reels_tab_context%3DTRUE"
);

console.log("PASS GlowSafariRedirectTests");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
