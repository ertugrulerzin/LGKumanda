(function () {
      var sent = new Set(), timer = null;
      function report(raw, mime, title) {
        try {
          var u = new URL(raw, document.baseURI);
          if (u.protocol !== 'https:' && u.protocol !== 'http:') return;
          if (u.username || u.password || sent.has(u.href) || sent.size >= 64) return;
          if (!mime && !/\.(mp4|m4v|m3u8|webm|mov)$/i.test(u.pathname)) return;
          if (!window.flutter_inappwebview || typeof window.flutter_inappwebview.callHandler !== 'function') return;
          sent.add(u.href);
          window.flutter_inappwebview.callHandler('videoSource', {url:u.href, mime:mime || '', title:title || document.title || 'Web videosu'});
        } catch (_) {}
      }
      function scan() {
        timer = null;
        document.querySelectorAll('video').forEach(function(v) {
          var name = v.getAttribute('aria-label') || v.title || document.title;
          if (v.currentSrc) report(v.currentSrc, v.getAttribute('type'), name);
          if (v.src) report(v.src, v.getAttribute('type'), name);
          v.querySelectorAll('source').forEach(function(s) { report(s.src, s.type, name); });
        });
      }
      function schedule() { if (!timer) timer = setTimeout(scan, 150); }
      document.addEventListener('DOMContentLoaded', scan);
      window.addEventListener('flutterInAppWebViewPlatformReady', scan);
      document.addEventListener('loadedmetadata', schedule, true);
      document.addEventListener('loadstart', schedule, true);
      new MutationObserver(schedule).observe(document, {subtree:true, childList:true, attributes:true, attributeFilter:['src','type']});
      try {
        new PerformanceObserver(function(list) {
          list.getEntries().forEach(function(e) { if (/\.m3u8(?:[?]|$)/i.test(e.name)) report(e.name, '', document.title); });
        }).observe({type:'resource', buffered:true});
      } catch (_) {}
      document.addEventListener('play', function(e) {
        var v = e.target;
        if (!v || !v.pause) return;
        scan();
        v.pause(); v.muted = true;
        try { window.flutter_inappwebview.callHandler('tvMedia'); } catch (_) {}
      }, true);
      scan();
    })();
