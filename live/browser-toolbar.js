'use strict';
(() => {
  let host = document;
  try {if (window.parent !== window && window.parent.document.querySelector('#stage')) host = window.parent.document;} catch (_) {}
  let toolbar = host.querySelector('#browser-toolbar');
  if (!toolbar) {
    const style = host.createElement('style');
    style.textContent = `
      #browser-toolbar{position:fixed;right:8px;top:50%;transform:translateY(-50%);display:flex;flex-direction:column;gap:8px;align-items:center;z-index:1200;background:none;border:0;padding:0}
      #browser-toolbar .browser-tool-button{position:static;display:inline-flex;align-items:center;justify-content:center;flex:none;width:34px;height:34px;padding:8px;border:0;border-radius:7px;background:transparent;color:#c3c4ca;cursor:pointer}
      #browser-toolbar .browser-tool-button:hover{color:#fff;background:#272a31}#browser-toolbar .browser-tool-button:focus-visible{outline:2px solid #ed8a3a;outline-offset:2px}
      #browser-toolbar svg{display:block;width:18px;height:18px;fill:none;stroke:currentColor;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}
      body:has(>#stage){box-sizing:border-box;padding:0 48px}
      body>#stage{width:min(calc(100vw - 96px),177.777778vh);height:min(calc((100vw - 96px)*.5625),100vh)}
      @supports(height:100dvh){body>#stage{width:min(calc(100vw - 96px),177.777778dvh);height:min(calc((100vw - 96px)*.5625),100dvh)}}
      @media(max-width:600px){#browser-toolbar{right:4px;gap:6px}#browser-toolbar .browser-tool-button{width:30px;height:30px;padding:6px}body:has(>#stage){padding:0 38px}body>#stage{width:min(calc(100vw - 76px),177.777778dvh);height:min(calc((100vw - 76px)*.5625),100dvh)}}
    `;
    style.textContent += `
      html:fullscreen body:has(>#stage),html:-webkit-full-screen body:has(>#stage){padding:0}
      html:fullscreen body>#stage,html:-webkit-full-screen body>#stage{width:min(100vw,177.777778vh);height:min(56.25vw,100vh)}
      @supports(height:100dvh){html:fullscreen body>#stage,html:-webkit-full-screen body>#stage{width:min(100vw,177.777778dvh);height:min(56.25vw,100dvh)}}
      html:fullscreen #browser-toolbar,html:-webkit-full-screen #browser-toolbar{right:16px}
      html:fullscreen #browser-toolbar .browser-tool-button,html:-webkit-full-screen #browser-toolbar .browser-tool-button{background:#15171c99;color:#fff}
      html:fullscreen #canvas,html:-webkit-full-screen #canvas{width:min(100vw,177.777778vh)!important;height:min(56.25vw,100vh)!important}
      @supports(height:100dvh){html:fullscreen #canvas,html:-webkit-full-screen #canvas{width:min(100vw,177.777778dvh)!important;height:min(56.25vw,100dvh)!important}}
    `;
    host.head.append(style);
    toolbar = host.createElement('nav');
    toolbar.id = 'browser-toolbar';
    toolbar.setAttribute('aria-label','Game controls');
    host.body.append(toolbar);
  }
  if (host === document && !host.querySelector('#stage')) {
    const style = host.createElement('style');
    style.textContent = `#canvas{position:fixed!important;left:50%!important;top:50%!important;transform:translate(-50%,-50%);width:min(calc(100vw - 96px),177.777778vh)!important;height:min(calc((100vw - 96px)*.5625),100vh)!important}@media(max-width:600px){#canvas{width:min(calc(100vw - 76px),177.777778dvh)!important;height:min(calc((100vw - 76px)*.5625),100dvh)!important}}`;
    host.head.append(style);
  }
  window.MarsBrowserToolbar = {host, toolbar};
})();
