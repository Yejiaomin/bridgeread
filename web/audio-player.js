// Persistent HTML5 Audio element for iOS Safari autoplay compatibility.
// iOS only allows play() on an Audio element that was first activated by user gesture.
// By reusing the SAME element and only changing src, subsequent plays work from timers.

(function() {
  var audio = new Audio();
  audio.preload = 'auto';

  var onEndCallback = null;
  var onPositionCallback = null;
  var positionInterval = null;

  audio.addEventListener('ended', function() {
    if (onEndCallback) onEndCallback();
  });

  function startPositionTracking() {
    stopPositionTracking();
    positionInterval = setInterval(function() {
      if (onPositionCallback && !audio.paused) {
        onPositionCallback(Math.floor(audio.currentTime * 1000));
      }
    }, 100);
  }

  function stopPositionTracking() {
    if (positionInterval) {
      clearInterval(positionInterval);
      positionInterval = null;
    }
  }

  window._brAudio = {
    play: function(url) {
      audio.src = url;
      audio.load();
      var p = audio.play();
      if (p && p.catch) p.catch(function(e) { console.warn('[audio] play blocked:', e); });
      startPositionTracking();
    },
    pause: function() {
      audio.pause();
    },
    resume: function() {
      var p = audio.play();
      if (p && p.catch) p.catch(function(e) { console.warn('[audio] resume blocked:', e); });
    },
    stop: function() {
      audio.pause();
      audio.currentTime = 0;
      stopPositionTracking();
    },
    onEnd: function(cb) { onEndCallback = cb; },
    onPosition: function(cb) { onPositionCallback = cb; },
    isPlaying: function() { return !audio.paused; },
    getDuration: function() { return Math.floor((audio.duration || 0) * 1000); },
    getPosition: function() { return Math.floor((audio.currentTime || 0) * 1000); }
  };
})();
