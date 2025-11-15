-- FAG Protocol v1.0 Network Layer
-- Handles all rednet communication, message serialization, and error handling

local protocol = require("fag.protocol")

local network = {}

-- Network state
network.modem_side = nil
network.is_initialized = false

-- Initialize the network (open rednet on all modems)
function network.init(modem_side)
  if network.is_initialized then
    return true
  end
  
  local modems_found = {}
  
  -- If specific modem specified, use it
  if modem_side then
    if peripheral.getType(modem_side) == "modem" then
      rednet.open(modem_side)
      network.modem_side = modem_side
      network.is_initialized = true
      return true
    else
      return false, "No modem on side: " .. modem_side
    end
  end
  
  -- Otherwise, find and open ALL modems
  local sides = {"top", "bottom", "left", "right", "front", "back"}
  for _, side in ipairs(sides) do
    if peripheral.getType(side) == "modem" then
      rednet.open(side)
      table.insert(modems_found, side)
    end
  end
  
  if #modems_found == 0 then
    return false, "No modem found"
  end
  
  -- Store first modem as primary (for display purposes)
  network.modem_side = modems_found[1]
  network.is_initialized = true
  
  return true
end

-- Send a message to a specific computer
function network.send(target_id, msg)
  if not network.is_initialized then
    return false, "Network not initialized"
  end
  
  -- Validate message before sending
  local valid, err = protocol.validate_message(msg)
  if not valid then
    return false, "Invalid message: " .. err
  end
  
  -- Serialize the message
  local serialized = textutils.serialize(msg)
  
  -- Send via rednet with FAG protocol identifier
  rednet.send(target_id, serialized, "FAG")
  
  return true
end

-- Broadcast a message to all computers
function network.broadcast(msg)
  if not network.is_initialized then
    return false, "Network not initialized"
  end
  
  -- Validate message before sending
  local valid, err = protocol.validate_message(msg)
  if not valid then
    return false, "Invalid message: " .. err
  end
  
  -- Serialize the message
  local serialized = textutils.serialize(msg)
  
  -- Broadcast via rednet with FAG protocol identifier
  rednet.broadcast(serialized, "FAG")
  
  return true
end

-- Receive a message (blocking or with timeout)
-- timeout: seconds to wait, or nil for indefinite
-- Returns: msg, sender_id or nil if timeout
function network.receive(timeout)
  if not network.is_initialized then
    return nil, nil, "Network not initialized"
  end
  
  -- Convert timeout from seconds to nil or keep it
  local sender_id, message, protocol_name = rednet.receive("FAG", timeout)
  
  if not message then
    return nil, nil, "Timeout"
  end
  
  -- Unserialize the message
  local success, msg = pcall(textutils.unserialize, message)
  if not success then
    return nil, sender_id, "Failed to unserialize message"
  end
  
  -- Validate the message
  local valid, err = protocol.validate_message(msg)
  if not valid then
    return nil, sender_id, "Invalid message: " .. err
  end
  
  return msg, sender_id
end

-- Non-blocking receive check
-- Returns: msg, sender_id or nil if no message waiting
function network.receive_nonblocking()
  return network.receive(0)
end

-- Message queue for buffering
network.message_buffer = {}
network.max_buffer_size = 100

-- Buffer a message for later processing
function network.buffer_message(msg, sender_id)
  if #network.message_buffer >= network.max_buffer_size then
    -- Remove oldest message
    table.remove(network.message_buffer, 1)
  end
  
  table.insert(network.message_buffer, {
    msg = msg,
    sender_id = sender_id,
    received_at = os.epoch("utc")
  })
end

-- Get next buffered message
function network.get_buffered_message()
  if #network.message_buffer == 0 then
    return nil
  end
  
  local entry = table.remove(network.message_buffer, 1)
  return entry.msg, entry.sender_id
end

-- Check if there are buffered messages
function network.has_buffered_messages()
  return #network.message_buffer > 0
end

-- Clear message buffer
function network.clear_buffer()
  network.message_buffer = {}
end

-- Logging utility
network.log_enabled = false
network.log_file = nil

function network.enable_logging(filename)
  network.log_enabled = true
  network.log_file = filename
end

function network.log(message)
  if not network.log_enabled then
    return
  end
  
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local log_entry = "[" .. timestamp .. "] " .. message .. "\n"
  
  if network.log_file then
    local file = fs.open(network.log_file, "a")
    file.write(log_entry)
    file.close()
  else
    print(log_entry)
  end
end

-- Send with retry logic
function network.send_with_retry(target_id, msg, max_retries, retry_delay)
  max_retries = max_retries or 3
  retry_delay = retry_delay or 1
  
  for attempt = 1, max_retries do
    local success, err = network.send(target_id, msg)
    
    if success then
      network.log("Sent message to " .. target_id .. ": " .. protocol.get_message_description(msg))
      return true
    end
    
    network.log("Failed to send message (attempt " .. attempt .. "/" .. max_retries .. "): " .. err)
    
    if attempt < max_retries then
      sleep(retry_delay)
    end
  end
  
  return false, "Failed after " .. max_retries .. " attempts"
end

-- Lookup table for known computers
network.known_computers = {}

function network.register_computer(computer_id, name, role)
  network.known_computers[computer_id] = {
    name = name,
    role = role,
    last_seen = os.epoch("utc")
  }
end

function network.get_computer_name(computer_id)
  local info = network.known_computers[computer_id]
  if info then
    return info.name
  end
  return "Computer " .. computer_id
end

-- Update last seen timestamp
function network.update_last_seen(computer_id)
  if network.known_computers[computer_id] then
    network.known_computers[computer_id].last_seen = os.epoch("utc")
  end
end

return network
