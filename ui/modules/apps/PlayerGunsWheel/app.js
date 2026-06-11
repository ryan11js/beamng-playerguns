'use strict';

// Weapon wheel. The vehicle controller publishes 'playerGuns_wheel'
// {open, weapons[], current} when the Weapon Wheel bind is pressed and
// released. While open, the wheel tracks the mouse direction from screen
// center; on release it sends the highlighted index back through
// extensions.playerGuns_input.selectWeapon.
//
// The overlay uses position:fixed and centers on the viewport, so the app's
// own box (small, parked in a corner) only hosts the code. Segments are built
// from the payload, so weapons added to weapons.lua show up with no UI work.

var EXT = 'extensions.playerGuns_input';
var DEADZONE_PX = 50;

angular.module('beamng.apps')
.directive('playerGunsWheel', ['$document', function ($document) {
  return {
    template:
      '<div>' +
        '<div ng-show="!open" style="width:100%;height:100%;display:flex;align-items:center;justify-content:center;' +
          'color:rgba(255,255,255,.5);font-family:sans-serif;font-size:9px;text-align:center;">wheel</div>' +
        '<div ng-show="open" style="position:fixed;left:50%;top:50%;transform:translate(-50%,-50%);' +
          'pointer-events:none;z-index:9000;">' +
          '<svg ng-attr-width="{{ size }}" ng-attr-height="{{ size }}">' +
            '<g ng-repeat="seg in segments track by seg.idx">' +
              '<path ng-attr-d="{{ seg.path }}" ' +
                'ng-attr-fill="{{ seg.idx === highlight ? \'rgba(240,160,32,.85)\' : (seg.idx === current ? \'rgba(255,255,255,.38)\' : \'rgba(0,0,0,.62)\') }}" ' +
                'stroke="rgba(255,255,255,.25)" stroke-width="1.5"></path>' +
              '<text ng-attr-x="{{ seg.lx }}" ng-attr-y="{{ seg.ly }}" text-anchor="middle" dominant-baseline="middle" ' +
                'ng-attr-fill="{{ seg.idx === highlight ? \'#000\' : \'#fff\' }}" ' +
                'style="font-family:sans-serif;font-size:13px;font-weight:bold;text-shadow:none;">{{ seg.name }}</text>' +
            '</g>' +
            '<circle ng-attr-cx="{{ size/2 }}" ng-attr-cy="{{ size/2 }}" r="52" fill="rgba(0,0,0,.7)" stroke="rgba(255,255,255,.3)" stroke-width="1.5"></circle>' +
            '<text ng-attr-x="{{ size/2 }}" ng-attr-y="{{ size/2 }}" text-anchor="middle" dominant-baseline="middle" ' +
              'fill="#fff" style="font-family:sans-serif;font-size:14px;font-weight:bold;">{{ highlightName }}</text>' +
          '</svg>' +
        '</div>' +
      '</div>',
    replace: true,
    restrict: 'EA',
    scope: true,
    link: function (scope) {
      scope.open = false;
      scope.size = 460;
      scope.segments = [];
      scope.highlight = 0;
      scope.current = 0;
      scope.highlightName = '';

      var names = [];

      function polar(cx, cy, r, deg) {
        var rad = (deg - 90) * Math.PI / 180;
        return { x: cx + r * Math.cos(rad), y: cy + r * Math.sin(rad) };
      }

      // Donut segment centered on its slot angle (slot 0 = straight up).
      function segPath(cx, cy, rIn, rOut, a0, a1) {
        var p1 = polar(cx, cy, rOut, a0), p2 = polar(cx, cy, rOut, a1);
        var p3 = polar(cx, cy, rIn, a1), p4 = polar(cx, cy, rIn, a0);
        var large = (a1 - a0) > 180 ? 1 : 0;
        return 'M' + p1.x.toFixed(1) + ',' + p1.y.toFixed(1) +
          ' A' + rOut + ',' + rOut + ' 0 ' + large + ' 1 ' + p2.x.toFixed(1) + ',' + p2.y.toFixed(1) +
          ' L' + p3.x.toFixed(1) + ',' + p3.y.toFixed(1) +
          ' A' + rIn + ',' + rIn + ' 0 ' + large + ' 0 ' + p4.x.toFixed(1) + ',' + p4.y.toFixed(1) + ' Z';
      }

      function buildSegments() {
        var n = names.length;
        if (!n) { scope.segments = []; return; }
        var c = scope.size / 2;
        var step = 360 / n;
        var gap = Math.min(4, step * 0.06);
        var segs = [];
        for (var i = 0; i < n; i++) {
          var mid = i * step;
          var a0 = mid - step / 2 + gap, a1 = mid + step / 2 - gap;
          var lp = polar(c, c, (62 + (c - 10)) / 2, mid);
          segs.push({
            idx: i + 1,
            name: names[i],
            path: segPath(c, c, 62, c - 10, a0, a1),
            lx: lp.x.toFixed(1),
            ly: lp.y.toFixed(1)
          });
        }
        scope.segments = segs;
      }

      function onMouseMove(e) {
        var cx = window.innerWidth / 2, cy = window.innerHeight / 2;
        var dx = e.clientX - cx, dy = e.clientY - cy;
        if (Math.sqrt(dx * dx + dy * dy) < DEADZONE_PX) return;
        var n = names.length;
        if (!n) return;
        var deg = (Math.atan2(dx, -dy) * 180 / Math.PI + 360) % 360;
        var idx = (Math.round(deg / (360 / n)) % n) + 1;
        if (idx !== scope.highlight) {
          scope.$evalAsync(function () {
            scope.highlight = idx;
            scope.highlightName = names[idx - 1] || '';
          });
        }
      }

      function attach() { $document[0].addEventListener('mousemove', onMouseMove); }
      function detach() { $document[0].removeEventListener('mousemove', onMouseMove); }

      scope.$on('playerGuns_wheel', function (evt, p) {
        if (!p) return;
        scope.$evalAsync(function () {
          if (p.open) {
            names = p.weapons || [];
            scope.current = p.current || 1;
            scope.highlight = scope.current;
            scope.highlightName = names[scope.current - 1] || '';
            buildSegments();
            scope.open = true;
            attach();
          } else {
            if (scope.open && scope.highlight >= 1) {
              bngApi.engineLua(EXT + '.selectWeapon(' + scope.highlight + ')');
            }
            scope.open = false;
            detach();
          }
        });
      });

      scope.$on('$destroy', detach);
    }
  };
}]);
