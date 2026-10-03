// Full-window viewer for the Mermaid diagrams: an expand button on each one,
// then wheel or buttons to zoom, drag to pan, Esc to close.
//
// Material for MkDocs renders every diagram into a *closed* shadow root, which
// no script can read. This file loads after Material's bundle but before the
// Mermaid library arrives, so it asks for open shadow roots on Mermaid hosts
// only, then clones the finished SVG into the viewer. Nothing is re-rendered.
(function () {
  "use strict";

  var attach = Element.prototype.attachShadow;
  Element.prototype.attachShadow = function (init) {
    if (this.classList && this.classList.contains("mermaid")) {
      init = Object.assign({}, init, { mode: "open" });
    }
    return attach.call(this, init);
  };

  var dialog, stage, svgHolder, scale = 1, x = 0, y = 0;

  function apply() {
    svgHolder.style.transform = "translate(" + x + "px," + y + "px) scale(" + scale + ")";
  }

  function zoom(factor, cx, cy) {
    var rect = stage.getBoundingClientRect();
    cx = cx === undefined ? rect.width / 2 : cx - rect.left;
    cy = cy === undefined ? rect.height / 2 : cy - rect.top;
    var next = Math.min(8, Math.max(0.2, scale * factor));
    // keep the point under the cursor where it is
    x = cx - (cx - x) * (next / scale);
    y = cy - (cy - y) * (next / scale);
    scale = next;
    apply();
  }

  function fit() {
    var svg = svgHolder.querySelector("svg");
    var box = svg.getBoundingClientRect();
    var w = box.width / scale, h = box.height / scale;
    var rect = stage.getBoundingClientRect();
    scale = Math.min(rect.width / w, rect.height / h) * 0.95;
    x = (rect.width - w * scale) / 2;
    y = (rect.height - h * scale) / 2;
    apply();
  }

  function build() {
    dialog = document.createElement("dialog");
    dialog.className = "dz-dialog";
    dialog.setAttribute("aria-label", "Diagram viewer");
    dialog.innerHTML =
      '<div class="dz-bar">' +
      '<span class="dz-hint">Scroll to zoom, drag to move, Esc to close</span>' +
      '<button type="button" data-dz="in" title="Zoom in" aria-label="Zoom in">+</button>' +
      '<button type="button" data-dz="out" title="Zoom out" aria-label="Zoom out">&minus;</button>' +
      '<button type="button" data-dz="fit" title="Fit to window" aria-label="Fit to window">Fit</button>' +
      '<button type="button" data-dz="close" title="Close" aria-label="Close">&times;</button>' +
      "</div>" +
      '<div class="dz-stage"><div class="dz-svg"></div></div>';
    document.body.appendChild(dialog);
    stage = dialog.querySelector(".dz-stage");
    svgHolder = dialog.querySelector(".dz-svg");

    dialog.addEventListener("click", function (e) {
      var action = e.target.getAttribute && e.target.getAttribute("data-dz");
      if (action === "in") zoom(1.25);
      if (action === "out") zoom(0.8);
      if (action === "fit") fit();
      if (action === "close") dialog.close();
    });
    stage.addEventListener("wheel", function (e) {
      e.preventDefault();
      zoom(e.deltaY < 0 ? 1.15 : 0.87, e.clientX, e.clientY);
    }, { passive: false });

    var dragging = false, sx = 0, sy = 0;
    stage.addEventListener("pointerdown", function (e) {
      dragging = true; sx = e.clientX - x; sy = e.clientY - y;
      stage.setPointerCapture(e.pointerId);
    });
    stage.addEventListener("pointermove", function (e) {
      if (!dragging) return;
      x = e.clientX - sx; y = e.clientY - sy; apply();
    });
    stage.addEventListener("pointerup", function () { dragging = false; });
    dialog.addEventListener("close", function () { svgHolder.innerHTML = ""; });
  }

  function open(host) {
    var svg = host.shadowRoot && host.shadowRoot.querySelector("svg");
    if (!svg) return;
    if (!dialog) build();
    var copy = svg.cloneNode(true);
    copy.removeAttribute("style");            // drop Mermaid's max-width
    copy.setAttribute("width", svg.getBoundingClientRect().width);
    copy.setAttribute("height", svg.getBoundingClientRect().height);
    svgHolder.innerHTML = "";
    svgHolder.appendChild(copy);
    scale = 1; x = 0; y = 0; apply();
    dialog.showModal();
    fit();
  }

  function enhance(host) {
    if (host.dataset.dzReady || !host.shadowRoot || !host.shadowRoot.querySelector("svg")) return;
    host.dataset.dzReady = "1";
    var wrap = document.createElement("div");
    wrap.className = "dz-wrap";
    host.parentNode.insertBefore(wrap, host);
    wrap.appendChild(host);
    var button = document.createElement("button");
    button.type = "button";
    button.className = "dz-open";
    button.title = "Open the diagram full window";
    button.setAttribute("aria-label", "Open the diagram full window");
    button.textContent = "⤢ Expand";
    button.addEventListener("click", function () { open(host); });
    host.addEventListener("click", function () { open(host); });
    wrap.appendChild(button);
  }

  function scan() {
    document.querySelectorAll("div.mermaid").forEach(enhance);
  }

  new MutationObserver(scan).observe(document.documentElement, { childList: true, subtree: true });
  document.addEventListener("DOMContentLoaded", scan);
})();
