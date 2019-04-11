#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <l4d2util_rounds>
#include <left4downtown>
#include <l4d2_direct>
#include <colors>

/*
1: Collect underpants
2a: Fetch all maps from each preset pool into a plugin pool
	- if a map is tagged for 2+ pools in the preset, load it only into one of them
2b: Remove until there's only cmt_poolsize maps or less in each plugin pool
2c: Store the pool order, ie pool 1 is used for map 1, pool 2 for map 2, pool 1 for map 3, pool 3 for map 4, etc
2d: Go through vetoing process
2e: Select the final maplist from the remaining maps according to the pool order
3: Profit
*/

/*
TODO
	- replace "poolsize" and "minpoolsize" with parameters in the tagrank command, so we can specify those variables on a per-rank basis
	- add command to abort mapset
*/

public Plugin:myinfo =
{
	name = "Custom Map Transitions",
	author = "Stabby",
	description = "Makes games more fun and varied! Yay!",
	version = "12",
	url = "https://github.com/Stabbath/L4D2-Stuff"
};

#define DIR_CFGS "cmt/"
#define PATH_KV  "cfg/cmt/mapnames.txt"
#define BUF_SZ   64

new Handle: g_hCvarPoolsize;
new Handle: g_hCvarMinPoolsize;
new Handle: g_hCvarVetoCount;

new Handle: g_hArrayTags;				//stores tags for indexing g_hTriePools
new Handle: g_hTriePools;				//stores pool array handles by tag name
new Handle: g_hArrayTagOrder;			//stores tags by rank
new Handle: g_hArrayMapOrder;			//stores finalised map list in order
new Handle: g_hTrieTagUses;				//how many different ranks a tag has, ie how many played maps will be based on this tag
new         g_iVetoesUsed[2];
new bool:   g_bMaplistFinalized;
new         g_iMapsPlayed;
new bool:   g_bMapsetInitialized;
new         g_iMapCount;
new         g_iTeamCampaignScore[2];
new Handle: g_hArrayTeamMapScore[2];
new Handle: g_hSDKCallSetCampaignScores;
new Handle: g_hForwardStart;
new Handle: g_hForwardNext;
new Handle: g_hForwardEnd;

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	g_hForwardStart = CreateGlobalForward("OnCMTStart", ET_Ignore, Param_Cell, Param_String );	// right before loading first map; params: 1 = maplist size; 2 = name of first map
	g_hForwardNext = CreateGlobalForward("OnCMTNextKnown", ET_Ignore, Param_String );			// after loading a map (to let other plugins know what the next map will be ahead of time); 1 = name of next map
	g_hForwardEnd = CreateGlobalForward("OnCMTEnd", ET_Ignore );								// after last map is played; no params

	return APLRes_Success;
}

public OnPluginStart() {
	SetRandomSeed(seed:GetEngineTime());

	//Pre-match commands
	//RegConsoleCmd(	"sm_forcemapset",	ForceMapSet,
	//				"Starts a mapset according to the maps specified in the params.");
	RegAdminCmd(	"sm_mapset",		ForceMapSet, ADMFLAG_CHANGEMAP,
					"Loads the mapset for the specified group. Use without params for syntax.");
	RegServerCmd(	"sm_addmap",		AddMap,
					"Adds a map to a map group under the specified tags. Use without params for syntax.");
	RegServerCmd(	"sm_tagrank",		TagRank,
					"Sets a tag's rank in the group. Use without params for syntax.");
	//Match commands
	RegConsoleCmd(	"sm_maplist",		Maplist,
					"Shows a player cmt's selected map list.");
	//RegConsoleCmd(	"sm_veto",			Veto,
	//				"Lets players veto a map. Uses per team per game cvar'd.");

	g_hCvarPoolsize = CreateConVar(		"cmt_poolsize", "1000",
										"How many maps will be initially pooled for each tag for each rank that uses that tag (can be a float).",
										FCVAR_NONE, true, 1.0, false);
	g_hCvarMinPoolsize = CreateConVar(	"cmt_minimum_poolsize", "1",
										"How many maps must remain in each pool after vetoing for each time that pool's tag is used/ranked.",
										FCVAR_NONE, true, 1.0, false);
	g_hCvarVetoCount = CreateConVar(	"cmt_veto_count", "0",
										"How many vetoes each team gets.",
										FCVAR_NONE, true, 0.0, false);

	g_hArrayTags = CreateArray(BUF_SZ/4);	//1 block = 4 characters => X characters = X/4 blocks
	g_hTriePools = CreateTrie();
	g_hArrayTagOrder = CreateArray(BUF_SZ/4);
	g_hArrayMapOrder = CreateArray(BUF_SZ/4);
	g_hTrieTagUses = CreateTrie();

	g_hArrayTeamMapScore[0] = CreateArray();
	g_hArrayTeamMapScore[1] = CreateArray();

	StartPrepSDKCall(SDKCall_GameRules);
	if (PrepSDKCall_SetFromConf(LoadGameConfigFile("left4downtown.l4d2"), SDKConf_Signature, "SetCampaignScores")) {
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		g_hSDKCallSetCampaignScores = EndPrepSDKCall();
	}
	else LogError("Could not find 'SetCampaignScores' signature in gamedata (left4downtown.l4d2.txt).");
}

//sm_nextmap '': Otherwise nextmap would be stuck and people wouldn't be able
//to play normal campaigns without the plugin
public OnPluginEnd() ServerCommand("sm_nextmap ''");
public OnMapStart() {
	ServerCommand("sm_nextmap ''");

	// let other plugins know what the map *after* this one will be (unless it is the last map)
	if (!g_bMaplistFinalized || g_iMapsPlayed >= g_iMapCount-1) return;
	decl String:buffer[BUF_SZ];
	GetArrayString(g_hArrayMapOrder, g_iMapsPlayed+1, buffer, BUF_SZ);
	
	Call_StartForward(g_hForwardNext);
	Call_PushString(buffer);
	Call_Finish();
}

public OnRoundStart(){
	CreateTimer(5.0, Timed_PostOnRoundStart);
}
public Action:Timed_PostOnRoundStart(Handle:timer) {
	if (!g_bMapsetInitialized) return;
	SDKCall(g_hSDKCallSetCampaignScores, g_iTeamCampaignScore[0], g_iTeamCampaignScore[1]);
	L4D2Direct_SetVSCampaignScore(0, g_iTeamCampaignScore[0]);
	L4D2Direct_SetVSCampaignScore(1, g_iTeamCampaignScore[1]);
}

public OnRoundEnd() {
	new round = _:InSecondHalfOfRound();
	CreateTimer(1.0, Timed_PostOnRoundEnd, round);
}
public Action:Timed_PostOnRoundEnd(Handle:timer, any:round) {
	if (!g_bMaplistFinalized) return;
	
	new score = L4D_GetTeamScore(round + 1);
	if (!round) {	//this if-el is so that scores for a map are shown right after round 1
		PushArrayCell(g_hArrayTeamMapScore[0], score);
		PushArrayCell(g_hArrayTeamMapScore[1], 0);
	} else {
		SetArrayCell(g_hArrayTeamMapScore[1], GetArraySize(g_hArrayTeamMapScore[1]) - 1, score);
	}
	g_iTeamCampaignScore[round] += score;
	L4D2Direct_SetVSCampaignScore(round, g_iTeamCampaignScore[round]);

	if (round) {
		SDKCall(g_hSDKCallSetCampaignScores, g_iTeamCampaignScore[0], g_iTeamCampaignScore[1]);
		if (++g_iMapsPlayed < g_iMapCount) {
			GotoNextMap();
		} else {
			// call ending forward
			Call_StartForward(g_hForwardEnd);
			Call_Finish();
		
			ServerCommand("sm_resetmatch");
		}
	}
}

//console cmd: loads a specified set of maps
public Action:ForceMapSet(client, args) {
	if (args < 1) {
		ReplyToCommand(client, "Syntax: sm_mapset <map1> <map2> <map3> <...>");
		ReplyToCommand(client, "Launches a mapset as specified.");
	}
	
	if (g_bMapsetInitialized) {
		ReplyToCommand(client, "Sorry, a map preset is already loaded. To select a different one you have to resetmatch and then load the config again before selecting a different mapset.");
		return Plugin_Handled;
	}
	
	//so things don't break and so the game starts right away
	ResetConVar(g_hCvarPoolsize);
	ResetConVar(g_hCvarMinPoolsize);
	ResetConVar(g_hCvarVetoCount);

	decl String:map[BUF_SZ];
	for (new i = 1; i <= args; i++) {
		GetCmdArg(i, map, BUF_SZ);
		ServerCommand("sm_addmap %s %d", map, i);
		ServerCommand("sm_tagrank %d %d", i, i-1);
	}
	g_bMapsetInitialized = true;
	CreateTimer(0.1, Timed_PostMapSet);

	return Plugin_Handled;
}

//console cmd: loads a cmt cfg
public Action:MapSet(client, args) {
	if (args < 1) {
		ReplyToCommand(client, "Syntax: sm_mapset <groupname>");
		ReplyToCommand(client, "Prepares the map pools for the specified group.");
	}

	if (g_bMapsetInitialized) {
		ReplyToCommand(client, "Sorry, a map preset is already loaded. To select a different one you have to resetmatch and then load the config again before selecting a different mapset.");
		return Plugin_Handled;
	}
	
	decl String:group[BUF_SZ];
	GetCmdArg(1, group, BUF_SZ);
	
	ServerCommand("exec %s%s.cfg", DIR_CFGS, group);
	PrintToChatAll("\x01Loading \x05%s \x01preset...", group);
	g_bMapsetInitialized = true;
	CreateTimer(0.1, Timed_PostMapSet);

	return Plugin_Handled;
}

//creates the initial map list after a map set has been loaded
public Action:Timed_PostMapSet(Handle:timer) {
	new mapnum = GetArraySize(g_hArrayTagOrder);
	new triesize = GetTrieSize(g_hTriePools);
	
	if (mapnum == 0) {
		g_bMapsetInitialized = false;	//failed to load it on the exec
		CPrintToChatAll("{red}Failed to load preset!");
		return Plugin_Handled;
	}

	if (g_iMapCount < triesize) {
		g_bMapsetInitialized = false;	//bad preset format
		CPrintToChatAll("Preset has {red}improper tagranks{default}: the number of maps to be played does not match the highest rank. Should have N+1 tagranks for highest rank N.");
		return Plugin_Handled;
	}
	
	//all this to cut each pool down to cmt_poolsize*tagUses maps
	decl String:buffer[BUF_SZ];
	decl Handle:hArrayMapPool;
	new Float:poolsize = GetConVarFloat(g_hCvarPoolsize);
	new tagnum = GetArraySize(g_hArrayTags);
	decl sizepool, tagUses;
	for (new i = 0; i < tagnum; i++) {
		GetArrayString(g_hArrayTags, i, buffer, BUF_SZ);
		GetTrieValue(g_hTrieTagUses, buffer, tagUses);
		GetTrieValue(g_hTriePools, buffer, hArrayMapPool);
		while ((sizepool = GetArraySize(hArrayMapPool)) > RoundToFloor(poolsize*float(tagUses))) {
			RemoveFromArray(hArrayMapPool, GetRandomInt(0, sizepool - 1));
		}
	}

	PrintToChatAll("Map set has been loaded!");

	//if no vetoes are allowed, just go straight to vetoingisover
	if (GetConVarInt(g_hCvarVetoCount) == 0) {
		VetoingIsOver();
	} else {
		for (new i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i) && !IsFakeClient(i))
				FakeClientCommand(i, "sm_maplist");
		}
		PrintToChatAll("\x01You may now veto maps from the map list. \x05ex: !veto c1m1_hotel \n(\x05!veto \x01for more info)");
	}

	return Plugin_Handled;
}

//returns a handle to the first array which is found to contain the specified mapname (should be the first and only one)
stock Handle:GetPoolThatContainsMap(String:map[], &index, String:tag[]) {
	decl Handle:hArrayMapPool;

	for (new i = 0; i < GetArraySize(g_hArrayTags); i++) {
		GetArrayString(g_hArrayTags, i, tag, BUF_SZ);
		GetTrieValue(g_hTriePools, tag, hArrayMapPool);
		if ((index = FindStringInArray(hArrayMapPool, map)) >= 0) {
			return hArrayMapPool;
		}
	}
	return INVALID_HANDLE;
}

//client cmd: vetoes a map off the list
public Action:Veto(client, args) {
	if (!g_bMapsetInitialized) {
		ReplyToCommand(client, "No mapset is loaded, what are you trying to veto?");
		return Plugin_Handled;		
	}

	new team = GetClientTeam(client) - 2;
	if (team < 0) {
		ReplyToCommand(client, "You're a spectator, no veto for you.");
		return Plugin_Handled;
	}
	
	if (g_bMaplistFinalized) {
		ReplyToCommand(client, "The time for vetoes is already over!");
		return Plugin_Handled;
	}
	
	if (g_iVetoesUsed[team] == GetConVarInt(g_hCvarVetoCount)) {
		ReplyToCommand(client, "Your team has used all of its vetoes!");
		return Plugin_Handled;
	}

	if (args < 1) {
		PrintToChat(client, "\x01Syntax: \"\x05!veto \x01<\x05mapname\x01|\x05@void\x01|\x05@voidall\x01>\". \x05@void \x01throws away one of your vetoes, \x05@voidall \x01throws away all remaining ones.");
		return Plugin_Handled;
	}
	
	decl String:map[BUF_SZ];
	GetCmdArg(1, map, BUF_SZ);
	
	if (StrEqual(map, "@void", false)) {
		new tmp = GetConVarInt(g_hCvarVetoCount);
		++g_iVetoesUsed[team];
		PrintToChatAll("\x01Veto discarded.\n Remaining vetoes: \x05%d \x01- \x05%d\x01.", tmp - g_iVetoesUsed[0], tmp - g_iVetoesUsed[1]);
	} else
	if (StrEqual(map, "@voidall", false)) {
		new tmp = GetConVarInt(g_hCvarVetoCount);
		g_iVetoesUsed[team] = tmp;
		PrintToChatAll("\x01All vetoes discarded.\n Remaining vetoes: \x05%d \x01- \x05%d\x01.", tmp - g_iVetoesUsed[0], tmp - g_iVetoesUsed[1]);
	} else {
	
		decl index;
		decl String:tag[BUF_SZ];
		new Handle:hArrayPool = GetPoolThatContainsMap(map, index, tag);
		if (hArrayPool == INVALID_HANDLE) {
			CPrintToChat(client, "{red}Invalid map! {default}No pool contains it.");
			return Plugin_Handled;
		}

		decl tagUses;
		GetTrieValue(g_hTrieTagUses, tag, tagUses);
		if (GetArraySize(hArrayPool) <= GetConVarInt(g_hCvarMinPoolsize)*tagUses) {
			CPrintToChat(client, "{red}Sorry! {default}There are too few maps in the pool the specified map belongs to: no more can be removed. If this happens with all of the pools, use !veto @void to get rid of all remaining vetoes.");
			return Plugin_Handled;
		}
	
		RemoveFromArray(hArrayPool, index);
		new tmp = GetConVarInt(g_hCvarVetoCount);
		++g_iVetoesUsed[team];
		PrintToChatAll("\x01Map \x05%s \x01has been removed from its pool. \nRemaining vetoes: \x05%d \x01- \x05%d\x01.", map, tmp - g_iVetoesUsed[0], tmp - g_iVetoesUsed[1]);

	}

	if (g_iVetoesUsed[0] == GetConVarInt(g_hCvarVetoCount) && g_iVetoesUsed[1] == GetConVarInt(g_hCvarVetoCount)) {
		PrintToChatAll("\x04Vetoing is over!");
		VetoingIsOver();
	}
	
	return Plugin_Handled;
}

//called after the last veto has been used
stock VetoingIsOver() {
	g_bMaplistFinalized = true;
	
	decl i, mapIndex;
	decl Handle:hArrayPool;
	decl String:tag[BUF_SZ];
	decl String:map[BUF_SZ];

	//Select 1 random map for each rank out of the remaining ones
	for (i = 0; i < GetArraySize(g_hArrayTagOrder); i++) {
		GetArrayString(g_hArrayTagOrder, i, tag, BUF_SZ);
		GetTrieValue(g_hTriePools, tag, hArrayPool);
		mapIndex = GetRandomInt(0, GetArraySize(hArrayPool) - 1);	

		GetArrayString(hArrayPool, mapIndex, map, BUF_SZ);
		RemoveFromArray(hArrayPool, mapIndex);
		PushArrayString(g_hArrayMapOrder, map);
	}

	//clear things because we only need the finalised map order in memory
	for (i = 0; i < GetArraySize(g_hArrayTagOrder); i++) {
		GetArrayString(g_hArrayTagOrder, i, tag, BUF_SZ);
		GetTrieValue(g_hTriePools, tag, hArrayPool);
		ClearArray(hArrayPool);
	}
	ClearTrie(g_hTriePools);
	ClearArray(g_hArrayTagOrder);

	//Show final maplist to everyone
	PrintToChatAll("Map list has been settled!");
	for (i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i))
			FakeClientCommand(i, "sm_maplist");
	}

	PrintToChatAll("\x01Game will start in \x048 \x01seconds.");
	CreateTimer(8.0, Timed_GiveThemTimeToReadTheMapList);
}

public Action:Timed_GiveThemTimeToReadTheMapList(Handle:timer) {
	ResetScores();	//scores wouldn't cross over because of forced map change before 2nd round end, but doesnt hurt
	
	// call starting forward
	decl String:buffer[BUF_SZ];
	GetArrayString(g_hArrayMapOrder, 0, buffer, BUF_SZ);
	
	Call_StartForward(g_hForwardStart);
	Call_PushCell(g_iMapCount);
	Call_PushString(buffer);
	Call_Finish();
	
	GotoNextMap(true);
}

//client cmd: displays map list
public Action:Maplist(client, args) {
	if (!g_bMapsetInitialized) {
		PrintToChat(client, "No mapset is loaded, so there's no maplist.");
		return Plugin_Handled;
	}

	new String:output[BUF_SZ] = "Maplist: ";
	decl String:buffer[BUF_SZ];

	if (g_bMaplistFinalized)
		Format(output, BUF_SZ, "%s\t %-4d-%4d", output, g_iTeamCampaignScore[0], g_iTeamCampaignScore[1]);

	PrintToChat(client, output);

	if (g_bMaplistFinalized) {
		/*	Final Maplist	*/
		for (new i = 0; i < GetArraySize(g_hArrayMapOrder); i++) {
			GetArrayString(g_hArrayMapOrder, i, buffer, BUF_SZ);
			FormatEx(output, BUF_SZ, "%d - %s", i + 1, buffer);

			if (GetPrettyName(buffer)) Format(output, BUF_SZ, "\x05%s \x01(%s)", output, buffer);

			if (g_iMapsPlayed > i) 
				Format(output, BUF_SZ, "%s\t %-4d-%4d", output, GetArrayCell(g_hArrayTeamMapScore[0], i), GetArrayCell(g_hArrayTeamMapScore[1], i));

			PrintToChat(client, "%s", output);				
		}
	} else {
		/*	Mid-veto Maplist	*/
		decl Handle:hArrayMapPool;
		decl String:tag[BUF_SZ];
		decl j;
		for (new i = 0; i < GetArraySize(g_hArrayTags); i++) {
			GetArrayString(g_hArrayTags, i, tag, BUF_SZ);

			output = "";
			for (j = 0; j < GetArraySize(g_hArrayTagOrder); j++) {
				GetArrayString(g_hArrayTagOrder, j, buffer, BUF_SZ);
				if (StrEqual(tag, buffer, false)) Format(output, BUF_SZ, "%s%s %d", output, output[0] == '\0' ? "" : ",", j + 1);
			}
			PrintToChat(client, "%s - %s", output, tag);

			GetTrieValue(g_hTriePools, tag, hArrayMapPool);
			for (j = 0; j < GetArraySize(hArrayMapPool); j++) {
				GetArrayString(hArrayMapPool, j, buffer, BUF_SZ);

				FormatEx(output, BUF_SZ, "\t%s", buffer);
				if (GetPrettyName(buffer)) Format(output, BUF_SZ, "\x05%s \x01(%s)", output, buffer);
				PrintToChat(client, "%s", output);
			}
		}
	}
	return Plugin_Handled;
}

//changes map
GotoNextMap(bool:force=false) {
	decl String:buffer[BUF_SZ];
	GetArrayString(g_hArrayMapOrder, g_iMapsPlayed, buffer, BUF_SZ);
	
	if (force) {
		ForceChangeLevel(buffer, "Custom map transitions.");
	} else {
//		L4D2Direct_SetVSInFinaleMap(false);	//so finales won't cause the game to end
		SetNextMap(buffer);
	}
}

//sets teams' campagin scores to 0
stock ResetScores() {
	GameRules_SetProp("m_iSurvivorScore", 0, _, 0); //reset scores
	GameRules_SetProp("m_iSurvivorScore", 0, _, 1); //
}

//server cmd: specifies a rank for a given tag
public Action:TagRank(args) {
	if (args < 2) {
		ReplyToCommand(0, "Syntax: sm_tagrank <tag> <map number>");
		ReplyToCommand(0, "Sets tag <tag> as the tag to be used to fetch maps for map <map number> in the map list.");
		ReplyToCommand(0, "Rank 0 is map 1, rank 1 is map 2, etc.");
	} else {
		decl String:buffer[BUF_SZ];
		GetCmdArg(2, buffer, BUF_SZ);
		new index = StringToInt(buffer);
		
		GetCmdArg(1, buffer, BUF_SZ);
		
		decl tagUses;
		if (!GetTrieValue(g_hTrieTagUses, buffer, tagUses)) tagUses = 0;
		SetTrieValue(g_hTrieTagUses, buffer, ++tagUses);

		if (index >= GetArraySize(g_hArrayTagOrder)) {
			ResizeArray(g_hArrayTagOrder, index + 1);
		}
		
		g_iMapCount++;
		SetArrayString(g_hArrayTagOrder, index, buffer);
		if (FindStringInArray(g_hArrayTags, buffer) < 0) PushArrayString(g_hArrayTags, buffer);
	}
	
	return Plugin_Handled;
}

//server cmd: adds a map to the maplist under specified tags
public Action:AddMap(args) {
	if (args < 2) {
		ReplyToCommand(0, "Syntax: sm_addmap <mapname> <tag1> <tag2> <...>");
		ReplyToCommand(0, "Adds <mapname> to the map selection and tags it with every mentioned tag.");
	} else {
		decl String:map[BUF_SZ];
		GetCmdArg(1, map, BUF_SZ);
		
		decl String:tag[BUF_SZ];
		
		//add the map under only one of the tags
		//TODO - maybe we should add it under all tags, since it might be removed from 1+ or even all of them anyway
		//also, if that ends up being implemented, remember to remove vetoed maps from ALL the pools it belongs to
		if (args == 2) {
			GetCmdArg(2, tag, BUF_SZ);
		} else {
			GetCmdArg(GetRandomInt(2, args), tag, BUF_SZ);
		}

		decl Handle:hArrayMapPool;
		if (!GetTrieValue(g_hTriePools, tag, hArrayMapPool))
			SetTrieValue(g_hTriePools, tag, (hArrayMapPool = CreateArray(BUF_SZ/4)));

		PushArrayString(hArrayMapPool, map);
	}
	
	return Plugin_Handled;
}

//return 0 if pretty name not found, 1 otherwise
stock GetPrettyName(String:map[]) {
	static Handle:hKvMapNames = INVALID_HANDLE;
	if (hKvMapNames == INVALID_HANDLE) {
		hKvMapNames = CreateKeyValues("Custom Map Transitions Map Names");
		if (!FileToKeyValues(hKvMapNames, PATH_KV)) {
			LogMessage("Couldn't create KV for map names.");
			hKvMapNames = INVALID_HANDLE;
			return 0;
		}
	}
	
	decl String:buffer[BUF_SZ];
	KvGetString(hKvMapNames, map, buffer, BUF_SZ, "no");
	if (!StrEqual(buffer, "no")) {
		strcopy(map, BUF_SZ, buffer);
		return 1;
	}
	return 0;
}
