-- Factory LAN Safety Monitoring
-- Monitors stress levels and performs local safety shutoffs

local protocol = require("fag.protocol")

local safety = {}

-- Calculate total stress usage across all modules
function safety.calculate_total_stress(modules)
  local total_stress = 0
  local total_capacity = 0
  local module_count = 0
  
  for module_id, module_data in pairs(modules) do
    if module_data.stress_units and module_data.stress_capacity then
      total_stress = total_stress + module_data.stress_units
      total_capacity = total_capacity + module_data.stress_capacity
      module_count = module_count + 1
    end
  end
  
  return {
    total_stress = total_stress,
    total_capacity = total_capacity,
    module_count = module_count,
    stress_ratio = total_capacity > 0 and (total_stress / total_capacity) or 0
  }
end

-- Check for overstress condition
function safety.check_overstress(modules, threshold, safety_margin)
  threshold = threshold or 0.95
  safety_margin = safety_margin or 0.05
  
  local stress_info = safety.calculate_total_stress(modules)
  
  -- Check if we're over threshold
  local target_threshold = threshold - safety_margin
  
  if stress_info.stress_ratio >= target_threshold then
    return true, stress_info, "Overstress approaching"
  end
  
  -- Also check if any capacity is exceeded
  if stress_info.total_stress > stress_info.total_capacity then
    return true, stress_info, "Overstress exceeded"
  end
  
  return false, stress_info, "Normal"
end

-- Find modules to disable to reduce stress
function safety.find_modules_to_disable(modules, target_reduction)
  local candidates = {}
  
  -- Build list of enabled modules with their stress contribution
  for module_id, module_data in pairs(modules) do
    if module_data.enabled and module_data.stress_units and module_data.stress_units > 0 then
      table.insert(candidates, {
        module_id = module_id,
        stress_units = module_data.stress_units,
        priority = module_data.priority or 5  -- Default priority
      })
    end
  end
  
  -- Sort by priority (lower priority = disable first) then by stress (higher = disable first)
  table.sort(candidates, function(a, b)
    if a.priority ~= b.priority then
      return a.priority < b.priority  -- Lower priority first
    else
      return a.stress_units > b.stress_units  -- Higher stress first
    end
  end)
  
  -- Select modules until we meet target reduction
  local to_disable = {}
  local total_reduction = 0
  
  for _, candidate in ipairs(candidates) do
    table.insert(to_disable, candidate.module_id)
    total_reduction = total_reduction + candidate.stress_units
    
    if total_reduction >= target_reduction then
      break
    end
  end
  
  return to_disable, total_reduction
end

-- Check for modules that haven't sent data recently
function safety.check_stale_modules(modules, timeout_ms)
  timeout_ms = timeout_ms or 10000  -- 10 seconds default
  local current_time = os.epoch("utc")
  local stale_modules = {}
  
  for module_id, module_data in pairs(modules) do
    if module_data.last_updated then
      local age = current_time - module_data.last_updated
      if age > timeout_ms then
        table.insert(stale_modules, {
          module_id = module_id,
          age_seconds = age / 1000.0,
          last_updated = module_data.last_updated
        })
      end
    end
  end
  
  return stale_modules
end

-- Check for critical RPM conditions
function safety.check_rpm_critical(modules)
  local critical_modules = {}
  
  for module_id, module_data in pairs(modules) do
    -- Check if RPM dropped to 0 while stress is high
    if module_data.rpm == 0 and 
       module_data.stress_units and 
       module_data.stress_capacity and
       module_data.stress_units > (module_data.stress_capacity * 0.1) then
      
      table.insert(critical_modules, {
        module_id = module_id,
        reason = "RPM zero with high stress demand"
      })
    end
  end
  
  return critical_modules
end

-- Generate alert message for overstress
function safety.create_overstress_alert(factory_id, stress_info, affected_modules)
  local details = {
    current_stress = stress_info.total_stress,
    stress_capacity = stress_info.total_capacity,
    overstress_amount = stress_info.total_stress - stress_info.total_capacity,
    stress_ratio = stress_info.stress_ratio
  }
  
  local message = string.format(
    "Overstress detected: %d/%d SU (%.1f%%)",
    stress_info.total_stress,
    stress_info.total_capacity,
    stress_info.stress_ratio * 100
  )
  
  return protocol.build_message(protocol.MSG_TYPES.FACTORY_ALERT, {
    factory_id = factory_id,
    alert_type = protocol.ALERT_TYPES.OVERSTRESS,
    severity = stress_info.stress_ratio >= 1.0 and protocol.SEVERITY.CRITICAL or protocol.SEVERITY.HIGH,
    affected_modules = affected_modules,
    details = details,
    message = message
  })
end

-- Generate alert for offline module
function safety.create_module_offline_alert(factory_id, module_id, age_seconds)
  return protocol.build_message(protocol.MSG_TYPES.FACTORY_ALERT, {
    factory_id = factory_id,
    alert_type = protocol.ALERT_TYPES.MODULE_OFFLINE,
    severity = protocol.SEVERITY.MEDIUM,
    affected_modules = {module_id},
    details = {
      age_seconds = age_seconds,
      last_seen = os.epoch("utc") - (age_seconds * 1000)
    },
    message = string.format("Module %s offline for %.1f seconds", module_id, age_seconds)
  })
end

-- Generate alert for RPM critical
function safety.create_rpm_critical_alert(factory_id, critical_modules)
  local module_ids = {}
  for _, info in ipairs(critical_modules) do
    table.insert(module_ids, info.module_id)
  end
  
  return protocol.build_message(protocol.MSG_TYPES.FACTORY_ALERT, {
    factory_id = factory_id,
    alert_type = protocol.ALERT_TYPES.RPM_CRITICAL,
    severity = protocol.SEVERITY.HIGH,
    affected_modules = module_ids,
    details = {
      count = #critical_modules,
      modules = critical_modules
    },
    message = string.format("RPM critical on %d module(s)", #critical_modules)
  })
end

-- Safety monitor state
function safety.create_monitor()
  local monitor = {
    last_overstress_check = 0,
    last_stale_check = 0,
    overstress_active = false,
    disabled_by_safety = {},  -- Modules disabled by safety system
    modules_seen_online = {}  -- Track which modules have been online at least once
  }
  
  function monitor:check(modules, config)
    local current_time = os.epoch("utc")
    local alerts = {}
    local actions = {}
    
    -- Check for overstress (every 2 seconds)
    if current_time - self.last_overstress_check > 2000 then
      local is_overstress, stress_info, reason = safety.check_overstress(
        modules,
        0.95,
        config.stress_safety_margin or 0.05
      )
      
      if is_overstress then
        if not self.overstress_active then
          -- First detection - only alert, no automatic shutoff
          self.overstress_active = true
          
          -- Get list of all enabled modules for alert context
          local enabled_modules = {}
          for module_id, module_data in pairs(modules) do
            if module_data.enabled then
              table.insert(enabled_modules, module_id)
            end
          end
          
          -- Create alert (no automatic actions)
          table.insert(alerts, safety.create_overstress_alert(
            config.factory_id,
            stress_info,
            enabled_modules
          ))
        end
      else
        self.overstress_active = false
      end
      
      self.last_overstress_check = current_time
    end
    
    -- Track modules that are currently online
    for module_id, module_data in pairs(modules) do
      local age = current_time - (module_data.last_updated or 0)
      if age < (config.module_timeout * 1000) then
        -- Mark this module as having been seen online
        self.modules_seen_online[module_id] = true
      end
    end
    
    -- Check for stale modules (every 5 seconds)
    if current_time - self.last_stale_check > 5000 then
      local stale_modules = safety.check_stale_modules(
        modules,
        config.module_timeout * 1000
      )
      
      if #stale_modules > 0 and config.alert_on_module_offline then
        for _, stale in ipairs(stale_modules) do
          -- Only alert if this module was previously seen online
          if self.modules_seen_online[stale.module_id] then
            table.insert(alerts, safety.create_module_offline_alert(
              config.factory_id,
              stale.module_id,
              stale.age_seconds
            ))
          end
        end
      end
      
      self.last_stale_check = current_time
    end
    
    -- Check for RPM critical
    local critical_rpms = safety.check_rpm_critical(modules)
    if #critical_rpms > 0 then
      table.insert(alerts, safety.create_rpm_critical_alert(
        config.factory_id,
        critical_rpms
      ))
    end
    
    return alerts, actions
  end
  
  function monitor:was_disabled_by_safety(module_id)
    return self.disabled_by_safety[module_id] ~= nil
  end
  
  function monitor:clear_safety_disable(module_id)
    self.disabled_by_safety[module_id] = nil
  end
  
  return monitor
end

return safety
