/// Injected at document start in every frame. Reports media URLs the page requests
/// (fetch, XHR, <video>/<source>, resource timing) to the native side. In recording
/// mode it also copies every MediaSource buffer the player appends.
enum Sniffer {
    static let handlerName = "yakala"

    /// Turns recording mode on for documents loaded after it is installed.
    static let recordingFlag = "window.__yakalaRec = true;"

    /// Sets playback speed on every video, in this frame and nested frames.
    static func speedScript(_ rate: Double) -> String {
        "window.postMessage({ yakalaSpeed: \(rate) }, '*');"
    }

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

      // ---- Recording mode: copy MediaSource buffers in append order ----
      const send = msg => { try { window.webkit.messageHandlers.yakala.postMessage(msg); } catch (e) {} };
      const recOn = () => window.__yakalaRec === true;
      const frameID = Math.random().toString(36).slice(2, 10);
      let sessions = 0, tracks = 0;
      const hookSource = MS => {
        if (!MS || !MS.prototype || MS.prototype.__yakalaHooked) return;
        MS.prototype.__yakalaHooked = true;
        const add = MS.prototype.addSourceBuffer;
        MS.prototype.addSourceBuffer = function (mime) {
          const sb = add.apply(this, arguments);
          try {
            if (recOn()) {
              if (!this.__yakalaID) this.__yakalaID = frameID + '-' + (++sessions);
              const t = { id: this.__yakalaID + '-' + (++tracks), seq: 0, chain: Promise.resolve() };
              sb.__yakala = t;
              send({ type: 'mse-track', session: this.__yakalaID, track: t.id, mime: String(mime),
                     page: location.href, title: window.top === window ? document.title : '' });
            }
          } catch (e) {}
          return sb;
        };
      };
      hookSource(window.MediaSource);
      hookSource(window.ManagedMediaSource);
      hookSource(window.WebKitMediaSource);
      if (window.SourceBuffer && !SourceBuffer.prototype.__yakalaHooked) {
        SourceBuffer.prototype.__yakalaHooked = true;
        const append = SourceBuffer.prototype.appendBuffer;
        SourceBuffer.prototype.appendBuffer = function (data) {
          const t = this.__yakala;
          if (t) {
            try {
              const view = data instanceof ArrayBuffer ? new Uint8Array(data)
                : new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
              const blob = new Blob([view]);
              const seq = t.seq++;
              t.chain = t.chain.then(() => new Promise(done => {
                const r = new FileReader();
                r.onload = () => {
                  const s = String(r.result);
                  send({ type: 'mse-data', track: t.id, seq: seq, data: s.slice(s.indexOf(',') + 1) });
                  done();
                };
                r.onerror = () => { send({ type: 'mse-data', track: t.id, seq: seq, data: '' }); done(); };
                r.readAsDataURL(blob);
              }));
            } catch (e) {}
          }
          return append.apply(this, arguments);
        };
      }
      const hookKeys = name => {
        const original = HTMLMediaElement.prototype[name];
        if (!original) return;
        HTMLMediaElement.prototype[name] = function (keys) {
          if (keys && recOn()) send({ type: 'mse-drm', page: location.href });
          return original.apply(this, arguments);
        };
      };
      hookKeys('setMediaKeys');
      hookKeys('webkitSetMediaKeys');

      window.addEventListener('message', e => {
        const rate = e.data && e.data.yakalaSpeed;
        if (!rate) return;
        document.querySelectorAll('video').forEach(v => { try { v.playbackRate = rate; } catch (err) {} });
        document.querySelectorAll('iframe').forEach(f => {
          try { f.contentWindow.postMessage({ yakalaSpeed: rate }, '*'); } catch (err) {}
        });
      });
    })();
    """#
}
