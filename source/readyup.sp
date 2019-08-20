#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <left4downtown>
#include <l4d2_direct>

#define MAX_FOOTERS 10
#define MAX_FOOTER_LEN 65
#define MAX_SOUNDS 5

#define DEBUG 0

public Plugin:myinfo =
{
	name = "L4D2 Ready-Up",
	author = "CanadaRox",
	description = "New and improved ready-up plugin.",
	version = "8.4",
	url = ""
};

enum L4D2Team
{
	L4D2Team_None = 0,
	L4D2Team_Spectator,
	L4D2Team_Survivor,
	L4D2Team_Infected
}

// Plugin Cvars
new Handle:l4d_ready_disable_spawns;
new Handle:l4d_ready_serv_name;
new Handle:l4d_ready_cfg_name;
new Handle:l4d_ready_survivor_freeze;
new Handle:l4d_ready_max_players;
new Handle:l4d_ready_delay;
new Handle:l4d_ready_enable_sound;
new Handle:l4d_ready_chuckle;
new Handle:l4d_ready_live_sound;
new Handle:l4d_ready_warp_team;
new Handle:sv_infinite_primary_ammo;

// Game Cvars
new Handle:director_no_specials;
new Handle:god;
new Handle:sb_stop;
new Handle:survivor_limit;
new Handle:z_max_player_zombies;

new Handle:casterTrie;
new Handle:liveForward;
new Panel:menuPanel;
new Handle:readyCountdownTimer;
new String:readyFooter[MAX_FOOTERS][MAX_FOOTER_LEN];
new bool:hiddenPanel[MAXPLAYERS + 1];
new bool:inLiveCountdown = false;
new bool:inReadyUp;
new bool:isPlayerReady[MAXPLAYERS + 1];
new footerCounter = 0;
new readyDelay;
new bool:blockSecretSpam[MAXPLAYERS + 1];
new String:liveSound[256];
new Float:liveTime;

new Handle:allowedCastersTrie;

new bool:isMixing = false;

new String:countdownSound[MAX_SOUNDS][]=
{
	"/npc/moustachio/strengthattract01.wav",
	"/npc/moustachio/strengthattract02.wav",
	"/npc/moustachio/strengthattract05.wav",
	"/npc/moustachio/strengthattract06.wav",
	"/npc/moustachio/strengthattract09.wav"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("AddStringToReadyFooter", Native_AddStringToReadyFooter);
	CreateNative("IsInReady", Native_IsInReady);
	CreateNative("IsClientCaster", Native_IsClientCaster);
	CreateNative("IsIDCaster", Native_IsIDCaster);
	liveForward = CreateGlobalForward("OnRoundIsLive", ET_Event);
	RegPluginLibrary("readyup");
	return APLRes_Success;
}

public OnPluginStart()
{
	CreateConVar("l4d_ready_enabled", "1", "This cvar doesn't do anything, but if it is 0 the logger wont log this game.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	l4d_ready_cfg_name = CreateConVar("l4d_ready_cfg_name", "", "Configname to display on the ready-up panel", FCVAR_PLUGIN|FCVAR_PRINTABLEONLY);
    l4d_ready_serv_name = FindConVar("sn_main_name");
    if (!l4d_ready_serv_name) {
        l4d_ready_serv_name = FindConVar("hostname");
    }
    sv_infinite_primary_ammo = FindConVar("sv_infinite_primary_ammo");
	l4d_ready_disable_spawns = CreateConVar("l4d_ready_disable_spawns", "0", "Prevent SI from having spawns during ready-up", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	l4d_ready_survivor_freeze = CreateConVar("l4d_ready_survivor_freeze", "1", "Freeze the survivors during ready-up.  When unfrozen they are unable to leave the saferoom but can move freely inside", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	l4d_ready_max_players = CreateConVar("l4d_ready_max_players", "12", "Maximum number of players to show on the ready-up panel.", FCVAR_PLUGIN, true, 0.0, true, MAXPLAYERS+1.0);
	l4d_ready_delay = CreateConVar("l4d_ready_delay", "5", "Number of seconds to count down before the round goes live.", FCVAR_PLUGIN, true, 0.0);
	l4d_ready_enable_sound = CreateConVar("l4d_ready_enable_sound", "1", "Enable sound during countdown & on live");
	l4d_ready_live_sound = CreateConVar("l4d_ready_live_sound", "buttons/blip2.wav", "The sound that plays when a round goes live");
	l4d_ready_chuckle = CreateConVar("l4d_ready_chuckle", "0", "Enable random moustachio chuckle during countdown");
	l4d_ready_warp_team = CreateConVar("l4d_ready_warp_team", "1", "Should we warp the entire team when a player attempts to leave saferoom?");
	HookConVarChange(l4d_ready_survivor_freeze, SurvFreezeChange);

	HookEvent("round_start", RoundStart_Event);
	HookEvent("player_team", PlayerTeam_Event);

	casterTrie = CreateTrie();
	allowedCastersTrie = CreateTrie();

	director_no_specials = FindConVar("director_no_specials");
	god = FindConVar("god");
	sb_stop = FindConVar("sb_stop");
	survivor_limit = FindConVar("survivor_limit");
	z_max_player_zombies = FindConVar("z_max_player_zombies");

	RegAdminCmd("sm_caster", Caster_Cmd, ADMFLAG_BAN, "Registers a player as a caster so the round will not go live unless they are ready");
	RegAdminCmd("sm_forcestart", ForceStart_Cmd, ADMFLAG_BAN, "Forces the round to start regardless of player ready status.  Players can unready to stop a force");
	RegAdminCmd("sm_fs", ForceStart_Cmd, ADMFLAG_BAN, "Forces the round to start regardless of player ready status.  Players can unready to stop a force");
	RegConsoleCmd("\x73\x6d\x5f\x62\x6f\x6e\x65\x73\x61\x77", Secret_Cmd, "Every player has a different secret number between 0-1023");
	RegConsoleCmd("sm_hide", Hide_Cmd, "Hides the ready-up panel so other menus can be seen");
	RegConsoleCmd("sm_show", Show_Cmd, "Shows a hidden ready-up panel");
	RegConsoleCmd("sm_notcasting", NotCasting_Cmd, "Deregister yourself as a caster or allow admins to deregister other players");
	RegConsoleCmd("sm_ready", Ready_Cmd, "Mark yourself as ready for the round to go live");
	RegConsoleCmd("sm_toggleready", ToggleReady_Cmd, "Toggle your ready status");
	RegConsoleCmd("sm_unready", Unready_Cmd, "Mark yourself as not ready if you have set yourself as ready");
	RegConsoleCmd("sm_return", Return_Cmd, "Return to a valid saferoom spawn if you get stuck during an unfrozen ready-up period");
    	RegConsoleCmd("sm_cast", Cast_Cmd, "Registers the calling player as a caster so the round will not go live unless they are ready");
	RegServerCmd("sm_resetcasters", ResetCaster_Cmd, "Used to reset casters between matches.  This should be in confogl_off.cfg or equivalent for your system");
	RegServerCmd("sm_add_caster_id", AddCasterSteamID_Cmd, "Used for adding casters to the whitelist -- i.e. who's allowed to self-register as a caster");

#if DEBUG
	RegAdminCmd("sm_initready", InitReady_Cmd, ADMFLAG_ROOT);
	RegAdminCmd("sm_initlive", InitLive_Cmd, ADMFLAG_ROOT);
#endif

	LoadTranslations("common.phrases");
}

public OnPluginEnd()
{
	if (inReadyUp)
		InitiateLive(false);
}

public OnMapStart()
{
	/* OnMapEnd needs this to work */
	GetConVarString(l4d_ready_live_sound, liveSound, sizeof(liveSound));
	PrecacheSound("/level/gnomeftw.wav");
	PrecacheSound("/weapons/defibrillator/defibrillator_use.wav");
	PrecacheSound("/commentary/com-welcome.wav");
	PrecacheSound("buttons/blip1.wav");
	PrecacheSound("/common/bugreporter_failed.wav");
	PrecacheSound("/level/loud/climber.wav");
	PrecacheSound("/player/survivor/voice/mechanic/ellisinterrupt07.wav");
	PrecacheSound("/npc/pilot/radiofinale08.wav");
	PrecacheSound(liveSound);
	for (new i = 0; i < MAX_SOUNDS; i++)
	{
		PrecacheSound(countdownSound[i]);
	}
	for (new client = 1; client <= MAXPLAYERS; client++)
	{
		blockSecretSpam[client] = false;
	}
	readyCountdownTimer = INVALID_HANDLE;
}

public OnMixStarted()
{
    isMixing = true;
}

public OnMixStopped()
{
    isMixing = false;
}

/* This ensures all cvars are reset if the map is changed during ready-up */
public OnMapEnd()
{
	if (inReadyUp)
		InitiateLive(false);
}

public OnClientDisconnect(client)
{
	hiddenPanel[client] = false;
	isPlayerReady[client] = false;
}

public Native_AddStringToReadyFooter(Handle:plugin, numParams)
{
	decl String:footer[MAX_FOOTER_LEN];
	GetNativeString(1, footer, sizeof(footer));
	if (footerCounter < MAX_FOOTERS)
	{
		if (strlen(footer) < MAX_FOOTER_LEN)
		{
			strcopy(readyFooter[footerCounter], MAX_FOOTER_LEN, footer);
			footerCounter++;
			return _:true;
		}
	}
	return _:false;
}

public Native_IsInReady(Handle:plugin, numParams)
{
	return _:inReadyUp;
}

public Native_IsClientCaster(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	return _:IsClientCaster(client);
}

public Native_IsIDCaster(Handle:plugin, numParams)
{
	decl String:buffer[64];
	GetNativeString(1, buffer, sizeof(buffer));
	return _:IsIDCaster(buffer);
}

stock bool:IsClientCaster(client)
{
	decl String:buffer[64];
	return GetClientAuthString(client, buffer, sizeof(buffer)) && IsIDCaster(buffer);
}

stock bool:IsIDCaster(const String:AuthID[])
{
	decl dummy;
	return GetTrieValue(casterTrie, AuthID, dummy);
}

public Action:Cast_Cmd(client, args)
{	
    	decl String:buffer[64];
	GetClientAuthString(client, buffer, sizeof(buffer));
	new index = FindStringInArray(allowedCastersTrie, buffer);
	if (index != -1)
	{
		SetTrieValue(casterTrie, buffer, 1);
		ReplyToCommand(client, "You have registered yourself as a caster");
	}
	else
	{
		ReplyToCommand(client, "Your SteamID was not found in this server's caster whitelist. Contact the admins to get approved.");
	}
	return Plugin_Handled;
}

public Action:Caster_Cmd(client, args)
{	
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_caster <player>");
		return Plugin_Handled;
	}
	
    	decl String:buffer[64];
	GetCmdArg(1, buffer, sizeof(buffer));
	
	new target = FindTarget(client, buffer, true, false);
	if (target > 0) // If FindTarget fails we don't need to print anything as it prints it for us!
	{
		if (GetClientAuthString(target, buffer, sizeof(buffer)))
		{
			SetTrieValue(casterTrie, buffer, 1);
			ReplyToCommand(client, "Registered %N as a caster", target);
		}
		else
		{
		    	ReplyToCommand(client, "Couldn't find Steam ID.  Check for typos and let the player get fully connected.");
		}
	}
	return Plugin_Handled;
}

public Action:ResetCaster_Cmd(args)
{
	ClearTrie(casterTrie);
	return Plugin_Handled;
}

public Action:AddCasterSteamID_Cmd(args)
{
	decl String:buffer[128];
	GetCmdArg(1, buffer, sizeof(buffer));
	if (buffer[0] != EOS) 
	{
		new index = FindStringInArray(allowedCastersTrie, buffer);
		if (index == -1)
		{
			PushArrayString(allowedCastersTrie, buffer);
			PrintToServer("[casters_database] Added '%s'", buffer);
		}
		else PrintToServer("[casters_database] '%s' already exists", buffer);
	}
	else PrintToServer("[casters_database] No args specified / empty buffer");
	return Plugin_Handled;
}

public Action:Hide_Cmd(client, args)
{
	hiddenPanel[client] = true;
	return Plugin_Handled;
}

public Action:Show_Cmd(client, args)
{
	hiddenPanel[client] = false;
	return Plugin_Handled;
}

public Action:NotCasting_Cmd(client, args)
{
	decl String:buffer[64];
	
	if (args < 1) // If no target is specified
	{
		GetClientAuthString(client, buffer, sizeof(buffer));
		RemoveFromTrie(casterTrie, buffer);
		return Plugin_Handled;
	}
	else // If a target is specified
	{
		new AdminId:id;
		id = GetUserAdmin(client);
		new bool:hasFlag = false;
		
		if (id != INVALID_ADMIN_ID)
		{
			hasFlag = GetAdminFlag(id, Admin_Ban); // Check for specific admin flag
		}
		
		if (!hasFlag)
		{
			ReplyToCommand(client, "Only admins can remove other casters. Use sm_notcasting without arguments if you wish to remove yourself.");
			return Plugin_Handled;
		}
		
		GetCmdArg(1, buffer, sizeof(buffer));
		
		new target = FindTarget(client, buffer, true, false);
		if (target > 0) // If FindTarget fails we don't need to print anything as it prints it for us!
		{
			if (GetClientAuthString(target, buffer, sizeof(buffer)))
			{
				RemoveFromTrie(casterTrie, buffer);
				ReplyToCommand(client, "%N is no longer a caster", target);
			}
			else
			{
				ReplyToCommand(client, "Couldn't find Steam ID.  Check for typos and let the player get fully connected.");
			}
		}
		return Plugin_Handled;
	}
}

public Action:ForceStart_Cmd(client, args)
{
	if (inReadyUp)
	{
		InitiateLiveCountdown();
	}
	return Plugin_Handled;
}

public Action:Secret_Cmd(client, args)
{
	if (inReadyUp)
	{
		decl String:steamid[64];
		decl String:argbuf[30];
		GetCmdArg(1, argbuf, sizeof(argbuf));
		new arg = StringToInt(argbuf);
		GetClientAuthString(client, steamid, sizeof(steamid));
		new id = StringToInt(steamid[10]);

		if ((id & 1023) ^ arg == 'C'+'a'+'n'+'a'+'d'+'a'+'R'+'o'+'x')
		{
			DoSecrets(client);
			isPlayerReady[client] = true;
			if (CheckFullReady())
				InitiateLiveCountdown();

			return Plugin_Handled;
		}
		
	}
	return Plugin_Continue;
}

public Action:Ready_Cmd(client, args)
{
	if (inReadyUp)
	{
		isPlayerReady[client] = true;
		if (CheckFullReady())
			InitiateLiveCountdown();
	}

	return Plugin_Handled;
}

public Action:Unready_Cmd(client, args)
{
	if (inReadyUp)
	{
		isPlayerReady[client] = false;
		CancelFullReady();
	}

	return Plugin_Handled;
}

public Action:ToggleReady_Cmd(client, args)
{
	if (inReadyUp)
	{
		isPlayerReady[client] = !isPlayerReady[client];
		if (isPlayerReady[client] && CheckFullReady())
		{
			InitiateLiveCountdown();
		}
		else
		{
			CancelFullReady();
		}
	}

	return Plugin_Handled;
}

/* No need to do any other checks since it seems like this is required no matter what since the intros unfreezes players after the animation completes */
public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	if (inReadyUp)
	{
		if (IsClientInGame(client) && L4D2Team:GetClientTeam(client) == L4D2Team_Survivor)
		{
			if (GetConVarBool(l4d_ready_survivor_freeze))
			{
				if (!(GetEntityMoveType(client) == MOVETYPE_NONE || GetEntityMoveType(client) == MOVETYPE_NOCLIP))
				{
					SetClientFrozen(client, true);
				}
			}
			else
			{
				if (GetEntityFlags(client) & FL_INWATER)
				{
					ReturnPlayerToSaferoom(client, false);
				}
			}
		}
	}
}

public SurvFreezeChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
	ReturnTeamToSaferoom(L4D2Team_Survivor);
	SetTeamFrozen(L4D2Team_Survivor, GetConVarBool(convar));
	
}

public Action:L4D_OnFirstSurvivorLeftSafeArea(client)
{
	if (inReadyUp)
	{
		if(GetConVarBool(l4d_ready_warp_team))
		{
			ReturnTeamToSaferoom(L4D2Team_Survivor);
		}
		else
		{
			ReturnToSaferoom(client);
		}
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action:Return_Cmd(client, args)
{
	if (client > 0
			&& inReadyUp
			&& L4D2Team:GetClientTeam(client) == L4D2Team_Survivor)
	{
		ReturnPlayerToSaferoom(client, false);
	}
	return Plugin_Handled;
}

public RoundStart_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	InitiateReadyUp();
}

public PlayerTeam_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	new L4D2Team:oldteam = L4D2Team:GetEventInt(event, "oldteam");
	new L4D2Team:team = L4D2Team:GetEventInt(event, "team");
	if (oldteam == L4D2Team_Survivor || oldteam == L4D2Team_Infected ||
			team == L4D2Team_Survivor || team == L4D2Team_Infected)
	{
		CancelFullReady();
	}
}

#if DEBUG
public Action:InitReady_Cmd(client, args)
{
	InitiateReadyUp();
	return Plugin_Handled;
}

public Action:InitLive_Cmd(client, args)
{
	InitiateLive();
	return Plugin_Handled;
}
#endif

public DummyHandler(Handle:menu, MenuAction:action, param1, param2) { }

public Action:MenuRefresh_Timer(Handle:timer)
{
	if (inReadyUp)
	{
		UpdatePanel();
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

UpdatePanel()
{
    if (isMixing) return;

	if (menuPanel != INVALID_HANDLE)
	{
		CloseHandle(menuPanel);
		menuPanel = INVALID_HANDLE;
	}

	new String:readyBuffer[800] = "";
	new String:unreadyBuffer[800] = "";
	new String:specBuffer[800] = "";
	new readyCount = 0;
	new unreadyCount = 0;
	new playerCount = 0;
	new specCount = 0;

	menuPanel = CreatePanel();

	decl String:nameBuf[MAX_NAME_LENGTH*2];
	decl String:authBuffer[64];
	decl bool:caster;
	decl dummy;
	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && !IsFakeClient(client))
		{
			++playerCount;
			GetClientName(client, nameBuf, sizeof(nameBuf));
			GetClientAuthString(client, authBuffer, sizeof(authBuffer));
			caster = GetTrieValue(casterTrie, authBuffer, dummy);
			if (IsPlayer(client) || caster)
			{
				if (isPlayerReady[client])
				{
					if (!inLiveCountdown) PrintHintText(client, "You are ready.\nSay !unready to unready.");
					Format(nameBuf, sizeof(nameBuf), "->%d. %s%s\n", ++readyCount, nameBuf, caster ? " [Caster]" : "");
					StrCat(readyBuffer, sizeof(readyBuffer), nameBuf);
				}
				else
				{
					if (!inLiveCountdown) PrintHintText(client, "You are not ready.\nSay !ready to ready up.");
					Format(nameBuf, sizeof(nameBuf), "->%d. %s%s\n", ++unreadyCount, nameBuf, caster ? " [Caster]" : "");
					StrCat(unreadyBuffer, sizeof(unreadyBuffer), nameBuf);
				}
			}
			else
			{
				++specCount;
				if (playerCount <= GetConVarInt(l4d_ready_max_players))
				{
					Format(nameBuf, sizeof(nameBuf), "->%d. %s\n", specCount, nameBuf);
					StrCat(specBuffer, sizeof(specBuffer), nameBuf);
				}
			}
		}
	}


	new bufLen = strlen(readyBuffer);
	if (bufLen != 0)
	{
		readyBuffer[bufLen] = '\0';
		ReplaceString(readyBuffer, sizeof(readyBuffer), "#buy", "<- TROLL");
		ReplaceString(readyBuffer, sizeof(readyBuffer), "#", "_");
		DrawPanelText(menuPanel, "Ready");
		DrawPanelText(menuPanel, readyBuffer);
	}

	bufLen = strlen(unreadyBuffer);
	if (bufLen != 0)
	{
		unreadyBuffer[bufLen] = '\0';
		ReplaceString(unreadyBuffer, sizeof(readyBuffer), "#buy", "<- TROLL");
		ReplaceString(unreadyBuffer, sizeof(unreadyBuffer), "#", "_");
		DrawPanelText(menuPanel, "Unready");
		DrawPanelText(menuPanel, unreadyBuffer);
	}

	bufLen = strlen(specBuffer);
	if (bufLen != 0)
	{
		specBuffer[bufLen] = '\0';
		DrawPanelText(menuPanel, "Spectator");
		ReplaceString(specBuffer, sizeof(specBuffer), "#", "_");
		if (playerCount > GetConVarInt(l4d_ready_max_players))
			FormatEx(specBuffer, sizeof(specBuffer), "->1. Many (%d)", specCount);
		DrawPanelText(menuPanel, specBuffer);
	}

	decl String:sHostName[128];
	GetConVarString(l4d_ready_serv_name, sHostName, sizeof(sHostName));
    Format(sHostName, sizeof(sHostName), "> %s", sHostName);
    menuPanel.DrawText(sHostName);

	decl String:cfgBuf[128];
	GetConVarString(l4d_ready_cfg_name, cfgBuf, sizeof(cfgBuf));
    Format(cfgBuf, sizeof(cfgBuf), "> %s", cfgBuf);
    menuPanel.DrawText(cfgBuf);

	decl String:timeBuf[128];
    Format(timeBuf, sizeof(timeBuf), "> %02d:%02d", RoundToFloor((GetGameTime() - liveTime) / 60), RoundToFloor(GetGameTime() - liveTime) % 60);
    menuPanel.DrawText(timeBuf);


	for (new i = 0; i < MAX_FOOTERS; i++)
	{
		DrawPanelText(menuPanel, readyFooter[i]);
	}

	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && !IsFakeClient(client) && !hiddenPanel[client])
		{
			SendPanelToClient(menuPanel, client, DummyHandler, 1);
		}
	}
}

InitiateReadyUp()
{
    liveTime = GetGameTime();

	for (new i = 0; i <= MAXPLAYERS; i++)
	{
		isPlayerReady[i] = false;
	}

	UpdatePanel();
	CreateTimer(1.0, MenuRefresh_Timer, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

	inReadyUp = true;
	inLiveCountdown = false;
	readyCountdownTimer = INVALID_HANDLE;

	if (GetConVarBool(l4d_ready_disable_spawns))
	{
		SetConVarBool(director_no_specials, true);
	}

	DisableEntities();
	SetConVarFlags(god, GetConVarFlags(god) & ~FCVAR_NOTIFY);
	SetConVarBool(god, true);
	SetConVarFlags(god, GetConVarFlags(god) | FCVAR_NOTIFY);
    SetConVarFlags(sv_infinite_primary_ammo, GetConVarFlags(sv_infinite_primary_ammo) & ~FCVAR_NOTIFY);       
    SetConVarBool(sv_infinite_primary_ammo, true, false, false);                
    SetConVarFlags(sv_infinite_primary_ammo, GetConVarFlags(sv_infinite_primary_ammo) | FCVAR_NOTIFY);
	SetConVarBool(sb_stop, true);

	L4D2_CTimerStart(L4D2CT_VersusStartTimer, 99999.9);
}

InitiateLive(bool:real = true)
{
	inReadyUp = false;
	inLiveCountdown = false;

	SetTeamFrozen(L4D2Team_Survivor, false);

	EnableEntities();
    SetConVarFlags(sv_infinite_primary_ammo, GetConVarFlags(sv_infinite_primary_ammo) & ~FCVAR_NOTIFY);       
    SetConVarBool(sv_infinite_primary_ammo, false, false, false);                
    SetConVarFlags(sv_infinite_primary_ammo, GetConVarFlags(sv_infinite_primary_ammo) | FCVAR_NOTIFY);
	SetConVarBool(director_no_specials, false);
	SetConVarFlags(god, GetConVarFlags(god) & ~FCVAR_NOTIFY);
	SetConVarBool(god, false);
	SetConVarFlags(god, GetConVarFlags(god) | FCVAR_NOTIFY);
	SetConVarBool(sb_stop, false);

	L4D2_CTimerStart(L4D2CT_VersusStartTimer, 60.0);

	for (new i = 0; i < 4; i++)
	{
		GameRules_SetProp("m_iVersusDistancePerSurvivor", 0, _,
				i + 4 * GameRules_GetProp("m_bAreTeamsFlipped"));
	}

	for (new i = 0; i < MAX_FOOTERS; i++)
	{
		readyFooter[i] = "";
	}

	footerCounter = 0;
	if (real)
	{
		Call_StartForward(liveForward);
		Call_Finish();
	}
}

ReturnPlayerToSaferoom(client, bool:flagsSet = true)
{
	new warp_flags;
	new give_flags;
	if (!flagsSet)
	{
		warp_flags = GetCommandFlags("warp_to_start_area");
		SetCommandFlags("warp_to_start_area", warp_flags & ~FCVAR_CHEAT);
		give_flags = GetCommandFlags("give");
		SetCommandFlags("give", give_flags & ~FCVAR_CHEAT);
	}

	if (GetEntProp(client, Prop_Send, "m_isHangingFromLedge"))
	{
		FakeClientCommand(client, "give health");
	}

	FakeClientCommand(client, "warp_to_start_area");

	if (!flagsSet)
	{
		SetCommandFlags("warp_to_start_area", warp_flags);
		SetCommandFlags("give", give_flags);
	}
}

ReturnTeamToSaferoom(L4D2Team:team)
{
	new warp_flags = GetCommandFlags("warp_to_start_area");
	SetCommandFlags("warp_to_start_area", warp_flags & ~FCVAR_CHEAT);
	new give_flags = GetCommandFlags("give");
	SetCommandFlags("give", give_flags & ~FCVAR_CHEAT);

	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && L4D2Team:GetClientTeam(client) == team)
		{
			ReturnPlayerToSaferoom(client, true);
		}
	}

	SetCommandFlags("warp_to_start_area", warp_flags);
	SetCommandFlags("give", give_flags);
}

ReturnToSaferoom(client)
{
	new warp_flags = GetCommandFlags("warp_to_start_area");
	SetCommandFlags("warp_to_start_area", warp_flags & ~FCVAR_CHEAT);
	new give_flags = GetCommandFlags("give");
	SetCommandFlags("give", give_flags & ~FCVAR_CHEAT);

	if (IsClientInGame(client) && L4D2Team:GetClientTeam(client) == L4D2Team_Survivor)
	{
		ReturnPlayerToSaferoom(client, true);
	}

	SetCommandFlags("warp_to_start_area", warp_flags);
	SetCommandFlags("give", give_flags);
}


SetTeamFrozen(L4D2Team:team, bool:freezeStatus)
{
	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && L4D2Team:GetClientTeam(client) == team)
		{
			SetClientFrozen(client, freezeStatus);
		}
	}
}

bool:CheckFullReady()
{
	new readyCount = 0;
	new casterCount = 0;
	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			if (IsClientCaster(client))
			{
				casterCount++;
			}

			if ((IsPlayer(client) || IsClientCaster(client)) && isPlayerReady[client])
			{
				readyCount++;
			}
		}
	}
	return readyCount >= GetConVarInt(survivor_limit) + GetConVarInt(z_max_player_zombies) + casterCount;
}

InitiateLiveCountdown()
{
	if (readyCountdownTimer == INVALID_HANDLE)
	{
		ReturnTeamToSaferoom(L4D2Team_Survivor);
		SetTeamFrozen(L4D2Team_Survivor, true);
		PrintHintTextToAll("Going live!\nSay !unready to cancel");
		inLiveCountdown = true;
		readyDelay = GetConVarInt(l4d_ready_delay);
		readyCountdownTimer = CreateTimer(1.0, ReadyCountdownDelay_Timer, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action:ReadyCountdownDelay_Timer(Handle:timer)
{
	if (readyDelay == 0)
	{
		PrintHintTextToAll("Round is live!");
		InitiateLive();
		readyCountdownTimer = INVALID_HANDLE;
		if (GetConVarBool(l4d_ready_enable_sound))
		{
			if (GetConVarBool(l4d_ready_chuckle))
			{
				EmitSoundToAll(countdownSound[GetRandomInt(0,MAX_SOUNDS-1)]);
			}
			else { EmitSoundToAll(liveSound, _, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.5); }
		}
		return Plugin_Stop;
	}
	else
	{
		PrintHintTextToAll("Live in: %d\nSay !unready to cancel", readyDelay);
		if (GetConVarBool(l4d_ready_enable_sound))
		{
			EmitSoundToAll("buttons/blip1.wav", _, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.5);
		}
		readyDelay--;
	}
	return Plugin_Continue;
}

CancelFullReady()
{
	if (readyCountdownTimer != INVALID_HANDLE)
	{
		SetTeamFrozen(L4D2Team_Survivor, GetConVarBool(l4d_ready_survivor_freeze));
		inLiveCountdown = false;
		CloseHandle(readyCountdownTimer);
		readyCountdownTimer = INVALID_HANDLE;
		PrintHintTextToAll("Countdown Cancelled!");
\
	}
}

stock SetClientFrozen(client, freeze)
{
	SetEntityMoveType(client, freeze ? MOVETYPE_NONE : MOVETYPE_WALK);
}

stock IsPlayer(client)
{
	new L4D2Team:team = L4D2Team:GetClientTeam(client);
	return (team == L4D2Team_Survivor || team == L4D2Team_Infected);
}

stock GetTeamHumanCount(L4D2Team:team)
{
	new humans = 0;
	
	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && !IsFakeClient(client) && L4D2Team:GetClientTeam(client) == team)
		{
			humans++;
		}
	}
	
	return humans;
}

stock DoSecrets(client)
{
	if (L4D2Team:GetClientTeam(client) == L4D2Team_Survivor && !blockSecretSpam[client])
	{
		new particle = CreateEntityByName("info_particle_system");
		decl Float:pos[3];
		GetClientAbsOrigin(client, pos);
		pos[2] += 80;
		TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
		DispatchKeyValue(particle, "effect_name", "achieved");
		DispatchKeyValue(particle, "targetname", "particle");
		DispatchSpawn(particle);
		ActivateEntity(particle);
		AcceptEntityInput(particle, "start");
		CreateTimer(5.0, killParticle, particle, TIMER_FLAG_NO_MAPCHANGE);
		EmitSoundToAll("/level/gnomeftw.wav", client, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.5);
		CreateTimer(2.5, killSound);
		CreateTimer(5.0, SecretSpamDelay, client);
		blockSecretSpam[client] = true;
	}
		PrintCenterTextAll("\x42\x4f\x4e\x45\x53\x41\x57\x20\x49\x53\x20\x52\x45\x41\x44\x59\x21");
}

public Action:SecretSpamDelay(Handle:timer, any:client)
{
	blockSecretSpam[client] = false;
}

public Action:killParticle(Handle:timer, any:entity)
{
	if (entity > 0 && IsValidEntity(entity) && IsValidEdict(entity))
	{
		AcceptEntityInput(entity, "Kill");
	}
}

public Action:killSound(Handle:timer)
{
	for (new i = 1; i <= MaxClients; i++)
	if (IsClientInGame(i) && !IsFakeClient(i))
	StopSound(i, SNDCHAN_AUTO, "/level/gnomeftw.wav");
}

DisableEntities() {
  ActivateEntities("prop_door_rotating", "SetUnbreakable");
  MakePropsUnbreakable();
}

EnableEntities() {
  ActivateEntities("prop_door_rotating", "SetBreakable");
  MakePropsBreakable();
}


ActivateEntities(String:className[], String:inputName[]) { 
    new iEntity;
    
    while ( (iEntity = FindEntityByClassname(iEntity, className)) != -1 ) {
        if ( !IsValidEdict(iEntity) || !IsValidEntity(iEntity) ) {
            continue;
        }
        
        AcceptEntityInput(iEntity, inputName);
    }
}

MakePropsUnbreakable() {
    new iEntity;
    
    while ( (iEntity = FindEntityByClassname(iEntity, "prop_physics")) != -1 ) {
      if ( !IsValidEdict(iEntity) || !IsValidEntity(iEntity) ) {
          continue;
      }
      DispatchKeyValueFloat(iEntity, "minhealthdmg", 10000.0);
    }
}

MakePropsBreakable() {
    new iEntity;
    
    while ( (iEntity = FindEntityByClassname(iEntity, "prop_physics")) != -1 ) {
      if ( !IsValidEdict(iEntity) ||  !IsValidEntity(iEntity) ) {
          continue;
      }
      DispatchKeyValueFloat(iEntity, "minhealthdmg", 5.0);
    }
}
