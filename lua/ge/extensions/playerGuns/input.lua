-- PlayerGuns input bridge (GE).
-- Persists custom binds for the Controls UI and pushes them into BeamNG's binding
-- table when the weapon controller is active (keyboard Q/O/P often missing otherwise).

local M = {}

local SETTINGS_PATH = 'settings/playerGuns/keybinds.json'

local DEFAULT_BINDINGS = {
  fire = { device = 'mouse', control = 'button0', label = 'LMB', title = 'Fire', pgAction = 'pg_fire' },
  reload = { device = 'keyboard', control = 'q', label = 'Q', title = 'Reload', pgAction = 'pg_reload' },
  weaponUp = { device = 'keyboard', control = 'p', label = 'P', title = 'Next Weapon', pgAction = 'pg_weaponUp' },
  weaponDown = { device = 'keyboard', control = 'o', label = 'O', title = 'Prev Weapon', pgAction = 'pg_weaponDown' },
}

-- Factory defaults: fire on mouse, rest on keyboard (matches shipped inputmaps).
local FACTORY_BINDINGS = {
  fire = { device = 'mouse', control = 'button0', label = 'LMB' },
  reload = { device = 'keyboard', control = 'q', label = 'Q' },
  weaponUp = { device = 'keyboard', control = 'p', label = 'P' },
  weaponDown = { device = 'keyboard', control = 'o', label = 'O' },
}

local bindings = {}
local active = false
local bindingsApplied = false

local function deepCopy(tbl)
  local out = {}
  for k, v in pairs(tbl) do
    if type(v) == 'table' then
      out[k] = deepCopy(v)
    else
      out[k] = v
    end
  end
  return out
end

local function loadBindings()
  bindings = deepCopy(DEFAULT_BINDINGS)
  for action, def in pairs(FACTORY_BINDINGS) do
    bindings[action].device = def.device
    bindings[action].control = def.control
    bindings[action].label = def.label
  end
  if jsonReadFile then
    local data = jsonReadFile(SETTINGS_PATH)
    if type(data) == 'table' then
      for action, def in pairs(data) do
        if DEFAULT_BINDINGS[action] and type(def) == 'table' and def.control then
          bindings[action].device = def.device or bindings[action].device
          bindings[action].control = def.control
          bindings[action].label = def.label or def.control
        end
      end
    end
  end
end

local function saveBindings()
  if not jsonWriteFile then return end
  local data = {}
  for action, def in pairs(bindings) do
    if DEFAULT_BINDINGS[action] then
      data[action] = {
        device = def.device,
        control = def.control,
        label = def.label,
      }
    end
  end
  jsonWriteFile(SETTINGS_PATH, data, true)
end

local function publishBindingsUi()
  if guihooks and guihooks.trigger then
    guihooks.trigger('playerGuns_bindings', M.getBindingsForUi())
  end
end

local function deviceName(devType)
  if not devType then return 'keyboard0' end
  if devType:find('0') then return devType end
  return devType .. '0'
end

-- Push one action→control pair into the live binding table (best-effort API).
local function trySetOneBinding(devName, pgAction, control)
  local cib = extensions.core_input_bindings
  if not cib then return false end
  local attempts = {
    function() if cib.setMenuActionBinding then return cib.setMenuActionBinding(devName, pgAction, control) end end,
    function() if cib.setActionBinding then return cib.setActionBinding(devName, pgAction, control) end end,
    function() if cib.setBinding then return cib.setBinding(devName, pgAction, control) end end,
    function() if cib.bind then return cib.bind(devName, pgAction, control) end end,
    function() if cib.setMenuActionBinding then return cib.setMenuActionBinding(pgAction, control, devName) end end,
  }
  for _, fn in ipairs(attempts) do
    local ok, result = pcall(fn)
    if ok and result ~= false then return true end
  end
  return false
end

function M.applyGameBindings()
  if not extensions.core_input_bindings then
    log('W', 'playerGuns.input', 'core_input_bindings unavailable — bind Q/O/P in Options > Controls (PlayerGuns).')
    return false
  end
  local any = false
  for action, bind in pairs(bindings) do
    local def = DEFAULT_BINDINGS[action]
    if def and bind.control and bind.device then
      local pgAction = def.pgAction
      local dev = deviceName(bind.device)
      if trySetOneBinding(dev, pgAction, bind.control) then
        any = true
      end
    end
  end
  if extensions.core_input_bindings.saveAllDevices then
    pcall(extensions.core_input_bindings.saveAllDevices)
  end
  if extensions.core_input_bindings.save then
    pcall(extensions.core_input_bindings.save)
  end
  bindingsApplied = any
  if any then
    log('I', 'playerGuns.input', 'Applied PlayerGuns bindings to game input system.')
  end
  return any
end

local function probeActiveOnVehicle(vehId)
  if not be or not be.getObjectByID then return end
  local veh = be:getObjectByID(vehId)
  if not veh then
    M._setActive(false)
    return
  end
  veh:queueLuaCommand([[
    local has = controller and controller.getControllerSafe('playerGuns') ~= nil
    obj:queueGameEngineLua('extensions.playerGuns_input._setActive(' .. tostring(has) .. ')')
  ]])
end

function M._setActive(isActive)
  active = isActive and true or false
  if active then
    M.applyGameBindings()
  else
    bindingsApplied = false
  end
end

function M.setActive(isActive)
  M._setActive(isActive)
end

function M.getBindingsForUi()
  local out = { active = active, bindingsApplied = bindingsApplied, actions = {} }
  local order = { 'fire', 'reload', 'weaponDown', 'weaponUp' }
  for _, action in ipairs(order) do
    local def = DEFAULT_BINDINGS[action]
    local b = bindings[action] or def
    table.insert(out.actions, {
      action = action,
      device = b.device,
      control = b.control,
      label = b.label or b.control,
      title = def and def.title or action,
      pgAction = def and def.pgAction or '',
    })
  end
  return out
end

function M.getBindings()
  return M.getBindingsForUi()
end

function M.setBinding(action, device, control, label)
  if not DEFAULT_BINDINGS[action] then return end
  bindings[action] = bindings[action] or deepCopy(DEFAULT_BINDINGS[action])
  bindings[action].device = device or 'keyboard'
  bindings[action].control = control or ''
  bindings[action].label = label or control or '?'
  saveBindings()
  M.applyGameBindings()
  publishBindingsUi()
end

function M.resetBindings()
  bindings = deepCopy(DEFAULT_BINDINGS)
  for action, def in pairs(FACTORY_BINDINGS) do
    bindings[action].device = def.device
    bindings[action].control = def.control
    bindings[action].label = def.label
  end
  saveBindings()
  M.applyGameBindings()
  publishBindingsUi()
end

function M.onExtensionLoaded()
  loadBindings()
  publishBindingsUi()
  log('I', 'playerGuns.input', 'PlayerGuns input bridge loaded.')
end

function M.onVehicleSwitched(oldID, newID, player)
  active = false
  bindingsApplied = false
  if newID then
    probeActiveOnVehicle(newID)
  end
end

return M
