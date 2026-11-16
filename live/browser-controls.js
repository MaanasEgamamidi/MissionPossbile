'use strict';
(() => {
  const started = performance.now();
  const mount = window.MarsBrowserToolbar || {host:document, toolbar:document.body};
  const style = document.createElement('style');
  style.textContent = `
    #browser-fullscreen{position:fixed;top:16px;right:16px;z-index:1200;padding:10px 15px;border:1px solid #7778;border-radius:7px;background:#191c23e8;color:#fff;font:500 13px system-ui;cursor:pointer}
    #browser-loading{position:fixed;inset:0;z-index:1100;display:flex;flex-direction:column;gap:16px;align-items:center;justify-content:center;background:#111318;color:#f4f1ed;font:15px system-ui}
    #browser-loading[hidden]{display:none}
    #browser-loading .loader{width:34px;height:34px;border:3px solid #424348;border-top-color:#ed8a3a;border-radius:50%;animation:browser-spin 1s linear infinite}
    #browser-loading p{margin:0;color:#a9a9ad;font-size:13px;max-width:420px;text-align:center;padding:0 24px}
    @keyframes browser-spin{to{transform:rotate(360deg)}}
    @media(prefers-reduced-motion:reduce){#browser-loading .loader{animation:none}}
  `;
  document.head.append(style);
  const fullscreen = document.createElement('button');
  fullscreen.id = 'browser-fullscreen';
  fullscreen.className = 'browser-tool-button';
  fullscreen.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5"/></svg>';
  fullscreen.title = 'Enter fullscreen';
  fullscreen.type = 'button';
  fullscreen.setAttribute('aria-label', 'Enter fullscreen');
  mount.toolbar.append(fullscreen);
  let host = document;
  try { if (window.parent !== window && window.parent.document) host = window.parent.document; } catch (_) {}
  function updateFullscreen() {
    const active = Boolean(host.fullscreenElement || host.webkitFullscreenElement);
    fullscreen.title = active ? 'Exit fullscreen' : 'Enter fullscreen';
    fullscreen.setAttribute('aria-label', active ? 'Exit fullscreen' : 'Enter fullscreen');
  }
  fullscreen.addEventListener('click', async () => {
    try {
      if (host.fullscreenElement || host.webkitFullscreenElement) {
        if (host.exitFullscreen) await host.exitFullscreen();
        else host.webkitExitFullscreen?.();
      } else {
        if (host.documentElement.requestFullscreen) await host.documentElement.requestFullscreen();
        else host.documentElement.webkitRequestFullscreen?.();
      }
    } catch (_) {
      fullscreen.title = 'Fullscreen unavailable in this browser';
    }
  });
  host.addEventListener('fullscreenchange', updateFullscreen);
  host.addEventListener('webkitfullscreenchange', updateFullscreen);
  const loading = document.createElement('div');
  loading.id = 'browser-loading';
  loading.setAttribute('role', 'status');
  loading.setAttribute('aria-live', 'polite');
  const spinner = document.createElement('div');
  spinner.className = 'loader';
  spinner.setAttribute('aria-hidden', 'true');
  const title = document.createElement('div');
  title.textContent = 'Loading…';
  const detail = document.createElement('p');
  detail.textContent = 'This may take a moment.';
  loading.append(spinner, title, detail);
  document.body.append(loading);
  let finishing = false;
  const observer = new MutationObserver(syncLoading);
  function syncLoading() {
    if (finishing) return;
    const status = document.querySelector('#status');
    if (!status) {
      finishing = true;
      observer.disconnect();
      setTimeout(() => { loading.hidden = true; }, Math.max(0, 2000 - (performance.now() - started)));
      return;
    }
    const notice = document.querySelector('#status-notice');
    if (notice && getComputedStyle(notice).display !== 'none' && notice.textContent.trim()) {
      spinner.hidden = true;
      if (title.textContent !== 'Unable to load game') title.textContent = 'Unable to load game';
      const errorText = notice.textContent.trim();
      if (detail.textContent !== errorText) detail.textContent = errorText;
      return;
    }
    const progress = document.querySelector('#status-progress');
    if (progress?.hasAttribute('value') && progress.max > 0) {
      const label = `Loading… ${Math.min(100, Math.round(progress.value / progress.max * 100))}%`;
      if (title.textContent !== label) title.textContent = label;
    }
  }
  observer.observe(document.body, {childList:true, subtree:true, attributes:true, attributeFilter:['value','max','style'], characterData:true});
  syncLoading();
})();
