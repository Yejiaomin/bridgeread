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
  var onLoadingCb = null; // called with true=loading, false=ready
  var posInterval = null;
  var retryCount = 0;     // prevent infinite retry loops
  var MAX_RETRIES = 3;

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

  // Auto-resume AudioContext if iOS suspends it
  setInterval(function() {
    if (ctx && ctx.state === 'interrupted') {
      console.warn('[WebAudio] Context interrupted, resuming...');
      ctx.resume();
    }
    if (ctx && ctx.state === 'suspended' && mainSource) {
      console.warn('[WebAudio] Context suspended during playback, resuming...');
      ctx.resume();
    }
  }, 500);

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
      if (!mainSource) return; // manually stopped

      // Check if audio actually finished or was interrupted
      var elapsed = ctx.currentTime - mainStartTime + mainOffset;
      var duration = buffer.duration;
      var pctPlayed = duration > 0 ? elapsed / duration : 1;

      if (pctPlayed < 0.85 && duration > 1 && retryCount < MAX_RETRIES) {
        // Audio ended prematurely — likely iOS context interruption
        retryCount++;
        console.warn('[WebAudio] Premature end at ' + (pctPlayed * 100).toFixed(0) +
          '%, retry ' + retryCount + '/' + MAX_RETRIES +
          ', resuming from ' + elapsed.toFixed(1) + 's');
        mainSource = null;
        var retryBuffer = buffer; // capture for closure
        var retryOffset = elapsed;
        // Wait a short moment for context to stabilize before retrying
        setTimeout(function() {
          // Guard: don't retry if a new play() was called in the meantime
          if (mainBuffer !== retryBuffer) return;
          if (ctx.state !== 'running') {
            ctx.resume().then(function() {
              if (mainBuffer !== retryBuffer) return;
              playBuffer(retryBuffer, retryOffset);
            });
          } else {
            playBuffer(retryBuffer, retryOffset);
          }
        }, 200);
        return;
      }

      // Normal completion (or max retries reached)
      if (retryCount >= MAX_RETRIES) {
        console.warn('[WebAudio] Max retries reached, treating as completed');
      }
      retryCount = 0;
      mainSource = null;
      stopPositionTracking();
      if (onEndCb) onEndCb();
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
      retryCount = 0; // new track, reset retries
      var cached = bufferCache[url];
      if (cached) {
        if (onLoadingCb) onLoadingCb(false);
        playBuffer(cached, 0);
      } else {
        // Not cached — notify loading, then load and play
        if (onLoadingCb) onLoadingCb(true);
        loadBuffer(url).then(function(buffer) {
          if (onLoadingCb) onLoadingCb(false);
          if (buffer) playBuffer(buffer, 0);
          else if (onEndCb) onEndCb();
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
    onLoading: function(cb) { onLoadingCb = cb; },
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
