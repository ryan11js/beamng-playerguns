'use strict';

// Live telemetry readout for PlayerGuns. Data is pushed by the GE extension
// playerGuns_telemetry via the 'playerGuns_telemetry' guihook every 0.5s.

var TELEM_EXT = 'extensions.playerGuns_telemetry';

angular.module('beamng.apps')
.directive('playerGunsDebug', [function () {
  return {
    template:
      '<div style="width:100%;height:100%;box-sizing:border-box;overflow:auto;' +
        'background:rgba(0,0,0,.6);border-radius:6px;padding:8px 10px;' +
        'color:#fff;font-family:monospace;font-size:11px;pointer-events:auto;' +
        'text-shadow:0 0 3px rgba(0,0,0,.9);">' +
        '<div style="display:flex;align-items:center;margin-bottom:6px;">' +
          '<div style="font-weight:bold;flex:1;font-family:sans-serif;">PG Telemetry</div>' +
          '<button type="button" ng-click="toggleEnabled($event)" ' +
            'ng-style="{background: enabled ? \'rgba(40,180,80,.4)\' : \'rgba(180,40,40,.4)\'}" ' +
            'style="padding:2px 8px;border:none;border-radius:3px;color:#fff;cursor:pointer;font-size:10px;">' +
            '{{ enabled ? "REC" : "OFF" }}' +
          '</button>' +
        '</div>' +
        '<table style="width:100%;border-collapse:collapse;">' +
          '<tr><td style="opacity:.7;">session</td><td style="text-align:right;">{{ sessionSec }}s</td></tr>' +
          '<tr><td style="opacity:.7;">shots / impacts</td><td style="text-align:right;">{{ shots }} / {{ impacts }}</td></tr>' +
          '<tr><td style="opacity:.7;">self-hits (&lt;6m)</td>' +
            '<td style="text-align:right;" ng-style="{color: selfHits > 0 ? \'#ff6060\' : \'#60ff80\'}">{{ selfHits }}</td></tr>' +
          '<tr><td style="opacity:.7;">bails</td><td style="text-align:right;">{{ bails }}</td></tr>' +
          '<tr><td style="opacity:.7;">hot reuse</td>' +
            '<td style="text-align:right;" ng-style="{color: hotReuse > 0 ? \'#ffb060\' : \'#fff\'}">{{ hotReuse }}</td></tr>' +
          '<tr><td style="opacity:.7;">traj err avg</td>' +
            '<td style="text-align:right;" ng-style="{color: trajAvg > 3 ? \'#ffb060\' : \'#fff\'}">{{ trajAvg }}&deg;</td></tr>' +
          '<tr><td style="opacity:.7;">traj err max</td>' +
            '<td style="text-align:right;" ng-style="{color: trajMax > 10 ? \'#ff6060\' : \'#fff\'}">{{ trajMax }}&deg;</td></tr>' +
          '<tr><td style="opacity:.7;">mount sag now/max</td><td style="text-align:right;">{{ sagNow }} / {{ sagMax }} m</td></tr>' +
        '</table>' +
        '<div style="display:flex;gap:4px;margin-top:8px;">' +
          '<button type="button" ng-click="dump($event)" ' +
            'style="flex:1;padding:5px;background:rgba(240,160,32,.4);border:none;border-radius:3px;color:#fff;cursor:pointer;font-size:11px;font-weight:bold;">' +
            'Dump JSON</button>' +
          '<button type="button" ng-click="resetTelem($event)" ' +
            'style="padding:5px 8px;background:rgba(255,255,255,.15);border:none;border-radius:3px;color:#fff;cursor:pointer;font-size:11px;">' +
            'Reset</button>' +
        '</div>' +
        '<div ng-show="lastDump" style="margin-top:5px;font-size:9px;opacity:.7;word-break:break-all;">saved: {{ lastDump }}</div>' +
      '</div>',
    replace: true,
    restrict: 'EA',
    scope: true,
    link: function (scope) {
      scope.enabled = true;
      scope.sessionSec = 0;
      scope.shots = 0;
      scope.impacts = 0;
      scope.selfHits = 0;
      scope.bails = 0;
      scope.hotReuse = 0;
      scope.trajAvg = 0;
      scope.trajMax = 0;
      scope.sagNow = 0;
      scope.sagMax = 0;
      scope.lastDump = '';

      scope.$on('playerGuns_telemetry', function (evt, p) {
        if (!p) return;
        scope.$evalAsync(function () {
          scope.enabled = !!p.enabled;
          scope.sessionSec = p.sessionSec || 0;
          scope.shots = p.shots || 0;
          scope.impacts = p.impacts || 0;
          scope.selfHits = p.selfHits || 0;
          scope.bails = p.bails || 0;
          scope.hotReuse = p.hotReuse || 0;
          scope.trajAvg = p.trajAvg || 0;
          scope.trajMax = p.trajMax || 0;
          scope.sagNow = p.sagNow || 0;
          scope.sagMax = p.sagMax || 0;
        });
      });

      scope.toggleEnabled = function ($event) {
        if ($event) $event.stopPropagation();
        var next = !scope.enabled;
        bngApi.engineLua(TELEM_EXT + '.setEnabled(' + (next ? 'true' : 'false') + ')');
        scope.enabled = next;
      };

      scope.dump = function ($event) {
        if ($event) $event.stopPropagation();
        bngApi.engineLua(TELEM_EXT + '.dump()', function (path) {
          scope.$evalAsync(function () {
            scope.lastDump = path || 'settings/playerGuns/telemetry.json';
          });
        });
      };

      scope.resetTelem = function ($event) {
        if ($event) $event.stopPropagation();
        bngApi.engineLua(TELEM_EXT + '.reset()');
      };
    }
  };
}]);
