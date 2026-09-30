"""Lua 5.1 regression harness. Pass the directory containing lupa as argv[1].
Mocks validate addon control flow, not WoW rendering or server telemetry.
"""
import sys
import unittest
from pathlib import Path
if len(sys.argv) > 1 and Path(sys.argv[1]).is_dir():
    sys.path.insert(0, sys.argv.pop(1))
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
def source(file):
    return (ROOT / file).read_text(encoding="utf-8-sig")
def section(file, start, end):
    text = source(file)
    return text[text.index(start):text.index(end, text.index(start))]

MOCKS = r"""
now=1; sounds={}; alerts={}; tickers={}; delayed={}; timers={}; afterDelays={}
CLASSIC_API_VERSION=11515; SUPERWOW_VERSION="2.2"
AutoBG_Settings={}
function GetTime() return now end
function UnitName(u) if u=="player" then return "Me" else return "Enemy" end end
function UnitFactionGroup() return "Alliance" end
function UnitExists(u) return not (u=="player" and playerExists==false) end
function UnitIsVisible() return visible~=false end
function UnitDistanceSquared() return distanceSquared or 25, rangeKnown~=false end
function UnitInLineOfSight() return sight~=false and not sightUnknown end
function UnitGUID(u) if u=="player" then return "0x00000000" end return "0x00000001" end
function UnitTokenFromName() return nil end
function UnitClass() return "Rogue", "ROGUE" end
function UnitLevel() return 60 end
function UnitRace() return "Human", "Human" end
function UnitIsPlayer() return true end
function UnitCanAttack() return true end
function UnitIsFriend() return nil end
function UnitHealth() return 100 end
function UnitHealthMax() return 100 end
function UnitIsDead() return false end
function UnitIsGhost() return false end
function UnitIsUnit() return false end
function IsInInstance() return inBG, inBG and "pvp" or "none" end
function GetRealZoneText() return "Warsong Gulch" end
function GetBattlefieldStatus() return inBG and "active" or "none", "Warsong Gulch" end
function GetNumBattlefieldScores() return 1 end
function GetBattlefieldScore() return "Enemy",0,0,0,0,0,0,0,"Rogue","ROGUE" end
function RequestBattlefieldScoreData() end
function GetLocale() return "enUS" end
function SpellInfo(id) if id==999 then return "Invisibility" end end
function SpellStopCasting() castStops=(castStops or 0)+1; queuedCast=nil end
function SpellStopTargeting() terrainStops=(terrainStops or 0)+1 end
function ClearTarget() targetClears=(targetClears or 0)+1 end
function PlaySoundFile(path) sounds[#sounds+1]=path end
table.wipe=function(t) for k in pairs(t) do t[k]=nil end end
wipe=table.wipe
C_Timer={
 NewTicker=function(t,f) tickers[#tickers+1]=f end,
 After=function(t,f) delayed[#delayed+1]=f; afterDelays[#afterDelays+1]=t end,
 NewTimer=function(delay,callback)
  local timer={due=now+delay,cancelled=false}
  function timer:Cancel() self.cancelled=true end
  function timer:IsCancelled() return self.cancelled end
  timers[#timers+1]=timer
  delayed[#delayed+1]=function()
   if timer.cancelled then return end
   now=math.max(now,timer.due)
   callback()
  end
  return timer
 end
}
C_UnitAuras={
 GetAuraDataByIndex=function(u,i) return auras and auras[i] end,
 GetAuraSlots=function(u,filter,max,token,out)
  table.wipe(out)
  for i=1,#(auras or {}) do out[i]=i end
  out.n=#(auras or {})
  return nil,out.n
 end,
 GetAuraDataBySlot=function(u,i) return auras and auras[i] end
}
local methods={}
function methods:SetScript(k,v) self.scripts[k]=v end
function methods:RegisterEvent(e) self.events[e]=true end
function methods:SetWidth(v) self.width=v end
function methods:StartMoving() self.moving=true end
function methods:StopMovingOrSizing() self.moving=false end
function methods:GetWidth() return self.width or 200 end
function methods:SetHeight(v) self.height=v end
function methods:GetHeight() return self.height or 20 end
function methods:SetScale(v) self.scale=v end
function methods:GetScale() return self.scale or 1 end
function methods:SetText(v) self.text=v end
function methods:GetText() return self.text end
function methods:SetTexture(v) self.texture=v end
function methods:SetTexCoord(...) self.texcoords={...} end
function methods:SetFont(path,size) self.fontSize=size end
function methods:SetJustifyH(v) self.justify=v end
function methods:SetPoint(...) self.point={...}; self.points=self.points or {}; self.points[self.point[1]]=self.point end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:IsShown() return self.shown end
function methods:SetShown(v) self.shown=v end
function methods:GetStringWidth() return #(self.text or "")*7 end
function methods:GetFrameLevel() return 1 end
function methods:GetParent() return self.parent end
function methods:CreateTexture() return CreateFrame("Texture",nil,self) end
function methods:CreateFontString() return CreateFrame("FontString",nil,self) end
local noops={"SetBackdrop","SetBackdropColor","SetBackdropBorderColor","SetTextColor",
 "SetVertexColor","SetAlpha","SetAllPoints","ClearAllPoints",
 "SetMovable","SetClampedToScreen","EnableMouse","RegisterForClicks","RegisterForDrag",
 "SetFrameStrata","SetFrameLevel","SetHighlightTexture","SetNormalTexture","SetPushedTexture",
 "SetDisabledTexture","SetStatusBarTexture","SetStatusBarColor","SetMinMaxValues","SetValue",
 "SetDrawLayer","SetShadowOffset","SetShadowColor"}
for _,k in ipairs(noops) do methods[k]=function() end end
function CreateFrame(kind,name,parent)
 local f=setmetatable({scripts={},events={},shown=true,parent=parent},{__index=methods})
 if name then _G[name]=f end
 return f
end
UIParent=CreateFrame("Frame")
function fire(frame,event,...) frame.scripts.OnEvent(frame,event,...) end
"""
class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCKS)
    def runlua(self,text):
        self.lua.execute(text)
    def load_units(self):
        self.lua.execute(source("AutoBG_Targets.lua"))
        self.lua.execute(source("AutoBG_Spy.lua"))
        self.runlua("""
            fire(AutoBG_Targets,"PLAYER_LOGIN")
            fire(AutoBG_SpyEventFrame,"PLAYER_LOGIN")
        """)
    def bg(self):
        self.load_units()
        self.runlua('inBG=true; fire(AutoBG_Targets,"UPDATE_BATTLEFIELD_SCORE")')

    def load_core(self):
        self.runlua("""
            SlashCmdList={}; queues={}; accepted={}; requested={}
            hooks={}; function hooksecurefunc(name,callback) hooks[name]=callback end
            function PlaySound() end
            function GetBattlefieldStatus(id)
                local q=queues[id] or {}
                return q.status or "none",q.map
            end
            function AcceptBattlefieldPort(id,accept) accepted[#accepted+1]={id,accept} end
            function GetBattlefieldWinner() return nil end
            function GetBattlefieldInfo() return battlefieldName or 'Warsong Gulch' end
            function AutoBG_IsPlayerAFK() return false end
        """)
        self.lua.execute(source("AutoBG.lua"))
        self.runlua('fire(AutoBGFrame,"ADDON_LOADED","AutoBG")')

    def test_delayed_accept_ownership_and_setting(self):
        self.load_core()
        self.runlua("""
            AutoBG_Settings.AutoAccept=true; AutoBG_Settings.AutoAcceptDelay=5
            AutoBG_Settings.NotifySound=false
            queues[1]={status="confirm",map="Warsong Gulch"}
            fire(AutoBGFrame,"UPDATE_BATTLEFIELD_STATUS")
            local old=delayed[#delayed]
            queues[1].status="queued"
            fire(AutoBGFrame,"UPDATE_BATTLEFIELD_STATUS")
            queues[1].status="confirm"
            fire(AutoBGFrame,"UPDATE_BATTLEFIELD_STATUS")
            local current=delayed[#delayed]
            old(); assert(#accepted==0)
            AutoBG_Settings.AutoAccept=false
            current(); assert(#accepted==0)
            AutoBG_Settings.AutoAccept=true
            current(); assert(#accepted==1 and accepted[1][2]==1)
        """)

    def test_invalid_saved_accept_delay_is_normalized_before_queue_events(self):
        self.load_core()
        self.runlua("""
            for _,value in ipairs({'invalid',false,{},-10,'5',999}) do
                AutoBG_Settings.AutoAcceptDelay=value
                fire(AutoBGFrame,'ADDON_LOADED','AutoBG')
                local expected=value=='5' and 5 or (value==999 and 119 or 0)
                assert(AutoBG_Settings.AutoAcceptDelay==expected)
            end
            AutoBG_Settings.AutoAcceptDelay='invalid'
            fire(AutoBGFrame,'ADDON_LOADED','AutoBG')
            AutoBG_Settings.AutoAccept=true; AutoBG_Settings.NotifySound=false
            queues[1]={status='confirm',map='Warsong Gulch'}
            fire(AutoBGFrame,'UPDATE_BATTLEFIELD_STATUS')
            assert(#accepted==1)
        """)

    def test_disabling_login_queue_invalidates_its_pending_callback(self):
        self.load_core()
        self.runlua("""
            AutoBG_Settings.AutoQueueLogin=true
            AutoBG_QueueAllBGs=function() requested[#requested+1]='login' end
            fire(AutoBGFrame,'PLAYER_ENTERING_WORLD')
            assert(#delayed==1)
            AutoBG_Settings.AutoQueueLogin=false
            delayed[1](); assert(#requested==0)
        """)

    def test_enabled_login_queue_still_runs_after_delay(self):
        self.load_core()
        self.runlua("""
            AutoBG_Settings.AutoQueueLogin=true
            AutoBG_QueueAllBGs=function() requested[#requested+1]='login' end
            fire(AutoBGFrame,'PLAYER_ENTERING_WORLD')
            delayed[1](); assert(#requested==1)
        """)

    def test_queue_cancel_supersedes_callback(self):
        self.load_core()
        self.runlua("""
            AutoBG_GetSelectedBGs=function() return {"Warsong Gulch","Arathi Basin"} end
            AutoBG_TriggerBattlegroundFinder=function(name) requested[#requested+1]=name end
            AutoBG_QueueAllBGs()
            assert(#requested==1)
            local old=delayed[#delayed]
            AutoBG_CancelAllQueues()
            AutoBG_QueueAllBGs()
            assert(#requested==2)
            old(); assert(#requested==2)
            delayed[#delayed](); assert(#requested==3)
        """)

    def test_finder_failure_releases_local_queue_state(self):
        self.load_core()
        self.runlua("""
            AutoBG_GetSelectedBGs=function() return {"Warsong Gulch","Arathi Basin"} end
            AutoBG_QueueAllBGs()
            local old=delayed[#delayed]
            auras={{spellId=26013,name="Deserter"}}
            AutoBG_TriggerBattlegroundFinder("Warsong Gulch")
            table.wipe(auras); table.wipe(delayed)
            old()
            assert(#delayed==0)
        """)

    def prepare_rejoin(self, start=True):
        self.load_core()
        self.runlua('''
            AutoBG_Settings.AutoRejoin=true; AutoBG_Settings.AutoLeave=false
            AutoBG_Settings.NotifySound=false; inBG=true
            function GetBattlefieldWinner() return 1 end
            function JoinBattlegroundQueue(name) requested[#requested+1]=name end
            fire(AutoBGFrame,'PLAYER_ENTERING_WORLD')
            queues[1]={status='active',map='Warsong Gulch'}
            fire(AutoBGFrame,'UPDATE_BATTLEFIELD_STATUS')
            inBG=false; queues[1]=nil
        ''')
        if start:
            self.runlua('''
            fire(AutoBGFrame,'PLAYER_ENTERING_WORLD')
            if #requested==0 then table.remove(delayed,1)() end
            assert(#requested==1)
            ''')

    def test_rejoin_retry_is_local_and_bounded(self):
        self.prepare_rejoin()
        self.runlua('''
            local index=1
            while delayed[index] and index<20 do
                local callback=delayed[index]; index=index+1; callback()
            end
            assert(#requested==3, 'Rejoin must stop after three attempts')
            assert(index<20, 'Retry chain must terminate')
        ''')

    def test_unrelated_queue_does_not_confirm_rejoin(self):
        self.prepare_rejoin()
        self.runlua('''
            queues[2]={status='queued',map='Arathi Basin'}
            delayed[#delayed]()
            assert(#requested==2, 'A different queue cannot confirm WSG')
            queues[1]={status='queued',map='Warsong Gulch'}
            delayed[#delayed]()
            fire(AutoBGFrame,'UPDATE_BATTLEFIELD_STATUS')
            assert(#requested==2)
        ''')

    def test_queue_window_submission_does_not_publish_rejoin_success(self):
        self.prepare_rejoin()
        self.runlua('''
            function JoinBattlefield() end
            fire(AutoBGFrame,'BATTLEFIELDS_SHOW')
            delayed[1]()
            assert(#requested==2, 'Submission must still verify queue state')
        ''')

    def test_manual_queue_and_cancel_supersede_rejoin(self):
        self.prepare_rejoin()
        self.runlua('''
            local old=delayed[1]
            AutoBG_TriggerBattlegroundFinder('Arathi Basin')
            old(); assert(#requested==2)
            AutoBG_CancelAllQueues()
            fire(AutoBGFrame,'UPDATE_BATTLEFIELD_STATUS')
            old(); assert(#requested==2)
        ''')

    def test_disabling_rejoin_before_queue_window_cancels_submission(self):
        self.prepare_rejoin()
        self.runlua('''
            joined=0; function JoinBattlefield() joined=joined+1 end
            AutoBG_Settings.AutoRejoin=false
            fire(AutoBGFrame,'BATTLEFIELDS_SHOW'); assert(joined==0)
            delayed[1]()
            AutoBG_Settings.AutoRejoin=true
            fire(AutoBGFrame,'UPDATE_BATTLEFIELD_STATUS')
            assert(#requested==1)
            AutoBG_TriggerBattlegroundFinder('Arathi Basin')
            fire(AutoBGFrame,'BATTLEFIELDS_SHOW'); assert(joined==1)
        ''')

    def test_cancelled_queue_callbacks_cannot_close_a_later_queue_window(self):
        self.load_core()
        self.runlua('''
            closed=0
            function JoinBattlegroundQueue() end
            function JoinBattlefield() end
            function CloseBattlefield() closed=closed+1 end
            AutoBG_TriggerBattlegroundFinder('Warsong Gulch')
            fire(AutoBGFrame,'BATTLEFIELDS_SHOW')
            assert(closed==1)
            local callbacks={unpack(delayed)}
            AutoBG_CancelAllQueues()
            for _,callback in ipairs(callbacks) do callback() end
            assert(closed==1,'Cancelled work cannot close a new window')
            fire(AutoBGFrame,'BATTLEFIELDS_SHOW'); assert(closed==1)
        ''')

    def test_delayed_leave_cannot_leave_a_different_or_disabled_match(self):
        self.load_core()
        self.runlua('''
            AutoBG_Settings.AutoLeave=true; inBG=true; left=0
            function GetBattlefieldWinner() return 1 end
            function LeaveBattlefield() left=left+1 end
            fire(AutoBGFrame,'PLAYER_ENTERING_WORLD')
            queues[1]={status='active',map='Warsong Gulch'}
            fire(AutoBGFrame,'UPDATE_BATTLEFIELD_STATUS')
            AutoBG_Settings.AutoLeave=false
            delayed[#delayed](); assert(left==0)
            AutoBG_Settings.AutoLeave=true; inBG=false
            fire(AutoBGFrame,'PLAYER_ENTERING_WORLD')
            delayed[1](); assert(left==0)
        ''')

    def test_auto_exit_clears_queued_spells_again_immediately_before_leaving(self):
        self.load_core()
        self.runlua('''
            AutoBG_Settings.AutoLeave=true; inBG=true; queuedCast=45605
            function GetBattlefieldWinner() return 1 end
            function LeaveBattlefield()
                assert(queuedCast==nil, 'Queued spells must not survive auto-exit')
                assert(castStops==2 and terrainStops==2 and targetClears==2)
                left=true
            end
            fire(AutoBGFrame,'PLAYER_ENTERING_WORLD')
            queues[1]={status='active',map='Warsong Gulch'}
            fire(AutoBGFrame,'UPDATE_BATTLEFIELD_STATUS')
            assert(queuedCast==nil and not left)
            assert(afterDelays[#afterDelays]==0.3, 'Keep the deferred exit guard')
            queuedCast=52717
            delayed[#delayed]()
            assert(left)
        ''')

    def test_auto_exit_requires_a_live_player_at_departure(self):
        self.load_core()
        self.runlua('''
            AutoBG_Settings.AutoLeave=true; inBG=true; left=0
            function GetBattlefieldWinner() return 1 end
            function LeaveBattlefield() left=left+1 end
            fire(AutoBGFrame,'PLAYER_ENTERING_WORLD')
            queues[1]={status='active',map='Warsong Gulch'}
            fire(AutoBGFrame,'UPDATE_BATTLEFIELD_STATUS')
            playerExists=false
            delayed[#delayed]()
            assert(left==0, 'Do not call leave against an unloaded player')
        ''')

    def test_stale_match_end_does_not_arm_exit_in_the_outside_world(self):
        self.load_core()
        self.runlua('''
            AutoBG_Settings.AutoLeave=true; inBG=true
            fire(AutoBGFrame,'PLAYER_ENTERING_WORLD')
            inBG=false
            function GetBattlefieldWinner() return 1 end
            hooks.WorldStateScoreFrame_Update()
            assert(#delayed==0 and castStops==nil, 'Ignore stale winner state outside a BG')
        ''')

    def test_leave_hook_preserves_bg_identity_when_native_zone_state_changes_first(self):
        self.load_core()
        self.runlua('''
            AutoBG_Settings.AutoRejoin=true; AutoBG_Settings.AutoLeave=false
            zoneName='Warsong Gulch'; function GetRealZoneText() return zoneName end
            inBG=true; fire(AutoBGFrame,'PLAYER_ENTERING_WORLD')
            function JoinBattlegroundQueue(bg) requested[#requested+1]=bg end
            inBG=false; zoneName='Stormwind City'
            hooks.LeaveBattlefield()
            fire(AutoBGFrame,'PLAYER_ENTERING_WORLD')
            if #requested==0 then delayed[#delayed]() end
            assert(#requested==1 and requested[1]=='Warsong')
            assert(AutoBG_Settings.LastPlayedBG=='Warsong Gulch')
        ''')

    def test_rejoin_waits_for_world_load_and_first_engine_tick(self):
        self.prepare_rejoin(start=False)
        self.runlua('''
            joined=0; function JoinBattlefield() joined=joined+1 end
            fire(AutoBGFrame,'ZONE_CHANGED_NEW_AREA')
            fire(AutoBGFrame,'UPDATE_BATTLEFIELD_STATUS')
            fire(AutoBGFrame,'BATTLEFIELDS_SHOW')
            assert(#requested==0 and joined==0)
            fire(AutoBGFrame,'PLAYER_ENTERING_WORLD')
            fire(AutoBGFrame,'UPDATE_BATTLEFIELD_STATUS')
            assert(#requested==0, 'No queue request inside world-load dispatch')
            table.remove(delayed,1)()
            assert(#requested==1 and now==1, 'First engine tick adds no fixed wait')
        ''')

    def test_rejoin_does_not_query_player_auras_until_player_exists(self):
        self.prepare_rejoin(start=False)
        self.runlua('''
            playerExists=false
            C_UnitAuras.GetAuraDataByIndex=function() error('Player is unloading') end
            fire(AutoBGFrame,'PLAYER_ENTERING_WORLD')
            table.remove(delayed,1)()
            assert(#requested==0)
            assert(timers[#timers].due<=now+0.05)
            playerExists=true
            C_UnitAuras.GetAuraDataByIndex=function() return nil end
            fire(AutoBGFrame,'UPDATE_BATTLEFIELD_STATUS')
            assert(#requested==1 and now==1, 'Ready event bypasses the fallback wait')
        ''')

    def test_rejoin_recovers_stale_active_status_without_another_event(self):
        self.prepare_rejoin(start=False)
        self.runlua('''
            queues[1]={status='active',map='Warsong Gulch'}
            fire(AutoBGFrame,'PLAYER_ENTERING_WORLD')
            table.remove(delayed,1)()
            assert(#requested==0)
            local wait=timers[#timers] and (timers[#timers].due-now) or afterDelays[#afterDelays]
            assert(wait<=0.051, 'Readiness fallback must react within 50ms')
            queues[1]=nil
            delayed[#delayed]()
            assert(#requested==1 and now<=1.051)
        ''')

    def test_rejoin_readiness_wait_is_bounded(self):
        self.prepare_rejoin(start=False)
        self.runlua('''
            playerExists=false
            fire(AutoBGFrame,'PLAYER_ENTERING_WORLD')
            local index=1
            while delayed[index] and index<120 do
                local callback=delayed[index]; index=index+1; callback()
            end
            assert(#requested==0 and index<120, 'Stop the short readiness retry chain')
            playerExists=true
            fire(AutoBGFrame,'UPDATE_BATTLEFIELD_STATUS')
            assert(#requested==0, 'A timed-out transition must not revive')
        ''')

    def test_rejoin_list_must_identify_the_requested_battleground(self):
        self.prepare_rejoin()
        self.runlua('''
            joined=0; function JoinBattlefield() joined=joined+1 end
            battlefieldName='Arathi Basin'
            fire(AutoBGFrame,'BATTLEFIELDS_SHOW'); assert(joined==0)
            function GetBattlefieldInfo() return nil end
            fire(AutoBGFrame,'BATTLEFIELDS_SHOW'); assert(joined==0)
            function GetBattlefieldInfo() return 'Warsong Gulch' end
            fire(AutoBGFrame,'BATTLEFIELDS_SHOW'); assert(joined==1)
        ''')

    def test_rejoin_submits_each_list_once_and_leaves_other_windows_alone(self):
        self.prepare_rejoin()
        self.runlua('''
            joined=0; closed=0
            function JoinBattlefield() joined=joined+1 end
            function CloseBattlefield() closed=closed+1 end
            fire(AutoBGFrame,'BATTLEFIELDS_SHOW')
            fire(AutoBGFrame,'BATTLEFIELDS_SHOW')
            fire(AutoBGFrame,'BATTLEFIELDS_SHOW')
            assert(joined==1, 'Duplicate list replies cannot join twice')
            local before=closed; battlefieldName='Arathi Basin'
            fire(AutoBGFrame,'BATTLEFIELDS_SHOW')
            -- The retry is delayed[1]; the rest are dismissal callbacks.
            for i=2,#delayed do delayed[i]() end
            assert(closed==before, 'An unrelated list must not be dismissed')
        ''')

    def test_rejoin_status_confirmation_cancels_retry_immediately(self):
        self.prepare_rejoin()
        self.runlua('''
            local retry=delayed[1]
            queues[1]={status='queued',map='Warsong Gulch'}
            fire(AutoBGFrame,'UPDATE_BATTLEFIELD_STATUS')
            queues[1]=nil
            retry()
            assert(#requested==1, 'Verified success cannot later become a retry')
        ''')

    def test_rejoin_response_timeout_starts_again_after_list_submission(self):
        self.prepare_rejoin()
        self.runlua('''
            function JoinBattlefield() end
            now=2.4; fire(AutoBGFrame,'BATTLEFIELDS_SHOW')
            delayed[1]()
            assert(#requested==1, 'Allow a full response window after submission')
            delayed[#delayed]()
            assert(#requested==2)
        ''')

    def test_world_departure_blocks_late_rejoin_callbacks_and_list_replies(self):
        self.prepare_rejoin()
        self.runlua('''
            local retry=delayed[1]
            joined=0; function JoinBattlefield() joined=joined+1 end
            fire(AutoBGFrame,'PLAYER_LEAVING_WORLD')
            playerExists=false
            fire(AutoBGFrame,'BATTLEFIELDS_SHOW')
            retry()
            assert(#requested==1 and joined==0)
            playerExists=true
            fire(AutoBGFrame,'PLAYER_ENTERING_WORLD')
            retry(); assert(#requested==1)
            delayed[#delayed]()
            assert(#requested==2)
        ''')

    def test_manual_request_supersedes_rejoin_before_its_first_engine_tick(self):
        self.prepare_rejoin(start=False)
        self.runlua('''
            fire(AutoBGFrame,'PLAYER_ENTERING_WORLD')
            local ready=delayed[1]
            AutoBG_TriggerBattlegroundFinder('Arathi Basin')
            ready()
            assert(#requested==1 and requested[1]=='Arathi')
        ''')

    def test_deserter_arriving_between_list_request_and_reply_aborts_rejoin(self):
        self.prepare_rejoin()
        self.runlua('''
            joined=0; function JoinBattlefield() joined=joined+1 end
            auras={{spellId=26013,name='Deserter'}}
            fire(AutoBGFrame,'BATTLEFIELDS_SHOW')
            assert(joined==0)
            delayed[1]()
            assert(#requested==1)
        ''')

    def test_deserter_uses_identity(self):
        self.load_core()
        self.runlua("""
            UnitDebuff=function() error("Do not infer Deserter from an icon") end
            auras={{name="Unrelated",spellId=1}}
            assert(not AutoBG_HasDeserter())
            auras={{name="Deserter",spellId=26013,expirationTime=31}}
            local found,remaining=AutoBG_HasDeserter()
            assert(found and remaining==30)
        """)

    def test_fc_aura_slots_and_partial_raw_health(self):
        self.runlua("""
            function GetDistance() return nil end
            frame=CreateFrame("Frame")
            frame.healthBar=CreateFrame("Frame")
            frame.hpText=CreateFrame("FontString")
            frame.debuffText=CreateFrame("FontString")
            frame.distText=CreateFrame("FontString")
            function UnitXP(op) if op=="maxhealth" then return 3000 end end
            function GetDistanceColor() return "" end
        """)
        code="local SCAN_UNITS={'target'}\n"+section("AutoBG_FC.lua",
            "local carrierAuraSlots = {}", "-- 6.6 Hz Native Hardware Ticker")
        self.runlua(code+r"""
            auras={{name="Focused Assault",applications=4}}
            ScanCarrier("Enemy",frame,"Horde")
            assert(frame.hpText.text=="100%")
            assert(string.find(frame.debuffText.text,"4"))
            auras={}
            ScanCarrier("Enemy",frame,"Horde")
            assert(frame.debuffText.text=="")
        """)

    def test_all_lua_compiles(self):
        for path in ROOT.glob("*.lua"):
            with self.subTest(path=path.name):
                self.lua.execute("assert(loadstring(...))",path.read_text(encoding="utf-8-sig"))
    def test_defaults_and_migration(self):
        self.load_units()
        self.runlua("""
            assert(AutoBG_Settings.Targets.ButtonFontSize[10]==12)
            assert(AutoBG_Settings.Targets.ButtonHeight[40]==20)
            AutoBG_Settings.Targets={ButtonWidth={[10]=150,[15]=245},
                ButtonFontSize={[10]=10,[15]=14}, ButtonHeight={[10]=20},
                ButtonScale={[10]=1.2},StealthAlert=false}
            AutoBG_Targets:EnsureOptions()
            local o=AutoBG_Settings.Targets
            assert(o.ButtonWidth[10]==210 and o.ButtonWidth[15]==245)
            assert(o.ButtonFontSize[10]==12 and o.ButtonFontSize[15]==14)
            assert(o.ButtonScale[10]==1.2 and o.StealthAlert==false)
            o.ButtonFontSize[10]=10
            AutoBG_Targets:EnsureOptions()
            assert(o.ButtonFontSize[10]==10)
        """)
    def test_independent_positions_migrate_and_reset_one_bracket(self):
        self.load_core()
        self.load_units()
        self.runlua("""
            AutoBG_Settings.Positions={
                AutoBG_TargetsMainFrame={point="CENTER",relPoint="CENTER",x=80,y=90},
                AutoBG_TargetsMainFrame15={point="CENTER",relPoint="CENTER",x=160,y=170}}
            AutoBG_Settings.Targets={IndependentPositioning={[10]=false,[15]=true},
                ShowStealthIcon={[10]=false},ShowStealthText={[10]=false},
                ShowFlagCarrier={[10]=false},ButtonShowHealthBar={[10]=false}}
            AutoBG_Targets:EnsureOptions()
            local p=AutoBG_Settings.Positions
            assert(p.AutoBG_TargetsMainFrame10.x==80)
            assert(p.AutoBG_TargetsMainFrame15.x==160)
            p.AutoBG_TargetsMainFrame10.x=99
            assert(p.AutoBG_TargetsMainFrame40.x==80)
            assert(p.AutoBG_TargetsMainFrame.x==80)
            AutoBG_Targets:ResetPosition(10)
            AutoBG_Targets:EnsureOptions()
            assert(p.AutoBG_TargetsMainFrame10==nil)
            assert(p.AutoBG_TargetsMainFrame15.x==160)
            AutoBG_Targets:EnableConfigMode(10)
            assert(AutoBG_Targets.TargetButton[1].HealthBar:IsShown())
            assert(AutoBG_Targets.TargetButton[3].StealthIcon:IsShown())
        """)

    def test_named_aura_duration_and_unknown_visibility(self):
        self.load_units()
        self.runlua("""
            local yes,name,tex,duration=AutoBG_Targets.CheckIsStealthSpell(999)
            assert(yes and duration==18)
            visible=false
            assert(AutoBG_Targets.CheckUnitStealth("target")==nil)
            visible=true; auras={{spellId=20580,name="Shadowmeld"}}
            local yes,name,tex=AutoBG_Targets.CheckUnitStealth("target")
            assert(yes and name=="Shadowmeld" and string.find(tex,"ShadowMeld"))
            auras={}
            assert(AutoBG_Targets.CheckUnitStealth("target")==false)
        """)
    def test_bg_stealth_sound_icon_and_scoreboard(self):
        self.bg()
        self.runlua("""
            auras={{spellId=20580,name="Shadowmeld"}}
            fire(AutoBG_Targets,"UNIT_AURA","nameplate1")
            assert(#sounds==1)
            local row=AutoBG_Targets.TargetButton[1]
            assert(row.StealthIcon:IsShown() and string.find(row.StealthIcon.texture,"ShadowMeld"))
            fire(AutoBG_Targets,"UNIT_CASTEVENT","0x00000001",nil,"CAST",20580)
            fire(AutoBG_Targets,"UNIT_AURA","nameplate1")
            assert(#sounds==1)
            fire(AutoBG_Targets,"UPDATE_BATTLEFIELD_SCORE")
            assert(AutoBG_Spy.AlertWindow:IsShown())
            visible=false; auras={}
            fire(AutoBG_Targets,"UNIT_AURA","nameplate1")
            assert(row.StealthIcon:IsShown())
            visible=true
            fire(AutoBG_Targets,"UNIT_AURA","nameplate1")
            assert(not row.StealthIcon:IsShown())
            auras={{spellId=1784,name="Stealth"}}
            fire(AutoBG_Targets,"UNIT_AURA","nameplate1")
            assert(#sounds==2)
            fire(AutoBG_Targets,"UNIT_CASTEVENT","0x00000001",nil,"CAST",777)
            assert(row.StealthIcon:IsShown())
        """)
    def test_bg_muted_and_world_spy_disabled(self):
        self.bg()
        self.runlua("""
            AutoBG_Settings.Spy.Enabled=false
            auras={{spellId=1784,name="Stealth"}}
            fire(AutoBG_Targets,"UNIT_AURA","nameplate1")
            assert(#sounds==1)
            fire(AutoBG_Targets,"UNIT_CASTEVENT","0x00000001",nil,"MAINHAND",0)
            AutoBG_Settings.Targets.StealthAlert=false
            fire(AutoBG_Targets,"UNIT_CASTEVENT","0x00000001",nil,"CAST",20580)
            assert(#sounds==1 and AutoBG_Targets.TargetButton[1].StealthIcon:IsShown())
        """)
    def test_world_first_seconds_and_repeat(self):
        self.load_units()
        self.runlua("""
            auras={{spellId=20580,name="Shadowmeld"}}
            fire(AutoBG_SpyEventFrame,"UNIT_AURA","nameplate1")
            assert(#sounds==1 and AutoBG_Spy.AlertWindow:IsShown())
            assert(string.find(AutoBG_Spy.Frame.rows[1].Icon.texture,"ShadowMeld"))
            fire(AutoBG_SpyEventFrame,"UNIT_AURA","nameplate1")
            assert(#sounds==1)
            auras={}; fire(AutoBG_SpyEventFrame,"UNIT_AURA","nameplate1")
            auras={{spellId=5215,name="Prowl"}}
            fire(AutoBG_SpyEventFrame,"UNIT_AURA","nameplate1")
            assert(#sounds==2)
        """)
    def test_partial_spy_settings(self):
        self.load_units()
        self.runlua("""
            AutoBG_Settings.Spy={SoundAlert=false}
            auras={{spellId=1856,name="Vanish"}}
            AutoBG_Spy:RecordEnemy("New","ROGUE",60,"0x00000001",100,true,"Vanish",nil,"nameplate1")
            assert(#sounds==1 and AutoBG_Settings.Spy.Enabled)
            assert(AutoBG_Settings.Spy.SoundAlert==false)
            assert(AutoBG_Settings.Spy.StealthProximityOnly==true)
        """)
    def test_trinket_all_routes_and_duplicate(self):
        for spell in [52317,5579,23276,23277,23273,23274]:
            with self.subTest(spell=spell):
                self.setUp();self.bg()
                self.runlua(f"""
                    fire(AutoBG_Targets,"UNIT_CASTEVENT","0x00000001",nil,"CAST",{spell})
                    assert(AutoBG_Targets.TargetButton[1].Trinket.Text.text=="3:00")
                    now=11
                    fire(AutoBG_Targets,"CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF","Enemy uses Insignia of the Horde.")
                    for _,f in ipairs(tickers) do f() end
                    assert(AutoBG_Targets.TargetButton[1].Trinket.Text.text=="2:50")
                    now=181
                    for _,f in ipairs(tickers) do f() end
                    assert(AutoBG_Targets.TargetButton[1].Trinket.Text.text=="")
                    fire(AutoBG_Targets,"CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS","Enemy gains PvP Trinket.")
                    assert(AutoBG_Targets.TargetButton[1].Trinket.Text.text=="3:00")
                """)

    def test_preview_brackets_and_layout_bounds(self):
        self.load_units()
        self.runlua("""
            for _,size in ipairs({10,15,40}) do
                AutoBG_Targets:EnableConfigMode(size)
                assert(#sounds==0)
                local height=AutoBG_Settings.Targets.ButtonHeight[size]
                local main=AutoBG_Targets.MainFrame
                assert(main.height==20+size*height)
                assert(main.DragHeader.height==20 and main.DragHeader:IsShown())
                local first=AutoBG_Targets.TargetButton[1].point
                assert(first[2]==main and first[3]=="TOPLEFT" and first[5]==-20)
                assert(AutoBG_Targets.TargetButton[size]:IsShown())
            end
        """)

    def test_stealth_aura_transition_then_old_fade(self):
        self.bg()
        self.runlua("""
            fire(AutoBG_Targets,"UNIT_CASTEVENT","0x00000001",nil,"CAST",1856)
            auras={{spellId=1784,name="Stealth"}}
            fire(AutoBG_Targets,"UNIT_AURA","target")
            fire(AutoBG_Targets,"CHAT_MSG_SPELL_AURA_GONE_OTHER","Vanish fades from Enemy.")
            assert(AutoBG_Targets.TargetButton[1].StealthIcon:IsShown())
            assert(#sounds==1)
        """)
    def test_objective_fill_moves_between_ticks_and_settings_apply(self):
        code=section("AutoBG_Timers.lua", 'local FONT ', "-- Respawn Frame")
        code="local activeSortBuffer = {}\n"+code
        code+=section("AutoBG_Timers.lua", "local function TimeBarColor", "local AB_MAX_RESOURCES")
        self.runlua(code+"""
            local f=CreateBarTimerFrame("SmoothObjective","AB",1,1,1,0,0,5,true)
            AutoBG_Settings={ObjectiveWidth=310,ObjectiveHeight=20,
                ObjectiveScale=0.8,ObjectiveOpacity=0.6}
            local row=f.rows[1]
            row.bar.SetValue=function(self,v) self.value=v end
            now=1
            local data={Blacksmith={expire=10.75,faction="Horde"}}
            RenderCountdownBars(f,data,true,true,60,nil,"time")
            assert(row.bar.value==9.75 and row.labelFs.text=="Blacksmith")
            assert(f:GetWidth()==310 and row:GetHeight()==20 and f:GetScale()==0.8)
            assert(f.appearanceOpacity==0.6)
            now=1.25; this=f; f.scripts.OnUpdate()
            assert(row.bar.value==9.5 and row.timeFs.text=="0:09")
            now=10.7
            RenderCountdownBars(f,data,true,true,60,nil,"time")
            assert(row:IsShown() and row.bar.value>0)
            now=10.8; f.scripts.OnUpdate()
            assert(row.bar.value==0)
            RenderCountdownBars(f,data,true,true,60,nil,"time")
            assert(not f:IsShown() and row.fillExpiry==nil)
            AutoBG_Settings.TestAllTimers=true
            RenderCountdownBars(f,{},true,false,60,{{name="Preview",remaining=31}},"time")
            assert(row.bar.value==31 and row.fillExpiry==nil)
        """)

    def test_live_enemy_header_and_timer_rows_drag(self):
        self.bg()
        self.runlua("""
            local f=AutoBG_Targets.MainFrame
            assert(not AutoBG_Targets.isConfig and f.DragHeader:IsShown())
            f.DragHeader.scripts.OnDragStart()
            assert(f.moving)
            f.DragHeader.scripts.OnDragStop()
            assert(not f.moving)
        """)
        code=section("AutoBG_Timers.lua", 'local FONT ', "-- Respawn Frame")
        self.runlua(code+"""
            GameTooltip={Hide=function() end}
            local saved
            AutoBG_SavePosition=function(f,key) saved=key end
            local f=CreateBarTimerFrame("DragObjective","AB",1,1,1,0,0,5,true)
            f.rows[1].scripts.OnDragStart()
            assert(f.moving)
            f.rows[1].scripts.OnDragStop()
            assert(not f.moving and saved=="DragObjective")
        """)

    def test_objective_bars_fill_row_and_center_labels(self):
        code=section("AutoBG_Timers.lua", 'local FONT ', "-- Respawn Frame")
        self.runlua(code+"""
            local f=CreateBarTimerFrame("TestObjective","AB",1,1,1,0,0,2)
            local row=f.rows[1]
            assert(row.bar.points.TOPLEFT[2]==row)
            assert(row.bar.points.TOPLEFT[5]==-1)
            assert(row.bar.points.BOTTOMRIGHT[5]==1)
            assert(row.labelFs.parent==row.bar and row.timeFs.parent==row.bar)
            assert(row.labelFs.points.LEFT[4]==48)
            assert(row.labelFs.points.RIGHT[4]==-48)
            assert(row.labelFs.fontSize==13 and row.labelFs.justify=="CENTER")
            local compact=CreateBarTimerFrame("TestCompact","AV",1,1,1,0,0,8,true)
            assert(compact.rowHeight==22 and compact.headerHeight==19)
            assert(compact.rows[1].compact and compact.rows[8].bar)
            assert(compact.rows[1].labelFs.parent==compact.rows[1].bar)
            assert(compact.rows[1].timeFs.fontSize==12)

        """)

    def test_remote_cast_keeps_icon_but_never_warns(self):
        self.bg()
        self.runlua("""
            fire(AutoBG_Targets,"UNIT_CASTEVENT","0x00000001",nil,"CAST",1784)
            for _,f in ipairs(tickers) do f() end
            assert(#sounds==0)
            assert(AutoBG_Targets.TargetButton[1].StealthIcon:IsShown())
            auras={{spellId=1784,name="Stealth"}}
            fire(AutoBG_Targets,"UNIT_AURA","nameplate1")
            assert(#sounds==1)
        """)

    def test_far_or_occluded_observation_warns_only_on_approach(self):
        self.bg()
        self.runlua("""
            auras={{spellId=20580,name="Shadowmeld"}}
            distanceSquared=400
            fire(AutoBG_Targets,"UNIT_AURA","nameplate1")
            assert(#sounds==0 and AutoBG_Targets.TargetButton[1].StealthIcon:IsShown())
            distanceSquared=100; sight=false
            for _,f in ipairs(tickers) do f() end
            assert(#sounds==0)
            sight=true; rangeKnown=false
            for _,f in ipairs(tickers) do f() end
            assert(#sounds==0)
            rangeKnown=true; visible=false
            for _,f in ipairs(tickers) do f() end
            assert(#sounds==0)
            visible=true
            for _,f in ipairs(tickers) do f() end
            assert(#sounds==1)
            for _,f in ipairs(tickers) do f() end
            assert(#sounds==1)
        """)

    def test_world_remote_cast_then_local_observation(self):
        self.load_units()
        self.runlua("""
            fire(AutoBG_SpyEventFrame,"UNIT_CASTEVENT","0x00000001",nil,"CAST",5215)
            for _,f in ipairs(tickers) do f() end
            assert(#sounds==0 and AutoBG_Spy.Frame.rows[1].targetStealth)
            auras={{spellId=5215,name="Prowl"}}
            distanceSquared=121
            fire(AutoBG_SpyEventFrame,"UNIT_AURA","nameplate1")
            assert(#sounds==0)
            distanceSquared=25
            for _,f in ipairs(tickers) do f() end
            assert(#sounds==1)
        """)

    def test_stacked_stealth_names_update_bg_rows_and_clear_on_fade(self):
        self.bg()
        self.runlua("""
            local found,name,texture=AutoBG_Targets.CheckIsStealthName("Prowl (1)")
            assert(found and name=="Prowl" and string.find(texture,"prowl"))
            fire(AutoBG_Targets,"CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS","Enemy gains Stealth (1).")
            local row=AutoBG_Targets.TargetButton[1]
            assert(row.StealthIcon:IsShown())
            fire(AutoBG_Targets,"CHAT_MSG_SPELL_AURA_GONE_OTHER","Stealth (1) fades from Enemy.")
            assert(not row.StealthIcon:IsShown())
            fire(AutoBG_Targets,"CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF","Enemy casts Prowl (1).")
            assert(row.StealthIcon:IsShown() and string.find(row.StealthIcon.texture,"prowl"))
        """)

    def test_stacked_stealth_names_update_world_row_without_remote_alert(self):
        self.load_units()
        self.runlua("""
            fire(AutoBG_SpyEventFrame,"CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS","Sneaky gains Prowl (1).")
            local row=AutoBG_Spy.Frame.rows[1]
            assert(row.targetStealth and row.targetStealthSpell=="Prowl")
            assert(string.find(row.Icon.texture,"prowl") and #sounds==0)
            fire(AutoBG_SpyEventFrame,"CHAT_MSG_SPELL_AURA_GONE_OTHER","Prowl fades from Sneaky.")
            assert(not row.targetStealth)
            fire(AutoBG_SpyEventFrame,"CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF","Sneaky casts Vanish (1).")
            assert(row.targetStealth and row.targetStealthSpell=="Vanish" and #sounds==0)
        """)

    def test_spy_style_mode_warns_from_received_log_once_per_stealth_episode(self):
        self.load_units()
        self.runlua("""
            AutoBG_Settings.Spy.StealthProximityOnly=false
            fire(AutoBG_SpyEventFrame,"CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS","Sneaky gains Prowl (1).")
            local row=AutoBG_Spy.Frame.rows[1]
            assert(row.targetStealth and row.targetStealthSpell=="Prowl")
            assert(#sounds==1 and AutoBG_Spy.AlertWindow:IsShown())
            assert(AutoBG_Spy.AlertWindow.targetName=="Sneaky")
            assert(string.find(AutoBG_Spy.AlertWindow.Icon.texture,"prowl"))
            fire(AutoBG_SpyEventFrame,"CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF","Sneaky casts Prowl (1).")
            for _,f in ipairs(tickers) do f() end
            assert(#sounds==1)
            fire(AutoBG_SpyEventFrame,"CHAT_MSG_SPELL_AURA_GONE_OTHER","Prowl (1) fades from Sneaky.")
            assert(not row.targetStealth)
            fire(AutoBG_SpyEventFrame,"CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF","Sneaky casts Vanish (1).")
            assert(#sounds==2 and row.targetStealthSpell=="Vanish")
            assert(string.find(AutoBG_Spy.AlertWindow.Title.text,"Vanish"))
        """)

    def test_spy_style_mode_warns_from_cast_without_visible_unit(self):
        self.load_units()
        self.runlua("""
            AutoBG_Settings.Spy.StealthProximityOnly=false
            distanceSquared=900; visible=false; sight=false
            fire(AutoBG_SpyEventFrame,"UNIT_CASTEVENT","0x00000001",nil,"CAST",5215)
            assert(#sounds==1 and AutoBG_Spy.AlertWindow:IsShown())
            assert(AutoBG_Spy.Frame.rows[1].targetStealthSpell=="Prowl")
            fire(AutoBG_SpyEventFrame,"UNIT_CASTEVENT","0x00000001",nil,"CAST",5215)
            assert(#sounds==1)
        """)

    def test_spy_style_mode_does_not_change_bg_proximity_rule(self):
        self.bg()
        self.runlua("""
            AutoBG_Settings.Spy.StealthProximityOnly=false
            fire(AutoBG_Targets,"UNIT_CASTEVENT","0x00000001",nil,"CAST",1784)
            assert(AutoBG_Targets.TargetButton[1].StealthIcon:IsShown())
            assert(#sounds==0)
            auras={{spellId=1784,name="Stealth"}}
            distanceSquared=400
            fire(AutoBG_Targets,"UNIT_AURA","nameplate1")
            assert(#sounds==0)
            distanceSquared=25
            for _,f in ipairs(tickers) do f() end
            assert(#sounds==1)
        """)

    def test_same_faction_duel_can_turn_a_cached_friend_into_hostile(self):
        self.load_units()
        self.runlua("""
            local duel=false
            UnitCanAttack=function() return duel end
            fire(AutoBG_SpyEventFrame,"UNIT_CASTEVENT","0x00000001",nil,"CAST",5215)
            assert(not AutoBG_Spy.Frame.rows[1]:IsShown())
            duel=true
            auras={{spellId=5215,name="Prowl"}}
            fire(AutoBG_SpyEventFrame,"UNIT_CASTEVENT","0x00000001",nil,"CAST",5215)
            assert(AutoBG_Spy.Frame.rows[1].targetStealth)
            fire(AutoBG_SpyEventFrame,"UNIT_AURA","target")
            assert(#sounds==1 and AutoBG_Spy.AlertWindow:IsShown())
        """)

    def test_world_cast_only_alerts_when_exact_loaded_enemy_becomes_detectable(self):
        self.load_units()
        self.runlua("""
            local loaded=false
            local resolvedGUID="0x00000002"
            UnitExists=function(u)
                if u=="target" or u=="focus" or u=="mouseover" or u=="nameplate1" then return false end
                if u=="0x00000001" then return loaded end
                return true
            end
            UnitTokenFromName=function(name,exact)
                assert(name=="Enemy" and exact==true)
                if loaded then return "resolved" end
            end
            UnitGUID=function(u)
                if u=="player" then return "0x00000000" end
                if u=="resolved" then return resolvedGUID end
                return "0x00000001"
            end
            auras={{spellId=5215,name="Prowl"}}
            fire(AutoBG_SpyEventFrame,"UNIT_CASTEVENT","0x00000001",nil,"CAST",5215)
            for _,f in ipairs(tickers) do f() end
            assert(#sounds==0 and AutoBG_Spy.Frame.rows[1].targetStealth)
            now=1.6; loaded=true; distanceSquared=25
            for _,f in ipairs(tickers) do f() end
            assert(#sounds==0) -- A same-name unit with a different GUID cannot trigger it.
            resolvedGUID="0x00000001"; distanceSquared=400
            for _,f in ipairs(tickers) do f() end
            assert(#sounds==0)
            distanceSquared=25; sight=false
            for _,f in ipairs(tickers) do f() end
            assert(#sounds==0)
            sight=true; rangeKnown=false
            for _,f in ipairs(tickers) do f() end
            assert(#sounds==0)
            rangeKnown=true; visible=false
            for _,f in ipairs(tickers) do f() end
            assert(#sounds==0)
            visible=true
            for _,f in ipairs(tickers) do f() end
            assert(#sounds==1 and AutoBG_Spy.AlertWindow:IsShown())
            for _,f in ipairs(tickers) do f() end
            assert(#sounds==1)
        """)

    def test_pending_alert_rechecks_current_aura_and_identity(self):
        self.bg()
        self.runlua("""
            auras={{spellId=1784,name="Stealth"}}
            distanceSquared=400
            fire(AutoBG_Targets,"UNIT_AURA","nameplate1")
            distanceSquared=25; auras={}
            for _,f in ipairs(tickers) do f() end
            assert(#sounds==0)
            auras={{spellId=1784,name="Stealth"}}
            UnitGUID=function() return "0x00000002" end
            for _,f in ipairs(tickers) do f() end
            assert(#sounds==0)
        """)

    def test_cross_realm_target_and_focus_selection(self):
        self.bg()
        self.runlua("""
            AutoBG_Targets.TargetButton[1].targetName = "Enemy-Warsong"
            AutoBG_Targets.TargetButton[1].targetGUID = "0x00000001"
            UnitName = function(u) if u=="target" then return "Enemy" else return "Me" end end
            UnitExists = function(u) return true end
            AutoBG_Targets:RenderRoster()
            local btn = AutoBG_Targets.TargetButton[1]
            assert(btn.Selection:IsShown())
        """)

    def test_cross_realm_fc_scanning_and_targeting(self):
        self.runlua("""
            function GetDistance() return nil end
            frame=CreateFrame("Frame")
            frame.healthBar=CreateFrame("Frame")
            frame.hpText=CreateFrame("FontString")
            frame.debuffText=CreateFrame("FontString")
            frame.distText=CreateFrame("FontString")
            function GetDistanceColor() return "" end
        """)
        code = "local SCAN_UNITS={'target'}\n" + section("AutoBG_FC.lua",
            "local carrierAuraSlots = {}", "-- 6.6 Hz Native Hardware Ticker")
        self.runlua(code + r"""
            UnitName = function(u) return "Carrier" end
            ScanCarrier("Carrier-Warsong", frame, "Horde")
            assert(frame.carrierGuid == "0x00000001")
            assert(frame.hpText.text == "100%")
        """)

    def test_unknown_immunity_does_not_start_trinket(self):
        self.bg()
        self.runlua("""
            fire(AutoBG_Targets,"CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS","Enemy gains Immune Damage.")
            assert(AutoBG_Targets.TargetButton[1].Trinket.Text.text=="")
            fire(AutoBG_Targets,"UNIT_CASTEVENT","0x00000001",nil,"CAST",23506)
            assert(AutoBG_Targets.TargetButton[1].Trinket.Text.text=="")
        """)


    def test_modern_instant_vanish_event_and_duplicate_raw_event(self):
        self.bg()
        self.runlua("""
            fire(AutoBG_Targets,"UNIT_SPELLCAST_SUCCEEDED","nameplate1","Cast-1",1856)
            local b=AutoBG_Targets.TargetButton[1]
            assert(b.StealthIcon:IsShown() and string.find(b.HealthText:GetText(),"VANISH"))
            fire(AutoBG_Targets,"UNIT_CASTEVENT","0x00000001",nil,"CAST",1856)
            assert(#sounds==0)
            auras={{spellId=1856,name="Vanish"}}
            fire(AutoBG_Targets,"UNIT_AURA","nameplate1")
            fire(AutoBG_Targets,"UNIT_SPELLCAST_SUCCEEDED","target","Cast-1",1856)
            assert(#sounds==1)
        """)

    def test_cast_before_aura_update_keeps_indicator_until_settled(self):
        self.bg()
        self.runlua("""
            fire(AutoBG_Targets,"UNIT_CASTEVENT","0x00000001",nil,"CAST",1856)
            auras={}; fire(AutoBG_Targets,"UNIT_AURA","nameplate1")
            assert(AutoBG_Targets.TargetButton[1].StealthIcon:IsShown())
            now=1.6; auras={{spellId=1784,name="Stealth"}}
            for _,f in ipairs(tickers) do f() end
            assert(AutoBG_Targets.TargetButton[1].StealthIcon:IsShown())
            assert(string.find(AutoBG_Targets.TargetButton[1].HealthText:GetText(),"STEALTH"))
            assert(#sounds==0) -- A cast-only recheck does not authorize the popup.
            fire(AutoBG_Targets,"UNIT_AURA","nameplate1")
            assert(#sounds==1)
        """)

    def test_empty_settled_snapshot_clears_but_unloaded_unit_remains_unknown(self):
        self.bg()
        self.runlua("""
            fire(AutoBG_Targets,"UNIT_CASTEVENT","0x00000001",nil,"CAST",1784)
            now=1.6; visible=false; auras={}
            for _,f in ipairs(tickers) do f() end
            assert(AutoBG_Targets.TargetButton[1].StealthIcon:IsShown() and #sounds==0)
            visible=true; fire(AutoBG_Targets,"UNIT_AURA","nameplate1")
            assert(not AutoBG_Targets.TargetButton[1].StealthIcon:IsShown())
        """)

    def test_explicit_fade_and_attack_clear_inside_settling_window(self):
        self.bg()
        self.runlua("""
            fire(AutoBG_Targets,"UNIT_CASTEVENT","0x00000001",nil,"CAST",1784)
            fire(AutoBG_Targets,"CHAT_MSG_SPELL_AURA_GONE_OTHER","Stealth fades from Enemy.")
            assert(not AutoBG_Targets.TargetButton[1].StealthIcon:IsShown())
            fire(AutoBG_Targets,"UNIT_CASTEVENT","0x00000001",nil,"CAST",1856)
            fire(AutoBG_Targets,"UNIT_CASTEVENT","0x00000001",nil,"MAINHAND",0)
            assert(not AutoBG_Targets.TargetButton[1].StealthIcon:IsShown())
        """)

    def test_missing_slot_is_unknown_not_a_negative_aura_snapshot(self):
        self.bg()
        self.runlua("""
            auras={{spellId=1784,name="Stealth"}}
            fire(AutoBG_Targets,"UNIT_AURA","nameplate1")
            C_UnitAuras.GetAuraDataBySlot=function() return nil end
            assert(AutoBG_Targets.CheckUnitStealth("target")==nil)
            fire(AutoBG_Targets,"UNIT_AURA","target")
            assert(AutoBG_Targets.TargetButton[1].StealthIcon:IsShown())
        """)

    def test_spy_legacy_and_event_first_dispatch_preserve_nil_payloads(self):
        self.load_units()
        self.runlua("""
            event="UNIT_CASTEVENT"; arg1="0x00000001"; arg2=nil; arg3="CAST"; arg4=1856
            AutoBG_SpyEventFrame.scripts.OnEvent()
            local b=AutoBG_Spy.Frame.rows[1]
            assert(b.targetStealth and b.targetStealthSpell=="Vanish" and #sounds==0)
            AutoBG_SpyEventFrame.scripts.OnEvent("CHAT_MSG_SPELL_AURA_GONE_OTHER","Vanish fades from Enemy.")
            assert(not b.targetStealth)
        """)

    def test_spy_modern_cast_then_early_aura_and_later_authoritative_update(self):
        self.load_units()
        self.runlua("""
            fire(AutoBG_SpyEventFrame,"UNIT_SPELLCAST_SUCCEEDED","target","Cast-1",1857)
            auras={}; fire(AutoBG_SpyEventFrame,"UNIT_AURA","target")
            assert(AutoBG_Spy.Frame.rows[1].targetStealth and #sounds==0)
            now=1.6; auras={{spellId=1784,name="Stealth"}}
            for _,f in ipairs(tickers) do f() end
            assert(AutoBG_Spy.Frame.rows[1].targetStealth and #sounds==1)
            auras={}; fire(AutoBG_SpyEventFrame,"UNIT_AURA","target")
            assert(not AutoBG_Spy.Frame.rows[1].targetStealth)
        """)

    def test_spy_empty_header_collapses_and_rows_restore_readable_width(self):
        self.load_units()
        self.runlua("""
            AutoBG_Settings.Spy.Scale=1.25; AutoBG_Spy:ApplyScale(); AutoBG_Spy:RenderRows()
            assert(AutoBG_Spy.Frame:GetWidth()==96 and AutoBG_Spy.Frame:GetHeight()==24)
            assert(AutoBG_Spy.Frame:GetScale()==1.25)
            AutoBG_Spy:RecordEnemy("Enemy","ROGUE",60,"0x00000001")
            assert(AutoBG_Spy.Frame:GetWidth()==260 and AutoBG_Spy.Frame.rows[1]:IsShown())
            AutoBG_Spy:ClearHistory(); assert(AutoBG_Spy.Frame:GetWidth()==96)
            AutoBG_Settings.Spy.AutoHide=true; AutoBG_Spy:RenderRows()
            assert(not AutoBG_Spy.Frame:IsShown())
        """)

    def test_row_click_recovers_departed_or_mismatched_guid_and_keeps_valid_guid(self):
        self.bg()
        self.runlua("""
            TargetByName=function(n,exact) selectedName=n; assert(exact) end
            TargetUnit=function(g) selectedGuid=g end
            FocusUnit=function(g) focused=g end
            local b=AutoBG_Targets.TargetButton[1]; b.targetGUID="old"
            UnitExists=function(u) return u~="old" end
            b.scripts.OnClick(b,"LeftButton")
            assert(selectedName=="Enemy" and selectedGuid==nil)
            b.targetGUID="new"; b.scripts.OnClick(b,"LeftButton")
            assert(selectedGuid=="new")
            b.scripts.OnClick(b,"RightButton"); assert(focused=="new")
            selectedGuid=nil; UnitName=function() return "SomeoneElse" end
            b.scripts.OnClick(b,"LeftButton"); assert(selectedGuid==nil)
            AutoBG_Targets.SelectEnemy("Enemy-RealmA","new","LeftButton")
            UnitName=function() return "Enemy-RealmB" end
            AutoBG_Targets.SelectEnemy("Enemy-RealmA","new","LeftButton")
            assert(selectedGuid==nil)
        """)


    def test_new_vanish_supersedes_old_death_and_hidden_health_cannot_erase_it(self):
        self.bg()
        self.runlua("""
            UnitIsDead=function() return true end
            fire(AutoBG_Targets,"UNIT_HEALTH","target")
            assert(string.find(AutoBG_Targets.TargetButton[1].HealthText:GetText(),"DEAD"))
            fire(AutoBG_Targets,"UNIT_SPELLCAST_SUCCEEDED","nameplate1","Cast-1",1856)
            assert(AutoBG_Targets.TargetButton[1].StealthIcon:IsShown())
            assert(string.find(AutoBG_Targets.TargetButton[1].HealthText:GetText(),"VANISH"))
            visible=false; fire(AutoBG_Targets,"UNIT_HEALTH","nameplate1")
            assert(AutoBG_Targets.TargetButton[1].StealthIcon:IsShown())
            visible=true; fire(AutoBG_Targets,"UNIT_HEALTH","nameplate1")
            assert(not AutoBG_Targets.TargetButton[1].StealthIcon:IsShown())
        """)

    def test_spy_normal_class_icons_do_not_depend_on_another_addons_global(self):
        self.load_units()
        self.runlua(r"""
            AutoBG_Settings.Spy.SoundAlert=false
            local seen={}
            for _,class in ipairs({"WARRIOR","MAGE","ROGUE","DRUID","HUNTER","SHAMAN","PRIEST","WARLOCK","PALADIN"}) do
                -- Neither absent nor unrelated addon globals may dictate AutoBG's UVs.
                CLASS_ICON_TCOORDS=nil
                AutoBG_Spy:RecordEnemy(class,class,60,nil,75,false)
                local row=AutoBG_Spy.Frame.rows[1]; local uv=row.Icon.texcoords
                assert(not row.targetStealth and row.TagText:GetText()=="75%")
                assert(row.Icon.texture==[[Interface\Glues\CharacterCreate\UI-CharacterCreate-Classes]])
                assert(uv[2]-uv[1]<.25 and uv[4]-uv[3]<.25)
                local key=table.concat(uv,","); assert(not seen[key]); seen[key]=true
                CLASS_ICON_TCOORDS={[class]={0,1,0,1}}
                AutoBG_Spy:RenderRows()
                assert(table.concat(row.Icon.texcoords,",")==key)
            end
            assert(#sounds==0 and not AutoBG_Spy.AlertWindow:IsShown())
        """)

    def test_spy_reused_rows_restore_class_crop_and_keep_valid_nonrogue_meld(self):
        self.load_units()
        self.runlua(r"""
            AutoBG_Settings.Spy.SoundAlert=false
            AutoBG_Spy:RecordEnemy("Rogue","ROGUE",60,nil,100,true,"Vanish")
            local row=AutoBG_Spy.Frame.rows[1]
            assert(row.targetStealth and string.find(row.Icon.texture,"Ability_Stealth"))
            assert(string.find(row.TagText:GetText(),"VANISH"))
            AutoBG_Spy:RecordEnemy("Warrior","WARRIOR",60,nil,90,false)
            assert(AutoBG_Spy.Frame.rows[1]==row and not row.targetStealth)
            assert(row.Icon.texture==[[Interface\Glues\CharacterCreate\UI-CharacterCreate-Classes]])
            assert(row.Icon.texcoords[2]<.25 and row.TagText:GetText()=="90%")
            -- A new unknown-class entry must not retain either prior icon.
            AutoBG_Spy:RecordEnemy("Unknown",nil,60,nil,100,false)
            assert(not row.Icon:IsShown() and not row.targetStealth)
            AutoBG_Spy:RecordEnemy("Warrior","WARRIOR",60,nil,90,true,"Shadowmeld")
            local warrior=AutoBG_Spy.Frame.rows[2]
            assert(warrior.targetStealth and string.find(warrior.Icon.texture,"ShadowMeld"))
            assert(warrior.Icon.texcoords[1]==.07 and warrior.Icon.texcoords[2]==.93)
            AutoBG_Spy:SetUnitStealthState("Warrior",false)
            assert(not warrior.targetStealth and warrior.Icon.texcoords[2]<.25)
            assert(#sounds==0 and not AutoBG_Spy.AlertWindow:IsShown())
        """)

    def test_party_and_raid_allies_are_never_admitted_to_spy(self):
        self.load_units()
        self.runlua("""
            -- Setup party roster with Kwagga and lotus
            local party = {
                party1 = { name = "lotus", guid = "0x00000010", faction = "Horde" },
                party2 = { name = "Kwagga", guid = "0x00000020", faction = "Horde" },
            }
            GetNumPartyMembers = function() return 2 end
            GetNumRaidMembers = function() return 0 end
            UnitName = function(u)
                if u == "player" then return "Claude" end
                if party[u] then return party[u].name end
                if u == "0x00000010" then return "lotus" end
                if u == "0x00000020" then return "Kwagga" end
                return u
            end
            UnitGUID = function(u)
                if u == "player" then return "0x00000000" end
                if party[u] then return party[u].guid end
                return u
            end
            UnitFactionGroup = function(u)
                if u == "player" then return "Alliance" end
                if party[u] then return party[u].faction end
                if u == "0x00000010" or u == "0x00000020" then return "Horde" end
                return "Alliance"
            end
            UnitCanAttack = function(p, u)
                if u == "party1" or u == "party2" or u == "0x00000010" or u == "0x00000020" then
                    return false
                end
                return true
            end
            UnitIsFriend = function(p, u)
                if u == "party1" or u == "party2" or u == "0x00000010" or u == "0x00000020" then
                    return true
                end
                return false
            end
            UnitInParty = function(u)
                if u == "party1" or u == "party2" or u == "0x00000010" or u == "0x00000020" then
                    return true
                end
                return false
            end

            -- Fire PARTY_MEMBERS_CHANGED to build group roster
            fire(AutoBG_SpyEventFrame, "PARTY_MEMBERS_CHANGED")

            -- 1. Nameplate added for party member (cross-faction) must NOT be admitted
            fire(AutoBG_SpyEventFrame, "NAME_PLATE_UNIT_ADDED", "party1")
            fire(AutoBG_SpyEventFrame, "NAME_PLATE_UNIT_ADDED", "party2")
            assert(not AutoBG_Spy.Frame.rows[1]:IsShown(), "Party member nameplates must not enter Spy")

            -- 2. Spell cast telemetry from party member must NOT be admitted
            fire(AutoBG_SpyEventFrame, "UNIT_CASTEVENT", "0x00000010", nil, "CAST", 1064) -- Chain Heal
            assert(not AutoBG_Spy.Frame.rows[1]:IsShown(), "Party member casts must not enter Spy")

            -- 3. Chat combat log events from party member must NOT be admitted
            fire(AutoBG_SpyEventFrame, "CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF", "lotus casts Healing Wave.")
            assert(not AutoBG_Spy.Frame.rows[1]:IsShown(), "Party member buffs in chat must not enter Spy")

            fire(AutoBG_SpyEventFrame, "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS", "Kwagga hits Infinite Dragonspawn for 100.")
            assert(not AutoBG_Spy.Frame.rows[1]:IsShown(), "Party member hits in chat must not enter Spy")

            -- 4. Target changed to party member must NOT be admitted
            UnitExists = function(u) return u == "target" end
            UnitIsPlayer = function(u) return true end
            local oldUnitName = UnitName
            UnitName = function(u)
                if u == "target" then return "lotus" end
                return oldUnitName(u)
            end
            local oldUnitGUID = UnitGUID
            UnitGUID = function(u)
                if u == "target" then return "0x00000010" end
                return oldUnitGUID(u)
            end
            fire(AutoBG_SpyEventFrame, "PLAYER_TARGET_CHANGED")
            assert(not AutoBG_Spy.Frame.rows[1]:IsShown(), "Targeting party member must not enter Spy")
        """)

    def test_party_join_prunes_active_spy_rows_and_clears_hostility(self):
        self.load_units()
        self.runlua("""
            -- Initially, lotus is an open-world enemy player
            UnitCanAttack = function(p, u) return true end
            UnitFactionGroup = function(u)
                if u == "player" then return "Alliance" end
                return "Horde"
            end
            GetNumPartyMembers = function() return 0 end
            GetNumRaidMembers = function() return 0 end

            AutoBG_Spy:RecordEnemy("lotus", "SHAMAN", 60, "0x00000010", 100, false)
            assert(AutoBG_Spy.Frame.rows[1]:IsShown())
            assert(AutoBG_Spy.Frame.rows[1].NameText:GetText() == "lotus")

            -- lotus now joins player's party
            local party = {
                party1 = { name = "lotus", guid = "0x00000010" },
            }
            GetNumPartyMembers = function() return 1 end
            UnitName = function(u)
                if u == "player" then return "Claude" end
                if party[u] then return party[u].name end
                return u
            end
            UnitGUID = function(u)
                if u == "player" then return "0x00000000" end
                if party[u] then return party[u].guid end
                return u
            end
            UnitCanAttack = function(p, u)
                if u == "party1" or u == "0x00000010" then return false end
                return true
            end
            UnitIsFriend = function(p, u)
                if u == "party1" or u == "0x00000010" then return true end
                return false
            end
            UnitInParty = function(u)
                if u == "party1" or u == "0x00000010" then return true end
                return false
            end

            -- Event fires: party roster changes
            fire(AutoBG_SpyEventFrame, "PARTY_MEMBERS_CHANGED")

            -- Row must be cleared and hidden immediately
            assert(not AutoBG_Spy.Frame.rows[1]:IsShown(), "Spy row must be pruned when enemy joins party")
        """)

class CarrierOwnershipTests(unittest.TestCase):
    # Use the complete module: button handlers and exported commands share ownership.
    def runlua(self, text):
        self.lua.execute(text)

    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCKS)
        self.runlua('''
            names={other="Other", live="Carrier"}; targetUnit="other"; focusUnit="other"
            focusCalls=0; targetCalls=0; printed={}
            local function resolve(u)
                if u=="target" then return targetUnit end
                if u=="focus" then return focusUnit end
                return u
            end
            function UnitExists(u) return names[resolve(u)]~=nil end
            function UnitName(u) return names[resolve(u)] end
            function UnitIsUnit(a,b) return resolve(a)==resolve(b) end
            function UnitTokenFromName() return resolvedUnit end
            function TargetUnit(u)
                targetCalls=targetCalls+1
                if UnitExists(u) then targetUnit=resolve(u) end
            end
            function FocusUnit(u)
                focusCalls=focusCalls+1
                if UnitExists(u) then focusUnit=resolve(u) end
            end
            function TargetByName() if nameMatch then targetUnit=nameMatch end end
            function AutoBG_Print(msg) printed[#printed+1]=msg end
        ''')
        self.lua.execute(source("AutoBG_FC.lua"))
        self.runlua('fire(AutoBG_FCEventFrame,"CHAT_MSG_BG_SYSTEM_HORDE","Alliance flag was picked up by Carrier!")')

    def test_missing_carrier_does_not_focus_previous_target_or_report_success(self):
        self.runlua('''
            assert(not AutoBG_FocusCarrier("enemy"))
            assert(not AutoBG_TargetCarrier("enemy"))
            assert(focusCalls==0 and focusUnit=="other" and #printed==0)
            this=AutoBG_HordeFC; arg1="RightButton"; this.scripts.OnClick()
            assert(focusCalls==0 and focusUnit=="other")
        ''')

    def test_stale_cached_guid_resolves_current_carrier(self):
        self.runlua('''
            AutoBG_HordeFC.carrierGuid="0x0000DEAD"; resolvedUnit="live"
            assert(AutoBG_TargetCarrier("enemy") and targetUnit=="live")
            this=AutoBG_HordeFC; arg1="RightButton"; this.scripts.OnClick()
            assert(focusUnit=="live" and focusCalls==1)
        ''')

    def test_mismatched_cached_identity_uses_verified_name_match(self):
        self.runlua('''
            names["0x0000DEAD"]="Different"; AutoBG_HordeFC.carrierGuid="0x0000DEAD"
            nameMatch="live"
            assert(AutoBG_FocusCarrier("enemy") and focusUnit=="live")
        ''')

    def test_qualified_realm_conflict_is_not_selected(self):
        self.runlua('''
            fire(AutoBG_FCEventFrame,"CHAT_MSG_BG_SYSTEM_HORDE","Alliance flag was picked up by Carrier-First!")
            names.live="Carrier-Second"; resolvedUnit="live"; nameMatch="live"
            assert(not AutoBG_FocusCarrier("enemy") and focusCalls==0)
        ''')

    def test_successful_exact_name_focus_and_target(self):
        self.runlua('''
            nameMatch="live"
            assert(AutoBG_TargetCarrier("enemy") and targetUnit=="live")
            assert(AutoBG_FocusCarrier("enemy") and focusUnit=="live")
            assert(#printed==2)
        ''')

    def test_horde_missing_enemy_does_not_select_friendly_carrier(self):
        self.runlua('''
            function UnitFactionGroup() return "Horde" end
            nameMatch="live"
            assert(AutoBG_GetEnemyCarrier()==nil)
            assert(AutoBG_GetFriendlyCarrier()=="Carrier")
            assert(not AutoBG_TargetCarrier("enemy") and targetCalls==0)
            assert(not AutoBG_FocusCarrier("enemy") and focusCalls==0)
        ''')

    def test_horde_missing_friendly_does_not_select_enemy_carrier(self):
        self.runlua('''
            function UnitFactionGroup() return "Horde" end
            fire(AutoBG_FCEventFrame,"PLAYER_ENTERING_WORLD")
            fire(AutoBG_FCEventFrame,"CHAT_MSG_BG_SYSTEM_ALLIANCE","Horde flag was picked up by Carrier!")
            assert(AutoBG_GetFriendlyCarrier()==nil and AutoBG_GetEnemyCarrier()=="Carrier")
            assert(not AutoBG_TargetCarrier("friendly") and targetCalls==0)
        ''')

    def test_unknown_distance_is_not_zero(self):
        self.lua.execute(section("AutoBG_FC.lua", "local function GetDistance(unit)", "local carrierAuraSlots") + '\nTestDistance=GetDistance')
        self.runlua('''
            distanceSquared=0; rangeKnown=false
            assert(TestDistance("live")==nil)
            rangeKnown=true; assert(TestDistance("live")==0)
            distanceSquared=100; assert(TestDistance("live")==10)
            rangeKnown=false
            function UnitXP() return 12 end
            assert(TestDistance("live")==12)
        ''')


class TimerFeatureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCKS)
        self.lua.execute('''
            chatSent = {}
            SlashCmdList = {}
            function hooksecurefunc() end
            function PlaySound() end
            function SendChatMessage(msg, chatType)
                chatSent[#chatSent+1] = { msg = msg, chatType = chatType }
            end
            function IsControlKeyDown() return ctrlDown == true end
        ''')
        self.lua.execute(source("AutoBG_Timers.lua"))

    def test_game_start_timer_shows_countdown_and_clears_on_begin(self):
        self.lua.execute('''
            inBG = true
            now = 100
            fire(AutoBG_TimersEventFrame, 'PLAYER_ENTERING_WORLD')
            assert(not AutoBG_StartTimerFrame:IsShown())

            -- 1. Pre-match announcement in WSG
            fire(AutoBG_TimersEventFrame, 'CHAT_MSG_BG_SYSTEM_NEUTRAL', 'The Battle for Warsong Gulch begins in 2 minutes.')
            tickers[1]()
            assert(AutoBG_StartTimerFrame:IsShown())
            local row = AutoBG_StartTimerFrame.rows[1]
            assert(row:IsShown())
            assert(row.displayTime == '2:00')
            assert(row.announceText == 'Match Starts: 2:00')

            -- 2. 30 seconds update
            fire(AutoBG_TimersEventFrame, 'CHAT_MSG_BG_SYSTEM_NEUTRAL', 'The battle begins in 30 seconds.')
            tickers[1]()
            assert(AutoBG_StartTimerFrame:IsShown())
            assert(row.displayTime == '0:30')

            -- 3. Match start clears the timer
            fire(AutoBG_TimersEventFrame, 'CHAT_MSG_BG_SYSTEM_NEUTRAL', 'The battle has begun!')
            tickers[1]()
            assert(not AutoBG_StartTimerFrame:IsShown())
        ''')

    def test_ab_projection_ctrl_click_announces_to_chat(self):
        self.lua.execute('''
            inBG = true
            now = 500
            AutoBG_Settings.TestAllTimers = true
            tickers[1]()
            assert(AutoBG_ABProjectionFrame:IsShown())
            assert(AutoBG_ABProjectionFrame.announceText == 'Win in 03:45')

            -- Normal click without Ctrl must not send chat
            ctrlDown = false
            AutoBG_ABProjectionFrame.scripts.OnClick()
            assert(#chatSent == 0)

            -- Ctrl+Click announces projection to BATTLEGROUND channel
            ctrlDown = true
            AutoBG_ABProjectionFrame.scripts.OnClick()
            assert(#chatSent == 1)
            assert(chatSent[1].msg == 'Win in 03:45')
            assert(chatSent[1].chatType == 'BATTLEGROUND')
        ''')

    def test_ab_projection_live_timer_counts_down_every_second(self):
        self.lua.execute('''
            inBG = true
            now = 100
            AutoBG_Settings.TestAllTimers = false
            AutoBG_Settings.ABProjection = true

            local wsScores = {
                [1] = "Bases: 3  400/2000",
                [2] = "Bases: 2  350/2000",
            }
            function GetRealZoneText() return "Arathi Basin" end
            function GetNumWorldStateUI() return 2 end
            function GetWorldStateUIInfo(i) return 1, wsScores[i], nil end

            fire(AutoBG_TimersEventFrame, 'ZONE_CHANGED_NEW_AREA')
            tickers[1]()

            assert(AutoBG_ABProjectionFrame:IsShown())
            assert(string.find(AutoBG_ABProjectionFrame.r1Status:GetText(), "Win 16:00") ~= nil)
            assert(AutoBG_ABProjectionFrame.announceText == 'Win in 16:00')

            -- 1 second elapsed: timer must count down live to 15:59
            now = 101
            tickers[1]()
            assert(string.find(AutoBG_ABProjectionFrame.r1Status:GetText(), "Win 15:59") ~= nil)
            assert(AutoBG_ABProjectionFrame.announceText == 'Win in 15:59')

            -- 2 seconds elapsed: timer must count down live to 15:58
            now = 102
            tickers[1]()
            assert(string.find(AutoBG_ABProjectionFrame.r1Status:GetText(), "Win 15:58") ~= nil)
            assert(AutoBG_ABProjectionFrame.announceText == 'Win in 15:58')

            -- Ctrl+Click announces the live remaining time
            chatSent = {}
            ctrlDown = true
            AutoBG_ABProjectionFrame.scripts.OnClick()
            assert(#chatSent == 1)
            assert(chatSent[1].msg == 'Win in 15:58')

            -- At 6 seconds (now = 106), server score tick arrives (+10 score for 3 bases)
            now = 106
            wsScores[1] = "Bases: 3  410/2000"
            tickers[1]()
            assert(string.find(AutoBG_ABProjectionFrame.r1Status:GetText(), "Win 15:54") ~= nil)
            assert(AutoBG_ABProjectionFrame.announceText == 'Win in 15:54')
        ''')

    def test_projection_base_change_does_not_overwrite_observed_score(self):
        self.lua.execute('''
            inBG=true; now=100; AutoBG_Settings.ABProjection=true
            wsScores={'Bases: 3  400/2000','Bases: 2  350/2000'}
            function GetRealZoneText() return 'Arathi Basin' end
            function GetNumWorldStateUI() return 2 end
            function GetWorldStateUIInfo(i) return 1,wsScores[i],nil end
            fire(AutoBG_TimersEventFrame,'ZONE_CHANGED_NEW_AREA'); tickers[1]()
            now=103; wsScores[1]='Bases: 4  400/2000'; tickers[1]()
            local previous=AutoBG_ABProjectionFrame.announceText
            now=103.1; tickers[1]()
            assert(AutoBG_ABProjectionFrame.announceText==previous,
                'A stable server score must not reset interpolation after a base change')
        ''')

    def test_accept_delay_slider_range_and_clamping(self):
        self.lua.execute(source("AutoBG.lua"))
        self.lua.execute('''
            AutoBG_Settings.AutoAcceptDelay = 119
            fire(AutoBGFrame, 'ADDON_LOADED', 'AutoBG')
            assert(AutoBG_Settings.AutoAcceptDelay == 119)

            AutoBG_Settings.AutoAcceptDelay = 200
            fire(AutoBGFrame, 'ADDON_LOADED', 'AutoBG')
            assert(AutoBG_Settings.AutoAcceptDelay == 119)
        ''')


if __name__=="__main__":
    unittest.main(verbosity=2)
