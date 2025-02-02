---------------------------------------------------------------------------------------------------
-- Threat Widget
---------------------------------------------------------------------------------------------------
local ADDON_NAME, Addon = ...
local ThreatPlates = Addon.ThreatPlates

local Widget = Addon.Widgets:NewWidget("Threat")

---------------------------------------------------------------------------------------------------
-- Imported functions and constants
---------------------------------------------------------------------------------------------------

-- Lua APIs
local tostring = tostring
local string_format = string.format

-- WoW APIs
local UnitIsUnit, UnitDetailedThreatSituation, UnitName, UnitClass = UnitIsUnit, UnitDetailedThreatSituation, UnitName, UnitClass
local GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit
local GetRaidTargetIndex = GetRaidTargetIndex
local IsInGroup, IsInRaid, GetNumGroupMembers, GetNumSubgroupMembers = IsInGroup, IsInRaid, GetNumGroupMembers, GetNumSubgroupMembers

-- ThreatPlates APIs
local GetThreatSituation = Addon.GetThreatSituation
local Font = Addon.Font
local TransliterateCyrillicLetters = Addon.TransliterateCyrillicLetters

local _G =_G
-- Global vars/functions that we don't upvalue since they might get hooked, or upgraded
-- List them here for Mikk's FindGlobals script
-- GLOBALS: CreateFrame

local PATH = "Interface\\AddOns\\TidyPlates_ThreatPlates\\Widgets\\ThreatWidget\\"
local THREAT_REFERENCE = {
  [0] = "LOW",
  [1] = "MEDIUM",
  [2] = "MEDIUM",
  [3] = "HIGH",
}
local REVERSE_THREAT_SITUATION = {
  HIGH = "LOW",
  MEDIUM ="MEDIUM",
  LOW = "HIGH",
}

---------------------------------------------------------------------------------------------------
-- Cached configuration settings
---------------------------------------------------------------------------------------------------
local Settings, SettingsArt, ThreatColors, ThreatDetailsFunction

---------------------------------------------------------------------------------------------------
-- Event handling stuff
---------------------------------------------------------------------------------------------------

function Widget:UNIT_THREAT_LIST_UPDATE(unitid)
  if not unitid or unitid == "player" or UnitIsUnit("player", unitid) then return end

  local plate = GetNamePlateForUnit(unitid)
  if plate and plate.TPFrame.Active then
    local widget_frame = plate.TPFrame.widgets.Threat
    if widget_frame.Active then
      self:UpdateFrame(widget_frame, plate.TPFrame.unit)
    end
  end
end

function Widget:RAID_TARGET_UPDATE()
  self:UpdateAllFrames()
end

---------------------------------------------------------------------------------------------------
-- Widget functions for creation and update
---------------------------------------------------------------------------------------------------

function Widget:Create(tp_frame)
  -- Required Widget Code
  local widget_frame = _G.CreateFrame("Frame", nil, tp_frame)
  widget_frame:Hide()

  -- Custom Code
  --------------------------------------
  widget_frame:SetFrameLevel(tp_frame:GetFrameLevel() + 7)
  widget_frame.LeftTexture = widget_frame:CreateTexture(nil, "ARTWORK")
  widget_frame.RightTexture = widget_frame:CreateTexture(nil, "ARTWORK")
  widget_frame.RightTexture:SetPoint("LEFT", tp_frame.visual.healthbar, "RIGHT", 4, 0)
  widget_frame.RightTexture:SetSize(64, 64)

  widget_frame.Percentage = widget_frame:CreateFontString(nil, "OVERLAY")
  widget_frame.Percentage:SetFont("Fonts\\FRIZQT__.TTF", 11)

  self:UpdateLayout(widget_frame)
  --------------------------------------
  -- End Custom Code

  return widget_frame
end

function Widget:IsEnabled()
  return Addon.db.profile.threat.art.ON or Addon.db.profile.threatWidget.ThreatPercentage.Show
end

function Widget:OnEnable()
  self:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
  self:RegisterEvent("RAID_TARGET_UPDATE")
end

function Widget:OnDisable()
  self:UnregisterEvent("UNIT_THREAT_LIST_UPDATE")
  self:UnregisterEvent("RAID_TARGET_UPDATE")
end

function Widget:EnabledForStyle(style, unit)
  return not (unit.type == "PLAYER" or style == "NameOnly" or style == "NameOnly-Unique" or style == "etotem")
end

function Widget:OnUnitAdded(widget_frame, unit)
  local db = Addon.db.profile.threat.art

  if db.theme == "bar" then
    widget_frame.LeftTexture:ClearAllPoints()
    widget_frame.LeftTexture:SetSize(265, 64)
    widget_frame.LeftTexture:SetPoint("CENTER", widget_frame:GetParent(), "CENTER")
    widget_frame.LeftTexture:SetTexCoord(0, 1, 0, 1)

    widget_frame.RightTexture:Hide()
  else
    widget_frame.LeftTexture:ClearAllPoints()
    widget_frame.LeftTexture:SetSize(64, 64)
    widget_frame.LeftTexture:SetPoint("RIGHT", widget_frame:GetParent().visual.healthbar, "LEFT", -4, 0)
    widget_frame.LeftTexture:SetTexCoord(0, 0.25, 0, 1)

    widget_frame.RightTexture:SetTexCoord(0.75, 1, 0, 1)
    widget_frame.RightTexture:Show()
  end

  self:UpdateFrame(widget_frame, unit)
end

---------------------------------------------------------------------------------------------------
-- Threat value calculation
---------------------------------------------------------------------------------------------------

local function GetUnitThreatValue(unitid, mob_unitid)
  local is_tanking, status, scaled_percentage, _, threat_value = UnitDetailedThreatSituation(unitid, mob_unitid)
  return is_tanking, status, threat_value
end

local function GetUnitThreatPercentage(unitid, mob_unitid)
  local is_tanking, status, scaled_percentage, _, threat_value = UnitDetailedThreatSituation(unitid, mob_unitid)
  return is_tanking, status, scaled_percentage
end

-- If player is tanking, this function will return the unit and its threat value that is second on the threat table
-- If the player is not tanking, this funktion will return the tanking unit and its threat value
local function GetTopThreatUnitBesidesPlayer(unitid, threat_value_func)
  local top_unitid
  local top_threat_value = 0

  local group_type = (IsInRaid() and "raid") or "party"
  local num_group_members = (group_type == "raid" and GetNumGroupMembers()) or GetNumSubgroupMembers()
  for i = 1, num_group_members do
    local index_str = tostring(i)
    local group_unit_id = group_type .. index_str
   
    -- Only compare player's threat values to other group memebers, not to the player itself (in raid with GetNumGroupMembers)
    local _, group_unit_threat_value
    if not UnitIsUnit("player", group_unit_id) then
      _, _, group_unit_threat_value = threat_value_func(group_unit_id, unitid)
      if group_unit_threat_value and group_unit_threat_value > top_threat_value then
        top_threat_value = group_unit_threat_value
        top_unitid = group_unit_id
      end
    end

    group_unit_id = group_type .."pet" .. index_str
    _, _, group_unit_threat_value = threat_value_func(group_unit_id, unitid)
    if group_unit_threat_value and group_unit_threat_value > top_threat_value then
      top_threat_value = group_unit_threat_value
      top_unitid = group_unit_id
    end
  end

  local top_threat_unit_name = ""
  if top_unitid and ShowSecondPlayersName then
    top_threat_unit_name = TransliterateCyrillicLetters(UnitName(top_unitid)) .. ": "
  end

  return top_unitid, top_threat_value, top_threat_unit_name
end

local function GetTankThreatPercentage(unitid, db_threat_value)
  if not IsInGroup() then return nil, nil end

  local is_tanking, status, scaled_percentage, _, _ = UnitDetailedThreatSituation("player", unitid)
  if status == nil then return nil, nil end

  local threat_value_text = ""
  local threat_value_delta = 0

  if is_tanking then
    -- Tanking, so show difference to the 2nd player on the threat table, like: -50%
    local other_unitid, other_threat_value, other_threat_unit_name = GetTopThreatUnitBesidesPlayer(unitid, GetUnitThreatPercentage)
    if other_unitid then
      threat_value_delta = other_threat_value - scaled_percentage
      threat_value_text = other_threat_unit_name
    end

    -- If tanking, but other player has higher threat then add a "+"
    if threat_value_delta > 0 then
      threat_value_text = threat_value_text .. "+"
    end
  else
    -- Not tanking, so show own scaled percentage, like: 20% threat towards the currently tanking unit
    threat_value_delta = scaled_percentage
  end

  threat_value_text = threat_value_text .. string_format("%.0f%%", threat_value_delta)

  return status, threat_value_text
end

local function GetTankThreatValue(unitid, db_threat_value)
  if not IsInGroup() then return nil, nil end

  local is_tanking, status, scaled_percentage, _, threat_value = UnitDetailedThreatSituation("player", unitid)
  if status == nil then return nil, nil end

  local threat_value_text = ""
  local threat_value_delta = 0

  -- Tanking: - second
  if is_tanking then
    -- Tanking, so show difference to the 2nd player on the threat table, like: -1.5k
    local other_unitid, other_threat_value, other_threat_unit_name = GetTopThreatUnitBesidesPlayer(unitid, GetUnitThreatValue)
    if other_unitid then
      threat_value_delta = other_threat_value - threat_value
      threat_value_text = other_threat_unit_name
    end

    -- If tanking, but other player has higher threat then add a "+"
    if threat_value_delta > 0 then
      threat_value_text = threat_value_text .. "+"
    end
  else
    -- Not tanking, so show own threat value, like: 1.4k threat towards the currently tanking unit
    -- threat_value_delta = threat_value
    -- Formula from ShafferZee: https://github.com/Backupiseasy/ThreatPlates/issues/285
    if scaled_percentage ~= 0 then
      threat_value_delta = threat_value - threat_value / (scaled_percentage / 100)
    end
  end

  threat_value_text = threat_value_text .. Addon.Truncate(threat_value_delta)

  return status, threat_value_text
end

local function GetThreatDelta(unitid, threat_value_func)
  local is_tanking, status, threat_value = threat_value_func("player", unitid)

  local threat_value_text = ""
  local threat_value_delta = 0

  if IsInGroup() then
    -- If player is tanking, other unit will be the unit and its threat value that is second on the threat table
    -- If the player is not tanking, other unit will be the tanking unit and its threat value
    local other_unitid, other_threat_value, other_threat_unit_name = GetTopThreatUnitBesidesPlayer(unitid, threat_value_func)

    if other_unitid then
      threat_value_delta = other_threat_value - threat_value
      threat_value_text = other_threat_unit_name
    end

    -- If player is tanking, delta is already < 0 and arithmetic sign is already -.
    -- If the player is not tanking, detal is > 0 and we add the arithmetic sign +.
    -- No arithmetic sign means that the player is not in a group and no delta is used.
    if not is_tanking then
     threat_value_text = threat_value_text .. "+"
    end
  else
    -- If not in combat, show nothing. Otherwise show the unit's threat value as there are no other units involved 
    -- in combat for which we can get a threat value
    if status == nil then return nil, nil end

    threat_value_delta = threat_value 
  end

  return threat_value_text, threat_value_delta
end

local function GetThreatValueDelta(unitid, db_threat_value)
  local threat_value_text, threat_value_delta = GetThreatDelta(unitid, GetUnitThreatValue)
  return threat_value_delta ~= nil, threat_value_text .. Addon.Truncate(threat_value_delta)
end

local function GetThreatPercentageDelta(unitid, db_threat_value)
  local threat_value_text, threat_value_delta = GetThreatDelta(unitid, GetUnitThreatPercentage)
  return threat_value_delta ~= nil, threat_value_text .. string_format("%.0f%%", threat_value_delta)
end

local THREAT_DETAILS_FUNTIONS = {
  SCALED_PERCENTAGE = function(unitid)
    local _, status, scaled_percentage, _, _ = UnitDetailedThreatSituation("player", unitid)
    return status, string_format("%.0f%%", scaled_percentage)
  end,
  RAW_PERCENTAGE = function(unitid)
    local _, status, _, raw_percentage, _ = UnitDetailedThreatSituation("player", unitid)
    return status, string_format("%.0f%%", raw_percentage)
  end,
  TANK_PERCENTAGE = GetTankThreatPercentage,
  TANK_VALUE = GetTankThreatValue,
  THREAT_VALUE_DELTA = GetThreatValueDelta,
  THREAT_PERCENTAGE_DELTA = GetThreatPercentageDelta,
}

function Widget:UpdateFrame(widget_frame, unit)
  local db = Addon.db.profile.threat

  if not Addon:ShowThreatFeedback(unit) then
    widget_frame:Hide()
    return
  end

  -- unique_setting.useStyle is already checked when setting the style of the nameplate (to custom)
  local unique_setting = unit.CustomPlateSettings
  if unique_setting and not unique_setting.UseThreatColor then
    widget_frame:Hide()
    return
  end

  widget_frame.Percentage:SetHeight(widget_frame:GetHeight())

  -- As the widget is enabled, textures or percentages must be enabled.
  local style = (Addon:PlayerRoleIsTank() and "tank") or "dps"
  local threat_situation = GetThreatSituation(unit, style, db.toggle.OffTank)

  -- Show threat art (textures)
  if SettingsArt.ON and not (GetRaidTargetIndex(unit.unitid) and db.marked.art) then
    local texture = PATH
    if style ~= "tank" then
      -- Tanking uses regular textures / swapped for dps / healing
      texture = texture .. db.art.theme.."\\".. REVERSE_THREAT_SITUATION[threat_situation]
    else
      texture = texture .. db.art.theme.."\\".. threat_situation
    end

    if db.art.theme == "bar" then
      widget_frame.LeftTexture:SetTexture(texture)
      widget_frame.LeftTexture:Show()
    else
      widget_frame.LeftTexture:SetTexture(texture)
      widget_frame.RightTexture:SetTexture(texture)
      widget_frame.LeftTexture:Show()
      widget_frame.RightTexture:Show()
    end
  else
    widget_frame.LeftTexture:Hide()
    widget_frame.RightTexture:Hide()
  end

  local db_threat_value = Settings.ThreatPercentage
  if db_threat_value.Show and (not db_threat_value.OnlyInGroups or IsInGroup()) then
    local status, percentage_text = ThreatDetailsFunction(unit.unitid, db_threat_value)
    if status ~= nil then
      widget_frame.Percentage:SetText(percentage_text)
  
      local color
      if Settings.ThreatPercentage.UseThreatColor then
        color = ThreatColors[style].threatcolor[threat_situation]
      else
        color = Settings.ThreatPercentage.CustomColor
      end
      widget_frame.Percentage:SetTextColor(color.r, color.g, color.b)

      widget_frame.Percentage:Show()
    else
      widget_frame.Percentage:Hide()
    end
  else
    widget_frame.Percentage:Hide()
  end

  widget_frame:Show()
end

function Widget:UpdateLayout(widget_frame)
  -- widget_frame:ClearAllPoints()
  widget_frame:SetAllPoints(widget_frame:GetParent())

  Font:UpdateText(widget_frame, widget_frame.Percentage, Settings.ThreatPercentage)
end

function Widget:UpdateSettings()
  Settings = Addon.db.profile.threatWidget
  SettingsArt = Addon.db.profile.threat.art
  ThreatColors = Addon.db.profile.settings

  ShowSecondPlayersName = Settings.ThreatPercentage.SecondPlayersName

  ThreatDetailsFunction = THREAT_DETAILS_FUNTIONS[Settings.ThreatPercentage.Type]
end