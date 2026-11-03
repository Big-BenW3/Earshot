// Earshot landing: reveal sections once as they scroll in, and mark the
// sticky nav once the page has moved. Nothing here is needed to read or
// use the page.
(function () {
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var items = document.querySelectorAll('.reveal');
  if (reduce || !('IntersectionObserver' in window)) {
    items.forEach(function (el) { el.classList.add('is-in'); });
  } else {
    // Siblings that arrive together are staggered by 60 ms.
    var io = new IntersectionObserver(function (entries) {
      var batch = entries.filter(function (e) { return e.isIntersecting; });
      batch.forEach(function (e, i) {
        e.target.style.setProperty('--delay', Math.min(i, 4) * 60 + 'ms');
        e.target.classList.add('is-in');
        io.unobserve(e.target);
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.12 });
    items.forEach(function (el) { io.observe(el); });
  }

  var nav = document.querySelector('.nav');
  var onScroll = function () { nav.classList.toggle('is-stuck', window.scrollY > 8); };
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();
})();
