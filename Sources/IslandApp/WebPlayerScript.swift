import Foundation

/// Runs in playback pages, including child frames. It reads media metadata only.
/// Password fields, cookies and authentication tokens never enter the bridge.
enum WebPlayerScript {
    static let source = #"""
    (() => {
      if (window.__soloIsland) return;
      const handlers = Object.create(null);
      const ms = navigator.mediaSession;
      let positionState = null;
      if (ms && typeof ms.setActionHandler === 'function') {
        const original = ms.setActionHandler.bind(ms);
        try { ms.setActionHandler = function(action, handler) {
          const result = original(action, handler);
          handlers[action] = handler;
          return result;
        }; } catch (_) {}
      }
      // Some services expose metadata/controls through Media Session while
      // their audio element is outside the page's DOM. Keep the position the
      // service itself publishes, without inspecting its internal account/API.
      if (ms && typeof ms.setPositionState === 'function') {
        const originalPosition = ms.setPositionState.bind(ms);
        try { ms.setPositionState = function(state) {
          const result = originalPosition(state);
          positionState = state && Number.isFinite(state.duration) && state.duration > 0
            && Number.isFinite(state.position) && state.position >= 0
            ? {duration:state.duration, position:state.position, rate:Number.isFinite(state.playbackRate) ? state.playbackRate : 1,
               at:Date.now(), title:ms.metadata?.title || ''} : null;
          return result;
        }; } catch (_) {}
      }
      const pick = selectors => {
        for (const selector of selectors) { const el = document.querySelector(selector); if (el) return el; }
        return null;
      };
      let selectedMedia = null;
      const media = () => {
        const all = Array.from(document.querySelectorAll('audio,video'));
        selectedMedia = all.find(el => !el.paused && !el.ended) || (all.includes(selectedMedia) ? selectedMedia : null) || all.find(el => el.currentTime > 0) || all[0];
        return selectedMedia;
      };
      const finite = x => Number.isFinite(x) ? x : null;
      const text = selectors => (pick(selectors)?.textContent || '').trim().slice(0, 512);
      const snapshot = () => {
        const el = media(), meta = ms?.metadata;
        const position = positionState && (!positionState.title || positionState.title === meta?.title) ? positionState : null;
        const useSessionPosition = position && (!el || !Number.isFinite(el.duration) || el.duration <= 0);
        const sessionTime = position ? Math.min(position.duration, position.position
          + (ms?.playbackState === 'playing' ? Math.max(0, Date.now() - position.at) / 1000 * position.rate : 0)) : null;
        const title = meta?.title || (el ? text([
          '[data-testid="context-item-info-title"]', '.playbackSoundBadge__titleLink',
          '.title.ytmusic-player-bar', '[class*="PlayerBarDesktop_trackName"]', '.player-progress__title'
        ]) : '');
        const artist = meta?.artist || (el ? text([
          '[data-testid="context-item-info-subtitles"]', '.playbackSoundBadge__lightLink',
          '.byline.ytmusic-player-bar', '[class*="PlayerBarDesktop_artist"]', '.player__artist'
        ]) : '');
        const image = meta?.artwork?.slice(-1)[0]?.src || pick([
          'ytmusic-player-bar img', '[data-testid="now-playing-widget"] img', '.playbackSoundBadge__avatar img'
        ])?.src || null;
        return { title: String(title).trim().slice(0,512), artist: String(artist).slice(0,512),
          playing: !!(useSessionPosition ? ms?.playbackState === 'playing' : el ? !el.paused && !el.ended : ms?.playbackState === 'playing'),
          duration: (el ? finite(el.duration) : null) ?? position?.duration ?? null,
          elapsedTime: useSessionPosition ? sessionTime : (el ? finite(el.currentTime) : null) ?? sessionTime,
          playbackRate: (el ? finite(el.playbackRate) : null) ?? position?.rate ?? 1, artworkURL: image ? String(image).slice(0,2048) : null };
      };
      const controls = {
        'next-track': ['nexttrack', ['[data-testid="control-button-skip-forward"]', '.player-controls__btn_next', '[class*="PlayerBarDesktop_next"]', 'ytmusic-player-bar .next-button', '.skipControl__next', 'button[aria-label="Next track"]', 'button[aria-label="Следующий трек"]']],
        'previous-track': ['previoustrack', ['[data-testid="control-button-skip-back"]', '.player-controls__btn_prev', '[class*="PlayerBarDesktop_previous"]', 'ytmusic-player-bar .previous-button', '.skipControl__previous', 'button[aria-label="Previous track"]', 'button[aria-label="Предыдущий трек"]']]
      };
      const command = async (action, value) => {
        const el = media();
        if (action === 'seek') {
          if (!Number.isFinite(value) || value < 0) return 'unavailable';
          if (handlers.seekto) { handlers.seekto({action:'seekto',seekTime:value,fastSeek:false}); return 'ok'; }
          if (el && Number.isFinite(el.duration)) { el.currentTime = Math.min(value, el.duration); return 'ok'; }
        } else if (action === 'toggle-play-pause') {
          const playing = el ? !el.paused : ms?.playbackState === 'playing';
          const name = playing ? 'pause' : 'play';
          if (handlers[name]) { await handlers[name]({action:name}); return 'ok'; }
          if (el) { if (playing) el.pause(); else await el.play(); return 'ok'; }
        } else if (controls[action]) {
          const [name, selectors] = controls[action];
          if (handlers[name]) { await handlers[name]({action:name}); return 'ok'; }
          const button = pick(selectors);
          if (button && !button.disabled && button.getAttribute('aria-disabled') !== 'true') { button.click(); return 'ok'; }
        }
        return 'unavailable';
      };
      const send = () => {
        try { window.webkit?.messageHandlers?.soloPlayer?.postMessage(snapshot()); } catch (_) {}
      };
      window.__soloIsland = {snapshot,command,send};
      setInterval(send, 500);
      document.addEventListener('play', send, true);
      document.addEventListener('pause', send, true);
      document.addEventListener('loadedmetadata', send, true);
      send();
    })();
    """#
}
