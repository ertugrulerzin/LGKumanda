/// Injected at document start in every frame. Reports media URLs the page requests
/// (fetch, XHR, <video>/<source>, resource timing) to the native side.
enum Sniffer {
    static let handlerName = "yakala"

    static let source = #"""
    (() => {
      if (window.__yakala) return;
      window.__yakala = true;
      const RX = /\.(m3u8|mp4|m4v|webm|flv|mov|mpd|vtt|srt|ass|ssa|ttml|dfxp)(\?|#|&|$)/i;
      const CT = /mpegurl|dash\+xml|^video\/|^text\/vtt/i;
      const seen = new Set();
      const post = (url, hint, label) => {
        try {
          if (!url || typeof url !== 'string') return;
          if (url.startsWith('blob:') || url.startsWith('data:')) return;
          const abs = new URL(url, location.href).href;
          if (!RX.test(abs) && !hint) return;
          if (seen.has(abs)) return;
          seen.add(abs);
          window.webkit.messageHandlers.yakala.postMessage({
            url: abs, hint: hint || '', label: label || '', page: location.href,
            title: (window.top === window ? document.title : '')
          });
        } catch (e) {}
      };

      const origFetch = window.fetch;
      if (origFetch) {
        window.fetch = function (input, init) {
          try { post(typeof input === 'string' ? input : (input && input.url)); } catch (e) {}
          const p = origFetch.apply(this, arguments);
          p.then(r => {
            try { const ct = r.headers.get('content-type') || ''; if (CT.test(ct)) post(r.url, ct); } catch (e) {}
          }).catch(() => {});
          return p;
        };
      }

      const xopen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (method, url) {
        this.__yakalaURL = String(url);
        post(this.__yakalaURL);
        return xopen.apply(this, arguments);
      };
      const xsend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function () {
        this.addEventListener('load', () => {
          try {
            const ct = this.getResponseHeader('content-type') || '';
            if (CT.test(ct)) post(this.responseURL || this.__yakalaURL, ct);
          } catch (e) {}
        });
        return xsend.apply(this, arguments);
      };

      const scan = () => {
        document.querySelectorAll('video, audio, source').forEach(el => {
          const src = el.currentSrc || el.src;
          if (src) post(src, el.tagName === 'SOURCE' ? '' : 'media');
        });
        document.querySelectorAll('track').forEach(el => {
          if (el.src) post(el.src, 'subtitle', el.label || el.srclang || '');
        });
      };
      document.addEventListener('loadstart', e => {
        const t = e.target;
        if (t && (t.currentSrc || t.src)) post(t.currentSrc || t.src, 'media');
      }, true);
      const startObserver = () => {
        scan();
        new MutationObserver(scan).observe(document.documentElement, {
          childList: true, subtree: true, attributes: true, attributeFilter: ['src']
        });
      };
      if (document.documentElement) startObserver();
      else document.addEventListener('DOMContentLoaded', startObserver);

      try {
        new PerformanceObserver(list => list.getEntries().forEach(e => post(e.name)))
          .observe({ type: 'resource', buffered: true });
      } catch (e) {}
    })();
    """#
}
