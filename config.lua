-- Factory LAN Computer Configuration

return {
  -- Identity
  factory_id = "iron",             -- Factory identifier
  
  -- Network
  scada_id = 1,                    -- Computer ID of the SCADA computer
  
  -- Timing
  snapshot_interval = 5,           -- Seconds between factory snapshots to SCADA (5-10 recommended)
  
  -- Expected modules (optional, for monitoring)
  -- List all modules that should be part of this factory
  expected_modules = {
    "crusher_01",
    "crusher_02",
    "fan_01",
    "press_01"
  },
  
  -- Safety settings (alerts only, no automatic shutoffs)
  alert_on_overstress = true,      -- Send alerts when overstress detected
  stress_safety_margin = 0.05,     -- Alert threshold: 5% below capacity
  
  -- Alert settings
  alert_on_module_offline = true,  -- Send alert when module goes offline
  module_timeout = 10,             -- Seconds before considering module offline
  
  -- Local UI settings
  ui_refresh_rate = 1,             -- Seconds between UI updates
  display_mode = "summary",        -- "summary", "detailed", or "none"
  
  -- Logging
  enable_logging = true,           -- Enable logging
  log_file = "factory_lan.log",    -- Log file path
  log_alerts = true,               -- Log all alerts
  log_commands = true              -- Log all commands
}
