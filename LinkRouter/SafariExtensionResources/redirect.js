(() => {
  "use strict";

  const allowedDomains = ["facebook.com", "fb.com", "fb.me", "fb.watch", "fbwat.ch"];
  const allowedNativeSchemes = new Set([
    "fb:",
    "facebook-reels:",
    "facebook-stories:",
    "facebook-stories-list:"
  ]);
  const host = window.location.hostname.toLowerCase().replace(/\.$/, "");
  const allowed = allowedDomains.some((domain) => host === domain || host.endsWith(`.${domain}`));
  if (!allowed || !["http:", "https:"].includes(window.location.protocol)) {
    return;
  }

  const marker = `glow-redirect:${window.location.href}`;

  function nativeRouteFromPage() {
    const elements = document.querySelectorAll('meta[property="al:ios:url"]');
    for (const element of elements) {
      const content = element.getAttribute("content")?.trim();
      if (!content) {
        continue;
      }
      try {
        const candidate = new URL(content);
        if (allowedNativeSchemes.has(candidate.protocol)) {
          return candidate.href;
        }
      } catch (_error) {
        // Ignore malformed metadata and use the validated web URL fallback.
      }
    }
    return undefined;
  }

  function validatedWebURL(rawValue) {
    if (!rawValue) {
      return undefined;
    }
    try {
      const candidate = new URL(rawValue, window.location.href);
      const candidateHost = candidate.hostname.toLowerCase().replace(/\.$/, "");
      const candidateAllowed = allowedDomains.some(
        (domain) => candidateHost === domain || candidateHost.endsWith(`.${domain}`)
      );
      if (
        candidateAllowed &&
        ["http:", "https:"].includes(candidate.protocol) &&
        !candidate.username &&
        !candidate.password &&
        !candidate.port
      ) {
        return candidate;
      }
    } catch (_error) {
      // Ignore malformed canonical metadata.
    }
    return undefined;
  }

  function canonicalWebURL() {
    const canonical = document.querySelectorAll('link[rel="canonical"]')[0]?.getAttribute("href");
    const openGraph = document.querySelectorAll('meta[property="og:url"]')[0]?.getAttribute("content");
    const currentURL = validatedWebURL(window.location.href);
    const canonicalURL = validatedWebURL(canonical);
    const openGraphURL = validatedWebURL(openGraph);
    if (!currentURL) {
      return canonicalURL || openGraphURL;
    }

    const isShareWrapper = /^\/share\/(?:p|r|v)(?:\/|$)/i.test(currentURL.pathname);
    if (!isShareWrapper) {
      return currentURL;
    }

    const resolvedDestination = [canonicalURL, openGraphURL].find(
      (candidate) =>
        candidate &&
        candidate.pathname !== "/" &&
        !/^\/share\/(?:p|r|v)(?:\/|$)/i.test(candidate.pathname)
    );
    return resolvedDestination || currentURL;
  }

  function wwwLinkRoute() {
    const webURL = canonicalWebURL();
    return webURL
      ? `fb-www-link://www_link/?url=${encodeURIComponent(webURL.href)}`
      : undefined;
  }

  function redirectIfReady() {
    if (window.sessionStorage.getItem(marker) === "attempted") {
      return true;
    }
    const target = nativeRouteFromPage() || wwwLinkRoute();
    if (!target) {
      return false;
    }
    window.sessionStorage.setItem(marker, "attempted");
    window.location.replace(target);
    return true;
  }

  redirectIfReady();
})();
