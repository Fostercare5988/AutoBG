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
CLASSIC_API_VERSION=11514; SUPERWOW_VERSION="2.2"
AutoBG_Settings={}
function GetTime() return now end
function UnitName(u) if u=="player" then return "Me" else return "Enemy" end end
function UnitFactionGroup() return "Alliance" end
function UnitExists() return true end
function UnitIsVisible() return visible~=false end
function UnitDistanceSquared() return distanceSquared or 25, rangeKnown~=false end
function UnitInLineOfSight() return sight~=false and not sightUnknown end
function UnitGUID(u) if u=="player" then return "0x00000000" end return "0x00000001" end
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
 "SetVertexColor","SetAlpha","SetTexCoord","SetAllPoints","ClearAllPoints",
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
            assert(compact.rowHeight==24 and compact.headerHeight==19)
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

if __name__=="__main__":
    unittest.main(verbosity=2)
