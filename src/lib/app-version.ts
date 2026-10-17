export const APP_VERSION = import.meta.env.VITE_APP_VERSION || 'local';
const RELOAD_KEY = 'stride-version-reload-to';

export function watchAppVersion(): () => void {
  let checking = false;
  const check = async () => {
    if (checking || !navigator.onLine) return;
    checking = true;
    try {
      const response = await fetch(`/version.json?check=${Date.now()}`, { cache: 'no-store', headers: { 'Cache-Control': 'no-cache' } });
      if (!response.ok) return;
      const remote = await response.json() as { commit?: string };
      if (!remote.commit || remote.commit === APP_VERSION || sessionStorage.getItem(RELOAD_KEY) === remote.commit) return;
      sessionStorage.setItem(RELOAD_KEY, remote.commit);
      const registrations = await navigator.serviceWorker?.getRegistrations() ?? [];
      await Promise.all(registrations.map((registration) => registration.unregister()));
      const cacheNames = await caches.keys();
      await Promise.all(cacheNames.map((name) => caches.delete(name)));
      window.location.reload();
    } catch (error) {
      console.warn('Could not check for a newer StrideStock app version.', error);
    } finally {
      checking = false;
    }
  };
  void check();
  const timer = window.setInterval(() => void check(), 5 * 60 * 1000);
  window.addEventListener('focus', check);
  return () => { window.clearInterval(timer); window.removeEventListener('focus', check); };
}
