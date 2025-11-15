-- Factory LAN Computer Main Program
-- Tier 2: Aggregates module data, routes commands, performs safety monitoring

-- Load dependencies
local protocol = require("fag.protocol")
local network = require("fag.network")
local safety = require("safety")
local config = require("config")

-- Factory state
local state = {
  running = true,
  modules = {},  -- Table of all module data indexed by module_id
  last_snapshot_send = 0,
  startup_time = os.epoch("utc"),
  safety_monitor = nil,
  pending_commands = {}  -- Track commands sent to modules
}

-- Statistics
local stats = {
  modules_online = 0,
  modules_offline = 0,
  total_stress = 0,
  total_capacity = 0,
  active_modules = 0,
  inactive_modules = 0
}

-- Logging
local function log(message)
  if config.enable_logging then
    local timestamp = os.date("%H:%M:%S")
    local log_msg = "[" .. timestamp .. "] " .. message
    
    if config.log_file then
      local file = fs.open(config.log_file, "a")
      file.writeLine(log_msg)
      file.close()
    end
    
    print(log_msg)
  end
end

-- Update statistics
local function update_stats()
  stats.modules_online = 0
  stats.modules_offline = 0
  stats.total_stress = 0
  stats.total_capacity = 0
  stats.active_modules = 0
  stats.inactive_modules = 0
  
  local current_time = os.epoch("utc")
  
  for module_id, module_data in pairs(state.modules) do
    -- Check if module is online
    local age = current_time - (module_data.last_updated or 0)
    if age < (config.module_timeout * 1000) then
      stats.modules_online = stats.modules_online + 1
    else
      stats.modules_offline = stats.modules_offline + 1
    end
    
    -- Use max stress (all modules share same kinetic network)
    -- Don't sum - that would count the same network multiple times!
    if module_data.stress_units and module_data.stress_units > stats.total_stress then
      stats.total_stress = module_data.stress_units
    end
    if module_data.stress_capacity and module_data.stress_capacity > stats.total_capacity then
      stats.total_capacity = module_data.stress_capacity
    end
    
    -- Count active/inactive
    if module_data.enabled then
      stats.active_modules = stats.active_modules + 1
    else
      stats.inactive_modules = stats.inactive_modules + 1
    end
  end
end

-- Handle module_data message
local function handle_module_data(msg, sender_id)
  local module_id = msg.module_id
  
  -- Validate this module belongs to our factory
  if msg.factory_id ~= config.factory_id then
    log("WARNING: Received data from wrong factory: " .. msg.factory_id)
    return
  end
  
  -- Store/update module data
  state.modules[module_id] = {
    module_id = msg.module_id,
    factory_id = msg.factory_id,
    rpm = msg.rpm,
    stress_units = msg.stress_units,
    stress_capacity = msg.stress_capacity,
    items_per_min = msg.items_per_min,
    enabled = msg.enabled,
    last_updated = msg.timestamp,
    sender_id = sender_id
  }
  
  -- Log if this is first time seeing this module
  if not state.modules[module_id] then
    log("New module registered: " .. module_id)
  end
end

-- Handle module acknowledgment
local function handle_module_ack(msg, sender_id)
  local command_id = msg.command_id
  
  if state.pending_commands[command_id] then
    state.pending_commands[command_id].acks = state.pending_commands[command_id].acks or {}
    state.pending_commands[command_id].acks[msg.module_id] = {
      success = true,
      new_state = msg.new_state,
      received_at = os.epoch("utc")
    }
    
    log("Command " .. command_id .. " ACK from " .. msg.module_id)
  end
end

-- Handle module negative acknowledgment
local function handle_module_nack(msg, sender_id)
  local command_id = msg.command_id
  
  if state.pending_commands[command_id] then
    state.pending_commands[command_id].acks = state.pending_commands[command_id].acks or {}
    state.pending_commands[command_id].acks[msg.module_id] = {
      success = false,
      reason = msg.reason,
      current_state = msg.current_state,
      received_at = os.epoch("utc")
    }
    
    log("Command " .. command_id .. " NACK from " .. msg.module_id .. ": " .. msg.reason)
  end
end

-- Handle SCADA command
local function handle_scada_command(msg, sender_id)
  -- Validate target factory
  if msg.target_factory ~= config.factory_id then
    log("WARNING: Received command for wrong factory: " .. msg.target_factory)
    return
  end
  
  log("Received SCADA command: " .. msg.command .. " (ID: " .. msg.command_id .. ")")
  
  -- Track this command
  state.pending_commands[msg.command_id] = {
    received_at = os.epoch("utc"),
    command = msg.command,
    targets = msg.targets,
    source = msg.source,
    acks = {}
  }
  
  -- Send immediate acknowledgment to SCADA
  local factory_ack = protocol.build_message(protocol.MSG_TYPES.FACTORY_ACK, {
    factory_id = config.factory_id,
    command_id = msg.command_id,
    success = true,
    commands_forwarded = 0,
    results = {}
  })
  
  -- Process command based on type
  local commands_forwarded = 0
  local results = {}
  
  if msg.command == protocol.COMMAND_TYPES.MODULE_CONTROL then
    -- Forward commands to individual modules
    for _, target in ipairs(msg.targets or {}) do
      local module_id = target.module_id
      local module_data = state.modules[module_id]
      
      if not module_data then
        results[module_id] = "invalid_target"
        log("WARNING: Unknown module " .. module_id)
      else
        -- Build module_command
        local module_cmd = protocol.build_message(protocol.MSG_TYPES.MODULE_COMMAND, {
          command_id = msg.command_id,
          target_module = module_id,
          action = target.action,
          parameters = target.parameters or {},
          source = msg.source,
          priority = msg.priority
        })
        
        -- Send to module
        local success, err = network.send(module_data.sender_id, module_cmd)
        if success then
          results[module_id] = "command_sent"
          commands_forwarded = commands_forwarded + 1
        else
          results[module_id] = "send_failed"
          log("ERROR: Failed to send command to " .. module_id .. ": " .. err)
        end
      end
    end
    
  elseif msg.command == protocol.COMMAND_TYPES.FACTORY_SHUTDOWN then
    -- Shutdown all modules
    for module_id, module_data in pairs(state.modules) do
      local module_cmd = protocol.build_message(protocol.MSG_TYPES.MODULE_COMMAND, {
        command_id = msg.command_id,
        target_module = module_id,
        action = protocol.ACTIONS.DISABLE,
        parameters = {},
        source = msg.source,
        priority = protocol.PRIORITY.HIGH
      })
      
      network.send(module_data.sender_id, module_cmd)
      results[module_id] = "shutdown_sent"
      commands_forwarded = commands_forwarded + 1
    end
    
  elseif msg.command == protocol.COMMAND_TYPES.FACTORY_RESTART then
    -- Restart all modules
    for module_id, module_data in pairs(state.modules) do
      local module_cmd = protocol.build_message(protocol.MSG_TYPES.MODULE_COMMAND, {
        command_id = msg.command_id,
        target_module = module_id,
        action = protocol.ACTIONS.RESTART,
        parameters = {},
        source = msg.source,
        priority = protocol.PRIORITY.HIGH
      })
      
      network.send(module_data.sender_id, module_cmd)
      results[module_id] = "restart_sent"
      commands_forwarded = commands_forwarded + 1
    end
  end
  
  -- Update acknowledgment
  factory_ack.commands_forwarded = commands_forwarded
  factory_ack.results = results
  
  -- Send to SCADA
  network.send(config.scada_id, factory_ack)
  
  if config.log_commands then
    log("Forwarded " .. commands_forwarded .. " commands to modules")
  end
end

-- Send factory snapshot to SCADA
local function send_factory_snapshot()
  -- Update statistics
  update_stats()
  
  -- Build snapshot message
  local snapshot = protocol.build_message(protocol.MSG_TYPES.FACTORY_SNAPSHOT, {
    factory_id = config.factory_id,
    modules = state.modules,
    summary = {
      total_stress_used = stats.total_stress,
      total_stress_capacity = stats.total_capacity,
      active_modules = stats.active_modules,
      inactive_modules = stats.inactive_modules,
      modules_with_errors = 0  -- TODO: Track errors
    },
    lan_status = {
      uptime = os.epoch("utc") - state.startup_time,
      modules_online = stats.modules_online,
      modules_offline = stats.modules_offline
    }
  })
  
  -- Send to SCADA
  local success, err = network.send(config.scada_id, snapshot)
  if not success then
    log("ERROR: Failed to send snapshot: " .. err)
  end
  
  state.last_snapshot_send = os.epoch("utc")
end

-- Handle incoming messages
local function handle_message(msg, sender_id)
  network.update_last_seen(sender_id)
  
  if msg.msg_type == protocol.MSG_TYPES.MODULE_DATA then
    handle_module_data(msg, sender_id)
    
  elseif msg.msg_type == protocol.MSG_TYPES.MODULE_ACK then
    handle_module_ack(msg, sender_id)
    
  elseif msg.msg_type == protocol.MSG_TYPES.MODULE_NACK then
    handle_module_nack(msg, sender_id)
    
  elseif msg.msg_type == protocol.MSG_TYPES.SCADA_COMMAND then
    handle_scada_command(msg, sender_id)
    
  elseif msg.msg_type == protocol.MSG_TYPES.EMERGENCY_STOP then
    log("EMERGENCY STOP received!")
    -- Broadcast to all modules
    network.broadcast(msg)
    
  elseif msg.msg_type == protocol.MSG_TYPES.HEARTBEAT then
    -- Ignore for now
    
  else
    log("Received unexpected message type: " .. msg.msg_type)
  end
end

-- Send heartbeat
local function send_heartbeat()
  local msg = protocol.build_message(protocol.MSG_TYPES.HEARTBEAT, {
    sender_id = os.getComputerID(),
    sender_type = "factory_lan",
    factory_id = config.factory_id,
    uptime = os.epoch("utc") - state.startup_time,
    status = "operational",
    modules_online = stats.modules_online
  })
  
  network.broadcast(msg)
end

-- Display status
local function display_status()
  term.clear()
  term.setCursorPos(1, 1)
  
  print("=== Factory LAN Computer ===")
  print("Factory: " .. config.factory_id)
  print("Computer ID: " .. os.getComputerID())
  print("")
  
  update_stats()
  
  print("Modules: " .. stats.modules_online .. " online, " .. stats.modules_offline .. " offline")
  print("Active: " .. stats.active_modules .. " / Inactive: " .. stats.inactive_modules)
  print("")
  
  print("Stress: " .. stats.total_stress .. " / " .. stats.total_capacity .. " SU")
  if stats.total_capacity > 0 then
    local stress_pct = (stats.total_stress / stats.total_capacity) * 100
    print("Stress %: " .. string.format("%.1f%%", stress_pct))
  end
  print("")
  
  print("Network: " .. (network.is_initialized and "OK" or "ERROR"))
  print("SCADA: " .. config.scada_id)
  print("")
  
  -- List modules
  if config.display_mode == "detailed" then
    print("--- Modules ---")
    local count = 0
    for module_id, module_data in pairs(state.modules) do
      if count < 5 then  -- Show max 5 modules
        local status = module_data.enabled and "ON" or "OFF"
        print(module_id .. ": " .. status .. " " .. module_data.rpm .. " RPM")
        count = count + 1
      end
    end
    if count < #state.modules then
      print("... " .. (#state.modules - count) .. " more")
    end
  end
  
  print("")
  print("Press Ctrl+T to stop")
end

-- Main program
local function main()
  print("=== Factory LAN Computer Starting ===")
  print("Factory: " .. config.factory_id)
  print("SCADA ID: " .. config.scada_id)
  print("")
  
  -- Initialize network
  log("Initializing network...")
  local success, err = network.init()
  if not success then
    log("FATAL: Failed to initialize network: " .. err)
    return
  end
  log("Network initialized on " .. network.modem_side)
  
  -- Enable logging
  if config.enable_logging then
    network.enable_logging(config.log_file)
  end
  
  -- Initialize safety monitor
  state.safety_monitor = safety.create_monitor()
  log("Safety monitor initialized")
  
  -- Send initial heartbeat
  send_heartbeat()
  log("Startup complete")
  
  -- Main loop timers
  local heartbeat_timer = os.startTimer(30)
  local display_timer = os.startTimer(1)
  
  while state.running do
    -- Check if time to send snapshot
    local current_time = os.epoch("utc")
    local time_since_snapshot = (current_time - state.last_snapshot_send) / 1000.0
    
    if time_since_snapshot >= config.snapshot_interval then
      send_factory_snapshot()
    end
    
    -- Run safety checks (alerts only, no automatic actions)
    local alerts, actions = state.safety_monitor:check(state.modules, config)
    
    -- Send alerts to SCADA
    for _, alert in ipairs(alerts) do
      network.send(config.scada_id, alert)
      if config.log_alerts then
        log("ALERT: " .. alert.message)
      end
    end
    
    -- Note: actions are generated but not executed (monitoring only)
    
    -- Check for incoming messages (non-blocking)
    local msg, sender_id = network.receive_nonblocking()
    if msg then
      handle_message(msg, sender_id)
    end
    
    -- Handle timers
    local event, param = os.pullEvent()
    
    if event == "timer" then
      if param == heartbeat_timer then
        send_heartbeat()
        heartbeat_timer = os.startTimer(30)
      elseif param == display_timer then
        if config.display_mode ~= "none" then
          display_status()
        end
        display_timer = os.startTimer(config.ui_refresh_rate)
      end
    end
    
    sleep(0.05)
  end
  
  log("Factory LAN shutting down")
  term.clear()
  term.setCursorPos(1, 1)
  print("Factory LAN stopped")
end

-- Run with error handling
local success, err = pcall(main)
if not success then
  term.clear()
  term.setCursorPos(1, 1)
  print("ERROR: " .. tostring(err))
  print("")
  print("Check log file: " .. config.log_file)
end
