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
now=1; sounds={}; alerts={}; tickers={}; delayed={}
CLASSIC_API_VERSION=11515; SUPERWOW_VERSION="2.2"
AutoBG_Settings={}
function GetTime() return now end
function UnitName(u) if u=="player" then return "Me" else return "Enemy" end end
function UnitFactionGroup() return "Alliance" end
function UnitExists() return true end
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
function PlaySoundFile(path) sounds[#sounds+1]=path end
table.wipe=function(t) for k in pairs(t) do t[k]=nil end end
wipe=table.wipe
C_Timer={
 NewTicker=function(t,f) tickers[#tickers+1]=f end,
 After=function(t,f) delayed[#delayed+1]=f end
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
            function hooksecurefunc() end
            function PlaySound() end
            function GetBattlefieldStatus(id)
                local q=queues[id] or {}
                return q.status or "none",q.map
            end
            function AcceptBattlefieldPort(id,accept) accepted[#accepted+1]={id,accept} end
            function GetBattlefieldWinner() return nil end
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
                local expected=value=='5' and 5 or (value==999 and 120 or 0)
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

if __name__=="__main__":
    unittest.main(verbosity=2)
