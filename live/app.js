'use strict';
const browserNotice = document.querySelector('#browser-notice');
document.querySelector('#play-link').addEventListener('click', event => {
  event.preventDefault();
  if (event.currentTarget.getAttribute('aria-disabled') !== 'true') browserNotice.showModal();
});
document.querySelector('#cancel-browser').addEventListener('click', () => browserNotice.close());
const dialog = document.querySelector('#downloads');
document.querySelector('#download-button').addEventListener('click', () => dialog.showModal());
dialog.addEventListener('click', event => {if (event.target === dialog) {const rect = dialog.getBoundingClientRect(); if(event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) dialog.close();}});
function enableLink(id, path) {
  const url = new URL(path, location.href);
  const releaseDownload = url.origin === 'https://github.com' && /^\/(?:MaanasEgamamidi\/(?:MissionPossible|MissionPossbile)|udaykamboj\/mission-possible-live)\/releases\/download\//.test(url.pathname);
  if (url.origin !== location.origin && !releaseDownload) throw new Error('Invalid build URL');
  const link = document.querySelector(id);
  link.href = url.href;
  link.removeAttribute('aria-disabled');
}
fetch('builds.json', {cache: 'no-cache'})
  .then(response => {if (!response.ok) throw new Error('No builds'); return response.json();})
  .then(builds => {
    if (builds.web) { enableLink('#play-link', builds.web); enableLink('#continue-browser', builds.web); }
    if (builds.windows) enableLink('#windows-link', builds.windows);
    if (builds.macos) enableLink('#macos-link', builds.macos);
  })
  .catch(() => {});
