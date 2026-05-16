'use strict';

console.log('[PlayerGunsAmmo] app.js loaded — registering directive');

angular.module('beamng.apps')
.directive('playerGunsAmmo', [function () {
  console.log('[PlayerGunsAmmo] directive factory called');
  return {
    template:
      '<div style="position:relative;width:100%;height:100%;color:#fff;font-family:sans-serif;pointer-events:none;text-shadow:0 0 4px rgba(0,0,0,.9);">' +
        '<div ng-show="weapon" style="position:absolute;right:0;bottom:0;text-align:right;background:rgba(0,0,0,.45);padding:8px 12px;border-radius:4px;min-width:140px;">' +
          '<div style="font-size:12px;letter-spacing:2px;opacity:.85;">{{ weapon }}</div>' +
          '<div style="font-size:28px;font-weight:bold;line-height:1.1;">' +
            '<span>{{ ammo }}</span><span style="margin:0 4px;opacity:.6;">/</span><span>{{ mag }}</span>' +
          '</div>' +
          '<div ng-show="reloading" style="margin-top:6px;height:4px;background:rgba(255,255,255,.2);border-radius:2px;overflow:hidden;">' +
            '<div ng-style="{ width: (reloadProgress * 100) + \'%\' }" style="height:100%;background:#f0a020;transition:width 60ms linear;"></div>' +
          '</div>' +
        '</div>' +
      '</div>',
    replace: true,
    restrict: 'EA',
    scope: true,
    link: function (scope, element, attrs) {
      console.log('[PlayerGunsAmmo] link function called — directive rendering');
      scope.weapon = '';
      scope.ammo = 0;
      scope.mag = 0;
      scope.reloading = false;
      scope.reloadProgress = 0;

      scope.$on('playerGuns_hud', function (evt, payload) {
        if (!payload) return;
        scope.$evalAsync(function () {
          scope.weapon = payload.weapon || '';
          scope.ammo = payload.ammo || 0;
          scope.mag = payload.mag || 0;
          scope.reloading = !!payload.reloading;
          scope.reloadProgress = payload.reloadProgress || 0;
        });
      });
    }
  };
}]);
