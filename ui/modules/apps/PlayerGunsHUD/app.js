'use strict';

angular.module('beamng.apps')
.directive('playerGunsHud', [function () {
  return {
    template:
      '<div class="player-guns-hud">' +
        '<style>' +
          '.player-guns-hud{position:relative;width:100%;height:100%;color:#fff;font-family:sans-serif;pointer-events:none;text-shadow:0 0 4px rgba(0,0,0,.9);}' +
          '.player-guns-hud .crosshair{position:absolute;left:50%;top:50%;width:22px;height:22px;margin-left:-11px;margin-top:-11px;}' +
          '.player-guns-hud .cross-h,.player-guns-hud .cross-v{position:absolute;background:rgba(255,255,255,.85);box-shadow:0 0 3px rgba(0,0,0,.9);}' +
          '.player-guns-hud .cross-h{left:0;right:0;top:50%;height:2px;margin-top:-1px;}' +
          '.player-guns-hud .cross-v{top:0;bottom:0;left:50%;width:2px;margin-left:-1px;}' +
          '.player-guns-hud .weapon-info{position:absolute;right:8px;bottom:8px;text-align:right;background:rgba(0,0,0,.45);padding:8px 12px;border-radius:4px;min-width:140px;}' +
          '.player-guns-hud .weapon-name{font-size:12px;letter-spacing:2px;opacity:.85;}' +
          '.player-guns-hud .ammo{font-size:28px;font-weight:bold;line-height:1.1;}' +
          '.player-guns-hud .ammo .sep{margin:0 4px;opacity:.6;}' +
          '.player-guns-hud .reload-bar{margin-top:6px;height:4px;background:rgba(255,255,255,.2);border-radius:2px;overflow:hidden;}' +
          '.player-guns-hud .reload-fill{height:100%;background:#f0a020;transition:width .1s linear;}' +
        '</style>' +
        '<div class="crosshair"><div class="cross-h"></div><div class="cross-v"></div></div>' +
        '<div class="weapon-info" ng-show="weapon">' +
          '<div class="weapon-name">{{ weapon }}</div>' +
          '<div class="ammo"><span>{{ ammo }}</span><span class="sep">/</span><span>{{ mag }}</span></div>' +
          '<div class="reload-bar" ng-show="reloading"><div class="reload-fill" ng-style="{ width: (reloadProgress * 100) + \'%\' }"></div></div>' +
        '</div>' +
      '</div>',
    replace: true,
    restrict: 'E',
    scope: true,
    link: function (scope, element, attrs) {
      scope.weapon = 'Uzi';
      scope.ammo = 31;
      scope.mag = 31;
      scope.reloading = false;
      scope.reloadProgress = 0;

      // Vehicle controller publishes via gui.send('playerGuns_hud', payload).
      scope.$on('playerGuns_hud', function (evt, payload) {
        if (!payload) return;
        scope.$evalAsync(function () {
          scope.weapon = payload.weapon || 'Unknown';
          scope.ammo = payload.ammo || 0;
          scope.mag = payload.mag || 0;
          scope.reloading = !!payload.reloading;
          scope.reloadProgress = payload.reloadProgress || 0;
        });
      });
    }
  };
}]);
