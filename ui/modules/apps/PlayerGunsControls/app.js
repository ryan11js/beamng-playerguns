'use strict';

console.log('[PlayerGunsControls] app.js loaded');

var EXT = 'extensions.playerGuns_input';

// Presets the game input system understands (control names from inputmaps).
var KEY_PRESETS = [
  { label: 'Q', device: 'keyboard', control: 'q' },
  { label: 'E', device: 'keyboard', control: 'e' },
  { label: 'R', device: 'keyboard', control: 'r' },
  { label: 'O', device: 'keyboard', control: 'o' },
  { label: 'P', device: 'keyboard', control: 'p' },
  { label: 'F', device: 'keyboard', control: 'f' },
  { label: 'G', device: 'keyboard', control: 'g' },
  { label: 'Space', device: 'keyboard', control: 'space' },
  { label: '1', device: 'keyboard', control: '1' },
  { label: '2', device: 'keyboard', control: '2' },
];

var MOUSE_PRESETS = [
  { label: 'LMB', device: 'mouse', control: 'button0' },
  { label: 'RMB', device: 'mouse', control: 'button2' },
  { label: 'MMB', device: 'mouse', control: 'button1' },
  { label: 'Mouse4', device: 'mouse', control: 'button3' },
  { label: 'Mouse5', device: 'mouse', control: 'button4' },
];

angular.module('beamng.apps')
.directive('playerGunsControls', [function () {
  return {
    template:
      '<div style="width:100%;height:100%;color:#fff;font-family:sans-serif;font-size:12px;' +
        'background:rgba(0,0,0,.6);border-radius:6px;padding:10px 12px;box-sizing:border-box;' +
        'pointer-events:auto;text-shadow:0 0 3px rgba(0,0,0,.9);overflow:auto;">' +
        '<div style="font-weight:bold;margin-bottom:8px;">PlayerGuns Controls</div>' +
        '<div ng-repeat="row in actions track by row.action" style="margin-bottom:8px;padding:6px 8px;background:rgba(255,255,255,.08);border-radius:4px;">' +
          '<div style="display:flex;justify-content:space-between;margin-bottom:4px;">' +
            '<span>{{ row.title }}</span>' +
            '<span style="font-weight:bold;">{{ row.label }} <span style="opacity:.6;font-weight:normal;">({{ row.control }})</span></span>' +
          '</div>' +
          '<div ng-show="pickerAction === row.action" style="display:flex;flex-wrap:wrap;gap:4px;margin-top:4px;">' +
            '<button type="button" ng-repeat="p in presetsFor(row) track by p.control" ' +
              'ng-click="assignPreset(row.action, p, $event)" ' +
              'style="padding:4px 8px;background:rgba(255,255,255,.2);border:none;border-radius:3px;color:#fff;cursor:pointer;font-size:11px;">{{ p.label }}</button>' +
          '</div>' +
          '<button type="button" ng-click="togglePicker(row.action, $event)" ' +
            'style="margin-top:4px;padding:4px 10px;background:rgba(240,160,32,.35);border:none;border-radius:3px;color:#fff;cursor:pointer;font-size:11px;">' +
            '{{ pickerAction === row.action ? "Hide keys" : "Change bind" }}' +
          '</button>' +
        '</div>' +
        '<div style="margin-top:8px;display:flex;flex-wrap:wrap;gap:6px;">' +
          '<button type="button" ng-click="resetDefaults($event)" ' +
            'style="flex:1;min-width:120px;padding:6px;background:rgba(255,255,255,.15);border:none;border-radius:4px;color:#fff;cursor:pointer;">Reset defaults</button>' +
          '<button type="button" ng-click="applyToGame($event)" ' +
            'style="flex:1;min-width:120px;padding:6px;background:rgba(80,180,255,.35);border:none;border-radius:4px;color:#fff;cursor:pointer;">Apply to game</button>' +
        '</div>' +
        '<div style="margin-top:8px;font-size:10px;opacity:.75;">' +
          'Active: {{ active ? "yes" : "no (equip PlayerGuns parts)" }} · Applied: {{ bindingsApplied ? "yes" : "no" }}' +
        '</div>' +
      '</div>',
    replace: true,
    restrict: 'EA',
    scope: true,
    link: function (scope) {
      scope.actions = [];
      scope.active = false;
      scope.bindingsApplied = false;
      scope.pickerAction = null;

      scope.presetsFor = function (row) {
        return row.action === 'fire' ? MOUSE_PRESETS : KEY_PRESETS;
      };

      function applyPayload(payload) {
        if (!payload) return;
        scope.$evalAsync(function () {
          scope.active = !!payload.active;
          scope.bindingsApplied = !!payload.bindingsApplied;
          scope.actions = payload.actions || [];
        });
      }

      function refreshFromEngine() {
        bngApi.engineLua(EXT + '.getBindings()', function (payload) {
          applyPayload(payload);
        });
      }

      scope.togglePicker = function (action, $event) {
        if ($event) $event.stopPropagation();
        scope.pickerAction = scope.pickerAction === action ? null : action;
      };

      scope.assignPreset = function (action, preset, $event) {
        if ($event) $event.stopPropagation();
        var lua = EXT + '.setBinding("' + action + '", "' + preset.device + '", "' + preset.control + '", "' + preset.label + '")';
        bngApi.engineLua(lua, function () {
          scope.pickerAction = null;
          refreshFromEngine();
        });
      };

      scope.resetDefaults = function ($event) {
        if ($event) $event.stopPropagation();
        scope.pickerAction = null;
        bngApi.engineLua(EXT + '.resetBindings()', function () {
          refreshFromEngine();
        });
      };

      scope.applyToGame = function ($event) {
        if ($event) $event.stopPropagation();
        bngApi.engineLua(EXT + '.applyGameBindings()', function () {
          refreshFromEngine();
        });
      };

      scope.$on('playerGuns_bindings', function (evt, payload) {
        applyPayload(payload);
      });

      refreshFromEngine();
    }
  };
}]);
