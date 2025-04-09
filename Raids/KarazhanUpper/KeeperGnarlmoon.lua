local module, L = BigWigs:ModuleDeclaration("Keeper Gnarlmoon", "Karazhan")

-- module variables
module.revision = 30002 -- Incremented revision
module.enabletrigger = module.translatedName
-- ADDED "flock" to toggle options
module.toggleoptions = { "lunarshift", "owlphase", "owlenrage", "moondebuff", "flock", "bosskill" }
module.zonename = {
 AceLibrary("AceLocale-2.2"):new("BigWigs")["Tower of Karazhan"],
 AceLibrary("Babble-Zone-2.2")["Tower of Karazhan"],
}
-- module defaults
module.defaultDB = {
 lunarshift = true,
 owlphase = true,
 owlenrage = true,
 moondebuff = true,
 flock = true, -- ADDED flock default
}

-- localization
L:RegisterTranslations("enUS", function()
 return {
  cmd = "Gnarlmoon",

  lunarshift_cmd = "lunarshift",
  lunarshift_name = "Lunar Shift Alert",
  lunarshift_desc = "Warns when Keeper Gnarlmoon begins to cast Lunar Shift",

  owlphase_cmd = "owlphase",
  owlphase_name = "Owl Phase Alert",
  owlphase_desc = "Warns when Keeper Gnarlmoon enters and exits the Owl Dimension phase",

  owlenrage_cmd = "owlenrage",
  owlenrage_name = "Owl Enrage Alert",
  owlenrage_desc = "Warns when the Owls are about to enrage",

  moondebuff_cmd = "moondebuff",
  moondebuff_name = "Moon Debuff Alert",
  moondebuff_desc = "Warns when you get affected by Red Moon or Blue Moon",

  -- ADDED Flock of Ravens localization
  flock_cmd = "flock",
  flock_name = "Flock of Ravens Alert",
  flock_desc = "Warns when Flock of Ravens are active and tracks kills.",
  -- !! IMPORTANT !! Verify this is the exact name of the summoned ravens
  trigger_ravenName = "Blood Raven",
  msg_flockStart = "Flock of Ravens detected! Kill them fast!",
  bar_flockCount = "Ravens Killed",
  msg_flockAllDead = "All Ravens killed!",

  trigger_lunarShiftCast = "Keeper Gnarlmoon begins to cast Lunar Shift",
  bar_lunarShiftCast = "Lunar Shift Casting!",
  bar_lunarShiftCD = "Next Lunar Shift",
  msg_lunarShift = "Lunar Shift casting!",

  trigger_owlPhaseStart = "Keeper Gnarlmoon gains Worgen Dimension",
  trigger_owlPhaseEnd = "Worgen Dimension fades from Keeper Gnarlmoon",
  msg_owlPhaseStart = "Owl Phase begins - kill the owls at the same time within 1 min!",
  msg_owlPhaseEnd = "Owl Phase ended!",

  bar_owlEnrage = "Owls Enrage",
  msg_owlEnrage = "Owls will enrage in 10 seconds!",
  msg_owlsEnraged = "Owls Enraged!",

  trigger_redMoon = "afflicted by Red Moon",
  trigger_blueMoon = "afflicted by Blue Moon",
  msg_redMoon = "You have RED MOON!",
  msg_blueMoon = "You have BLUE MOON!",
 }
end)

-- timer and icon variables
local timer = {
 lunarShiftCast = 5,
 lunarShiftCD = 30,
 owlPhase = 67, -- approximately based on logs
 owlEnrage = 60,
 -- No specific timer needed for Flock itself, maybe a timeout for the bar?
 flockBarTimeout = 45, -- How long the counter bar stays up if not all die (adjust as needed)
}

local icon = {
 lunarShift = "Spell_Nature_StarFall",
 owlPhase = "Ability_EyeOfTheOwl",
 owlEnrage = "Spell_Shadow_UnholyFrenzy",
 redMoon = "inv_misc_orb_05",
 blueMoon = "inv_ore_arcanite_02",
 flock = "Spell_Shadow_SummonImp", -- ADDED Flock icon
}

local color = {
 lunarShift = "Blue",
 owlPhase = "Green",
 owlEnrage = "Red",
 flock = "Orange", -- ADDED Flock color
}

-- Sync names MUST be unique. Appending revision helps.
local syncName = {
 lunarShift = "GnarlmoonLunarShift" .. module.revision,
 owlPhaseStart = "GnarlmoonOwlStart" .. module.revision,
 owlPhaseEnd = "GnarlmoonOwlEnd" .. module.revision,
 -- ADDED Flock sync names
 flockStart = "GnarlmoonFlockStart" .. module.revision,
 flockDeath = "GnarlmoonFlockDeath" .. module.revision, -- Base name for death sync
}

-- Total number of ravens expected
local TOTAL_RAVENS = 12

-- module functions
function module:OnEnable()
 self:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE")
 self:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS")
 self:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_OTHER")
 self:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
 self:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH") -- ADDED Event for mob deaths

 self:ThrottleSync(3, syncName.lunarShift)
 self:ThrottleSync(5, syncName.owlPhaseStart)
 self:ThrottleSync(5, syncName.owlPhaseEnd)
 -- ADDED Flock sync throttles
 self:ThrottleSync(2, syncName.flockStart)
 self:ThrottleSync(1, syncName.flockDeath) -- Allow death updates frequently
end

function module:OnSetup()
 self.started = nil
 self.phase = nil
 self.owlPhaseCount = 0
 -- ADDED Flock state variables
 self.flockPhaseActive = false
 self.flockKilledCount = 0
end

function module:OnEngage()
 self.phase = 1
 self.owlPhaseCount = 0
 -- ADDED Reset Flock state on engage
 self.flockPhaseActive = false
 self.flockKilledCount = 0
 self:RemoveBar(L["bar_flockCount"]) -- Ensure bar is removed from previous pulls

 if self.db.profile.lunarshift then
       self:Bar(L["bar_lunarShiftCD"], timer.lunarShiftCD, icon.lunarShift, true, color.lunarShift)
 end
end

-- ADDED Combat Log handler for Hostile Death
function module:CHAT_MSG_COMBAT_HOSTILE_DEATH(msg)
 -- Check if the message is "[Raven Name] dies."
 local ravenName = L["trigger_ravenName"]
 -- Use ^ to anchor search to the beginning, %.$ to anchor to the end for exact match
 if string.find(msg, "^" .. ravenName .. " dies%.$") then
  -- Check if flock module is enabled
  if not self.db.profile.flock then return end

  -- If this is the first raven death of this wave
  if not self.flockPhaseActive then
   self.flockPhaseActive = true
   self.flockKilledCount = 1
   -- Send a sync to start the alert and bar for everyone
   self:Sync(syncName.flockStart)
  else
   -- Already active, just increment count and send update
   self.flockKilledCount = self.flockKilledCount + 1
   -- Send sync with the new count
   -- Note: Syncing every death might be chatty, but necessary for count accuracy in Vanilla
   self:Sync(syncName.flockDeath .. " " .. self.flockKilledCount)

   -- Optional: Local update immediately for responsiveness
   self:FlockUpdate(self.flockKilledCount)
  end
 end
end

function module:CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE(msg)
 if string.find(msg, L["trigger_lunarShiftCast"]) then
  self:Sync(syncName.lunarShift)
 end
end

function module:CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS(msg)
 if string.find(msg, L["trigger_owlPhaseStart"]) then
  self:Sync(syncName.owlPhaseStart)
 end
end

function module:CHAT_MSG_SPELL_AURA_GONE_OTHER(msg)
 if string.find(msg, L["trigger_owlPhaseEnd"]) then
  self:Sync(syncName.owlPhaseEnd)
 end
end

function module:CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE(msg)
 if self.db.profile.moondebuff then
  if string.find(msg, L["trigger_redMoon"]) then
   self:Message(L["msg_redMoon"], "Important", true, "Alarm")
   self:WarningSign(icon.redMoon, 5, true, "RED")
  elseif string.find(msg, L["trigger_blueMoon"]) then
   self:Message(L["msg_blueMoon"], "Important", true, "Alert")
   self:WarningSign(icon.blueMoon, 5, "BLUE")
  end
 end
end

function module:BigWigs_RecvSync(sync, rest, nick)
 if sync == syncName.lunarShift then
  self:LunarShift()
 elseif sync == syncName.owlPhaseStart then
  self:OwlPhaseStart()
 elseif sync == syncName.owlPhaseEnd then
  self:OwlPhaseEnd()
 -- ADDED Flock sync handlers
 elseif sync == syncName.flockStart then
  self:FlockStart()
 -- Check if the sync message starts with the flockDeath sync name
 elseif string.find(sync, "^" .. syncName.flockDeath) then
  -- Extract the count number from the rest of the sync message
  local _, _, countStr = string.find(sync, syncName.flockDeath .. " (%d+)")
  if countStr then
   local count = tonumber(countStr)
   if count then
    self:FlockUpdate(count)
   end
  end
 end
end

-- ADDED Function to handle the start of the Flock phase
function module:FlockStart()
 if not self.db.profile.flock then return end

 -- Set state (even if already set locally, sync confirms)
 self.flockPhaseActive = true
 self.flockKilledCount = 1 -- Sync only sent on first kill

 self:Message(L["msg_flockStart"], "Urgent", nil, icon.flock, "Alert")
 -- Start the bar showing 1/12
 self:Bar(L["bar_flockCount"], string.format("%d/%d", self.flockKilledCount, TOTAL_RAVENS), timer.flockBarTimeout, icon.flock, true, color.flock)
end

-- ADDED Function to update the Flock kill count
function module:FlockUpdate(count)
 if not self.db.profile.flock or not self.flockPhaseActive then return end

 -- Update local count based on sync
 self.flockKilledCount = count

 -- Check if all ravens are dead
 if self.flockKilledCount >= TOTAL_RAVENS then
  self:Message(L["msg_flockAllDead"], "Positive", nil, icon.flock)
  self:RemoveBar(L["bar_flockCount"])
  -- Reset state for the next potential wave (if any)
  self.flockPhaseActive = false
  self.flockKilledCount = 0
 else
  -- Update the bar with the new count and reset its timer
  self:Bar(L["bar_flockCount"], string.format("%d/%d", self.flockKilledCount, TOTAL_RAVENS), timer.flockBarTimeout, icon.flock, true, color.flock)
 end
end


function module:LunarShift()
 if self.db.profile.lunarshift then
  self:Message(L["msg_lunarShift"], "Important")
  self:RemoveBar(L["bar_lunarShiftCD"])
  self:Bar(L["bar_lunarShiftCast"], timer.lunarShiftCast, icon.lunarShift, true, color.lunarShift)
  self:DelayedBar(timer.lunarShiftCast, L["bar_lunarShiftCD"], timer.lunarShiftCD - timer.lunarShiftCast, icon.lunarShift, true, color.lunarShift)
 end
end

function module:OwlPhaseStart()
 -- TODO add owl hp display
 if self.db.profile.owlphase then
  self.owlPhaseCount = self.owlPhaseCount + 1
  self:Message(L["msg_owlPhaseStart"], "Attention")

  if self.db.profile.owlenrage then
   self:Bar(L["bar_owlEnrage"], timer.owlEnrage, icon.owlEnrage, true, color.owlEnrage)
  end

  -- Cancel Lunar Shift bars during owl phase
  self:RemoveBar(L["bar_lunarShiftCast"])
  self:RemoveBar(L["bar_lunarShiftCD"])
 end
end

function module:OwlPhaseEnd()
 if self.db.profile.owlphase then
  self:Message(L["msg_owlPhaseEnd"], "Positive")
  self:RemoveBar(L["bar_owlEnrage"])

  -- It's possible Flock happens during Owl Phase. Decide if the Flock bar should also be removed here.
  -- If ravens can persist after Owl Phase ends, DO NOT remove the bar here.
  -- If ravens are *only* during Owl Phase, uncomment the next line:
  -- self:RemoveBar(L["bar_flockCount"])
  -- self.flockPhaseActive = false -- Reset state if tied to Owl Phase end
 end
end

function module:Test()
 -- Enable all options for testing
 self.db.profile.lunarshift = true
 self.db.profile.owlphase = true
 self.db.profile.owlenrage = true
 self.db.profile.moondebuff = true
 self.db.profile.flock = true -- ADDED flock enable for test

 -- Initialize module state
 self:OnSetup()

 self.phase = 1
 self.owlPhaseCount = 0
 -- ADDED Flock state reset for test
 self.flockPhaseActive = false
 self.flockKilledCount = 0

 local events = {
  -- Initial Lunar Shift
  { time = 3, text = "Keeper Gnarlmoon begins to cast Lunar Shift." },

  { time = 9, text = "Keeper Gnarlmoon begins to cast Lunar Shift." },

  -- ADDED Flock Simulation (starts slightly after a shift maybe?)
  { time = 12, text = L["trigger_ravenName"] .. " dies." }, -- First raven dies
  { time = 13, text = L["trigger_ravenName"] .. " dies." }, -- Second
  { time = 14, text = L["trigger_ravenName"] .. " dies." },
  { time = 15, text = L["trigger_ravenName"] .. " dies." },
  { time = 16, text = L["trigger_ravenName"] .. " dies." },
  { time = 17, text = L["trigger_ravenName"] .. " dies." },
  { time = 18, text = L["trigger_ravenName"] .. " dies." },
  { time = 19, text = L["trigger_ravenName"] .. " dies." },
  { time = 20, text = L["trigger_ravenName"] .. " dies." },
  { time = 21, text = L["trigger_ravenName"] .. " dies." },
  { time = 22, text = L["trigger_ravenName"] .. " dies." },
  { time = 23, text = L["trigger_ravenName"] .. " dies." }, -- Last raven dies


  -- First Owl Phase (at 66.66% HP)
  { time = 30, text = "Keeper Gnarlmoon gains Worgen Dimension (1)." },

  -- Moon debuffs
  { time = 32, text = "You are afflicted by Red Moon (1)." },
  { time = 42, text = "You are afflicted by Blue Moon (1)." },

  -- Owl Phase ends
  { time = 45, text = "Worgen Dimension fades from Keeper Gnarlmoon." },

  -- Second Lunar Shift
  { time = 55, text = "Keeper Gnarlmoon begins to cast Lunar Shift." },

  -- Second Owl Phase (at 33.33% HP)
  { time = 65, text = "Keeper Gnarlmoon gains Worgen Dimension (1)." },

  -- Moon debuffs again
  { time = 67, text = "You are afflicted by Blue Moon (1)." },
  { time = 77, text = "You are afflicted by Red Moon (1)." },

  -- Owl Phase ends
  { time = 80, text = "Worgen Dimension fades from Keeper Gnarlmoon." },

  -- Final Lunar Shift
  { time = 90, text = "Keeper Gnarlmoon begins to cast Lunar Shift." }
 }

 local handlers = {
  ["Keeper Gnarlmoon begins to cast Lunar Shift."] = function()
   print("Test: Keeper Gnarlmoon begins to cast Lunar Shift")
   module:CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE("Keeper Gnarlmoon begins to cast Lunar Shift.")
  end,
  ["Keeper Gnarlmoon gains Worgen Dimension (1)."] = function()
   print("Test: Keeper Gnarlmoon gains Worgen Dimension")
   module:CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS("Keeper Gnarlmoon gains Worgen Dimension")
  end,
  ["Worgen Dimension fades from Keeper Gnarlmoon."] = function()
   print("Test: Worgen Dimension fades from Keeper Gnarlmoon")
   module:CHAT_MSG_SPELL_AURA_GONE_OTHER("Worgen Dimension fades from Keeper Gnarlmoon")
  end,
  ["You are afflicted by Red Moon (1)."] = function()
   print("Test: You are afflicted by Red Moon")
   module:CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE("You are afflicted by Red Moon (1).")
  end,
  ["You are afflicted by Blue Moon (1)."] = function()
   print("Test: You are afflicted by Blue Moon")
   module:CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE("You are afflicted by Blue Moon (1).")
  end,
  -- ADDED Handler for Raven Death Test Events
  [L["trigger_ravenName"] .. " dies."] = function(eventText) -- Pass eventText
      print("Test: " .. eventText)
      module:CHAT_MSG_COMBAT_HOSTILE_DEATH(eventText)
  end,
 }

 -- Schedule each event at its absolute time
 for i, event in ipairs(events) do
  -- Ensure the key exists in handlers before scheduling
  local handlerKey = event.text
  -- For raven deaths, the handler key is generic, but we pass the specific text
  if string.find(event.text, L["trigger_ravenName"] .. " dies") then
    handlerKey = L["trigger_ravenName"] .. " dies."
  end

  if handlers[handlerKey] then
      self:ScheduleEvent("GnarlmoonTest" .. i, function(eventTextToPass)
          if handlers[handlerKey] then
              handlers[handlerKey](eventTextToPass) -- Pass the original event text
          end
      end, event.time, event.text) -- Pass the original event text
  else
      print("Warning: No handler defined for test event: " .. event.text)
  end
 end

 self:Message("Keeper Gnarlmoon test started", "Positive")
 return true
end

--/run local m=BigWigs:GetModule("Keeper Gnarlmoon"); BigWigs:SetupModule("Keeper Gnarlmoon");m:Test();