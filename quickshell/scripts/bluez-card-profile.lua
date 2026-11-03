#!/usr/bin/wpexec
cutils = require("common-utils")

local args = (...):parse()
local mode = args.mode or "list"
local dev_name = args.device or ""
local target = args.target or ""

local function fail(msg)
  print("ERROR: " .. msg)
  Core.quit()
end

if dev_name == "" then
  fail("missing device")
  return
end

local om = ObjectManager {
  Interest {
    type = "device",
    Constraint { "media.class", "=", "Audio/Device", type = "pw-global" },
  }
}

local handled = false

local function profile_available(profile)
  return profile and profile.available ~= "no"
end

local function handle_device(device)
  if handled then
    return
  end
  local name = device.properties["device.name"] or ""
  if name ~= dev_name then
    return
  end
  handled = true

  if mode == "list" then
    local active_index = nil
    for p in device:iterate_params("Profile") do
      local active = cutils.parseParam(p, "Profile")
      if active then
        active_index = active.index
      end
    end

    for p in device:iterate_params("EnumProfile") do
      local profile = cutils.parseParam(p, "EnumProfile")
      if profile_available(profile) then
        local current = (active_index ~= nil and profile.index == active_index) and "1" or "0"
        print(string.format("CODEC\t%s\t%s\t%s\t%s",
          tostring(profile.index), profile.name or "", profile.description or "", current))
      end
    end
    Core.quit()
    return
  end

  if mode == "set" then
    local target_index = tonumber(args.index)
    local target_codec = tostring(args.codec or "")
    if target == "" and target_index == nil and target_codec == "" then
      fail("missing target")
      return
    end

    -- A stale index must not outrank the profile the UI picked: try the exact
    -- profile name first, then the codec literal, then the index.
    local target_lower = tostring(target):lower()
    local match = nil
    local best_rank = 4
    for p in device:iterate_params("EnumProfile") do
      local profile = cutils.parseParam(p, "EnumProfile")
      if profile_available(profile) then
        local pname = profile.name or ""
        local description = tostring(profile.description or ""):lower()
        local rank = 4
        if target ~= "" and (pname == target or pname:lower() == target_lower) then
          rank = 1
        elseif target_codec ~= "" and description:find(target_codec:lower(), 1, true) then
          rank = 2
        elseif target_index ~= nil and tonumber(profile.index) == target_index then
          rank = 3
        end
        if rank < best_rank then
          best_rank = rank
          match = profile
          if rank == 1 then
            break
          end
        end
      end
    end

    if not match then
      fail("profile not found: " .. (target ~= "" and target or target_codec))
      return
    end

    local param = Pod.Object {
      "Spa:Pod:Object:Param:Profile", "Profile",
      index = tonumber(match.index),
      save = true,
    }
    device:set_param("Profile", param)
    Core.sync(function()
      print("OK\t" .. (match.name or target))
      Core.quit()
    end)
    return
  end

  fail("unknown mode " .. mode)
end

om:connect("object-added", function(_, device)
  handle_device(device)
end)

om:connect("installed", function()
  if handled then
    return
  end
  for device in om:iterate() do
    handle_device(device)
    if handled then
      return
    end
  end
  fail("device not found: " .. dev_name)
end)

om:activate()
Core.timeout_add(3000, function()
  if not handled then
    fail("timed out waiting for device " .. dev_name)
  end
  return false
end)
