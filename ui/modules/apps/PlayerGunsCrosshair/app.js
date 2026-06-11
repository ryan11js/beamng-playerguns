'use strict';

console.log('[PlayerGunsCrosshair] app.js loaded — registering directive');

angular.module('beamng.apps')
.directive('playerGunsCrosshair', [function () {
  console.log('[PlayerGunsCrosshair] directive factory called');

  // Static, screen-centered reticle. No mouse tracking (GE-side mouse position is
  // not readable); the weapon aims at screen-center, so a fixed crosshair is correct.
  var line = 'position:absolute;background:#fff;box-shadow:0 0 2px rgba(0,0,0,.9);';
  var vert = 'width:2px;height:12px;left:21px;';
  var horiz = 'height:2px;width:12px;top:21px;';

  return {
    replace: true,
    restrict: 'EA',
    template:
      '<div style="position:relative;width:100%;height:100%;pointer-events:none;">' +
        '<div style="' + line + vert + 'top:2px;"></div>' +
        '<div style="' + line + vert + 'bottom:2px;"></div>' +
        '<div style="' + line + horiz + 'left:2px;"></div>' +
        '<div style="' + line + horiz + 'right:2px;"></div>' +
        '<div style="position:absolute;width:4px;height:4px;left:20px;top:20px;border-radius:50%;background:#fff;box-shadow:0 0 2px rgba(0,0,0,.9);"></div>' +
      '</div>'
  };
}]);
