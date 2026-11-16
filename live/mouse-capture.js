'use strict';
(() => {
  const canvas = document.querySelector('#canvas');
  if (!canvas) return;
  let gameplay = false;
  let overlayOpen = false;
  const nativeLock = canvas.requestPointerLock?.bind(canvas);
  const panel = document.createElement('div');
  panel.id = 'mouse-capture';
  panel.hidden = true;
  panel.style.cssText = 'position:fixed;right:16px;top:66px;z-index:1000;max-width:330px;padding:10px;border-radius:8px;background:#17191eed;color:#fff;font:13px/1.5 system-ui';
  const button = document.createElement('button');
  button.textContent = 'Click to resume mouse look';
  button.style.cssText = 'cursor:pointer;padding:10px 16px;border:1px solid #f1a15c;border-radius:6px;background:#ed8a3a;color:#211b17;font:600 13px system-ui';
  const message = document.createElement('div');
  message.setAttribute('role', 'status');
  panel.append(button, message);
  document.body.append(panel);
  function sync() {
    const locked = document.pointerLockElement === canvas;
    panel.hidden = !gameplay || overlayOpen || locked;
    canvas.style.cursor = (!gameplay || overlayOpen) ? 'auto' : locked ? 'none' : 'auto';
  }
  function failure() {
    if (!gameplay) return;
    message.textContent = 'Mouse capture is blocked. Try Chrome or Firefox, or download the desktop game.';
    sync();
  }
  function capture() {
    if (!gameplay || overlayOpen || document.pointerLockElement === canvas) return;
    if (!nativeLock) { failure(); return; }
    try {
      const result = nativeLock();
      if (result?.catch) result.catch(failure);
      return result;
    } catch (_) { failure(); }
  }
  // The game tells this bridge whether a menu or gameplay currently owns input.
  window.MarsBrowserMouse = {
    setOverlayOpen(open) {
      overlayOpen = Boolean(open);
      if (overlayOpen && document.pointerLockElement === canvas) document.exitPointerLock();
      sync();
    },
    setGameplay(enabled) {
      gameplay = Boolean(enabled);
      message.textContent = '';
      if ((!gameplay || overlayOpen) && document.pointerLockElement === canvas) document.exitPointerLock();
      sync();
    }
  };
  // Prevent stale engine capture requests from hiding the cursor over menus.
  if (nativeLock) canvas.requestPointerLock = capture;
  button.addEventListener('click', () => { canvas.focus(); capture(); });
  document.addEventListener('pointerlockchange', () => {
    if ((!gameplay || overlayOpen) && document.pointerLockElement === canvas) document.exitPointerLock();
    sync();
  });
  document.addEventListener('pointerlockerror', failure);
  canvas.addEventListener('pointerdown', () => canvas.focus());
})();
