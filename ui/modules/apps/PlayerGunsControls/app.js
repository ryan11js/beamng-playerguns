'use strict';

// Player Guns Controls: recoil/convergence toggles + visual rebinding.
// Rebinds are written as NATIVE BeamNG bindings via extensions.playerGuns_input
// (same persistence path as Options > Controls), so they work everywhere —
// including outside menus and on controllers. No key-capture needed: the user
// clicks the key/button on a visual layout instead.

var EXT = 'extensions.playerGuns_input';
var COLLAPSE_KEY = 'playerGuns_controls_collapsed';

// --- Keyboard layout (control codes are BeamNG keyboard control names) ---
var KEY_ROWS = [
  [
    { l: '1', c: '1' }, { l: '2', c: '2' }, { l: '3', c: '3' }, { l: '4', c: '4' }, { l: '5', c: '5' },
    { l: '6', c: '6' }, { l: '7', c: '7' }, { l: '8', c: '8' }, { l: '9', c: '9' }, { l: '0', c: '0' },
    { l: '-', c: 'minus' }, { l: '=', c: 'equals' }
  ],
  [
    { l: 'Q', c: 'q' }, { l: 'W', c: 'w', warn: 'walk fwd' }, { l: 'E', c: 'e' }, { l: 'R', c: 'r', warn: 'reset veh' },
    { l: 'T', c: 't' }, { l: 'Y', c: 'y' }, { l: 'U', c: 'u' }, { l: 'I', c: 'i' }, { l: 'O', c: 'o' },
    { l: 'P', c: 'p' }, { l: '[', c: 'lbracket' }, { l: ']', c: 'rbracket' }
  ],
  [
    { l: 'A', c: 'a', warn: 'walk left' }, { l: 'S', c: 's', warn: 'walk back' }, { l: 'D', c: 'd', warn: 'walk right' },
    { l: 'F', c: 'f' }, { l: 'G', c: 'g' }, { l: 'H', c: 'h' }, { l: 'J', c: 'j' }, { l: 'K', c: 'k' },
    { l: 'L', c: 'l' }, { l: ';', c: 'semicolon' }, { l: "'", c: 'apostrophe' }
  ],
  [
    { l: 'Z', c: 'z' }, { l: 'X', c: 'x' }, { l: 'C', c: 'c', warn: 'camera' }, { l: 'V', c: 'v' },
    { l: 'B', c: 'b' }, { l: 'N', c: 'n' }, { l: 'M', c: 'm' }, { l: ',', c: 'comma' },
    { l: '.', c: 'period' }, { l: '/', c: 'slash' }
  ],
  [
    { l: 'LShift', c: 'lshift', wide: true }, { l: 'LCtrl', c: 'lcontrol', wide: true },
    { l: 'LAlt', c: 'lalt', wide: true }, { l: 'Space', c: 'space', wide: true },
    { l: '\u2190', c: 'left' }, { l: '\u2191', c: 'up' }, { l: '\u2193', c: 'down' }, { l: '\u2192', c: 'right' }
  ]
];

var MOUSE_BUTTONS = [
  { l: 'LMB', c: 'button0' }, { l: 'RMB', c: 'button2' }, { l: 'MMB', c: 'button1' },
  { l: 'Mouse4', c: 'button3' }, { l: 'Mouse5', c: 'button4' }
];

// --- Controller layout (xinput control names; sticks-as-axes intentionally
// not bindable, stick CLICKS are) ---
var PAD_GROUPS = [
  { name: 'Bumpers / Triggers', keys: [
    { l: 'LT', c: 'triggerl' }, { l: 'LB', c: 'btn_l' }, { l: 'RB', c: 'btn_r' }, { l: 'RT', c: 'triggerr' }
  ]},
  { name: 'Face buttons', keys: [
    { l: 'Y', c: 'btn_y' }, { l: 'X', c: 'btn_x' }, { l: 'B', c: 'btn_b' }, { l: 'A', c: 'btn_a' }
  ]},
  { name: 'D-pad', keys: [
    { l: 'D-Up', c: 'upov' }, { l: 'D-Left', c: 'lpov' }, { l: 'D-Right', c: 'rpov' }, { l: 'D-Down', c: 'dpov' }
  ]},
  { name: 'Stick press / Menu', keys: [
    { l: 'L3', c: 'btn_lt' }, { l: 'R3', c: 'btn_rt' }, { l: 'Back', c: 'btn_back' }, { l: 'Start', c: 'btn_start' }
  ]}
];

angular.module('beamng.apps')
.directive('playerGunsControls', [function () {
  return {
    template:
      '<div ng-style="wrapperStyle()" ' +
        'style="width:100%;color:#fff;font-family:sans-serif;font-size:12px;' +
        'box-sizing:border-box;pointer-events:auto;text-shadow:0 0 3px rgba(0,0,0,.9);overflow:auto;">' +
        '<div ng-style="headerStyle()" style="display:flex;align-items:center;">' +
          '<div ng-show="!collapsed" style="font-weight:bold;flex:1;">Player Guns Controls</div>' +
          '<button type="button" ng-click="toggleCollapsed($event)" ' +
            'style="padding:2px 8px;background:rgba(0,0,0,.65);border:1px solid rgba(255,255,255,.25);border-radius:3px;color:#fff;cursor:pointer;font-size:11px;">' +
            '{{ collapsed ? "Expand" : "Minimize" }}' +
          '</button>' +
        '</div>' +
        '<div ng-show="!collapsed">' +

          // toggles
          '<div style="margin-bottom:8px;padding:6px 8px;background:rgba(255,255,255,.08);border-radius:4px;">' +
            '<div style="display:flex;justify-content:space-between;align-items:center;">' +
              '<span>Recoil / Spread</span>' +
              '<button type="button" ng-click="toggleRecoil($event)" ' +
                'ng-style="{background: recoilEnabled ? \'rgba(40,180,80,.4)\' : \'rgba(180,40,40,.4)\'}" ' +
                'style="padding:3px 12px;border:none;border-radius:3px;color:#fff;cursor:pointer;font-size:11px;font-weight:bold;">' +
                '{{ recoilEnabled ? "ON" : "OFF" }}' +
              '</button>' +
            '</div>' +
            '<div style="font-size:10px;opacity:.65;margin-top:2px;">Adds per-weapon spread to each shot.</div>' +
          '</div>' +
          '<div style="margin-bottom:8px;padding:6px 8px;background:rgba(255,255,255,.08);border-radius:4px;">' +
            '<div style="display:flex;justify-content:space-between;align-items:center;">' +
              '<span>Aim Convergence</span>' +
              '<button type="button" ng-click="toggleAimConverge($event)" ' +
                'ng-style="{background: aimConvergeEnabled ? \'rgba(40,180,80,.4)\' : \'rgba(180,40,40,.4)\'}" ' +
                'style="padding:3px 12px;border:none;border-radius:3px;color:#fff;cursor:pointer;font-size:11px;font-weight:bold;">' +
                '{{ aimConvergeEnabled ? "ON" : "OFF" }}' +
              '</button>' +
            '</div>' +
            '<div style="font-size:10px;opacity:.65;margin-top:2px;">Bullets meet the crosshair point instead of flying parallel to the camera.</div>' +
          '</div>' +

          // action rows
          '<div ng-repeat="row in actions track by row.action" style="margin-bottom:6px;padding:6px 8px;background:rgba(255,255,255,.08);border-radius:4px;">' +
            '<div style="display:flex;justify-content:space-between;align-items:center;">' +
              '<span style="font-weight:bold;">{{ row.title }}</span>' +
              '<span>' +
                '<span ng-repeat="b in row.binds" style="display:inline-block;margin-left:4px;padding:1px 6px;background:rgba(255,255,255,.18);border-radius:3px;font-size:11px;">' +
                  '{{ b.label }}<span style="opacity:.55;font-size:9px;"> {{ deviceTag(b) }}</span>' +
                '</span>' +
                '<span ng-show="!row.binds.length" style="opacity:.5;font-size:11px;">unbound</span>' +
              '</span>' +
            '</div>' +
            '<div style="display:flex;gap:4px;margin-top:5px;">' +
              '<button type="button" ng-click="openPicker(row.action, \'keyboard\', $event)" ng-style="pickBtnStyle(row.action, \'keyboard\')" ' +
                'style="padding:3px 8px;border:none;border-radius:3px;color:#fff;cursor:pointer;font-size:10px;">Keyboard</button>' +
              '<button type="button" ng-click="openPicker(row.action, \'mouse\', $event)" ng-style="pickBtnStyle(row.action, \'mouse\')" ' +
                'style="padding:3px 8px;border:none;border-radius:3px;color:#fff;cursor:pointer;font-size:10px;">Mouse</button>' +
              '<button type="button" ng-click="openPicker(row.action, \'xinput\', $event)" ng-style="pickBtnStyle(row.action, \'xinput\')" ' +
                'style="padding:3px 8px;border:none;border-radius:3px;color:#fff;cursor:pointer;font-size:10px;">' +
                'Controller{{ hasController ? "" : " (not detected)" }}</button>' +
              '<button type="button" ng-click="clearBind(row.action, $event)" ' +
                'style="margin-left:auto;padding:3px 8px;background:rgba(180,40,40,.3);border:none;border-radius:3px;color:#fff;cursor:pointer;font-size:10px;">Clear</button>' +
            '</div>' +

            // keyboard picker
            '<div ng-show="pickerAction === row.action && pickerDevice === \'keyboard\'" style="margin-top:6px;padding:6px;background:rgba(0,0,0,.35);border-radius:4px;">' +
              '<div ng-repeat="krow in keyRows" style="display:flex;gap:3px;margin-bottom:3px;justify-content:center;">' +
                '<button type="button" ng-repeat="k in krow" ng-click="pick(k.c, $event)" ' +
                  'ng-style="{flex: k.wide ? \'2 1 0\' : \'1 1 0\', background: k.warn ? \'rgba(200,140,30,.35)\' : \'rgba(255,255,255,.18)\'}" ' +
                  'title="{{ k.warn ? (\'stock conflict: \' + k.warn) : \'\' }}" ' +
                  'style="min-width:0;padding:5px 0;border:none;border-radius:3px;color:#fff;cursor:pointer;font-size:10px;">{{ k.l }}</button>' +
              '</div>' +
              '<div style="font-size:9px;opacity:.6;text-align:center;">Orange keys carry a stock BeamNG action.</div>' +
            '</div>' +

            // mouse picker
            '<div ng-show="pickerAction === row.action && pickerDevice === \'mouse\'" style="margin-top:6px;padding:6px;background:rgba(0,0,0,.35);border-radius:4px;display:flex;gap:4px;justify-content:center;">' +
              '<button type="button" ng-repeat="k in mouseButtons" ng-click="pick(k.c, $event)" ' +
                'style="flex:1;padding:6px 0;background:rgba(255,255,255,.18);border:none;border-radius:3px;color:#fff;cursor:pointer;font-size:10px;">{{ k.l }}</button>' +
            '</div>' +

            // controller picker
            '<div ng-show="pickerAction === row.action && pickerDevice === \'xinput\'" style="margin-top:6px;padding:6px;background:rgba(0,0,0,.35);border-radius:4px;">' +
              '<div ng-repeat="g in padGroups" style="margin-bottom:4px;">' +
                '<div style="font-size:9px;opacity:.6;margin-bottom:2px;">{{ g.name }}</div>' +
                '<div style="display:flex;gap:3px;">' +
                  '<button type="button" ng-repeat="k in g.keys" ng-click="pick(k.c, $event)" ' +
                    'style="flex:1;padding:5px 0;background:rgba(255,255,255,.18);border:none;border-radius:3px;color:#fff;cursor:pointer;font-size:10px;">{{ k.l }}</button>' +
                '</div>' +
              '</div>' +
              '<div style="font-size:9px;opacity:.6;text-align:center;">Stick axes stay free for driving. Stick clicks (L3/R3) bind fine.</div>' +
            '</div>' +
          '</div>' +

          '<div ng-show="conflictMsg" style="margin-bottom:6px;padding:5px 8px;background:rgba(200,140,30,.25);border-radius:4px;font-size:10px;">{{ conflictMsg }}</div>' +

          '<div style="margin-top:4px;">' +
            '<button type="button" ng-click="resetDefaults($event)" ' +
              'style="width:100%;padding:6px;background:rgba(255,255,255,.15);border:none;border-radius:4px;color:#fff;cursor:pointer;">Reset to defaults (LMB / Q / O / P)</button>' +
          '</div>' +
        '</div>' +
      '</div>',
    replace: true,
    restrict: 'EA',
    scope: true,
    link: function (scope) {
      scope.actions = [];
      scope.active = false;
      scope.recoilEnabled = false;
      scope.aimConvergeEnabled = false;
      scope.hasController = false;
      scope.pickerAction = null;
      scope.pickerDevice = null;
      scope.collapsed = false;
      scope.conflictMsg = '';
      scope.keyRows = KEY_ROWS;
      scope.mouseButtons = MOUSE_BUTTONS;
      scope.padGroups = PAD_GROUPS;

      try {
        scope.collapsed = window.localStorage.getItem(COLLAPSE_KEY) === '1';
      } catch (e) {}

      scope.deviceTag = function (b) {
        if (b.devicetype === 'xinput') return 'pad';
        if (b.devicetype === 'mouse') return 'mouse';
        return 'kb';
      };

      scope.wrapperStyle = function () {
        if (scope.collapsed) {
          return { background: 'transparent', padding: '0', borderRadius: '0', height: 'auto' };
        }
        return { background: 'rgba(0,0,0,.6)', padding: '10px 12px', borderRadius: '6px', height: '100%' };
      };
      scope.headerStyle = function () {
        return scope.collapsed
          ? { justifyContent: 'flex-end', marginBottom: '0' }
          : { justifyContent: 'space-between', marginBottom: '8px' };
      };
      scope.pickBtnStyle = function (action, device) {
        var on = scope.pickerAction === action && scope.pickerDevice === device;
        return { background: on ? 'rgba(240,160,32,.45)' : 'rgba(255,255,255,.15)' };
      };

      scope.toggleCollapsed = function ($event) {
        if ($event) $event.stopPropagation();
        scope.collapsed = !scope.collapsed;
        scope.pickerAction = null;
        try {
          window.localStorage.setItem(COLLAPSE_KEY, scope.collapsed ? '1' : '0');
        } catch (e) {}
      };

      scope.toggleRecoil = function ($event) {
        if ($event) $event.stopPropagation();
        var next = !scope.recoilEnabled;
        bngApi.engineLua(EXT + '.setRecoilEnabled(' + (next ? 'true' : 'false') + ')', function () {
          refreshFromEngine();
        });
      };

      scope.toggleAimConverge = function ($event) {
        if ($event) $event.stopPropagation();
        var next = !scope.aimConvergeEnabled;
        bngApi.engineLua(EXT + '.setAimConvergeEnabled(' + (next ? 'true' : 'false') + ')', function () {
          refreshFromEngine();
        });
      };

      function applyPayload(payload) {
        if (!payload) return;
        scope.$evalAsync(function () {
          scope.active = !!payload.active;
          scope.recoilEnabled = !!payload.recoilEnabled;
          scope.aimConvergeEnabled = !!payload.aimConvergeEnabled;
          scope.hasController = !!payload.hasController;
          var actions = payload.actions || [];
          for (var i = 0; i < actions.length; i++) {
            if (!actions[i].binds || !actions[i].binds.length) actions[i].binds = [];
          }
          scope.actions = actions;
        });
      }

      function refreshFromEngine() {
        bngApi.engineLua(EXT + '.getBindings()', function (payload) {
          applyPayload(payload);
        });
      }

      scope.openPicker = function (action, device, $event) {
        if ($event) $event.stopPropagation();
        if (scope.pickerAction === action && scope.pickerDevice === device) {
          scope.pickerAction = null;
          scope.pickerDevice = null;
        } else {
          scope.pickerAction = action;
          scope.pickerDevice = device;
        }
        scope.conflictMsg = '';
      };

      scope.pick = function (control, $event) {
        if ($event) $event.stopPropagation();
        var action = scope.pickerAction;
        var device = scope.pickerDevice;
        if (!action || !device) return;
        var lua = EXT + '.setBinding("' + action + '", "' + device + '", "' + control + '")';
        bngApi.engineLua(lua, function (conflicts) {
          scope.$evalAsync(function () {
            scope.pickerAction = null;
            scope.pickerDevice = null;
            var list = [];
            if (conflicts && conflicts.length) list = conflicts;
            else if (conflicts && typeof conflicts === 'object') {
              for (var k in conflicts) { if (conflicts.hasOwnProperty(k)) list.push(conflicts[k]); }
            }
            scope.conflictMsg = list.length
              ? 'This control is also bound to: ' + list.join(', ')
              : '';
          });
          refreshFromEngine();
        });
      };

      scope.clearBind = function (action, $event) {
        if ($event) $event.stopPropagation();
        bngApi.engineLua(EXT + '.clearBinding("' + action + '")', function () {
          refreshFromEngine();
        });
      };

      scope.resetDefaults = function ($event) {
        if ($event) $event.stopPropagation();
        scope.pickerAction = null;
        scope.pickerDevice = null;
        scope.conflictMsg = '';
        bngApi.engineLua(EXT + '.resetBindings()', function () {
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
