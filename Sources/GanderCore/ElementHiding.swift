import Foundation

/// Hiding parts of a page: the styles that apply saved choices, and the
/// in-page picker that lets someone point at what they want gone.
public enum ElementHiding {
    /// Name of the script message handler the picker reports to.
    public static let messageHandlerName = "ganderPicker"

    /// Hosts are compared without a leading "www.".
    public static func normalizedHost(_ host: String) -> String {
        let lowered = host.lowercased()
        return lowered.hasPrefix("www.") ? String(lowered.dropFirst(4)) : lowered
    }

    /// Rejects anything that could break out of the generated style rule.
    public static func isValidSelector(_ selector: String) -> Bool {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2000 else { return false }
        return !trimmed.unicodeScalars.contains { scalar in
            scalar == "{" || scalar == "}" || scalar == "<" || scalar.value < 0x20 || scalar.value == 0x7f
        }
    }

    /// Selectors grouped by the site they apply to.
    public static func selectorsByHost(_ elements: [HiddenElement]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for element in elements where isValidSelector(element.selector) {
            let host = normalizedHost(element.host)
            guard !host.isEmpty else { continue }
            let selector = element.selector.trimmingCharacters(in: .whitespacesAndNewlines)
            if result[host]?.contains(selector) != true {
                result[host, default: []].append(selector)
            }
        }
        return result
    }

    /// Script that hides the saved elements. It is safe to run repeatedly: at
    /// document start on every load, and again right after a change.
    public static func userScript(for elements: [HiddenElement]) -> String {
        let rules = selectorsByHost(elements)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = (try? encoder.encode(rules)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        (function () {
          var rules = \(json);
          var host = location.hostname.replace(/^www\\./, '').toLowerCase();
          var css = '';
          Object.keys(rules).forEach(function (key) {
            if (host === key || host.endsWith('.' + key)) {
              rules[key].forEach(function (selector) {
                css += selector + ' { display: none !important; }\\n';
              });
            }
          });
          var id = 'gander-hidden-elements';
          var style = document.getElementById(id);
          if (!css) {
            if (style) { style.remove(); }
            return;
          }
          if (!style) {
            style = document.createElement('style');
            style.id = id;
            (document.head || document.documentElement).appendChild(style);
          }
          style.textContent = css;
        })();
        """
    }

    /// Consent dialogs often lock page scrolling with a class on the root
    /// element. Hiding the dialog would leave the page stuck, so undo the lock.
    public static let scrollUnlockScript = """
    (function () {
      var style = document.createElement('style');
      style.id = 'gander-scroll-unlock';
      style.textContent =
        'html.sp-message-open, html.sp-message-open body, body.didomi-popup-open ' +
        '{ overflow: auto !important; position: static !important; }';
      (document.head || document.documentElement).appendChild(style);
    })();
    """

    public static let stopPickerScript = "window.__ganderPicker && window.__ganderPicker.stop();"

    /// Interactive picker. Hover outlines an element, a click hides it and
    /// reports a selector for it, ↑/↓ widen or narrow the outline, and
    /// Escape or Return finishes.
    public static let pickerScript = #"""
    (function () {
      if (window.__ganderPicker) { window.__ganderPicker.stop(); }

      function post(message) {
        try {
          window.webkit.messageHandlers.ganderPicker.postMessage(message);
        } catch (error) {
          (window.__ganderPickerLog = window.__ganderPickerLog || []).push(message);
        }
      }

      var box = document.createElement('div');
      box.style.cssText =
        'position:fixed;z-index:2147483647;pointer-events:none;box-sizing:border-box;display:none;' +
        'background:rgba(255,69,58,0.22);border:2px solid rgba(255,69,58,0.95);border-radius:4px;';
      var label = document.createElement('div');
      label.style.cssText =
        'position:absolute;left:-2px;font:11px/16px -apple-system,system-ui,sans-serif;color:#fff;' +
        'background:rgba(255,69,58,0.95);padding:1px 6px;border-radius:4px;white-space:nowrap;' +
        'max-width:320px;overflow:hidden;text-overflow:ellipsis;';
      box.appendChild(label);
      document.documentElement.appendChild(box);

      var hovered = null;  // the element under the pointer
      var target = null;   // the element outlined: `hovered` or an ancestor of it
      var trail = [];

      function escapeIdent(value) {
        return window.CSS && CSS.escape ? CSS.escape(value) : value.replace(/[^a-zA-Z0-9_-]/g, '\\$&');
      }

      // Names that look machine-generated change between visits, so a
      // selector built on them would stop matching.
      function isStable(token) {
        return token.length > 0 && token.length <= 40 && /^[a-zA-Z][a-zA-Z0-9_-]*$/.test(token) &&
          !/\d{3,}/.test(token) && !/^[a-f0-9-]{8,}$/i.test(token);
      }

      function count(selector) {
        try { return document.querySelectorAll(selector).length; } catch (error) { return -1; }
      }

      function isRoot(element) {
        return !element || element === document.documentElement || element === document.body;
      }

      function describe(element) {
        var name = escapeIdent(element.localName);
        if (element.id && isStable(element.id)) { return name + '#' + escapeIdent(element.id); }
        var classes = Array.prototype.filter.call(element.classList, isStable).slice(0, 3);
        var selector = name + classes.map(function (item) { return '.' + escapeIdent(item); }).join('');
        var parent = element.parentElement;
        if (parent) {
          var hasTwin = Array.prototype.some.call(parent.children, function (child) {
            try { return child !== element && child.matches(selector); } catch (error) { return true; }
          });
          if (hasTwin) {
            var index = 1;
            var sibling = element;
            while ((sibling = sibling.previousElementSibling)) {
              if (sibling.localName === element.localName) { index += 1; }
            }
            selector += ':nth-of-type(' + index + ')';
          }
        }
        return selector;
      }

      // Walks up until the path identifies exactly one element.
      function selectorFor(element) {
        if (isRoot(element)) { return null; }
        var parts = [];
        var node = element;
        while (!isRoot(node) && node.nodeType === 1 && parts.length < 40) {
          parts.unshift(describe(node));
          if (count(parts.join(' > ')) === 1) { return parts.join(' > '); }
          node = node.parentElement;
        }
        return node === document.body ? 'body > ' + parts.join(' > ') : parts.join(' > ');
      }

      function outline(element) {
        target = element;
        if (!element) { box.style.display = 'none'; return; }
        var rect = element.getBoundingClientRect();
        box.style.display = 'block';
        box.style.left = rect.left + 'px';
        box.style.top = rect.top + 'px';
        box.style.width = rect.width + 'px';
        box.style.height = rect.height + 'px';
        label.style.top = rect.top < 22 ? '2px' : '-20px';
        label.textContent = describe(element);
      }

      function swallow(event) {
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();
      }

      function onMove(event) {
        var element = document.elementFromPoint(event.clientX, event.clientY);
        // Compare with what was hovered, not what is outlined: after widening
        // with the arrow keys, a small wobble of the pointer must not undo it.
        if (isRoot(element) || element === hovered) { return; }
        hovered = element;
        trail = [];
        outline(element);
      }

      function onClick(event) {
        swallow(event);
        if (!target) { return; }
        var selector = selectorFor(target);
        if (!selector) { return; }
        target.style.setProperty('display', 'none', 'important');
        post({ type: 'hide', selector: selector, host: location.hostname });
        hovered = null;
        trail = [];
        outline(null);
      }

      function onKey(event) {
        if (event.key === 'Escape' || event.key === 'Enter') {
          swallow(event);
          stop();
          post({ type: 'done' });
        } else if (event.key === 'ArrowUp') {
          swallow(event);
          if (target && !isRoot(target.parentElement)) {
            trail.push(target);
            outline(target.parentElement);
          }
        } else if (event.key === 'ArrowDown') {
          swallow(event);
          if (trail.length) { outline(trail.pop()); }
        }
      }

      function onScroll() {
        if (target) { outline(target); }
      }

      var listeners = [
        ['mousemove', onMove], ['click', onClick], ['keydown', onKey], ['scroll', onScroll],
        ['mousedown', swallow], ['mouseup', swallow], ['pointerdown', swallow], ['pointerup', swallow],
        ['auxclick', swallow], ['contextmenu', swallow]
      ];
      listeners.forEach(function (entry) { window.addEventListener(entry[0], entry[1], true); });

      function stop() {
        listeners.forEach(function (entry) { window.removeEventListener(entry[0], entry[1], true); });
        box.remove();
        delete window.__ganderPicker;
      }

      window.__ganderPicker = { stop: stop, selectorFor: selectorFor };
    })();
    """#
}
