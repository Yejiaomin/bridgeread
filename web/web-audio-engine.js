// Web Audio API engine for BridgeRead
// Uses AudioContext (unlocked once by user gesture) for guaranteed playback.
// After unlock, createBufferSource().start() works from ANY context (timers, callbacks).
//
// Two channels:
//   Main: sequential narration/word audio (one at a time)
//   SFX:  fire-and-forget overlapping sounds

(function() {
  'use strict';

  var ctx = null;        // AudioContext — created + resumed on first user tap
  var mainSource = null; // current BufferSourceNode
  var mainBuffer = null; // current AudioBuffer being played
  var mainStartTime = 0; // ctx.currentTime when play started
  var mainOffset = 0;    // seek offset in seconds
  var mainPaused = false;
  var mainPausedAt = 0;  // how far into the buffer we were when paused

  var bufferCache = {};  // url → AudioBuffer (decoded, ready to play)
  var onEndCb = null;
  var onPositionCb = null;
  var posInterval = null;

  // ── Init: create AudioContext on first user gesture ─────────────────────

  function ensureContext() {
    if (ctx) return;
    ctx = new (window.AudioContext || window.webkitAudioContext)();
    console.log('[WebAudio] AudioContext created, state:', ctx.state);
  }

  // Unlock on ANY user gesture (touch, click, keydown)
  function unlock() {
    ensureContext();
    if (ctx.state === 'suspended') {
      ctx.resume().then(function() {
        console.log('[WebAudio] AudioContext unlocked!');
      });
    }
  }

  document.addEventListener('touchstart', unlock, { once: false, passive: true });
  document.addEventListener('touchend', unlock, { once: false, passive: true });
  document.addEventListener('click', unlock, { once: false, passive: true });

  // ── Buffer loading & caching ───────────────────────────────────────────

  function loadBuffer(url) {
    if (bufferCache[url]) return Promise.resolve(bufferCache[url]);

    return fetch(url)
      .then(function(res) {
        if (!res.ok) throw new Error('fetch failed: ' + res.status);
        return res.arrayBuffer();
      })
      .then(function(data) {
        ensureContext();
        return ctx.decodeAudioData(data);
      })
      .then(function(buffer) {
        bufferCache[url] = buffer;
        return buffer;
      })
      .catch(function(err) {
        console.warn('[WebAudio] load error:', url, err);
        return null;
      });
  }

  // ── Position tracking ──────────────────────────────────────────────────

  function stopPositionTracking() {
    if (posInterval) { clearInterval(posInterval); posInterval = null; }
  }

  function startPositionTracking() {
    stopPositionTracking();
    posInterval = setInterval(function() {
      if (onPositionCb && mainSource && !mainPaused) {
        var pos = (ctx.currentTime - mainStartTime + mainOffset) * 1000;
        onPositionCb(Math.floor(pos));
      }
    }, 100);
  }

  // ── Main player ────────────────────────────────────────────────────────

  function stopMain() {
    stopPositionTracking();
    if (mainSource) {
      try { mainSource.onended = null; mainSource.stop(); } catch(e) {}
      mainSource = null;
    }
    mainPaused = false;
    mainOffset = 0;
  }

  function playBuffer(buffer, offset) {
    ensureContext();
    stopMain();

    mainBuffer = buffer;
    mainSource = ctx.createBufferSource();
    mainSource.buffer = buffer;
    mainSource.connect(ctx.destination);

    mainSource.onended = function() {
      // Only fire onEnd if we didn't manually stop
      if (mainSource) {
        mainSource = null;
        stopPositionTracking();
        if (onEndCb) onEndCb();
      }
    };

    mainOffset = offset || 0;
    mainStartTime = ctx.currentTime;
    mainPaused = false;
    mainSource.start(0, mainOffset);
    startPositionTracking();
  }

  // ── Public API ─────────────────────────────────────────────────────────

  window._brWebAudio = {
    // Load + decode an audio file (returns Promise)
    preload: function(url) {
      return loadBuffer(url);
    },

    // Play audio from URL (loads if needed, plays immediately if cached)
    play: function(url) {
      ensureContext();
      var cached = bufferCache[url];
      if (cached) {
        playBuffer(cached, 0);
      } else {
        // Load then play
        loadBuffer(url).then(function(buffer) {
          if (buffer) playBuffer(buffer, 0);
          else if (onEndCb) onEndCb(); // load failed, treat as ended
        });
      }
    },

    pause: function() {
      if (mainSource && !mainPaused) {
        mainPausedAt = ctx.currentTime - mainStartTime + mainOffset;
        try { mainSource.onended = null; mainSource.stop(); } catch(e) {}
        mainSource = null;
        mainPaused = true;
        stopPositionTracking();
      }
    },

    resume: function() {
      if (mainPaused && mainBuffer) {
        playBuffer(mainBuffer, mainPausedAt);
      }
    },

    stop: function() {
      stopMain();
    },

    seek: function(ms) {
      if (mainBuffer) {
        var sec = ms / 1000;
        if (sec < 0) sec = 0;
        if (sec > mainBuffer.duration) sec = mainBuffer.duration;
        if (mainPaused) {
          mainPausedAt = sec;
        } else {
          playBuffer(mainBuffer, sec);
        }
      }
    },

    isPlaying: function() {
      return mainSource != null && !mainPaused;
    },

    getDuration: function() {
      return mainBuffer ? Math.floor(mainBuffer.duration * 1000) : 0;
    },

    getPosition: function() {
      if (!mainSource || mainPaused) {
        return Math.floor((mainPausedAt || 0) * 1000);
      }
      return Math.floor((ctx.currentTime - mainStartTime + mainOffset) * 1000);
    },

    onEnd: function(cb) { onEndCb = cb; },
    onPosition: function(cb) { onPositionCb = cb; },

    // ── SFX (fire-and-forget, overlaps with main) ────────────────────────
    playSfx: function(url) {
      ensureContext();
      var cached = bufferCache[url];
      if (cached) {
        var src = ctx.createBufferSource();
        src.buffer = cached;
        src.connect(ctx.destination);
        src.start(0);
      } else {
        loadBuffer(url).then(function(buffer) {
          if (buffer) {
            var src = ctx.createBufferSource();
            src.buffer = buffer;
            src.connect(ctx.destination);
            src.start(0);
          }
        });
      }
    },

    // ── Batch preload (for preloader) ────────────────────────────────────
    preloadBatch: function(urls) {
      return Promise.all(urls.map(function(u) { return loadBuffer(u); }));
    },

    // Debug
    cacheSize: function() { return Object.keys(bufferCache).length; },
    isUnlocked: function() { return ctx && ctx.state === 'running'; }
  };
})();
