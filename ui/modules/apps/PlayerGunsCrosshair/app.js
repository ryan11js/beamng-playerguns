'use strict';

console.log('[PlayerGunsCrosshair] app.js loaded — registering directive');

angular.module('beamng.apps')
.directive('playerGunsCrosshair', [function () {
  console.log('[PlayerGunsCrosshair] directive factory called');
  return {
    template:
      '<div style="position:relative;width:100%;height:100%;pointer-events:none;">' +
        '<div style="position:absolute;left:50%;top:50%;width:22px;height:22px;margin-left:-11px;margin-top:-11px;opacity:0.9;" ng-class="{ \'reloading\': reloading }">' +
          '<div style="position:absolute;left:0;right:0;top:50%;height:2px;margin-top:-1px;background:rgba(255,255,255,.85);box-shadow:0 0 3px rgba(0,0,0,.9);"></div>' +
          '<div style="position:absolute;top:0;bottom:0;left:50%;width:2px;margin-left:-1px;background:rgba(255,255,255,.85);box-shadow:0 0 3px rgba(0,0,0,.9);"></div>' +
          '<div style="position:absolute;left:50%;top:50%;width:4px;height:4px;margin-left:-2px;margin-top:-2px;background:rgba(255,255,255,.5);border-radius:50%;"></div>' +
        '</div>' +
      '</div>',
    replace: true,
    restrict: 'EA',
    scope: true,
    link: function (scope, element, attrs) {
      console.log('[PlayerGunsCrosshair] link function called — directive rendering');
      scope.reloading = false;

      // Listen to the same stream as the ammo app so the crosshair can dim
      // (or animate) during reload if we want — for now it's just status flag.
      scope.$on('playerGuns_hud', function (evt, payload) {
        if (!payload) return;
        scope.$evalAsync(function () {
          scope.reloading = !!payload.reloading;
        });
      });
    }
  };
}]);
