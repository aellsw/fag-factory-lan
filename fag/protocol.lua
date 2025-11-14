-- FAG Protocol v1.0 Core Library
-- Factories Are Great - Protocol Implementation
-- Provides message building, validation, and utilities for all tiers

local protocol = {}

-- Protocol Constants
protocol.PROTOCOL_NAME = "FAG"
protocol.PROTOCOL_VERSION = "1.0"
protocol.PROTOCOL_FULL = "FAG/1.0"

-- Message Types Registry
protocol.MSG_TYPES = {
  MODULE_DATA = "module_data",
  MODULE_ACK = "module_ack",
  MODULE_NACK = "module_nack",
  MODULE_COMMAND = "module_command",
  FACTORY_SNAPSHOT = "factory_snapshot",
  FACTORY_ALERT = "factory_alert",
  FACTORY_ACK = "factory_ack",
  SCADA_COMMAND = "scada_command",
  SCADA_QUERY = "scada_query",
  SCADA_QUERY_RESPONSE = "scada_query_response",
  HEARTBEAT = "heartbeat",
  EMERGENCY_STOP = "emergency_stop"
}

-- Action Types (for module_command)
protocol.ACTIONS = {
  ENABLE = "enable",
  DISABLE = "disable",
  SET_SPEED = "set_speed",
  RESTART = "restart"
}

-- Alert Types
protocol.ALERT_TYPES = {
  OVERSTRESS = "overstress",
  MODULE_OFFLINE = "module_offline",
  EMERGENCY_STOP = "emergency_stop",
  RPM_CRITICAL = "rpm_critical",
  PERIPHERAL_ERROR = "peripheral_error"
}

-- Severity Levels
protocol.SEVERITY = {
  LOW = "low",
  MEDIUM = "medium",
  HIGH = "high",
  CRITICAL = "critical"
}

-- Priority Levels
protocol.PRIORITY = {
  NORMAL = "normal",
  HIGH = "high",
  EMERGENCY = "emergency"
}

-- Command Types (for scada_command)
protocol.COMMAND_TYPES = {
  MODULE_CONTROL = "module_control",
  FACTORY_SHUTDOWN = "factory_shutdown",
  FACTORY_RESTART = "factory_restart",
  BALANCE_PRODUCTION = "balance_production"
}

-- Source Values
protocol.SOURCES = {
  SCADA_AUTO = "scada_auto",
  SCADA_OPERATOR = "scada_operator",
  SCADA_EMERGENCY = "scada_emergency",
  FACTORY_LAN = "factory_lan"
}

-- Build a base message with required fields
function protocol.build_message(msg_type, fields)
  local msg = {
    protocol = protocol.PROTOCOL_FULL,
    msg_type = msg_type,
    timestamp = os.epoch("utc")
  }
  
  -- Add all provided fields
  if fields then
    for k, v in pairs(fields) do
      msg[k] = v
    end
  end
  
  return msg
end

-- Validate a message has required base fields
function protocol.validate_message(msg)
  if not msg then
    return false, "Message is nil"
  end
  
  if type(msg) ~= "table" then
    return false, "Message is not a table"
  end
  
  if not msg.protocol or msg.protocol ~= protocol.PROTOCOL_FULL then
    return false, "Invalid or missing protocol field"
  end
  
  if not msg.msg_type then
    return false, "Missing msg_type field"
  end
  
  if not msg.timestamp then
    return false, "Missing timestamp field"
  end
  
  return true
end

-- Validate specific message types
function protocol.validate_module_data(msg)
  local required = {"module_id", "factory_id", "rpm", "stress_units", 
                   "stress_capacity", "items_per_min", "enabled"}
  
  for _, field in ipairs(required) do
    if msg[field] == nil then
      return false, "Missing required field: " .. field
    end
  end
  
  return true
end

function protocol.validate_module_command(msg)
  local required = {"command_id", "target_module", "action", "source", "priority"}
  
  for _, field in ipairs(required) do
    if msg[field] == nil then
      return false, "Missing required field: " .. field
    end
  end
  
  return true
end

function protocol.validate_factory_snapshot(msg)
  local required = {"factory_id", "modules", "lan_status"}
  
  for _, field in ipairs(required) do
    if msg[field] == nil then
      return false, "Missing required field: " .. field
    end
  end
  
  if type(msg.modules) ~= "table" then
    return false, "modules must be a table"
  end
  
  return true
end

function protocol.validate_scada_command(msg)
  local required = {"command_id", "target_factory", "command", 
                   "source", "priority", "override_local"}
  
  for _, field in ipairs(required) do
    if msg[field] == nil then
      return false, "Missing required field: " .. field
    end
  end
  
  return true
end

-- Command ID Generator
local command_counter = 0

function protocol.generate_command_id()
  command_counter = command_counter + 1
  return os.getComputerID() .. "_" .. command_counter
end

-- Timestamp utilities
function protocol.get_timestamp()
  return os.epoch("utc")
end

function protocol.is_stale(timestamp, max_age_ms)
  local now = os.epoch("utc")
  return (now - timestamp) > max_age_ms
end

-- Message age in milliseconds
function protocol.get_message_age(msg)
  if not msg.timestamp then
    return nil
  end
  return os.epoch("utc") - msg.timestamp
end

-- Pretty print message type for logging
function protocol.get_message_description(msg)
  if not msg or not msg.msg_type then
    return "Unknown message"
  end
  
  local desc = msg.msg_type
  
  if msg.module_id then
    desc = desc .. " from " .. msg.module_id
  elseif msg.factory_id then
    desc = desc .. " from " .. msg.factory_id
  end
  
  if msg.command_id then
    desc = desc .. " (cmd: " .. tostring(msg.command_id) .. ")"
  end
  
  return desc
end

return protocol
