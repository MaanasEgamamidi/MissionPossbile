'use strict';
(() => {
  const profiles = [
    {name:'Performance', width:1280, height:720, detail:'720p output, reduced detail, no shadows. Best for smooth play.'},
    {name:'Balanced', width:1600, height:900, detail:'900p output, clearer rendering and sun shadows. Uses more GPU power.'},
    {name:'Quality', width:1920, height:1080, detail:'1080p output, full material detail and light shadows. Most demanding.'}
  ];
  function read(key, fallback) { try {return localStorage.getItem(key) ?? fallback;} catch (_) {return fallback;} }
  const active = Math.max(0, Math.min(2, Number(read('mars-browser-quality', '0')) || 0));
  const canvas = document.querySelector('#canvas');
  if (canvas) {canvas.width = profiles[active].width; canvas.height = profiles[active].height;}
  const mount = window.MarsBrowserToolbar || {host:document, toolbar:document.body};
  const style = mount.host.createElement('style');
  style.textContent = `
    #browser-settings-button{position:fixed;top:16px;left:16px;z-index:1200;padding:10px 15px;border:1px solid #7778;border-radius:7px;background:#191c23e8;color:#fff;font:500 13px system-ui;cursor:pointer}
    #browser-settings{box-sizing:border-box;width:min(440px,calc(100vw - 32px));max-height:calc(100vh - 32px);overflow:auto;border:1px solid #52545b;border-radius:12px;padding:28px;background:#1a1d24;color:#f4f1ed;font:14px/1.6 system-ui;box-shadow:0 16px 80px #0009}
    #browser-settings::backdrop{background:#000a}#browser-settings h2{font-size:21px;font-weight:600;margin:0 0 20px}
    #browser-settings label{display:block;margin:16px 0 8px}#browser-settings select{box-sizing:border-box;width:100%;padding:12px;background:#282c35;border:1px solid #5a5e69;border-radius:6px;color:#fff;font:inherit}
    #browser-settings p{color:#b5b7be;font-size:12px;margin:12px 0}#browser-settings .settings-actions{display:flex;gap:12px;margin-top:24px}
    #browser-settings button{flex:1;padding:12px;border:1px solid #60636b;border-radius:6px;background:#2a2e38;color:#fff;font:500 13px system-ui;cursor:pointer}
    #browser-settings #apply-browser-settings{background:#ed8a3a;border-color:#ed8a3a;color:#211b17}
  `;
  mount.host.head.append(style);
  const button = document.createElement('button');
  button.id = 'browser-settings-button';button.className = 'browser-tool-button';button.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9.5 3-.5 2.2-2 .9-2-.7-2.5 4.2 1.6 1.6v1.6l-1.6 1.6L5 18.6l2-.7 2 .9.5 2.2h5l.5-2.2 2-.9 2 .7 2.5-4.2-1.6-1.6v-1.6l1.6-1.6L19 5.4l-2 .7-2-.9-.5-2.2Z"/><circle cx="12" cy="12" r="3"/></svg>';button.type = 'button';button.title = 'Settings';button.setAttribute('aria-label','Settings');
  const dialog = mount.host.createElement('dialog');dialog.id = 'browser-settings';dialog.setAttribute('aria-labelledby','browser-settings-title');
  dialog.innerHTML = `<h2 id="browser-settings-title">Browser graphics</h2>
    <label for="browser-quality">Graphics quality</label><select id="browser-quality"><option value="0">Performance</option><option value="1">Balanced</option><option value="2">Quality</option></select>
    <p id="browser-quality-description"></p>
    <label for="browser-fps">Frame rate limit</label><select id="browser-fps"><option value="30">30 FPS · Lower power use</option><option value="60">60 FPS · Recommended</option><option value="120">120 FPS · More demanding</option></select>
    <p>Higher settings may reduce performance. Some desktop effects are unavailable in browsers.</p>
    <p>Applying restarts the browser game. Save your progress first.</p>
    <p id="browser-settings-error" role="status"></p>
    <div class="settings-actions"><button id="cancel-browser-settings" type="button">Cancel</button><button id="apply-browser-settings" type="button">Apply & restart</button></div>`;
  mount.toolbar.prepend(button);
  mount.host.body.append(dialog);
  const quality = dialog.querySelector('#browser-quality');
  const fps = dialog.querySelector('#browser-fps');
  const description = dialog.querySelector('#browser-quality-description');
  const describe = () => {description.textContent = profiles[Number(quality.value)].detail;};
  button.addEventListener('click', () => {
    window.MarsBrowserMouse?.setOverlayOpen(true);
    if (document.pointerLockElement) document.exitPointerLock();
    quality.value = String(active);
    fps.value = ['30','60','120'].includes(read('mars-browser-fps','60')) ? read('mars-browser-fps','60') : '60';
    describe();dialog.showModal();
  });
  quality.addEventListener('change',describe);
  dialog.querySelector('#cancel-browser-settings').addEventListener('click',()=>dialog.close());
  dialog.addEventListener('close',()=>window.MarsBrowserMouse?.setOverlayOpen(false));
  dialog.querySelector('#apply-browser-settings').addEventListener('click',()=>{
    try {
      localStorage.setItem('mars-browser-quality',quality.value);
      localStorage.setItem('mars-browser-fps',fps.value);
      location.reload();
    } catch (_) {dialog.querySelector('#browser-settings-error').textContent = 'Your browser is blocking saved settings. Allow site storage to change graphics.';}
  });
})();
