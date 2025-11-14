## Factory LAN Computer (Tier 2) - Setup Guide

The Factory LAN Computer aggregates data from all modules in one factory and forwards it to SCADA.

## Files

- **`config.lua`** - Configuration
- **`main.lua`** - Main program
- **`safety.lua`** - Safety monitoring utilities
- **`README.md`** - This file

## Hardware Setup

### Required:
1. **Advanced ComputerCraft Computer** (for more memory)
2. **Wired Modem** (for module connections)
3. **Wireless Modem** (for SCADA connection) OR wired to SCADA

### Network Topology:
```
[SCADA Computer]
       |
  (wireless or wired)
       |
[Factory LAN] <--- YOU ARE HERE
       |
  (wired network)
     / | \
    /  |  \
[M1] [M2] [M3]  (Module Computers)
```

## Installation

### 1. Copy Files

```lua
mkdir fag
mkdir factory_lan

-- Copy these files:
--   fag/protocol.lua
--   fag/network.lua
--   factory_lan/config.lua
--   factory_lan/main.lua
--   factory_lan/safety.lua
```

### 2. Configure

Edit `factory_lan/config.lua`:

```lua
edit factory_lan/config.lua
```

**Important settings:**
- `factory_id` - Factory name (e.g., "iron", "steel")
- `scada_id` - Computer ID of SCADA (run `id` on SCADA computer)
- `expected_modules` - List of modules in this factory (optional)
- `snapshot_interval` - How often to send data to SCADA (5 seconds recommended)

**Example:**
```lua
return {
  factory_id = "iron",
  scada_id = 1,  -- Change to your SCADA's ID
  snapshot_interval = 5,
  expected_modules = {
    "crusher_01",
    "crusher_02",
    "fan_01"
  },
  enable_auto_safety = true,
  overstress_action = "disable"
}
```

### 3. Run

```lua
factory_lan/main.lua
```

**What you'll see:**
```
=== Factory LAN Computer ===
Factory: iron
Computer ID: 10

Modules: 3 online, 0 offline
Active: 3 / Inactive: 0

Stress: 1536 / 6144 SU
Stress %: 25.0%

Network: OK
SCADA: 1

Press Ctrl+T to stop
```

## Features

### Data Aggregation
- ✓ Receives `module_data` from all modules
- ✓ Stores latest state for each module
- ✓ Calculates factory-wide statistics
- ✓ Sends `factory_snapshot` to SCADA every 5 seconds

### Command Routing
- ✓ Receives `scada_command` from SCADA
- ✓ Forwards `module_command` to appropriate modules
- ✓ Tracks acknowledgments (ACK/NACK)
- ✓ Reports command results to SCADA

### Safety Monitoring
- ✓ **Overstress Detection** - Monitors total stress vs capacity
- ✓ **Automatic Shutoff** - Disables modules when overstressed
- ✓ **Module Offline Detection** - Alerts when modules stop responding
- ✓ **RPM Critical Detection** - Detects stalled machines
- ✓ **Alert Generation** - Sends alerts to SCADA

### Supported Commands from SCADA
- `module_control` - Control specific modules
- `factory_shutdown` - Shut down entire factory
- `factory_restart` - Restart all modules

## Safety System

### Overstress Protection

When total stress exceeds capacity:
1. Factory LAN detects overstress
2. Calculates modules to disable (lowest priority first)
3. Sends `factory_alert` to SCADA
4. If `enable_auto_safety = true`, automatically disables modules
5. Targets 90% stress level to provide safety margin

**Configuration:**
```lua
enable_auto_safety = true,       -- Enable automatic shutoffs
overstress_action = "disable",   -- "disable" or "alert"
stress_safety_margin = 0.05      -- 5% safety margin
```

### Module Offline Detection

Checks every 5 seconds for modules that haven't sent data:
- Default timeout: 10 seconds
- Sends `module_offline` alert to SCADA
- Configurable via `module_timeout` setting

### RPM Critical Detection

Detects when:
- RPM = 0 (machine stopped)
- Stress demand > 10% of capacity (machine should be running)
- Indicates power failure or mechanical issue

## Message Flow

### Data Flow (Upward):
```
Module --[module_data]--> Factory LAN --[factory_snapshot]--> SCADA
```

Every 2 seconds, modules send data.
Every 5 seconds, Factory LAN sends snapshot to SCADA.

### Command Flow (Downward):
```
SCADA --[scada_command]--> Factory LAN --[module_command]--> Module
                               |                                 |
                               |<--------[module_ack/nack]-------+
                               |
       <-------[factory_ack]---+
```

1. SCADA sends command
2. Factory LAN sends immediate ACK
3. Factory LAN forwards to module(s)
4. Modules respond with ACK/NACK
5. Factory LAN tracks results

### Alert Flow (Event-Driven):
```
Factory LAN --[factory_alert]--> SCADA
```

Sent immediately when:
- Overstress detected
- Module goes offline
- RPM critical condition
- Other safety issues

## Troubleshooting

### No modules detected

**Problem:** Module count shows 0

**Solutions:**
1. Make sure Module Computers are running
2. Check they're sending to correct Factory LAN ID
3. Verify `factory_id` matches in both configs
4. Check network connectivity (wired modems connected)

### No connection to SCADA

**Problem:** "ERROR: Failed to send snapshot"

**Solutions:**
1. Verify SCADA is running
2. Check `scada_id` matches actual SCADA computer ID
3. For wireless: check range (64 blocks)
4. For wired: check cable connections

### Modules showing offline

**Problem:** Modules detected but marked offline

**Solutions:**
1. Check Module Computers are still running
2. Verify `update_interval` isn't too high
3. Check `module_timeout` setting (default 10 sec)
4. Look for network congestion

### Overstress alerts

**Problem:** Constant overstress warnings

**Solutions:**
1. Add more power to Create network (motors, wheels)
2. Increase stress capacity (larger motors)
3. Reduce active machines
4. Let auto-safety system disable low-priority modules
5. Adjust `stress_safety_margin` if too sensitive

## Configuration Options

### Timing
```lua
snapshot_interval = 5        -- Seconds between snapshots to SCADA
module_timeout = 10          -- Seconds before module considered offline
ui_refresh_rate = 1          -- Seconds between display updates
```

### Safety
```lua
enable_auto_safety = true            -- Enable automatic safety actions
overstress_action = "disable"        -- "disable" or "alert"
stress_safety_margin = 0.05          -- Safety margin (5%)
alert_on_module_offline = true       -- Alert when modules go offline
```

### Display
```lua
display_mode = "summary"     -- "summary", "detailed", or "none"
```

- **summary** - Shows overall stats only
- **detailed** - Shows stats + list of modules
- **none** - No display (headless mode)

### Logging
```lua
enable_logging = true
log_file = "factory_lan.log"
log_alerts = true            -- Log all alerts
log_commands = true          -- Log all commands
```

## Testing

### Test Without SCADA

You can run Factory LAN before SCADA is ready:
1. Start Factory LAN
2. Start Module Computers
3. Factory LAN will receive module data
4. Display shows aggregated stats
5. Snapshot sends will fail (that's OK)
6. Once SCADA starts, everything connects

### Manual Testing

Test command routing with a script on another computer:

```lua
local protocol = require("fag.protocol")
local network = require("fag.network")

network.init()

local cmd = protocol.build_message("scada_command", {
  command_id = "test_1",
  target_factory = "iron",
  command = "module_control",
  targets = {
    {
      module_id = "crusher_01",
      action = "disable",
      parameters = {}
    }
  },
  source = "manual_test",
  priority = "normal",
  override_local = false
})

network.send(10, cmd)  -- Send to Factory LAN (ID 10)
print("Command sent!")
```

## Advanced Usage

### Multiple Factories

Run one Factory LAN per factory with different `factory_id`:
- Iron factory: `factory_id = "iron"`
- Steel factory: `factory_id = "steel"`
- Copper factory: `factory_id = "copper"`

All connect to the same SCADA.

### Priority Modules

Some modules can be marked as high priority (won't be disabled during overstress):

This requires modifying the module data. In future versions, SCADA can assign priorities.

### Monitoring Logs

View logs in real-time:
```lua
edit factory_lan.log
```

Or tail the log:
```lua
-- Create a tail script
while true do
  term.clear()
  term.setCursorPos(1,1)
  local f = fs.open("factory_lan.log", "r")
  if f then
    print(f.readAll())
    f.close()
  end
  sleep(1)
end
```

## Next Steps

Once Factory LAN is working:
1. **Connect to SCADA** - Deploy SCADA computer for global monitoring
2. **Add more modules** - Expand your factory
3. **Set up production** - Use SCADA for deficit calculations

## Performance Notes

- **Memory:** Factory LAN stores data for all modules - use Advanced Computer for large factories
- **Network:** Receives messages from N modules every 2 seconds + sends 1 snapshot every 5 seconds
- **CPU:** Safety checks run every 2-5 seconds
- **Scalability:** Tested with up to 20 modules per factory

## Support

See `FAG Documentation.txt` for complete protocol specification.
