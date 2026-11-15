import Foundation

/// Pointerless web navigation for the LG browser.
///
/// The LG browser has no arrow-key focus between links (arrows only scroll). The app adds it by running a small script
/// in the open page: launching the browser with a `javascript:` target runs it in the current page (verified on the TV).
/// Each arrow press runs the script with a direction; it moves a visible highlight to the nearest link, button or
/// clickable element in that direction, or scrolls when there is none. OK first "arms" the script, then a real ENTER
/// key is sent, so the activation happens inside a trusted key event (video players accept it as a user gesture).
/// Cross-origin players cannot be reached from the page, so OK on such a frame opens the player page itself.
/// Frames are only highlighted, never focused: a focused cross-origin frame would swallow the keys.
/// The script is joined into one line, so it must not contain `//` comments, `%` or `#`.
enum WebFocus {
    enum Action: String { case up, down, left, right, arm }

    static func action(for key: RemoteKey) -> Action? {
        switch key {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .enter: return .arm
        default: return nil
        }
    }

    /// `javascript:` URL for the browser's launch target. No `%` or `#` in the source, so light encoding is enough.
    static func url(_ action: Action) -> String {
        let source = script.replacingOccurrences(of: "\n", with: " ") + "('\(action.rawValue)')"
        return "javascript:" + (source.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? source)
    }

    static let script = """
    void (function (a) {
      var w = window, d = document, N = w.__lgnav;
      if (!N) {
        N = w.__lgnav = {};
        var box = d.createElement('div');
        box.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483647;border:4px solid rgb(255,64,129);border-radius:8px;box-shadow:0 0 0 3px rgba(255,255,255,.7);display:none';
        (d.body || d.documentElement).appendChild(box);
        N.sel = 'a[href],button,input,select,textarea,summary,iframe,video,[tabindex],[onclick],[role=button],[role=link],[role=tab],[role=menuitem],[role=option]';
        N.rect = function (e) {
          var r = e.getBoundingClientRect();
          if (r.width < 6 || r.height < 6) return null;
          var s = getComputedStyle(e);
          if (s.visibility == 'hidden' || s.display == 'none' || s.opacity == '0') return null;
          if (e.disabled || (e.getAttribute('tabindex') == '-1' && !e.__lg)) return null;
          return r;
        };
        N.list = function () {
          var out = [], seen = new Set(), q = d.querySelectorAll(N.sel), i;
          for (i = 0; i < q.length; i++) { out.push(q[i]); seen.add(q[i]); }
          var p = d.querySelectorAll('div,span,img,li,svg,label');
          for (i = 0; i < p.length && i < 3000; i++) {
            var e = p[i];
            if (seen.has(e) || getComputedStyle(e).cursor != 'pointer') continue;
            if (e.parentElement && getComputedStyle(e.parentElement).cursor == 'pointer') continue;
            out.push(e);
          }
          return out;
        };
        N.draw = function () {
          var e = N.cur;
          if (!e || !e.isConnected) { box.style.display = 'none'; return; }
          var r = e.getBoundingClientRect();
          box.style.display = 'block';
          box.style.left = (r.left - 6) + 'px'; box.style.top = (r.top - 6) + 'px';
          box.style.width = (r.width + 4) + 'px'; box.style.height = (r.height + 4) + 'px';
        };
        w.addEventListener('scroll', N.draw, true);
        w.addEventListener('resize', N.draw);
        N.set = function (e) {
          N.cur = e;
          if (e.tabIndex < 0 && !e.hasAttribute('tabindex')) { e.setAttribute('tabindex', '-1'); e.__lg = 1; }
          if (e.tagName == 'IFRAME') { var ae = d.activeElement; if (ae && ae.tagName == 'IFRAME') ae.blur(); try { w.focus(); } catch (x) {} }
          else { try { e.focus({ preventScroll: true }); } catch (x) {} }
          var r = e.getBoundingClientRect();
          if (r.top < 0 || r.bottom > innerHeight || r.left < 0 || r.right > innerWidth) e.scrollIntoView({ block: 'center', inline: 'center' });
          N.draw();
        };
        N.move = function (dir) {
          var c = N.cur && N.cur.isConnected ? N.cur.getBoundingClientRect() : null;
          var cx = c ? c.left + c.width / 2 : innerWidth / 2, cy = c ? c.top + c.height / 2 : 0;
          var best = null, bestScore = 1e9, L = N.list();
          for (var i = 0; i < L.length; i++) {
            var e = L[i];
            if (e == N.cur) continue;
            var r = N.rect(e);
            if (!r) continue;
            var dx = r.left + r.width / 2 - cx, dy = r.top + r.height / 2 - cy, m, o;
            if (!c) { if (r.bottom < 0 || r.top > innerHeight) continue; m = (r.top < 0 ? 100000 : 0) + r.top + 1; o = r.left * 0.12; }
            else if (dir == 'down') { if (r.top < c.bottom - 2 && dy <= 0) continue; m = dy; o = Math.abs(dx); }
            else if (dir == 'up') { if (r.bottom > c.top + 2 && dy >= 0) continue; m = -dy; o = Math.abs(dx); }
            else if (dir == 'right') { if (r.left < c.right - 2 && dx <= 0) continue; m = dx; o = Math.abs(dy); }
            else { if (r.right > c.left + 2 && dx >= 0) continue; m = -dx; o = Math.abs(dy); }
            if (m <= 0) continue;
            var score = m + o * 2.5;
            if (score < bestScore) { bestScore = score; best = e; }
          }
          if (best && (!c || bestScore < innerHeight * 1.5)) { N.set(best); return; }
          var v = innerHeight * 0.6, h = innerWidth * 0.6;
          scrollBy(dir == 'left' ? -h : dir == 'right' ? h : 0, dir == 'up' ? -v : dir == 'down' ? v : 0);
        };
        N.act = function (e, ev) {
          var t = e.tagName;
          if (t == 'IFRAME') { if (/^https?:/.test(e.src)) { if (ev) ev.preventDefault(); location.href = e.src; } return; }
          if (t == 'VIDEO') { if (ev) ev.preventDefault(); if (e.paused) e.play(); else e.pause(); return; }
          if (ev && /^(A|BUTTON|INPUT|SELECT|TEXTAREA|SUMMARY)$/.test(t) && d.activeElement === e) return;
          if (ev) ev.preventDefault();
          e.click();
        };
        d.addEventListener('keydown', function (ev) {
          if (ev.key != 'Enter' || !N.armed) return;
          N.armed = 0;
          if (N.cur && N.cur.isConnected) N.act(N.cur, ev);
        }, true);
      }
      if (a == 'arm') {
        var cur = N.cur && N.cur.isConnected ? N.cur : null;
        N.armed = 0;
        if (cur && (cur.tagName == 'IFRAME' || !d.hasFocus())) N.act(cur, null);
        else if (cur) N.armed = 1;
      }
      else N.move(a);
    })
    """
}
