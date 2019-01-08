/**
 * L4D2 Competitive Health Bonus Scoring System.
 * 
 * ConVars
 * ~~~~~
 * sm_perm_ratio [0.0, 1.0]
 *  
 * Defines how much permanent health should be worth 
 * compared to temporary health.
 * ~~~~~
 * sm_health_bonus_divisor [1.0,INT_MAX]
 * 
 * Defines the overall bonus divisor. Use this to make 
 * the bonus worth more (or less) compared to map distance.
 * ~~~~~
 * 
 * There's a permanent health pool and a temporary health pool.
 *
 * The permanent health pool represents the total amount of permanent health
 * that survivors have.
 *
 * The temporary health pool represents the total amount of temporary health
 * that survivors have + pain pills health + temporary health that survivors
 * get for free after a revive.
 *
 * Both pools are subjected to these factors:
 *
 * - Maximum map distance
 * - Permanent health ratio (defined by the cvar sm_perm_ratio) 
 * - Health divisor (defined by the cvar sm_health_bonus_divisor)
 * - Number of times the survivors have been incapacitated / killed.
 *
 * Pain pills in your inventory are worth the same in terms of temporary health
 * pool as 50 temporary health. Eating them will not reduce your bonus until you
 * bleed.
 *
 * Survivor deaths have the same kind of penalty on the bonus as incaps.
 * 
 * Author: Luckylock
 * 
 * Testers and feedback: Adam, Hib
 */

#include <sourcemod>
#include <left4downtown>
#include <sdktools>

#define DEBUG 0

/* Ratio */
#define PERM_RATIO GetConVarFloat(FindConVar("sm_perm_ratio"))

/* ConVars */
#define SURVIVOR_REVIVE_HEALTH GetConVarInt(FindConVar("survivor_revive_health"))
#define SURVIVOR_LIMIT GetConVarInt(FindConVar("survivor_limit"))
#define SURVIVOR_MAX_INCAPACITATED_COUNT GetConVarInt(FindConVar("survivor_max_incapacitated_count"))
#define MAX_REVIVES (SURVIVOR_LIMIT * SURVIVOR_MAX_INCAPACITATED_COUNT)
#define STOCK_TEMP_HEALTH (SURVIVOR_MAX_INCAPACITATED_COUNT * SURVIVOR_LIMIT * SURVIVOR_REVIVE_HEALTH)
#define PAIN_PILLS_HEALTH 50

/* Health divisor to keep bonus at reasonable numbers */
#define HEALTH_DIVISOR GetConVarInt(FindConVar("sm_health_bonus_divisor")) 

/* Health Index values */
#define HEALTH_TABLE_SIZE 6
#define PERM_HEALTH_INDEX 0
#define TEMP_HEALTH_INDEX 1
#define STOCK_TEMP_HEALTH_INDEX 2
#define PILLS_HEALTH_INDEX 3 
#define REVIVE_COUNT_INDEX 4
#define ALIVE_COUNT_INDEX 5

new Handle:hCvarValveSurvivalBonus;
new Handle:hCvarValveTieBreaker;
new firstRoundBonus;
new firstRoundHealth[HEALTH_TABLE_SIZE];
new bool:isFirstRound;

public Plugin myinfo =
{
	name = "L4D2 Competitive Health Bonus System",
	author = "Luckylock",
	description = "Scoring system for l4d2 competitive",
	version = "2.2",
	url = "https://github.com/LuckyServ/"
};

public OnPluginStart() 
{
    CreateConVar("sm_perm_ratio", "0.7", "Permanent health to temporary health ratio", 
        FCVAR_NONE, true, 0.0, true, 1.0);
    CreateConVar("sm_health_bonus_divisor", "200.0", "Health divisor to keep bonus at reasonable numbers",
        FCVAR_NONE, true, 1.0);
    RegConsoleCmd("sm_health", Cmd_ShowBonus, "Show current bonus");
    hCvarValveSurvivalBonus = FindConVar("vs_survival_bonus");
    hCvarValveTieBreaker = FindConVar("vs_tiebreak_bonus");
}

public Action Cmd_ShowBonus(client, args) 
{
    new health[HEALTH_TABLE_SIZE] = {0, 0, 0, 0, 0, 0};
    CalculateHealth(health);
    new finalBonus = CalculateFinalBonus(health);
    
    if (InSecondHalfOfRound()) {
        PrintRoundBonusClient(client, true, firstRoundHealth, firstRoundBonus);    
        PrintRoundBonusClient(client, false, health, finalBonus);    
    } else {
        PrintRoundBonusClient(client, true, health, finalBonus);
    }
}

public void CalculateHealth(int health[HEALTH_TABLE_SIZE]) 
{
    new revives = 0;

    for(new client = 1; client <= MaxClients; ++client) {
        if (IsSurvivor(client)) {
            if (IsPlayerAlive(client) && !L4D_IsPlayerIncapacitated(client)) {
                health[PERM_HEALTH_INDEX] += GetClientHealth(client);
                health[TEMP_HEALTH_INDEX] += GetTempHealth(client); 
                revives += L4D_GetPlayerReviveCount(client);
                health[ALIVE_COUNT_INDEX]++;
                if (HasPills(client)) {
                    health[PILLS_HEALTH_INDEX] += PAIN_PILLS_HEALTH; 
                }
            } else {
                revives += SURVIVOR_MAX_INCAPACITATED_COUNT; 
            }
        }
    }

    health[STOCK_TEMP_HEALTH_INDEX] = STOCK_TEMP_HEALTH - (revives * SURVIVOR_REVIVE_HEALTH);
    health[REVIVE_COUNT_INDEX] = revives;

#if DEBUG
    for (new i = 0; i < HEALTH_TABLE_SIZE; ++i) {
        PrintToChatAll("health[%d] = %d", i, health[i]);
    }
#endif
}

public int CalculateFinalBonus(health[HEALTH_TABLE_SIZE]) 
{
    health[PERM_HEALTH_INDEX] = 
        RoundFloat(health[PERM_HEALTH_INDEX] 
        * L4D_GetVersusMaxCompletionScore() 
        * PERM_RATIO / HEALTH_DIVISOR
        / (MAX_REVIVES + SURVIVOR_LIMIT) 
        * (MAX_REVIVES + SURVIVOR_LIMIT - health[REVIVE_COUNT_INDEX] - (SURVIVOR_LIMIT - health[ALIVE_COUNT_INDEX])));

    for (new i = TEMP_HEALTH_INDEX; i <= PILLS_HEALTH_INDEX; ++i) {
        health[i] = 
            RoundFloat(health[i]
            * L4D_GetVersusMaxCompletionScore() 
            * (1.0 - PERM_RATIO) / HEALTH_DIVISOR
            / (MAX_REVIVES + SURVIVOR_LIMIT) 
            * (MAX_REVIVES + SURVIVOR_LIMIT - health[REVIVE_COUNT_INDEX] - (SURVIVOR_LIMIT - health[ALIVE_COUNT_INDEX])));
    }

    return health[PERM_HEALTH_INDEX] 
            + health[TEMP_HEALTH_INDEX] 
            + health[STOCK_TEMP_HEALTH_INDEX]
            + health[PILLS_HEALTH_INDEX]; 
}

public int CalculateTotalTempHealth(health[HEALTH_TABLE_SIZE])
{
    return health[TEMP_HEALTH_INDEX]                             
            + health[STOCK_TEMP_HEALTH_INDEX]                           
            + health[PILLS_HEALTH_INDEX];
}

/** 
 * https://forums.alliedmods.net/showthread.php?t=144780 
 */
public int GetTempHealth(client) 
{
    new Float:buffer = GetEntPropFloat(client, Prop_Send, "m_healthBuffer"); 
    new Float:TempHealth = 0.0;

    if (buffer > 0) {
        new Float:difference = GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime");
        new Float:decay = GetConVarFloat(FindConVar("pain_pills_decay_rate"));
        new Float:constant = 1.0/decay;
        TempHealth = buffer - (difference / constant);
    }

    if (TempHealth < 0) {
        return 0;
    } else {
        return RoundFloat(TempHealth);
    }
}

public void OnMapStart() {
    isFirstRound = true;
    firstRoundBonus = 0;
    firstRoundHealth = {0, 0, 0, 0, 0, 0};
}

public Action L4D2_OnEndVersusModeRound(bool:countSurvivors) 
{
    new health[HEALTH_TABLE_SIZE] = {0, 0, 0, 0, 0, 0};
    CalculateHealth(health);
    new finalBonus = CalculateFinalBonus(health);

    SetConVarInt(hCvarValveSurvivalBonus, finalBonus / health[ALIVE_COUNT_INDEX]); 
    SetConVarInt(hCvarValveTieBreaker, 0);

    if (isFirstRound) {
        firstRoundBonus = finalBonus;
        copyTableValues(health, firstRoundHealth);
        PrintRoundBonusAll(true, health, finalBonus);
    } else {
        PrintRoundBonusAll(true, firstRoundHealth, firstRoundBonus);    
        PrintRoundBonusAll(false, health, finalBonus);    
    }

    isFirstRound = false;

    return Plugin_Continue;
}

public void PrintRoundBonusAll(bool firstRound, int health[HEALTH_TABLE_SIZE], int finalBonus)
{
    PrintToChatAll("\x04#%d \x01Bonus: \x05%d \x01[ Perm = \x03%d \x01| Temp = \x03%d \x01 | Pills = \x03%d \x01]", 
        firstRound ? 1 : 2, finalBonus, health[PERM_HEALTH_INDEX], health[TEMP_HEALTH_INDEX] + health[STOCK_TEMP_HEALTH_INDEX], 
        health[PILLS_HEALTH_INDEX]); 
}

public void PrintRoundBonusClient(int client, bool firstRound, int health[HEALTH_TABLE_SIZE], int finalBonus)
{
    PrintToChat(client, "\x04#%d \x01Bonus: \x05%d \x01[ Perm = \x03%d \x01| Temp = \x03%d \x01 | Pills = \x03%d \x01]", 
        firstRound ? 1 : 2, finalBonus, health[PERM_HEALTH_INDEX], health[TEMP_HEALTH_INDEX] + health[STOCK_TEMP_HEALTH_INDEX], 
        health[PILLS_HEALTH_INDEX]); 
}

public void copyTableValues(int health[HEALTH_TABLE_SIZE], int healthCopy[HEALTH_TABLE_SIZE])
{
    for (new i = 0; i < HEALTH_TABLE_SIZE; ++i) {
        healthCopy[i] = health[i];
    }
}

stock bool:IsSurvivor(client)                                                   
{                                                                               
    return client > 0 && client < MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2; 
}

stock bool:L4D_IsPlayerIncapacitated(client)
{
	return bool:GetEntProp(client, Prop_Send, "m_isIncapacitated");
}

stock L4D_GetPlayerReviveCount(client) 
{
	return GetEntProp(client, Prop_Send, "m_currentReviveCount");
}

stock bool HasPills(client)
{
	new item = GetPlayerWeaponSlot(client, 4);

	if (IsValidEdict(item))
	{
		decl String:buffer[64];
		GetEdictClassname(item, buffer, sizeof(buffer));
		return StrEqual(buffer, "weapon_pain_pills");
	}

	return false;
}

InSecondHalfOfRound()
{
    return GameRules_GetProp("m_bInSecondHalfOfRound");
}
